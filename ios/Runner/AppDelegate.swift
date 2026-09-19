import Flutter
import UIKit
import UniformTypeIdentifiers
import SQLite3
import VisionKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate, VNDocumentCameraViewControllerDelegate {
  private var documentPickerResult: FlutterResult?
  private var flutterChannel: FlutterMethodChannel?
  private var pickerMode: String = "db" // "db" or "csv"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DocumentPicker")
    let messenger = registrar!.messenger()
    let channel = FlutterMethodChannel(
      name: "com.hirokino.namecardapp/document_picker",
      binaryMessenger: messenger
    )
    self.flutterChannel = channel

    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else { return }
      if call.method == "pickDatabase" {
        self.documentPickerResult = result
        let types = [UTType.data]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        if let vc = UIApplication.shared.windows.first?.rootViewController {
          vc.present(picker, animated: true)
        }
      } else if call.method == "pickCsv" {
        // CSVファイル選択（UIDocumentPicker経由）
        // 戻り値: ファイルパス文字列 or nil（キャンセル時）
        self.documentPickerResult = result
        self.pickerMode = "csv"
        let types = [UTType.commaSeparatedText, UTType.plainText, UTType.data]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        if let vc = UIApplication.shared.windows.first?.rootViewController {
          vc.present(picker, animated: true)
        }
      } else if call.method == "scanDocument" {
        // VisionKitによるドキュメントスキャン（台形補正・斜め補正）
        self.documentPickerResult = result
        self.pickerMode = "scan"
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = self
        if let vc = UIApplication.shared.windows.first?.rootViewController {
          vc.present(scanner, animated: true)
        }
      } else if call.method == "importFromBackup" {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let backupURL = docsDir.appendingPathComponent("backup/namecard.db")
        if FileManager.default.fileExists(atPath: backupURL.path) {
          let json = self.readSQLiteToJSON(url: backupURL)
          result(json)
        } else {
          result(FlutterError(code: "NO_BACKUP", message: "バックアップが見つかりません", details: nil))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else {
      documentPickerResult?(FlutterError(code: "NO_FILE", message: "ファイルが選択されませんでした", details: nil))
      return
    }
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }

    if pickerMode == "csv" {
      // CSVモード: ファイルをDocumentsにコピーしてパスを返す
      let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
      let destURL = docsDir.appendingPathComponent("import_picked.csv")
      try? FileManager.default.removeItem(at: destURL)
      do {
        try FileManager.default.copyItem(at: url, to: destURL)
        documentPickerResult?(destURL.path)
      } catch {
        documentPickerResult?(FlutterError(code: "COPY_FAILED", message: "CSVファイルのコピーに失敗しました", details: nil))
      }
    } else {
      // DBモード: バックアップ保存してJSONで返す
      let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
      let backupDir = docsDir.appendingPathComponent("backup")
      try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
      let backupURL = backupDir.appendingPathComponent("namecard.db")
      try? FileManager.default.removeItem(at: backupURL)
      try? FileManager.default.copyItem(at: url, to: backupURL)

      // SQLite3で直接読み込みJSONで返す
      let json = self.readSQLiteToJSON(url: url)
      documentPickerResult?(json)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    documentPickerResult?(nil)
  }

  // ============================================================
  // VisionKit Document Scanner Delegate
  // ============================================================

  // スキャン成功時：補正済み画像をリサイズ・圧縮してDocumentsに保存
  func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
    controller.dismiss(animated: true)
    guard scan.pageCount > 0 else {
      documentPickerResult?(FlutterError(code: "NO_PAGE", message: "スキャン結果がありません", details: nil))
      return
    }
    // 最初のページを使用（名刺は1枚）
    let image = scan.imageOfPage(at: 0)

    // 長辺1200px以内にリサイズ
    let resized = resizeImage(image: image, maxLongSide: 1200)

    let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let fileName = "scanned_card_\(Int(Date().timeIntervalSince1970)).jpg"
    let fileURL = docsDir.appendingPathComponent(fileName)

    // JPEG品質70%で保存（約200〜300KB）
    if let data = resized.jpegData(compressionQuality: 0.7) {
      try? data.write(to: fileURL)
      documentPickerResult?(fileURL.path)
    } else {
      documentPickerResult?(FlutterError(code: "SAVE_FAILED", message: "画像の保存に失敗しました", details: nil))
    }
  }

  // 画像リサイズ（長辺を指定サイズ以内に収める）
  func resizeImage(image: UIImage, maxLongSide: CGFloat) -> UIImage {
    let width = image.size.width
    let height = image.size.height
    let longSide = max(width, height)

    // 既に小さい場合はそのまま返す
    if longSide <= maxLongSide { return image }

    let scale = maxLongSide / longSide
    let newWidth = width * scale
    let newHeight = height * scale
    let newSize = CGSize(width: newWidth, height: newHeight)

    UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
    image.draw(in: CGRect(origin: .zero, size: newSize))
    let resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
    UIGraphicsEndImageContext()
    return resized
  }

  // スキャンキャンセル時
  func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
    controller.dismiss(animated: true)
    documentPickerResult?(nil)
  }

  // スキャンエラー時
  func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
    controller.dismiss(animated: true)
    documentPickerResult?(FlutterError(code: "SCAN_ERROR", message: error.localizedDescription, details: nil))
  }

  func readSQLiteToJSON(url: URL) -> String {
    var db: OpaquePointer?
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      return "[]"
    }
    defer { sqlite3_close(db) }

    var stmt: OpaquePointer?
    let query = "SELECT user_id, name, name_kana, company, company_kana, department, title, email, phone, mobile_phone, fax, zip_code, address, note, image_path, voice_memo_path, project_codes, created_at, updated_at FROM business_cards"
    guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
      return "[]"
    }
    defer { sqlite3_finalize(stmt) }

    var rows: [[String: String]] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
      let cols = ["user_id","name","name_kana","company","company_kana","department","title","email","phone","mobile_phone","fax","zip_code","address","note","image_path","voice_memo_path","project_codes","created_at","updated_at"]
      var row: [String: String] = [:]
      for (i, col) in cols.enumerated() {
        if let val = sqlite3_column_text(stmt, Int32(i)) {
          row[col] = String(cString: val)
        } else {
          row[col] = ""
        }
      }
      rows.append(row)
    }

    if let data = try? JSONSerialization.data(withJSONObject: rows),
       let json = String(data: data, encoding: .utf8) {
      return json
    }
    return "[]"
  }
}
