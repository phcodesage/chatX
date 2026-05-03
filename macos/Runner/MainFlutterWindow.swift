import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Set a sensible minimum size for the desktop app.
    self.minSize = NSSize(width: 800, height: 600)

    // Set a comfortable default size if the window is smaller than desired.
    if windowFrame.width < 1100 || windowFrame.height < 700 {
      let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
      let defaultWidth: CGFloat = min(1200, screen.width * 0.85)
      let defaultHeight: CGFloat = min(800, screen.height * 0.85)
      let x = screen.origin.x + (screen.width - defaultWidth) / 2
      let y = screen.origin.y + (screen.height - defaultHeight) / 2
      self.setFrame(NSRect(x: x, y: y, width: defaultWidth, height: defaultHeight), display: true)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
