import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSPanel {
  var windowChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // NSPanel config for fullscreen overlay (Spotlight/Raycast behavior)
    self.isFloatingPanel = true
    self.becomesKeyOnlyIfNeeded = false
    self.hidesOnDeactivate = false
    self.styleMask.insert(.nonactivatingPanel)
    self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

    windowChannel = FlutterMethodChannel(
      name: "com.deckionary/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    windowChannel!.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "prepareForShow":
        NSApp.setActivationPolicy(.regular)
        self?.isFloatingPanel = true
        self?.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        self?.level = .popUpMenu
        NSApp.activate(ignoringOtherApps: true)
        self?.makeKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
          self?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
          self?.isFloatingPanel = false
          self?.level = .normal
        }
        result(nil)
      case "resetLevel":
        self?.level = .floating
        let showInDock = (call.arguments as? Bool) ?? false
        if !showInDock {
          NSApp.setActivationPolicy(.accessory)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()
  }
}
