import ExpensesCore
import Foundation
import SwiftUI

/// Amounts as the banks print them: "12 345 ₸", grouped with spaces.
public enum Money {
  /// Whole tenge: kopecks only add noise to a total.
  public static func tenge(_ value: Double) -> String {
    let rounded = Int(value.rounded())
    return "\(rounded < 0 ? "−" : "")\(grouped(abs(rounded))) ₸"
  }

  /// The amount in the currency the bank charged, for a payment not in tenge ("95,88 $").
  public static func original(_ push: Push) -> String? {
    guard let amount = push.amount, let currency = push.currency, currency != "₸" else { return nil }
    let cents = Int((abs(amount) * 100).rounded())
    let text = "\(grouped(cents / 100)),\(String(format: "%02d", cents % 100)) \(currency)"
    return amount < 0 ? "−" + text : text
  }

  /// Short, for the month grid: "1.9M", "450K", "900".
  public static func compact(_ value: Double) -> String {
    let magnitude = abs(value)
    if magnitude >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
    if magnitude >= 1_000 { return "\(Int((value / 1_000).rounded()))K" }
    return "\(Int(value.rounded()))"
  }

  static func grouped(_ value: Int) -> String {
    var digits = String(value)
    var parts: [String] = []
    while digits.count > 3 {
      parts.insert(String(digits.suffix(3)), at: 0)
      digits.removeLast(3)
    }
    parts.insert(digits, at: 0)
    return parts.joined(separator: " ")
  }
}

/// Colour and glyph per category. A category parse.js gains later gets a stable colour from its
/// name until it is given one here.
public struct CategoryStyle {
  public let color: Color
  public let symbol: String

  public init(_ category: String) {
    switch category {
    case "food": self.init(color: .green, symbol: "fork.knife")
    case "transport": self.init(color: .blue, symbol: "car.fill")
    case "subscriptions": self.init(color: .purple, symbol: "repeat")
    case "other": self.init(color: .gray, symbol: "questionmark")
    case let merged where merged.hasPrefix("+"): self.init(color: .secondary, symbol: "ellipsis")
    default:
      let palette: [Color] = [.orange, .pink, .teal, .indigo, .brown, .mint, .cyan]
      let index = category.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff } % palette.count
      self.init(color: palette[index], symbol: "tag.fill")
    }
  }

  private init(color: Color, symbol: String) {
    self.color = color
    self.symbol = symbol
  }

  public static let all = ["food", "transport", "subscriptions", "other"]
}

public enum Dates {
  public static func monthName(_ month: Month, calendar: Calendar = .current) -> String {
    let style = Date.FormatStyle(timeZone: calendar.timeZone).month(.wide).year()
    return month.start(calendar: calendar).formatted(style)
  }

  public static func shortMonth(_ month: Month, calendar: Calendar = .current) -> String {
    month.start(calendar: calendar).formatted(Date.FormatStyle(timeZone: calendar.timeZone).month(.wide))
  }

  public static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
    if calendar.isDate(date, inSameDayAs: now) { return "Today" }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
      return "Yesterday"
    }
    return date.formatted(Date.FormatStyle(timeZone: calendar.timeZone).weekday(.wide).day().month(.wide))
  }

  public static func time(_ date: Date, calendar: Calendar = .current) -> String {
    date.formatted(Date.FormatStyle(timeZone: calendar.timeZone).hour(.twoDigits(amPM: .omitted)).minute())
  }
}

struct CategoryIcon: View {
  let category: String
  var size: CGFloat = 26

  var body: some View {
    let style = CategoryStyle(category)
    Image(systemName: style.symbol)
      .font(.system(size: size * 0.45, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(Circle().fill(style.color.gradient))
  }
}

/// A horizontal bar per category, longest = the largest category. More categories than `limit`:
/// the largest `limit - 1`, then one bar for the rest together ("+3 more"), so the widget never
/// grows with the number of categories and nothing spent drops out of sight.
struct CategoryBars: View {
  let totals: [CategoryTotal]
  var limit = 4

  static func fit(_ totals: [CategoryTotal], limit: Int) -> [CategoryTotal] {
    guard totals.count > limit, limit > 1 else { return totals }
    let kept = Array(totals.prefix(limit - 1))
    let rest = totals.dropFirst(limit - 1)
    return kept + [CategoryTotal(category: "+\(rest.count) more", kzt: rest.reduce(0) { $0 + $1.kzt },
                                 count: rest.reduce(0) { $0 + $1.count })]
  }

  var body: some View {
    let shown = Self.fit(totals, limit: limit)
    let top = max(shown.first?.kzt ?? 1, 1)
    VStack(alignment: .leading, spacing: 6) {
      ForEach(shown, id: \.category) { total in
        VStack(alignment: .leading, spacing: 2) {
          HStack {
            Text(total.category.capitalized).font(.caption)
            Spacer(minLength: 4)
            Text(Money.tenge(total.kzt)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
          }
          GeometryReader { proxy in
            Capsule().fill(CategoryStyle(total.category).color.gradient)
              .frame(width: max(4, proxy.size.width * CGFloat(max(total.kzt, 0) / top)))
          }
          .frame(height: 5)
        }
      }
    }
  }
}
