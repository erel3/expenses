import Foundation

/// Where the payments are: iCloud Drive → Shortcuts. payments.json is the phone automation's;
/// manual-<device model>.json are the "Log Expense" shortcut's, one per device. Every file has one
/// writer, and this app is none of them: only ever read.
public enum ICloud {
  public static var folder: URL {
    URL(filePath: NSHomeDirectory()).appending(path: "Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents")
  }

  public static var payments: URL { folder.appending(path: "payments.json") }

  /// payments.json first, then the manual files by name, whichever exist. A file iCloud evicted
  /// shows as ".<name>.icloud" and counts under its real name, so it can be asked for.
  public static func dataFiles(in folder: URL = folder) -> [URL] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    let real = Set(names.map { name in
      name.hasPrefix(".") && name.hasSuffix(".icloud") ? String(name.dropFirst().dropLast(".icloud".count)) : name
    })
    let manual = real.filter { $0.hasPrefix("manual-") && $0.hasSuffix(".json") }.sorted()
    return ((real.contains("payments.json") ? ["payments.json"] : []) + manual).map { folder.appending(path: $0) }
  }
}

/// What the app hands the sandboxed widget through the App Group container: the payments of this
/// month and the last one, so the widget computes today and this month itself and a new day or
/// month needs no app.
public struct Snapshot: Codable, Equatable, Sendable {
  public var payments: [Push]
  /// When the app last read the phone's file, changed or not: a heartbeat. The widget dims and
  /// says so when it is old, because the app stopped (quit, crashed, not started at login) and the
  /// payments it shows may be missing new ones. Nil when no app ever wrote one.
  public var updated: Date?

  /// How old `updated` may get before the widget calls its numbers stale. The Mac app re-reads
  /// every 15 minutes and on wake, so twice that plus slack never fires while it runs. The iPhone
  /// app reads only when opened or when a shortcut runs its Refresh action, so a quiet afternoon
  /// is normal there: a day.
  #if os(iOS)
  public static let staleAfter: TimeInterval = 24 * 3600
  #else
  public static let staleAfter: TimeInterval = 45 * 60
  #endif

  public init(payments: [Push] = [], updated: Date? = nil) {
    self.payments = payments
    self.updated = updated
  }

  /// This month's and last month's payments from every push.
  public init(pushes: [Push], now: Date = .now, calendar: Calendar = .current) {
    let month = Month(now, calendar: calendar)
    let keep: Set<Month> = [month, month.previous]
    self.init(payments: Ledger.payments(pushes).filter { push in
      push.date.map { keep.contains(Month($0, calendar: calendar)) } ?? false
    }, updated: now)
  }

  public func isStale(now: Date = .now) -> Bool {
    guard let updated else { return true }
    return now.timeIntervalSince(updated) > Snapshot.staleAfter
  }

  /// Missing or unreadable reads as empty: the widget then shows zeroes, never an error.
  public static func load(from url: URL) -> Snapshot {
    guard let data = try? Data(contentsOf: url) else { return Snapshot() }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode(Snapshot.self, from: data)) ?? Snapshot()
  }

  public func save(to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(self).write(to: url, options: .atomic)
  }
}

public enum Store {
  /// iOS accepts only the `group.` form; the Mac app predates the iPhone and keeps its team-prefixed
  /// group (both are fine on macOS for a Developer ID app).
  #if os(iOS)
  public static let appGroup = "group.com.akim.expenses"
  #else
  public static let appGroup = "73R36N2A46.com.akim.expenses"
  #endif

  /// Only the signed app and widget touch this folder: macOS 15+ asks the user before an unsigned
  /// process reads another app's group container. `containerURL` returns a path even without the
  /// entitlement, so its result never says whether the group works.
  public static var directory: URL {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
      ?? URL(filePath: NSHomeDirectory()).appending(path: "Library/Group Containers/\(appGroup)")
  }

  public static var snapshotURL: URL { directory.appendingPathComponent("snapshot.json") }
}
