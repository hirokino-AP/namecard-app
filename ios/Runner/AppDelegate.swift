import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private var documentPickerResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "com.hirokino.namecardapp/document_picker",
      binaryMessenger: engineBridge.pluginRegistry.registrar(forPlugin: "DocumentPicker").messenger()
    )

    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "pickDatabase" {
        self?.documentPickerResult = result
        let types = [UTType.data]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        if let vc = UIApplication.shared.keyWindow?.rootViewController {
          vc.present(picker, animated: true)
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
    url.startAccessingSecurityScopedResource()
    let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let destURL = docsDir.appendingPathComponent("import_picked.db")
    try? FileManager.default.removeItem(at: destURL)
    do {
      try FileManager.default.copyItem(at: url, to: destURL)
      url.stopAccessingSecurityScopedResource()
      documentPickerResult?(destURL.path)
    } catch {
      url.stopAccessingSecurityScopedResource()
      documentPickerResult?(FlutterError(code: "COPY_FAILED", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    documentPickerResult?(nil)
  }
}
