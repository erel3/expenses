import Foundation

/// A change made in an app, appended to that device's edits-<device>.json and applied by parse.js
/// on every read. Nothing captured is ever rewritten or deleted: hiding is the undoable "delete".
public enum Correction: Equatable, Sendable {
  /// This payment only, or every payment of its merchant (parse.js: a payment's own wins).
  case category(id: String, value: String)
  case merchantCategory(merchant: String, value: String)
  /// The payment's tenge, e.g. a foreign payment's final settlement.
  case amount(id: String, value: Double)
  case hide(id: String)
  case unhide(id: String)
  /// Transfers whose details hold `value` ("*1858", a card's end) go to the owner's own account.
  case own(value: String)

  /// One JSON line, in the shape parse.js `readEdits` takes.
  public func line(at date: Date = .now) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = .current
    var fields: [String: Any] = ["time": formatter.string(from: date)]
    switch self {
    case .category(let id, let value): fields.merge(["edit": "category", "id": id, "value": value]) { $1 }
    case .merchantCategory(let merchant, let value): fields.merge(["edit": "category", "merchant": merchant, "value": value]) { $1 }
    case .amount(let id, let value): fields.merge(["edit": "amount", "id": id, "value": value]) { $1 }
    case .hide(let id): fields.merge(["edit": "hide", "id": id]) { $1 }
    case .unhide(let id): fields.merge(["edit": "unhide", "id": id]) { $1 }
    case .own(let value): fields.merge(["edit": "own", "value": value]) { $1 }
    }
    let data = (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])) ?? Data()
    return String(bytes: data, encoding: .utf8) ?? ""
  }

  /// Appends to this device's edits file through a coordinated write (iCloud sees one change).
  /// Only this app writes the file, so appending is safe.
  public func append(to file: URL, at date: Date = .now) throws {
    var failure: Error?
    var coordination: NSError?
    let line = Data((self.line(at: date) + "\n").utf8)
    NSFileCoordinator().coordinate(writingItemAt: file, options: .forMerging, error: &coordination) { url in
      do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
          try line.write(to: url, options: .atomic)
          return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
      } catch {
        failure = error
      }
    }
    if let error = coordination ?? failure { throw error }
  }
}
