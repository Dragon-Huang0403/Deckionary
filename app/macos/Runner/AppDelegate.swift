import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      if let mainWindow = sender.windows.first(where: { $0 is MainFlutterWindow }) as? MainFlutterWindow {
        mainWindow.windowChannel?.invokeMethod("dockClicked", arguments: nil)
      }
      for window in sender.windows {
        window.makeKeyAndOrderFront(self)
      }
    }
    return true
  }
}
