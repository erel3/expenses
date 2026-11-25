@testable import ExpensesCore
import Foundation
import XCTest

final class LedgerTests: XCTestCase {
  private let calendar = Fixtures.almaty

  private func payments() throws -> [Push] {
    let parser = try Parser(script: String(contentsOf: Fixtures.parseJS, encoding: .utf8))
    return Ledger.payments(try parser.reparse(Fixtures.text))
  }

  func testMonthTotalCountsRefundsAndForeignInTenge() throws {
    let november = Ledger.inMonth(try payments(), Month(year: 2026, month: 11), calendar: calendar)
    XCTAssertEqual(november.count, 6)
    XCTAssertEqual(Ledger.total(november), 5572.22 - 204.5 + 43674.3 + 3210 + 18078 + 12722, accuracy: 0.001)
  }

  func testMonthsFollowTheLocalCalendarNotUTC() throws {
    // 2026-10-31 23:59 in Almaty is 18:59 UTC: October either way; 2026-11-01 00:30 local is
    // still October 31 in UTC, and must count for November.
    let late = Push(time: "2026-11-01T00:30:00+05:00", app: "Kaspi.kz", title: "", body: "", amount: 1, kzt: 1)
    XCTAssertEqual(Ledger.inMonth([late], Month(year: 2026, month: 11), calendar: calendar).count, 1)
    XCTAssertEqual(Ledger.inMonth(try payments(), Month(year: 2026, month: 10), calendar: calendar).map(\.kzt), [1000])
  }

  func testCategoriesLargestFirstWithOtherForUnknownMerchants() throws {
    let november = Ledger.inMonth(try payments(), Month(year: 2026, month: 11), calendar: calendar)
    let totals = Ledger.byCategory(november)
    XCTAssertEqual(totals.map(\.category), ["subscriptions", "food", "other", "transport"])
    XCTAssertEqual(totals[1].kzt, 5572.22 - 204.5 + 18078, accuracy: 0.001)
    XCTAssertEqual(totals[1].count, 3)
  }

  func testDaysNewestFirst() throws {
    let days = Ledger.byDay(Ledger.inMonth(try payments(), Month(year: 2026, month: 11), calendar: calendar), calendar: calendar)
    XCTAssertEqual(days.count, 4)
    XCTAssertEqual(days[0].payments.map(\.merchant), ["SOME SHOP"])
    XCTAssertEqual(days.last?.payments.map(\.merchant), ["FACEIT", "WOLT.COM", "WOLT.COM"])
    XCTAssertEqual(Ledger.onDay(try payments(), Fixtures.date("2026-11-20T12:00:00+05:00"), calendar: calendar).count, 3)
  }

  func testMonthsListAlwaysHasTheCurrentOne() throws {
    let now = Fixtures.date("2027-01-05T10:00:00+05:00")
    XCTAssertEqual(Ledger.months(try payments(), now: now, calendar: calendar),
                   [Month(year: 2027, month: 1), Month(year: 2026, month: 11), Month(year: 2026, month: 10)])
    XCTAssertEqual(Month(year: 2026, month: 1).previous, Month(year: 2025, month: 12))
  }

  func testSnapshotKeepsThisAndLastMonthAndRoundTrips() throws {
    let old = Push(time: "2026-09-10T10:00:00+05:00", app: "Kaspi.kz", title: "", body: "", amount: 5, kzt: 5)
    let snapshot = Snapshot(pushes: try payments() + [old], now: Fixtures.date("2026-11-25T10:00:00+05:00"), calendar: calendar)
    XCTAssertEqual(snapshot.payments.count, 7)
    let url = FileManager.default.temporaryDirectory.appending(path: "expenses-\(UUID())/snapshot.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try snapshot.save(to: url)
    XCTAssertEqual(Snapshot.load(from: url), snapshot)
    XCTAssertEqual(Snapshot.load(from: url.appending(path: "missing")), Snapshot())
  }

  func testSnapshotGoesStaleWhenTheAppStopsWriting() {
    let now = Fixtures.date("2026-11-25T18:00:00+05:00")
    XCTAssertFalse(Snapshot(updated: now.addingTimeInterval(-20 * 60)).isStale(now: now))
    XCTAssertTrue(Snapshot(updated: now.addingTimeInterval(-50 * 60)).isStale(now: now))
    XCTAssertTrue(Snapshot().isStale(now: now), "never written by the app")
    let pushes = [Push(time: "2026-11-25T10:00:00+05:00", app: "Kaspi.kz", title: "", body: "", amount: 1, kzt: 1)]
    XCTAssertEqual(Snapshot(pushes: pushes, now: now).updated, now)
  }

  func testFilesAreTheExpensesFolderPlusTheOldLayoutUntilArchived() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "expenses-\(UUID())")
    let folder = root.appending(path: "Expenses")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["payments.json", "manual-iPhone.json", "Log Payment.shortcut"] {
      try Data().write(to: root.appending(path: name))
    }
    for name in ["iPhone-2026.json", ".Mac-2026.json.icloud", "archive-2026.json", "edits-Mac.json", "upload.json"] {
      try Data().write(to: folder.appending(path: name))
    }
    let files = ICloud.files(in: root)
    XCTAssertEqual(files.data.map(\.lastPathComponent),
                   ["manual-iPhone.json", "payments.json", "Mac-2026.json", "archive-2026.json", "iPhone-2026.json"])
    XCTAssertEqual(files.edits.map(\.lastPathComponent), ["edits-Mac.json"])
    XCTAssertEqual(ICloud.files(in: folder), files, "picking Expenses itself works the same")
    XCTAssertEqual(ICloud.editsFile(in: root).lastPathComponent, "edits-Mac.json")
  }

  func testCorrectionsApplyThroughJavaScriptCore() throws {
    let parser = try Parser(script: String(contentsOf: Fixtures.parseJS, encoding: .utf8))
    let plain = try parser.reparse(Fixtures.text)
    let wolt = try XCTUnwrap(plain.first { $0.merchant == "WOLT.COM" })
    let shop = try XCTUnwrap(plain.first { $0.merchant == "SOME SHOP" })
    let at = Fixtures.date("2026-11-25T12:00:00+05:00")
    let edits = [
      Correction.category(id: try XCTUnwrap(wolt.id), value: "delivery").line(at: at),
      Correction.hide(id: try XCTUnwrap(shop.id)).line(at: at),
      Correction.merchantCategory(merchant: "YANDEX.GO", value: "taxi").line(at: at)
    ].joined(separator: "\n")
    let pushes = try parser.reparse(Fixtures.text, edits: edits)
    XCTAssertEqual(pushes.first { $0.id == wolt.id }?.category, "delivery")
    XCTAssertEqual(pushes.first { $0.id == wolt.id }?.edited, ["category"])
    XCTAssertTrue(pushes.first { $0.id == shop.id }?.isHidden ?? false)
    XCTAssertEqual(Set(pushes.filter { $0.merchant == "YANDEX.GO" }.map(\.category)), ["taxi"])
    XCTAssertFalse(Ledger.payments(pushes).contains { $0.id == shop.id }, "hidden is out of totals")
    XCTAssertEqual(parser.categories(edits: edits), ["transport", "food", "subscriptions", "delivery", "taxi", "other"])
  }

  func testACorrectionLineIsWhatParseJSReads() throws {
    let at = Fixtures.date("2026-11-25T12:00:00+05:00")
    let line = Correction.amount(id: "abc", value: 950).line(at: at)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    XCTAssertEqual(object["edit"] as? String, "amount")
    XCTAssertEqual(object["value"] as? Double, 950)
    XCTAssertNotNil(Push.parseTime(try XCTUnwrap(object["time"] as? String)))
  }
}
