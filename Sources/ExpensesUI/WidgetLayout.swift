import ExpensesCore
import SwiftUI
import WidgetKit

/// The widget's three sizes. Takes the family, the time and the calendar explicitly so tests can
/// render every size on a fixed day.
public struct ExpensesWidgetView: View {
  let payments: [Push]
  let family: WidgetFamily
  let now: Date
  let calendar: Calendar
  /// The snapshot's heartbeat; see `Snapshot.updated`.
  let updated: Date?

  public init(payments: [Push], family: WidgetFamily, now: Date = .now, calendar: Calendar = .current,
              updated: Date? = .now) {
    self.payments = payments
    self.family = family
    self.now = now
    self.calendar = calendar
    self.updated = updated
  }

  private var stale: Bool { Snapshot(payments: [], updated: updated).isStale(now: now) }

  private var month: [Push] { Ledger.inMonth(payments, Month(now, calendar: calendar), calendar: calendar) }
  private var today: [Push] { Ledger.onDay(payments, now, calendar: calendar) }

  public var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Group {
        switch family {
        case .systemMedium: medium
        case .systemLarge, .systemExtraLarge: large
        default: small
        }
      }
      .opacity(stale ? 0.4 : 1)
      if stale { staleNote }
    }
  }

  /// The app stopped writing (or never ran): the numbers above may miss new payments.
  private var staleNote: some View {
    HStack(spacing: 4) {
      Image(systemName: "clock.badge.exclamationmark")
      if let updated {
        Text("Updated \(Text(updated, style: .relative)) ago")
      } else {
        Text("Open Expenses to start")
      }
    }
    .font(.caption2)
    .foregroundStyle(.orange)
    .lineLimit(1)
    .minimumScaleFactor(0.7)
  }

  private var small: some View {
    VStack(alignment: .leading, spacing: 10) {
      figure("Today", Ledger.total(today), big: true)
      Spacer(minLength: 0)
      figure(Dates.shortMonth(Month(now, calendar: calendar), calendar: calendar), Ledger.total(month), big: false)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var medium: some View {
    HStack(alignment: .top, spacing: 16) {
      small.frame(width: 120)
      CategoryBars(totals: Ledger.byCategory(month), limit: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
  }

  private var large: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top) {
        figure(Dates.shortMonth(Month(now, calendar: calendar), calendar: calendar), Ledger.total(month), big: true)
        Spacer()
        figure("Today", Ledger.total(today), big: false).multilineTextAlignment(.trailing)
      }
      CategoryBars(totals: Ledger.byCategory(month), limit: 4)
      VStack(spacing: 7) {
        ForEach(Array(Ledger.newestFirst(payments).prefix(6)), id: \.self) { push in
          HStack(spacing: 8) {
            CategoryIcon(category: push.shownCategory, size: 20)
            Text(push.merchant ?? push.title).font(.caption).lineLimit(1)
            Spacer(minLength: 4)
            Text(Money.tenge(push.kzt ?? 0)).font(.caption.monospacedDigit())
              .foregroundStyle((push.kzt ?? 0) < 0 ? .green : .primary)
          }
        }
      }
      Spacer(minLength: 0)
    }
  }

  private func figure(_ label: String, _ value: Double, big: Bool) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      Text(Money.tenge(value))
        .font(big ? .title2.bold().monospacedDigit() : .headline.monospacedDigit())
        .minimumScaleFactor(0.6)
        .lineLimit(1)
    }
  }
}
