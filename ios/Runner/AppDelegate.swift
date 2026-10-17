import Flutter
import UIKit
import UniformTypeIdentifiers
import SQLite3
import VisionKit
import Vision
import ImageIO

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
      if call.method == "convertToYomigana" {
        let text = call.arguments as? String ?? ""
        let yomigana = self.convertToYomigana(text)
        result(yomigana)
      } else if call.method == "convertListToYomigana" {
        // 会社名リストを一括変換
        let names = call.arguments as? [String] ?? []
        var results: [String: String] = [:]
        for name in names {
          results[name] = self.convertToYomigana(name)
        }
        result(results)
      } else if call.method == "pickDatabase" {
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
      } else if call.method == "recognizeText" {
        // 端末内OCR（Apple Vision）。引数: 画像パス / 戻り値: 行テキストのリスト
        guard let path = call.arguments as? String else {
          result(FlutterError(code: "BAD_ARGS", message: "画像パスが不正です", details: nil))
          return
        }
        self.recognizeText(path: path, result: result)
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

  // ============================================================
  // 端末内OCR（Apple Vision）：画像は端末外に送信しない
  // 認識結果を上→下（同じ高さなら左→右）の順に、認識ブロック1つ=1行で返す
  // ============================================================
  func recognizeText(path: String, result: @escaping FlutterResult) {
    guard #available(iOS 16.0, *) else {
      result(FlutterError(code: "UNSUPPORTED_OS", message: "端末内OCRはiOS 16以降が必要です", details: nil))
      return
    }
    guard let image = UIImage(contentsOfFile: path), let cgImage = image.cgImage else {
      result(FlutterError(code: "BAD_IMAGE", message: "画像を読み込めませんでした", details: nil))
      return
    }
    let orientation = cgOrientation(from: image.imageOrientation)

    DispatchQueue.global(qos: .userInitiated).async {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.recognitionLanguages = ["ja-JP", "en-US"]
      request.usesLanguageCorrection = false

      let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
      do {
        try handler.perform([request])
        let observations = request.results ?? []
        let sorted = observations.sorted { a, b in
          let yA = a.boundingBox.midY
          let yB = b.boundingBox.midY
          if yA != yB { return yA > yB }
          return a.boundingBox.minX < b.boundingBox.minX
        }
        let lines: [String] = sorted.compactMap { obs in
          guard let text = obs.topCandidates(1).first?.string else { return nil }
          let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
          return t.isEmpty ? nil : t
        }
        DispatchQueue.main.async { result(lines) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "OCR_FAILED", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  // UIImageの向き → Visionに渡す向き
  func cgOrientation(from o: UIImage.Orientation) -> CGImagePropertyOrientation {
    switch o {
    case .up: return .up
    case .upMirrored: return .upMirrored
    case .down: return .down
    case .downMirrored: return .downMirrored
    case .left: return .left
    case .leftMirrored: return .leftMirrored
    case .right: return .right
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }

  // 漢字→よみがな変換（Apple NLFramework使用）
  func convertToYomigana(_ text: String) -> String {
    // CFStringTransformで漢字→ローマ字→ひらがなに直接変換
    let mutableString = NSMutableString(string: text) as CFMutableString
    CFStringTransform(mutableString, nil, kCFStringTransformToLatin, false)
    CFStringTransform(mutableString, nil, kCFStringTransformLatinHiragana, false)
    // 長音符・アクセント記号を除去
    var result = mutableString as String
    result = result.replacingOccurrences(of: "\u{0304}", with: "")
    result = result.replacingOccurrences(of: "\u{0308}", with: "")
    result = result.replacingOccurrences(of: "\u{0301}", with: "")
    return result
  }

  func readSQLiteToJSON(url: URL) -> String {
    var db: OpaquePointer?
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      return "[]"
    }
    defer { sqlite3_close(db) }

    var stmt: OpaquePointer?
    let query = "SELECT user_id, name, name_kana, company, company_kana, department, title, industry, email, phone, mobile_phone, fax, zip_code, address, note, image_path, voice_memo_path, project_codes, created_at, updated_at FROM business_cards"
    guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
      return "[]"
    }
    defer { sqlite3_finalize(stmt) }

    var rows: [[String: String]] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
      let cols = ["user_id","name","name_kana","company","company_kana","department","title","industry","email","phone","mobile_phone","fax","zip_code","address","note","image_path","voice_memo_path","project_codes","created_at","updated_at"]
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
