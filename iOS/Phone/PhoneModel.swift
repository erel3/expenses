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
  @ObservationIgnored private var lastLoaded: Loaded?

  private init() {
    needsFolder = FolderAccess.folder() == nil
    feed.apply = { [weak self] correction in self?.apply(correction) }
  }

  func choose(_ folder: URL) {
    do {
      try FolderAccess.remember(folder)
      needsFolder = false
      lastLoaded = nil
      read()
    } catch {
      feed.problem = "Cannot keep access to that folder: \(error.localizedDescription)"
    }
  }

  /// A correction from the list: appended to edits-iPhone.json (this app's one file in the folder),
  /// then read again; the Mac sees it when iCloud brings the file over.
  func apply(_ correction: Correction) {
    guard let folder = FolderAccess.folder(), folder.startAccessingSecurityScopedResource() else {
      feed.problem = "No access to the Shortcuts folder any more: choose it again"
      return
    }
    defer { folder.stopAccessingSecurityScopedResource() }
    do {
      try correction.append(to: ICloud.editsFile(in: folder))
    } catch {
      feed.problem = "Cannot save the change: \(error.localizedDescription)"
      return
    }
    read()
  }

  /// Kaspi Gold statements picked in Files or shared from another app, into the Expenses folder.
  func importStatements(_ pdfs: [URL]) -> String {
    guard case .success(let parser) = parser else { return "parse.js is missing" }
    guard let folder = FolderAccess.folder(), folder.startAccessingSecurityScopedResource() else {
      needsFolder = true
      return "Choose the Shortcuts folder first"
    }
    defer { folder.stopAccessingSecurityScopedResource() }
    let reports = pdfs.map { pdf in
      let scoped = pdf.startAccessingSecurityScopedResource()
      defer { if scoped { pdf.stopAccessingSecurityScopedResource() } }
      do {
        let result = try StatementImport.run(pdf, parser: parser, into: ICloud.expenses(in: folder))
        return "\(result.rows) rows, \(result.from) to \(result.to)"
      } catch {
        return "\(pdf.lastPathComponent): \(error.localizedDescription)"
      }
    }
    lastLoaded = nil
    read()
    return reports.joined(separator: "\n")
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
    let files = ICloud.files(in: folder)
    guard !files.data.isEmpty else {
      feed.problem = "No payments here: choose iCloud Drive → Shortcuts"
      return
    }
    let loaded: Loaded
    do {
      loaded = try Library.load(files)
    } catch {
      feed.problem = error.localizedDescription
      return
    }
    feed.updated = .now
    do {
      if loaded != lastLoaded {
        feed.pushes = try parser.reparse(loaded.data, edits: loaded.edits)
        feed.categories = parser.categories(edits: loaded.edits)
        lastLoaded = loaded
      }
      feed.problem = nil
      handToWidget(feed.pushes)
    } catch {
      feed.problem = "\(error)"
    }
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
