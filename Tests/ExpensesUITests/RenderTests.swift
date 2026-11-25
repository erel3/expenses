import AppKit
import ExpensesCore
@testable import ExpensesUI
import SwiftUI
import WidgetKit
import XCTest

/// Renders every widget size and both window tabs off screen. Fails if a view cannot render or a
/// glyph does not exist. `EXPENSES_RENDER_DIR=/some/dir swift test` also writes PNGs to look at.
@MainActor
final class RenderTests: XCTestCase {
  static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Almaty")!
    return calendar
  }()
  static let now = Push.parseTime("2026-11-25T18:00:00+05:00")!

  static func payment(_ time: String, _ merchant: String, _ category: String, _ kzt: Double,
                      amount: Double? = nil, currency: String = "₸") -> Push {
    Push(time: time, app: "Kaspi.kz", title: "Kaspi Gold", body: "", amount: amount ?? kzt, currency: currency,
         kzt: kzt, merchant: merchant, category: category)
  }

  static let pushes = [
    payment("2026-11-25T08:10:00+05:00", "YANDEX.GO", "transport", 2480),
    payment("2026-11-25T13:05:00+05:00", "WOLT.COM", "food", 6567),
    payment("2026-11-25T10:08:00+05:00", "ANTHROPIC* CLAUDE SUB", "subscriptions", 107_905.52, amount: 232, currency: "$"),
    payment("2026-11-24T12:39:00+05:00", "SOME SHOP", "", 12722),
    payment("2026-11-20T21:03:24+05:00", "WOLT.COM", "food", -204.5),
    payment("2026-10-30T09:00:00+05:00", "ARBUZ", "food", 18078),
    Push(time: "2026-11-23T17:01:00+05:00", app: "Kaspi.kz", title: "Kaspi Gold", body: "Ваша покупка отклонена системой безопасности"),
    Push(time: "", app: "", title: "unreadable line", body: "{\"time\":\"2026-11-2")
  ]

  func testEverySymbolExists() {
    for category in CategoryStyle.all + ["groceries", "health"] {
      let symbol = CategoryStyle(category).symbol
      XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), symbol)
    }
  }

  func testManyCategoriesMergeIntoOneBar() {
    let totals = (1...7).map { CategoryTotal(category: "c\($0)", kzt: Double(100 * (8 - $0)), count: 1) }
    let shown = CategoryBars.fit(totals, limit: 4)
    XCTAssertEqual(shown.map(\.category), ["c1", "c2", "c3", "+4 more"])
    XCTAssertEqual(shown.last?.kzt, 400 + 300 + 200 + 100)
    XCTAssertEqual(CategoryBars.fit(Array(totals.prefix(4)), limit: 4).count, 4, "four fit: nothing merged")
  }

  func testMonthGridRenders() throws {
    let picker = MonthPicker(month: .constant(Month(year: 2026, month: 11)), payments: Ledger.payments(Self.pushes),
                             now: Self.now, calendar: Self.calendar)
    try render(picker.grid.padding(14).background(Color(nsColor: .windowBackgroundColor)), name: "month-grid")
    XCTAssertEqual(Money.compact(1_940_000), "1.9M")
    XCTAssertEqual(Money.compact(450_400), "450K")
    XCTAssertEqual(Money.compact(900), "900")
  }

  func testMoneyReadsLikeTheBanks() {
    XCTAssertEqual(Money.tenge(243_492.4), "243 492 ₸")
    XCTAssertEqual(Money.tenge(-204.5), "−205 ₸")  // rounds half away from zero
    XCTAssertEqual(Money.tenge(0), "0 ₸")
    XCTAssertEqual(Money.original(Self.pushes[2]), "232,00 $")
    XCTAssertNil(Money.original(Self.pushes[0]))
  }

  func testWidgetSizesRender() throws {
    let payments = Ledger.payments(Self.pushes)
    struct Case {
      let name: String
      let family: WidgetFamily
      let size: CGSize
      let payments: [Push]
    }
    let cases = [
      Case(name: "small", family: .systemSmall, size: CGSize(width: 170, height: 170), payments: payments),
      Case(name: "small-empty", family: .systemSmall, size: CGSize(width: 170, height: 170), payments: []),
      Case(name: "medium", family: .systemMedium, size: CGSize(width: 364, height: 170), payments: payments),
      Case(name: "large", family: .systemLarge, size: CGSize(width: 364, height: 382), payments: payments),
      Case(name: "small-stale", family: .systemSmall, size: CGSize(width: 170, height: 170), payments: payments),
      Case(name: "large-stale", family: .systemLarge, size: CGSize(width: 364, height: 382), payments: payments)
    ]
    for test in cases {
      let updated = test.name.hasSuffix("stale") ? Self.now.addingTimeInterval(-3 * 3600) : Self.now
      let view = ExpensesWidgetView(payments: test.payments, family: test.family, now: Self.now, calendar: Self.calendar,
                                    updated: updated)
        .padding(16)
        .frame(width: test.size.width, height: test.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
      try render(view, name: test.name)
    }
  }

  /// The window holds AppKit-backed controls (List, Picker) that ImageRenderer draws as a
  /// placeholder, so it is laid out in a real window, never ordered in (Batteries' way).
  func testWindowRenders() throws {
    let feed = Feed(pushes: Self.pushes, updated: Self.now)
    try renderWindow(PaymentsWindow(feed: feed, now: Self.now, calendar: Self.calendar) { Text("Open at login") }, name: "window")
    try renderWindow(PaymentsWindow(feed: feed, now: Self.now, calendar: Self.calendar, tab: .raw) { EmptyView() }, name: "window-raw")
    let empty = Feed(problem: "No payments.json in iCloud Drive → Shortcuts yet")
    try renderWindow(PaymentsWindow(feed: empty, now: Self.now, calendar: Self.calendar) { EmptyView() }, name: "window-empty")
  }

  private func renderWindow(_ view: some View, name: String) throws {
    let window = NSWindow(contentViewController: NSHostingController(rootView: view))
    window.styleMask = [.titled, .closable, .resizable]
    // Off screen the window background is not drawn: light, so the PNG reads in a dark-mode session.
    window.appearance = NSAppearance(named: .aqua)
    window.setContentSize(NSSize(width: 560, height: 680))
    window.layoutIfNeeded()
    RunLoop.main.run(until: .now.addingTimeInterval(0.4))
    XCTAssertFalse(window.isVisible, "must never show on screen")
    let content = try XCTUnwrap(window.contentView)
    let rep = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
    content.cacheDisplay(in: content.bounds, to: rep)
    XCTAssertGreaterThan(rep.pixelsWide, 500, name)
    guard let dir = ProcessInfo.processInfo.environment["EXPENSES_RENDER_DIR"] else { return }
    try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(filePath: dir).appending(path: "\(name).png"))
  }

  private func render(_ view: some View, name: String) throws {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try XCTUnwrap(renderer.cgImage, name)
    XCTAssertGreaterThan(image.width, 100, name)
    guard let dir = ProcessInfo.processInfo.environment["EXPENSES_RENDER_DIR"] else { return }
    let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    try png.write(to: URL(filePath: dir).appending(path: "\(name).png"))
  }
}
