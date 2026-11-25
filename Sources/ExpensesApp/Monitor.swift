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
  private var lastText: String?
  private var lastSnapshot: Snapshot?

  init(folder: URL = ICloud.folder) {
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
    // A newly installed widget has no timeline until its app asks for one.
    WidgetCenter.shared.reloadAllTimelines()
    read()
  }

  func read() {
    let parser: Parser
    switch self.parser {
    case .success(let value): parser = value
    case .failure(let error):
      feed.problem = "\(error)"
      return
    }
    let files = ICloud.dataFiles(in: folder)
    guard !files.isEmpty else {
      feed.problem = "No payments.json in iCloud Drive → Shortcuts yet"
      return
    }
    // One reparseLines over all files together, as reparse.mjs does: the duplicate rule and the
    // numbers stay the same as `just reparse`.
    var texts: [String] = []
    for file in files {
      // A file "Optimize Mac Storage" evicted is only a placeholder until asked for.
      try? FileManager.default.startDownloadingUbiquitousItem(at: file)
      do {
        texts.append(try coordinatedRead(file))
      } catch {
        feed.problem = "Cannot read \(file.lastPathComponent): \(error.localizedDescription)"
        return
      }
    }
    let text = texts.joined(separator: "\n")
    feed.updated = .now
    guard text != lastText else {
      feed.problem = nil
      handToWidget(feed.pushes)  // the heartbeat
      return
    }
    do {
      let pushes = try parser.reparse(text)
      lastText = text
      feed.pushes = pushes
      feed.problem = nil
      handToWidget(pushes)
    } catch {
      feed.problem = "\(error)"
    }
  }

  private func coordinatedRead(_ file: URL) throws -> String {
    var result: Result<String, Error> = .failure(CocoaError(.fileReadUnknown))
    var coordinationError: NSError?
    NSFileCoordinator(filePresenter: presenter).coordinate(readingItemAt: file, options: [], error: &coordinationError) { url in
      result = Result { try String(contentsOf: url, encoding: .utf8) }
    }
    if let coordinationError { throw coordinationError }
    return try result.get()
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
