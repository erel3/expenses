import AppKit
import ExpensesCore
import ExpensesUI
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  let monitor = Monitor()
  private var window: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = Self.mainMenu()
    monitor.start()
    Updater.shared.start()
    // Started at login: stay in the background for the widget. Started by hand: show the window.
    if SMAppService.mainApp.status != .enabled { showWindow() }
  }

  /// Opening the already running app from Finder, Spotlight or the Dock lands here.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    showWindow()
    return false
  }

  /// The Dock icon shows while the window is open: an app with a window behaves like one
  /// (⌘Tab, Mission Control), and goes back to the background when it closes.
  private func showWindow() {
    if window == nil {
      let window = Self.paymentsWindow(PaymentsWindow(feed: monitor.feed) {
        AddExpenseButton()
        SettingsMenu()
      })
      window.setFrameAutosaveName("Payments")
      window.delegate = self
      self.window = window
    }
    monitor.read()
    NSApp.setActivationPolicy(.regular)
    NSApp.activate()
    window?.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }

  /// Key equivalents come from the main menu, also for a background app: without one ⌘W and ⌘Q
  /// do nothing. ⌘W closes the window and keeps feeding the widget; ⌘Q quits.
  static func mainMenu() -> NSMenu {
    let app = NSMenu()
    app.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    app.addItem(withTitle: "Quit Expenses", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    let root = NSMenuItem()
    root.submenu = app
    let menu = NSMenu()
    menu.addItem(root)
    return menu
  }

  static func paymentsWindow(_ view: some View) -> NSWindow {
    let window = NSWindow(contentViewController: NSHostingController(rootView: view))
    window.title = "Expenses"
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.isReleasedWhenClosed = false
    window.setContentSize(NSSize(width: 560, height: 680))
    window.center()
    return window
  }
}

/// The window's settings, as Batteries' General pane has them: start at login (the widget stays
/// current only while the app runs), update checks, the project page.
struct SettingsMenu: View {
  @State private var openAtLogin = SMAppService.mainApp.status == .enabled
  @State private var checksForUpdates = Updater.shared.checksAutomatically
  @State private var error: String?

  var body: some View {
    HStack(spacing: 8) {
      if let error { Text(error).font(.caption).foregroundStyle(.red).lineLimit(1).help(error) }
      Menu {
        Toggle("Open at Login", isOn: Binding(get: { openAtLogin }, set: setOpenAtLogin))
        Divider()
        Toggle("Check for Updates Automatically", isOn: Binding(get: { checksForUpdates }, set: {
          Updater.shared.checksAutomatically = $0
          checksForUpdates = $0
        }))
        Button("Check for Updates Now") { Task { await Updater.shared.check(silent: false) } }
        Divider()
        Link("Expenses \(Updater.currentVersion) on GitHub", destination: Updater.page)
      } label: {
        Image(systemName: "gearshape")
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
    }
  }

  private func setOpenAtLogin(_ on: Bool) {
    do {
      if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
      error = nil
    } catch {
      self.error = error.localizedDescription
    }
    openAtLogin = SMAppService.mainApp.status == .enabled
  }
}

/// Runs the "Log Expense" shortcut rather than writing a payment itself: that shortcut is
/// manual-Mac.json's one writer (iCloud keeps one device's version of a file, so two writers can
/// lose a line). The window updates when the file changes.
struct AddExpenseButton: View {
  var body: some View {
    Button {
      NSWorkspace.shared.open(URL(string: "shortcuts://run-shortcut?name=Log%20Expense")!)
    } label: {
      Label("Add expense", systemImage: "plus")
    }
    .controlSize(.small)
  }
}
