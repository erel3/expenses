import AppKit
import ExpensesCore
import ExpensesUI
import Foundation
import WidgetKit

/// Reads payments.json and every manual-<device>.json whenever one changes, keeps the window's
/// feed, and hands the widget this month's and last month's payments through the App Group
/// container.
///
/// Read-only: no file is ever written or coordinated for writing. iCloud replaces files on every
/// sync, so a vnode watcher would lose them; an NSFilePresenter on the folder follows its items
/// instead, and a 15-minute timer plus a re-read on wake cover a missed notice.
@MainActor
final class Monitor {
  let feed = Feed()
  private let folder: URL
  private let parser: Result<Parser, Error>
  private var presenter: Presenter?
  private var timer: Timer?
  private var lastLoaded: Loaded?
  private var lastSnapshot: Snapshot?

  /// `folder`: iCloud Drive → Shortcuts; the data is in its Expenses folder (and, until archived,
  /// the old layout's files in Shortcuts itself), so the presenter watches all of it.
  init(folder: URL = ICloud.shortcuts) {
    self.folder = folder
    parser = Result { try Parser() }
  }

  func start() {
    let presenter = Presenter(url: folder) { [weak self] in
      Task { @MainActor in self?.read() }
    }
    NSFileCoordinator.addFilePresenter(presenter)
    self.presenter = presenter
    timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.read() }
    }
    timer?.tolerance = 60
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in self?.read() }
    }
    feed.apply = { [weak self] correction in self?.apply(correction) }
    // A newly installed widget has no timeline until its app asks for one.
    WidgetCenter.shared.reloadAllTimelines()
    read()
  }

  /// A correction from the window: appended to edits-Mac.json (this app's one file), then read
  /// again so the window, the widget and the iPhone (through iCloud) all see it.
  func apply(_ correction: Correction) {
    do {
      try correction.append(to: ICloud.editsFile(in: folder))
      read()
    } catch {
      feed.problem = "Cannot save the change: \(error.localizedDescription)"
    }
  }

  /// Kaspi Gold statements (PDF) into the Expenses folder, then read again. One line per file.
  func importStatements(_ pdfs: [URL]) -> [String] {
    guard case .success(let parser) = parser else { return ["parse.js is missing"] }
    let reports = pdfs.map { pdf in
      do {
        let result = try StatementImport.run(pdf, parser: parser, into: ICloud.expenses(in: folder))
        return "\(pdf.lastPathComponent): \(result.rows) rows, \(result.from) to \(result.to)"
      } catch {
        return "\(pdf.lastPathComponent): \(error.localizedDescription)"
      }
    }
    read()
    return reports
  }

  func read() {
    let parser: Parser
    switch self.parser {
    case .success(let value): parser = value
    case .failure(let error):
      feed.problem = "\(error)"
      return
    }
    let files = ICloud.files(in: folder)
    guard !files.data.isEmpty else {
      feed.problem = "No payments in iCloud Drive → Shortcuts → Expenses yet"
      return
    }
    // One reparseLines over all files together, as reparse.mjs does: the duplicate rule, the
    // corrections and the numbers stay the same as `just reparse`.
    let loaded: Loaded
    do {
      loaded = try Library.load(files, presenter: presenter)
    } catch {
      feed.problem = error.localizedDescription
      return
    }
    feed.updated = .now
    guard loaded != lastLoaded else {
      feed.problem = nil
      handToWidget(feed.pushes)  // the heartbeat
      return
    }
    do {
      let pushes = try parser.reparse(loaded.data, edits: loaded.edits)
      lastLoaded = loaded
      feed.pushes = pushes
      feed.categories = parser.categories(edits: loaded.edits)
      feed.problem = nil
      handToWidget(pushes)
    } catch {
      feed.problem = "\(error)"
    }
  }

  /// Written on every read, so `updated` beats while the app runs. WidgetKit rations reloads: one
  /// is asked for only when the payments changed, or when the widget was showing stale numbers;
  /// otherwise the widget picks the new stamp up on its own timeline.
  private func handToWidget(_ pushes: [Push]) {
    let snapshot = Snapshot(pushes: pushes)
    do {
      let shown = lastSnapshot ?? Snapshot.load(from: Store.snapshotURL)
      try snapshot.save(to: Store.snapshotURL)
      lastSnapshot = snapshot
      if snapshot.payments != shown.payments || shown.isStale() { WidgetCenter.shared.reloadAllTimelines() }
    } catch {
      feed.problem = "Cannot hand payments to the widget: \(error.localizedDescription)"
    }
  }
}

/// Tells the monitor when iCloud changed, replaced or delivered a file in the Shortcuts folder:
/// payments.json, a manual file, or one that just appeared.
private final class Presenter: NSObject, NSFilePresenter, @unchecked Sendable {
  let presentedItemURL: URL?
  let presentedItemOperationQueue = OperationQueue()
  private let changed: @Sendable () -> Void

  init(url: URL, changed: @escaping @Sendable () -> Void) {
    presentedItemURL = url
    self.changed = changed
    presentedItemOperationQueue.maxConcurrentOperationCount = 1
  }

  func presentedItemDidChange() { changed() }
  func presentedSubitemDidChange(at url: URL) { changed() }
  func presentedSubitemDidAppear(at url: URL) { changed() }
  func presentedItemDidGain(_ version: NSFileVersion) { changed() }
  func presentedItemDidResolveConflict(_ version: NSFileVersion) { changed() }
  func accommodatePresentedItemDeletion(completionHandler: @escaping @Sendable (Error?) -> Void) {
    changed()
    completionHandler(nil)
  }
}
