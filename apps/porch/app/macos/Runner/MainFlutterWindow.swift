import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerBackupExclusion(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

// Backup files live in Application Support, which Time Machine and other
// computer backups take by default. lib/backup_folder_adapter.dart asks
// for the backups folder to be marked excluded (NSURLIsExcludedFromBackupKey)
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
