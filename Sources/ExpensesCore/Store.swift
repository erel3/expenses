import Foundation

/// Where the phone's file is: iCloud Drive → Shortcuts. Only ever read; the phone is its one writer.
public enum ICloud {
  public static var payments: URL {
    URL(filePath: NSHomeDirectory())
      .appending(path: "Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/payments.json")
  }
}

/// What the app hands the sandboxed widget through the App Group container: the payments of this
/// month and the last one, so the widget computes today and this month itself and a new day or
/// month needs no app.
public struct Snapshot: Codable, Equatable, Sendable {
  public var payments: [Push]

  public init(payments: [Push] = []) {
    self.payments = payments
  }

  /// This month's and last month's payments from every push.
  public init(pushes: [Push], now: Date = .now, calendar: Calendar = .current) {
    let month = Month(now, calendar: calendar)
    let keep: Set<Month> = [month, month.previous]
    self.init(payments: Ledger.payments(pushes).filter { push in
      push.date.map { keep.contains(Month($0, calendar: calendar)) } ?? false
    })
  }

  /// Missing or unreadable reads as empty: the widget then shows zeroes, never an error.
  public static func load(from url: URL) -> Snapshot {
    guard let data = try? Data(contentsOf: url) else { return Snapshot() }
    return (try? JSONDecoder().decode(Snapshot.self, from: data)) ?? Snapshot()
  }

  public func save(to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(self).write(to: url, options: .atomic)
  }
}

public enum Store {
  public static let appGroup = "73R36N2A46.com.akim.expenses"

  /// Only the signed app and widget touch this folder: macOS 15+ asks the user before an unsigned
  /// process reads another app's group container. `containerURL` returns a path even without the
  /// entitlement, so its result never says whether the group works.
  public static var directory: URL {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
      ?? URL(filePath: NSHomeDirectory()).appending(path: "Library/Group Containers/\(appGroup)")
  }

  public static var snapshotURL: URL { directory.appendingPathComponent("snapshot.json") }
}
