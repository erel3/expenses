import ExpensesCore
import ExpensesUI
import Foundation
import Observation
import WidgetKit

/// The iPhone's reader. iOS gives an app no file watching in the background, so it reads when it
/// opens, when it comes back to the foreground, and when a shortcut runs "Refresh Expenses" right
/// after writing a line. Same files and the same parse.js as the Mac app and `just reparse`;
/// nothing is ever written to them.
@MainActor @Observable
final class PhoneModel {
  static let shared = PhoneModel()

  let feed = Feed()
  /// No usable folder yet: the app asks for iCloud Drive → Shortcuts.
  private(set) var needsFolder: Bool
  @ObservationIgnored private let parser: Result<Parser, Error> = Result { try Parser() }
  @ObservationIgnored private var lastText: String?

  private init() {
    needsFolder = FolderAccess.folder() == nil
  }

  func choose(_ folder: URL) {
    do {
      try FolderAccess.remember(folder)
      needsFolder = false
      lastText = nil
      read()
    } catch {
      feed.problem = "Cannot keep access to that folder: \(error.localizedDescription)"
    }
  }

  func read() {
    let parser: Parser
    switch self.parser {
    case .success(let value): parser = value
    case .failure(let error):
      feed.problem = "\(error)"
      return
    }
    guard let folder = FolderAccess.folder() else {
      needsFolder = true
      return
    }
    guard folder.startAccessingSecurityScopedResource() else {
      feed.problem = "No access to the Shortcuts folder any more: choose it again"
      needsFolder = true
      return
    }
    defer { folder.stopAccessingSecurityScopedResource() }
    let files = ICloud.dataFiles(in: folder)
    guard files.contains(where: { $0.lastPathComponent == "payments.json" }) else {
      feed.problem = "No payments.json in this folder: choose iCloud Drive → Shortcuts"
      return
    }
    var texts: [String] = []
    for file in files {
      try? FileManager.default.startDownloadingUbiquitousItem(at: file)
      do {
        texts.append(try Self.coordinatedRead(file))
      } catch {
        feed.problem = "Cannot read \(file.lastPathComponent): \(error.localizedDescription)"
        return
      }
    }
    let text = texts.joined(separator: "\n")
    feed.updated = .now
    do {
      if text != lastText {
        feed.pushes = try parser.reparse(text)
        lastText = text
      }
      feed.problem = nil
      handToWidget(feed.pushes)
    } catch {
      feed.problem = "\(error)"
    }
  }

  private static func coordinatedRead(_ file: URL) throws -> String {
    var result: Result<String, Error> = .failure(CocoaError(.fileReadUnknown))
    var coordinationError: NSError?
    NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordinationError) { url in
      result = Result { try String(contentsOf: url, encoding: .utf8) }
    }
    if let coordinationError { throw coordinationError }
    return try result.get()
  }

  /// As on the Mac: the heartbeat is written every read, a reload is asked for only when the
  /// payments changed or the widget was showing stale numbers.
  private func handToWidget(_ pushes: [Push]) {
    let snapshot = Snapshot(pushes: pushes)
    let shown = Snapshot.load(from: Store.snapshotURL)
    do {
      try snapshot.save(to: Store.snapshotURL)
      if snapshot.payments != shown.payments || shown.isStale() { WidgetCenter.shared.reloadAllTimelines() }
    } catch {
      feed.problem = "Cannot hand payments to the widget: \(error.localizedDescription)"
    }
  }
}

/// The folder the owner picked, kept as a bookmark in the App Group container: a picked URL is
/// only usable while the picker's grant lasts, a bookmark across launches and in the background.
enum FolderAccess {
  static var bookmarkURL: URL { Store.directory.appendingPathComponent("folder.bookmark") }

  static func remember(_ folder: URL) throws {
    guard folder.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
    defer { folder.stopAccessingSecurityScopedResource() }
    let data = try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    try FileManager.default.createDirectory(at: Store.directory, withIntermediateDirectories: true)
    try data.write(to: bookmarkURL, options: .atomic)
  }

  /// The remembered folder; a stale bookmark is renewed on the spot.
  static func folder() -> URL? {
    guard let data = try? Data(contentsOf: bookmarkURL) else { return nil }
    var stale = false
    guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
      return nil
    }
    if stale { try? remember(url) }
    return url
  }
}
