@testable import ExpensesCore
import Foundation
import XCTest

final class ParserTests: XCTestCase {
  private func parser() throws -> Parser {
    try Parser(script: String(contentsOf: Fixtures.parseJS, encoding: .utf8))
  }

  func testPaymentsRefundsForeignAndRawArePickedApart() throws {
    let pushes = try parser().reparse(Fixtures.text)
    // 11 lines: one probe and one repeated debit dropped.
    XCTAssertEqual(pushes.count, 9)
    let payments = Ledger.payments(pushes)
    // Time order across files: the October line comes first although it is near the file's end.
    XCTAssertEqual(payments.map(\.merchant), ["YANDEX.GO", "WOLT.COM", "WOLT.COM", "FACEIT", "YANDEX.GO", "Arbuz.kz", "SOME SHOP"])
    XCTAssertEqual(payments.map(\.kzt), [1000, 5572.22, -204.5, 43674.3, 3210, 18078, 12722])
    XCTAssertEqual(payments[3].amount, 95.88)
    XCTAssertEqual(payments[3].currency, "$")
    XCTAssertEqual(payments[6].shownCategory, "other")
    XCTAssertEqual(Ledger.raw(pushes).map(\.title), ["Presale is live", "Кешбэк за покупку"])
  }

  func testAnUnreadableLineIsARawPushNotAFailure() throws {
    let pushes = try parser().reparse(Fixtures.lines[0] + "\n{\"time\":\"2026-11-2")
    XCTAssertEqual(pushes.count, 2)
    XCTAssertEqual(pushes[1].title, "unreadable line")
    XCTAssertNil(pushes[1].date)
  }

  func testEmptyFileIsNoPushes() throws {
    XCTAssertEqual(try parser().reparse(""), [])
  }

  func testAScriptWithoutReparseLinesIsRefused() {
    XCTAssertThrowsError(try Parser(script: "function parse() {}"))
    XCTAssertThrowsError(try Parser(script: "this is not JavaScript"))
  }

  /// The app must count exactly what `just reparse` counts: same file through node.
  func testJavaScriptCoreAgreesWithNode() throws {
    let input = FileManager.default.temporaryDirectory.appending(path: "expenses-\(UUID()).json")
    try Fixtures.text.write(to: input, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: input) }
    let reparse = Fixtures.parseJS.deletingLastPathComponent().appending(path: "reparse.mjs")
    let node = Process()
    node.executableURL = URL(filePath: "/usr/bin/env")
    node.arguments = ["node", reparse.path, input.path]
    let out = Pipe()
    node.standardOutput = out
    node.standardError = Pipe()
    do { try node.run() } catch { throw XCTSkip("node is not available: \(error)") }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    node.waitUntilExit()
    try XCTSkipIf(node.terminationStatus == 127, "node is not on PATH")
    XCTAssertEqual(node.terminationStatus, 0)
    let fromNode = try (String(bytes: data, encoding: .utf8) ?? "").split(separator: "\n")
      .map { try JSONDecoder().decode(Push.self, from: Data($0.utf8)) }
    XCTAssertEqual(try parser().reparse(Fixtures.text), fromNode)
  }
}
