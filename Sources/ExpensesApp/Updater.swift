import AppKit
import ExpensesCore
import Foundation
import Observation
import os.log

/// Keeps the Mac app current from its GitHub releases, as LidGuard does: every 12 hours (and 10 s
/// after launch) it asks for the newest release. A newer one is offered, never installed silently
/// (owner, 2026-11-25: "same as lidguard"): a banner in the window when it is open, a small alert
/// otherwise. Install = download its zip, check that the new bundle is signed by the same team with
/// the same identifier, swap it in for the running one, relaunch.
@MainActor @Observable
final class Updater {
  static let repo = "Erel3/expenses"
  /// The project page; appctl also finds an app's releases from a github.com link in its binary.
  static let page = URL(string: "https://github.com/\(repo)")!
  static let latestURL = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
  static let checkEvery: TimeInterval = 12 * 3600
  static let teamID = "73R36N2A46"
  static let requirement =
    "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and identifier \"com.akim.expenses\""

  enum State: Equatable {
    case idle
    case available(version: String)
    case installing(version: String)
    case failed(String)
  }

  private(set) var state = State.idle
  @ObservationIgnored private var release: Release?
  @ObservationIgnored private var timer: Timer?
  @ObservationIgnored private let log = Logger(subsystem: "com.akim.expenses", category: "update")
  /// Whether the payments window is open: the offer then shows there instead of in an alert.
  @ObservationIgnored var windowOpen: () -> Bool = { false }
  /// The version the owner said "Later" to: not offered again until a newer one.
  @ObservationIgnored private var declined: String?

  static var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

  func start() {
    // `swift run` and test builds carry no real version; never let one replace itself.
    guard Bundle.main.bundleURL.pathExtension == "app" else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.check() }
    timer = Timer.scheduledTimer(withTimeInterval: Self.checkEvery, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.check() }
    }
    timer?.tolerance = 600
  }

  func check() {
    Task {
      do {
        var request = URLRequest(url: Self.latestURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Expenses/\(Self.current)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 404: no release published yet.
        guard status != 404 else { return }
        guard (200...299).contains(status) else { throw UpdateError("GitHub answered \(status)") }
        let latest = try JSONDecoder().decode(Release.self, from: data)
        guard Version.isNewer(latest.version, than: Self.current) else {
          log.info("up to date (\(Self.current, privacy: .public))")
          return
        }
        release = latest
        state = .available(version: latest.version)
        if !windowOpen() && declined != latest.version { offer(latest.version) }
      } catch {
        // A failed check is quiet: the next one comes in 12 hours.
        log.error("update check failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  func install() {
    guard let release, let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) else { return }
    state = .installing(version: release.version)
    Task {
      do {
        let app = try await Self.swapIn(from: asset.url)
        Self.relaunch(app)
      } catch {
        log.error("update failed: \(error.localizedDescription, privacy: .public)")
        state = .failed("Update to \(release.version) failed: \(error.localizedDescription)")
      }
    }
  }

  private func offer(_ version: String) {
    let alert = NSAlert()
    alert.messageText = "Expenses \(version) is available"
    alert.informativeText = "You have \(Self.current). Install it now? Expenses restarts in the background."
    alert.addButton(withTitle: "Install")
    alert.addButton(withTitle: "Later")
    NSApp.activate()
    if alert.runModal() == .alertFirstButtonReturn {
      install()
    } else {
      declined = version
    }
  }

  // MARK: Install

  /// Download, unpack, verify, replace. The running bundle is replaced only after the new one
  /// passed the signature check; `replaceItemAt` is a single swap with a backup.
  nonisolated private static func swapIn(from url: URL) async throws -> URL {
    let temp = FileManager.default.temporaryDirectory.appending(path: "expenses-update-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    let (download, response) = try await URLSession.shared.download(from: url)
    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
      throw UpdateError("download answered \(http.statusCode)")
    }
    let zip = temp.appending(path: "Expenses.zip")
    try FileManager.default.moveItem(at: download, to: zip)
    let unpacked = temp.appending(path: "unpacked")
    try await run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path], "unpack")
    let app = unpacked.appending(path: "Expenses.app")
    guard FileManager.default.fileExists(atPath: app.path) else { throw UpdateError("no Expenses.app in the zip") }
    try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R=\(requirement)", app.path], "signature check")
    let current = Bundle.main.bundleURL
    _ = try FileManager.default.replaceItemAt(current, withItemAt: app, backupItemName: "Expenses-old.app",
                                              options: .usingNewMetadataOnly)
    return current
  }

  /// Quit, then a shell waits for this process to end, stops the widget process of the old build
  /// (WidgetKit rejects every snapshot from a widget whose version no longer matches the bundle's)
  /// and opens the new app.
  private static func relaunch(_ app: URL) {
    let pid = ProcessInfo.processInfo.processIdentifier
    let path = app.path.replacingOccurrences(of: "'", with: "'\\''")
    let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; /usr/bin/pkill -x ExpensesWidget; /usr/bin/open -g '\(path)'"
    let shell = Process()
    shell.executableURL = URL(filePath: "/bin/sh")
    shell.arguments = ["-c", script]
    do {
      try shell.run()
      NSApp.terminate(nil)
    } catch {
      Logger(subsystem: "com.akim.expenses", category: "update").error("relaunch failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  nonisolated private static func run(_ tool: String, _ arguments: [String], _ what: String) async throws {
    try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
      let process = Process()
      process.executableURL = URL(filePath: tool)
      process.arguments = arguments
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      process.terminationHandler = { finished in
        if finished.terminationStatus == 0 {
          done.resume()
        } else {
          done.resume(throwing: UpdateError("\(what) failed (\(finished.terminationStatus))"))
        }
      }
      do { try process.run() } catch { done.resume(throwing: error) }
    }
  }
}

struct ReleaseAsset: Decodable {
  let name: String
  let url: URL

  enum CodingKeys: String, CodingKey {
    case name
    case url = "browser_download_url"
  }
}

struct Release: Decodable {
  let tag: String
  let assets: [ReleaseAsset]
  var version: String { tag.trimmingCharacters(in: CharacterSet(charactersIn: "v")) }

  enum CodingKeys: String, CodingKey {
    case tag = "tag_name"
    case assets
  }
}

struct UpdateError: LocalizedError {
  let errorDescription: String?
  init(_ message: String) { errorDescription = message }
}
