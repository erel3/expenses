import Foundation

/// A month of the calendar, as the window and the widget count it.
public struct Month: Hashable, Comparable, Sendable {
  public let year: Int
  public let month: Int

  public init(year: Int, month: Int) {
    self.year = year
    self.month = month
  }

  public init(_ date: Date, calendar: Calendar = .current) {
    let parts = calendar.dateComponents([.year, .month], from: date)
    self.init(year: parts.year!, month: parts.month!)
  }

  public var previous: Month { month == 1 ? Month(year: year - 1, month: 12) : Month(year: year, month: month - 1) }

  public func start(calendar: Calendar = .current) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: 1))!
  }

  public static func < (lhs: Month, rhs: Month) -> Bool { (lhs.year, lhs.month) < (rhs.year, rhs.month) }
}

public struct CategoryTotal: Hashable, Sendable {
  public let category: String
  public let kzt: Double
  public let count: Int

  public init(category: String, kzt: Double, count: Int) {
    self.category = category
    self.kzt = kzt
    self.count = count
  }
}

public struct Day: Hashable, Sendable {
  public let start: Date
  public let payments: [Push]
  public var kzt: Double { Ledger.total(payments) }
}

/// Sums over parsed pushes. Every figure is in tenge (`kzt`); a foreign payment the bank printed no
/// tenge for counts 0 and still shows in lists.
public enum Ledger {
  /// Payments that count: hidden ones are left out unless asked for (the window's "Show hidden").
  public static func payments(_ pushes: [Push], includingHidden: Bool = false) -> [Push] {
    pushes.filter { $0.isPayment && (includingHidden || !$0.isHidden) }
  }

  public static func raw(_ pushes: [Push]) -> [Push] { pushes.filter { !$0.isPayment && !$0.isHidden } }

  /// Hidden payments never count, even when listed.
  public static func total(_ payments: [Push]) -> Double {
    payments.reduce(0) { $0 + ($1.isHidden ? 0 : $1.kzt ?? 0) }
  }

  public static func inMonth(_ payments: [Push], _ month: Month, calendar: Calendar = .current) -> [Push] {
    payments.filter { $0.date.map { Month($0, calendar: calendar) == month } ?? false }
  }

  public static func onDay(_ payments: [Push], _ day: Date, calendar: Calendar = .current) -> [Push] {
    payments.filter { $0.date.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
  }

  /// Largest first; ties by name so the order never flickers.
  public static func byCategory(_ payments: [Push]) -> [CategoryTotal] {
    Dictionary(grouping: payments, by: \.shownCategory)
      .map { CategoryTotal(category: $0.key, kzt: total($0.value), count: $0.value.count) }
      .sorted { ($0.kzt, $1.category) > ($1.kzt, $0.category) }
  }

  /// Newest day first, newest payment first inside a day.
  public static func byDay(_ payments: [Push], calendar: Calendar = .current) -> [Day] {
    let dated = payments.compactMap { push in push.date.map { (push, $0) } }
    return Dictionary(grouping: dated) { calendar.startOfDay(for: $0.1) }
      .map { Day(start: $0.key, payments: $0.value.sorted { $0.1 > $1.1 }.map(\.0)) }
      .sorted { $0.start > $1.start }
  }

  /// Newest first; undated (unreadable) pushes last, in file order.
  public static func newestFirst(_ pushes: [Push]) -> [Push] {
    let dated = pushes.filter { $0.date != nil }.sorted { $0.date! > $1.date! }
    return dated + pushes.filter { $0.date == nil }
  }

  /// Months that have payments, newest first, always including `now`'s.
  public static func months(_ payments: [Push], now: Date = .now, calendar: Calendar = .current) -> [Month] {
    let months = Set(payments.compactMap { $0.date.map { Month($0, calendar: calendar) } } + [Month(now, calendar: calendar)])
    return months.sorted(by: >)
  }
}
