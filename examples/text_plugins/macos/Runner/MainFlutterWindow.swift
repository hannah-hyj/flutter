import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // macOS slows an app down when its window is covered or the display is off
  // (App Nap). The benchmark in lib/benchmark.dart then reports times that are
  // ten times too long. This activity tells macOS not to.
  private static var activity: NSObjectProtocol?

  override func awakeFromNib() {
    MainFlutterWindow.activity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiated, .latencyCritical],
      reason: "Text plugin benchmark")
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
