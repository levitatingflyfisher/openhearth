import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "PorchBackupExclusion") {
      registerBackupExclusion(messenger: registrar.messenger())
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

// Backup files live in Application Support, which iCloud and computer
// backups take by default. lib/backup_folder_adapter.dart asks for the
// backups folder to be marked excluded (NSURLIsExcludedFromBackupKey)
// before each file is written, and writes nothing if this fails.
func registerBackupExclusion(messenger: FlutterBinaryMessenger) {
  let channel = FlutterMethodChannel(
    name: "porch/backup_exclusion", binaryMessenger: messenger)
  channel.setMethodCallHandler { call, result in
    guard call.method == "excludeFromBackup",
      let args = call.arguments as? [String: Any],
      let path = args["path"] as? String
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    var url = URL(fileURLWithPath: path, isDirectory: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    do {
      try url.setResourceValues(values)
      result(nil)
    } catch {
      result(FlutterError(code: "exclude-failed", message: nil, details: nil))
    }
  }
}
