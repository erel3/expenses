import AppKit
import os
import SwiftUI

/// LidGuard's updater, ported: checks GitHub releases every 12 h (owner can switch that off) and
/// shows the release notes in a window. Nothing installs until the owner clicks Install Update.
/// The download must be signed by the owner's team, then replaces the bundle and relaunches.
@MainActor
final class Updater {
  static let shared = Updater()

  static let releasesURL = URL(string: "https://api.github.com/repos/Erel3/expenses/releases")!
  /// The project page, in the window's menu; appctl also finds the app's releases from a
  /// github.com/<owner>/<repo> link in its binary.
  static let page = URL(string: "https://github.com/Erel3/expenses")!
  static let checkInterval: TimeInterval = 12 * 60 * 60
  /// Only a bundle signed with the owner's Developer ID team is installed.
  static let designatedRequirement = #"anchor apple generic and certificate leaf[subject.OU] = "73R36N2A46""#

  private let log = Logger(subsystem: "com.akim.expenses", category: "update")
  private var timer: Timer?
  private var window: NSWindow?
  private var settings = UpdateSettings.load() {
    didSet { settings.save() }
  }

  var checksAutomatically: Bool {
    get { settings.checksAutomatically }
    set {
      settings.checksAutomatically = newValue
      if newValue { start() } else { stop() }
    }
  }

  static var currentVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
  }

  /// First check 5 s after launch when due, then every 12 h.
  func start() {
    guard settings.checksAutomatically, timer == nil else { return }
    let due = settings.lastCheck.map { Self.checkInterval - Date.now.timeIntervalSince($0) } ?? 0
    Task {
      try? await Task.sleep(for: .seconds(max(5, due)))
      await check(silent: true)
    }
    timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { _ in
      Task { @MainActor in await Updater.shared.check(silent: true) }
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  /// `silent`: the timer's check, which says nothing unless there is an update the owner has not skipped.
  func check(silent: Bool) async {
    var request = URLRequest(url: Self.releasesURL, timeoutInterval: 15)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("Expenses/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
    settings.lastCheck = .now
    let releases: [GitHubRelease]
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      guard (200...299).contains(status) else { throw UpdateError("GitHub answered HTTP \(status).") }
      releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
    } catch {
      log.error("update check failed: \(error.localizedDescription, privacy: .public)")
      if !silent { Self.alert("Could Not Check for Updates", error.localizedDescription) }
      return
    }
    let newer = releases.filter { Self.isNewer($0.version, than: Self.currentVersion) }
      .sorted { Self.isNewer($0.version, than: $1.version) }
    guard let latest = newer.first else {
      if !silent { Self.alert("You're Up to Date", "Expenses \(Self.currentVersion) is the latest version.") }
      return
    }
    if silent && settings.skippedVersion == latest.version { return }
    let notes = newer.map { "v\($0.version)\n\($0.body ?? "No release notes.")" }.joined(separator: "\n\n")
    show(latest, notes: notes)
  }

  private func show(_ release: GitHubRelease, notes: String, installing: Bool = false) {
    let view = UpdateView(version: release.version, notes: notes, installing: installing,
                          onInstall: { [weak self] in self?.install(release, notes: notes) },
                          onSkip: { [weak self] in
                            self?.settings.skippedVersion = release.version
                            self?.window?.close()
                          },
                          onLater: { [weak self] in self?.window?.close() })
    if let window {
      window.contentView = NSHostingView(rootView: view)
    } else {
      let window = NSWindow(contentViewController: NSHostingController(rootView: view))
      window.title = "Software Update"
      window.styleMask = [.titled, .closable]
      window.isReleasedWhenClosed = false
      window.center()
      self.window = window
    }
    NSApp.activate()
    window?.makeKeyAndOrderFront(nil)
  }

  private func install(_ release: GitHubRelease, notes: String) {
    guard let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
      Self.alert("Update Failed", "This release has no download.")
      return
    }
    show(release, notes: notes, installing: true)
    Task {
      do {
        let app = try await Self.download(asset.browserDownloadURL)
        settings.skippedVersion = nil
        relaunch(app)
      } catch {
        log.error("update failed: \(error.localizedDescription, privacy: .public)")
        window?.close()
        Self.alert("Update Failed", error.localizedDescription)
      }
    }
  }

  /// Downloads and unzips the release, checks its signature against the owner's team, and swaps it
  /// in place of the running bundle. Returns the bundle's URL to relaunch.
  nonisolated private static func download(_ url: URL) async throws -> URL {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("expenses-update-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: temp) }
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    let (file, response) = try await URLSession.shared.download(from: url)
    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
      throw UpdateError("Download failed: HTTP \(http.statusCode).")
    }
    let zip = temp.appendingPathComponent("Expenses.zip")
    try FileManager.default.moveItem(at: file, to: zip)
    try await run("/usr/bin/ditto", ["-x", "-k", zip.path, temp.path], failure: "Could not unzip the update.")
    let app = temp.appendingPathComponent("Expenses.app")
    try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R=\(designatedRequirement)", app.path],
                  failure: "The update is not signed by this app's developer.")
    let current = Bundle.main.bundleURL
    _ = try FileManager.default.replaceItemAt(current, withItemAt: app, backupItemName: "Expenses-old.app",
                                              options: .usingNewMetadataOnly)
    return current
  }

  /// After quitting, the same steps as `just install`: the old widget process would keep reporting
  /// the old version and WidgetKit would reject its snapshots, so it goes too; LaunchServices learns
  /// the new bundle (the widget gallery reads it from there); then the new app opens and, at launch,
  /// asks the widget to redraw.
  private func relaunch(_ app: URL) {
    let pid = ProcessInfo.processInfo.processIdentifier
    let path = app.path.replacingOccurrences(of: "'", with: "'\\''")
    let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; pkill -x ExpensesWidget; "
      + "\(lsregister) -f -R '\(path)'; pluginkit -a '\(path)/Contents/PlugIns/ExpensesWidget.appex'; open -g '\(path)'"
    let shell = Process()
    shell.executableURL = URL(fileURLWithPath: "/bin/sh")
    shell.arguments = ["-c", script]
    do {
      try shell.run()
      NSApp.terminate(nil)
    } catch {
      Self.alert("Update Installed", "Open Expenses again to finish.")
    }
  }

  nonisolated private static func run(_ tool: String, _ arguments: [String], failure: String) async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let status: Int32 = try await withCheckedThrowingContinuation { continuation in
      process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
      do { try process.run() } catch { continuation.resume(throwing: error) }
    }
    guard status == 0 else { throw UpdateError(failure) }
  }

  /// Semver order: 1.2.10 > 1.2.9, and a release beats its own prerelease (1.2.3 > 1.2.3-beta.1).
  nonisolated static func isNewer(_ remote: String, than local: String) -> Bool {
    func split(_ version: String) -> ([Int], String?) {
      let parts = version.trimmingCharacters(in: CharacterSet(charactersIn: "v")).split(separator: "-", maxSplits: 1)
      return ((parts.first ?? "").split(separator: ".").compactMap { Int($0) }, parts.count > 1 ? String(parts[1]) : nil)
    }
    let (remoteCore, remotePre) = split(remote)
    let (localCore, localPre) = split(local)
    for index in 0..<max(remoteCore.count, localCore.count) {
      let remotePart = index < remoteCore.count ? remoteCore[index] : 0
      let localPart = index < localCore.count ? localCore[index] : 0
      if remotePart != localPart { return remotePart > localPart }
    }
    switch (remotePre, localPre) {
    case (nil, nil): return false
    case (nil, _?): return true
    case (_?, nil): return false
    case let (remote?, local?): return remote > local
    }
  }

  private static func alert(_ title: String, _ message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    NSApp.activate()
    alert.runModal()
  }
}

struct UpdateError: LocalizedError {
  let errorDescription: String?
  init(_ message: String) { errorDescription = message }
}

struct GitHubRelease: Decodable, Sendable {
  let tagName: String
  let body: String?
  let assets: [GitHubAsset]

  var version: String { tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v")) }

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case body
    case assets
  }
}

struct GitHubAsset: Decodable, Sendable {
  let name: String
  let browserDownloadURL: URL

  enum CodingKeys: String, CodingKey {
    case name
    case browserDownloadURL = "browser_download_url"
  }
}

/// The updater's own state, apart from the alert settings.
struct UpdateSettings: Codable {
  var checksAutomatically = true
  var skippedVersion: String?
  var lastCheck: Date?

  private static let key = "updates"

  static func load() -> UpdateSettings {
    UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? UpdateSettings()
  }

  func save() {
    UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.key)
  }
}

/// The update window: icon, versions, release notes, and the three choices.
struct UpdateView: View {
  let version: String
  let notes: String
  let installing: Bool
  let onInstall: () -> Void
  let onSkip: () -> Void
  let onLater: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      VStack(spacing: 6) {
        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
        Text("Expenses \(version) Is Available").font(.headline)
        Text("You have \(Updater.currentVersion).").font(.subheadline).foregroundStyle(.secondary)
      }
      ScrollView {
        Text((try? AttributedString(markdown: notes, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
          ?? AttributedString(notes))
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
          .padding(12)
      }
      .background(Color(nsColor: .textBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 6))
      if installing {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text("Downloading and installing…").foregroundStyle(.secondary)
        }
      } else {
        HStack(spacing: 12) {
          Button("Not Now", action: onLater).keyboardShortcut(.cancelAction)
          Button("Skip This Version", action: onSkip)
          Button("Install Update", action: onInstall).keyboardShortcut(.defaultAction)
        }
      }
    }
    .padding(20)
    .frame(width: 480, height: 360)
  }
}
