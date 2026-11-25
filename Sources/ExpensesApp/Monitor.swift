import AppKit
import ExpensesCore
import ExpensesUI
import Foundation
import WidgetKit

/// Reads the phone's payments.json whenever it changes, keeps the window's feed, and hands the
/// widget this month's and last month's payments through the App Group container.
///
/// Read-only: the file is never written or coordinated for writing. iCloud replaces the file on
/// every sync, so a vnode watcher would lose it; an NSFilePresenter follows the item instead, and a
/// 15-minute timer plus a re-read on wake cover a missed notice.
@MainActor
final class Monitor {
  let feed = Feed()
  private let url: URL
  private let parser: Result<Parser, Error>
  private var presenter: Presenter?
  private var timer: Timer?
  private var lastText: String?
  private var lastSnapshot: Snapshot?

  init(url: URL = ICloud.payments) {
    self.url = url
    parser = Result { try Parser() }
  }

  func start() {
    let presenter = Presenter(url: url) { [weak self] in
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
    // A file "Optimize Mac Storage" evicted is only a placeholder until asked for.
    try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    let text: String
    do {
      text = try coordinatedRead()
    } catch {
      feed.problem = FileManager.default.fileExists(atPath: url.path)
        ? "Cannot read payments.json: \(error.localizedDescription)"
        : "No payments.json in iCloud Drive → Shortcuts yet"
      return
    }
    feed.updated = .now
    guard text != lastText else {
      feed.problem = nil
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

  private func coordinatedRead() throws -> String {
    var result: Result<String, Error> = .failure(CocoaError(.fileReadUnknown))
    var coordinationError: NSError?
    NSFileCoordinator(filePresenter: presenter).coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
      result = Result { try String(contentsOf: url, encoding: .utf8) }
    }
    if let coordinationError { throw coordinationError }
    return try result.get()
  }

  /// WidgetKit rations reloads: ask for one only when what the widget draws changed.
  private func handToWidget(_ pushes: [Push]) {
    let snapshot = Snapshot(pushes: pushes)
    guard snapshot != lastSnapshot else { return }
    do {
      try snapshot.save(to: Store.snapshotURL)
      lastSnapshot = snapshot
      WidgetCenter.shared.reloadAllTimelines()
    } catch {
      feed.problem = "Cannot hand payments to the widget: \(error.localizedDescription)"
    }
  }
}

/// Tells the monitor when iCloud changed, replaced or delivered payments.json.
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
  func presentedItemDidGain(_ version: NSFileVersion) { changed() }
  func presentedItemDidResolveConflict(_ version: NSFileVersion) { changed() }
  func accommodatePresentedItemDeletion(completionHandler: @escaping @Sendable (Error?) -> Void) {
    changed()
    completionHandler(nil)
  }
}
