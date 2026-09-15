import Flutter
import UIKit
import UniformTypeIdentifiers
import SQLite3

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private var documentPickerResult: FlutterResult?
  private var flutterChannel: FlutterMethodChannel?

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

    // バックアップ保存
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

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    documentPickerResult?(nil)
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
