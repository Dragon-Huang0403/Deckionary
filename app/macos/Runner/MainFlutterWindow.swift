import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSPanel {
  var windowChannel: FlutterMethodChannel?
  /// Captured before app activation so getActiveWindowScreenFrame returns
  /// the screen of the *previously* focused app, not Deckionary's own window.
  private var lastActiveScreen: NSScreen?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    self.isFloatingPanel = false
    self.hidesOnDeactivate = false
    self.level = .normal
    NSApp.setActivationPolicy(.regular)

    windowChannel = FlutterMethodChannel(
      name: "com.deckionary/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    windowChannel!.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "prepareForShow":
        // Snapshot the active screen BEFORE activation changes NSScreen.main
        self?.lastActiveScreen = NSScreen.main
        NSApp.setActivationPolicy(.regular)
        self?.isFloatingPanel = true
        self?.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        self?.level = .popUpMenu
        NSApp.activate(ignoringOtherApps: true)
        self?.makeKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
          self?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
          self?.level = .floating
        }
        result(nil)
      case "resetLevel":
        self?.level = .floating
        let showInDock = (call.arguments as? Bool) ?? false
        if !showInDock {
          NSApp.setActivationPolicy(.accessory)
        }
        result(nil)
      case "setNormalMode":
        self?.styleMask.remove(.nonactivatingPanel)
        self?.isFloatingPanel = false
        self?.level = .normal
        self?.collectionBehavior = [.fullScreenAuxiliary]
        NSApp.setActivationPolicy(.regular)
        result(nil)
      case "setLaunchOnStartup":
        if #available(macOS 13.0, *) {
          let enabled = (call.arguments as? Bool) ?? false
          if enabled {
            try? SMAppService.mainApp.register()
          } else {
            try? SMAppService.mainApp.unregister()
          }
        }
        result(nil)
      case "setOverlayMode":
        self?.styleMask.insert(.nonactivatingPanel)
        self?.isFloatingPanel = true
        self?.level = .floating
        self?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        result(nil)
      case "getActiveWindowScreenFrame":
        // Use the screen captured in prepareForShow (before activation changed
        // NSScreen.main to Deckionary's own window).
        // Convert from macOS bottom-left origin to top-left origin to match
        // screen_retriever's coordinate system.
        if let screen = self?.lastActiveScreen ?? NSScreen.main,
           let primary = NSScreen.screens.first {
          let frame = screen.visibleFrame
          let primaryHeight = primary.frame.height
          let topLeftY = primaryHeight - frame.origin.y - frame.size.height
          result([
            "x": frame.origin.x,
            "y": topLeftY,
            "width": frame.size.width,
            "height": frame.size.height,
          ] as [String: Double])
        } else {
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()
  }
}
