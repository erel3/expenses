import AppKit

// Background app (LSUIElement): no Dock icon while it only feeds the widget. Opening it from
// Finder or Spotlight shows the payments window, and the Dock icon with it.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
