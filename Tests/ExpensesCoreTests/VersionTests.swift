import ExpensesCore
import XCTest

final class VersionTests: XCTestCase {
  func testNewerComparesNumbersNotText() {
    XCTAssertTrue(Version.isNewer("0.1.10", than: "0.1.9"))
    XCTAssertTrue(Version.isNewer("v0.2.0", than: "0.1.10"))
    XCTAssertTrue(Version.isNewer("1.0", than: "0.9.9"))
    XCTAssertFalse(Version.isNewer("0.1.0", than: "0.1.0"))
    XCTAssertFalse(Version.isNewer("0.1", than: "0.1.0"))
    XCTAssertFalse(Version.isNewer("0.1.0", than: "0.2.0"))
  }
}
