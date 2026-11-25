import ExpensesCore
import Observation
import SwiftUI

/// What the window shows; the app replaces `pushes` whenever the phone's file changes.
@MainActor @Observable
public final class Feed {
  public var pushes: [Push]
  /// Why the last read failed, shown in the window's footer; nil when it worked.
  public var problem: String?
  public var updated: Date?

  public init(pushes: [Push] = [], problem: String? = nil, updated: Date? = nil) {
    self.pushes = pushes
    self.problem = problem
    self.updated = updated
  }
}

/// Payments of a month, grouped by day, with a category filter, and the raw pushes beside them.
public struct PaymentsWindow<Footer: View>: View {
  let feed: Feed
  let now: Date
  let calendar: Calendar
  let footer: Footer
  @State private var month: Month
  @State private var category: String?
  @State private var tab: Tab

  enum Tab { case payments, raw }

  public init(feed: Feed, now: Date = .now, calendar: Calendar = .current, @ViewBuilder footer: () -> Footer) {
    self.init(feed: feed, now: now, calendar: calendar, tab: .payments, footer: footer)
  }

  init(feed: Feed, now: Date, calendar: Calendar, tab: Tab, @ViewBuilder footer: () -> Footer) {
    self.feed = feed
    _tab = State(initialValue: tab)
    self.now = now
    self.calendar = calendar
    self.footer = footer()
    _month = State(initialValue: Month(now, calendar: calendar))
  }

  public var body: some View {
    VStack(spacing: 0) {
      Picker("", selection: $tab) {
        Text("Payments").tag(Tab.payments)
        Text("Raw pushes (\(Ledger.raw(feed.pushes).count))").tag(Tab.raw)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()
      .padding(.vertical, 10)
      Divider()
      switch tab {
      case .payments: payments
      case .raw: raw
      }
      Divider()
      HStack {
        status
        Spacer()
        footer
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
    }
  }

  // MARK: Payments

  private var payments: some View {
    let all = Ledger.payments(feed.pushes)
    let inMonth = Ledger.inMonth(all, month, calendar: calendar)
    let totals = Ledger.byCategory(inMonth)
    let shown = category.map { picked in inMonth.filter { $0.shownCategory == picked } } ?? inMonth
    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Picker("Month", selection: $month) {
          ForEach(Ledger.months(all, now: now, calendar: calendar), id: \.self) { month in
            Text(Dates.monthName(month, calendar: calendar)).tag(month)
          }
        }
        .labelsHidden()
        .fixedSize()
        Spacer()
        Text(Money.tenge(Ledger.total(shown))).font(.title.bold().monospacedDigit())
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(totals, id: \.category) { total in chip(total) }
        }
      }
      if shown.isEmpty {
        ContentUnavailableView("No payments", systemImage: "creditcard",
                               description: Text("Nothing was spent in \(Dates.monthName(month, calendar: calendar)) yet."))
      } else {
        List {
          ForEach(Ledger.byDay(shown, calendar: calendar), id: \.start) { day in
            Section {
              // Identified by the push itself: offsets repeat from one day section to the next, and List
              // then reused another day's row (seen in the render test).
              ForEach(day.payments, id: \.self) { push in row(push) }
            } header: {
              HStack {
                Text(Dates.day(day.start, now: now, calendar: calendar))
                Spacer()
                Text(Money.tenge(day.kzt)).monospacedDigit()
              }
            }
          }
        }
        .listStyle(.inset)
      }
    }
    .padding([.horizontal, .top], 14)
    .onChange(of: month) { category = nil }
  }

  private func chip(_ total: CategoryTotal) -> some View {
    let picked = category == total.category
    return Button {
      category = picked ? nil : total.category
    } label: {
      HStack(spacing: 6) {
        CategoryIcon(category: total.category, size: 18)
        Text(total.category.capitalized)
        Text(Money.tenge(total.kzt)).monospacedDigit().foregroundStyle(.secondary)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(Capsule().fill(picked ? CategoryStyle(total.category).color.opacity(0.25) : Color.secondary.opacity(0.1)))
      .overlay(Capsule().strokeBorder(picked ? CategoryStyle(total.category).color : .clear))
    }
    .buttonStyle(.plain)
  }

  private func row(_ push: Push) -> some View {
    HStack(spacing: 10) {
      CategoryIcon(category: push.shownCategory)
      VStack(alignment: .leading, spacing: 2) {
        Text(push.merchant.flatMap { $0.isEmpty ? nil : $0 } ?? push.title).lineLimit(1)
        Text([push.app, push.date.map { Dates.time($0, calendar: calendar) }].compactMap { $0 }.joined(separator: " · "))
          .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        Text(Money.tenge(push.kzt ?? 0)).monospacedDigit()
          .foregroundStyle((push.kzt ?? 0) < 0 ? .green : .primary)
        if let original = Money.original(push) {
          Text(original).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
      }
    }
    .padding(.vertical, 2)
  }

  // MARK: Raw

  private var raw: some View {
    let pushes = Ledger.newestFirst(Ledger.raw(feed.pushes))
    return Group {
      if pushes.isEmpty {
        ContentUnavailableView("No raw pushes", systemImage: "tray",
                               description: Text("Every push so far was understood as a payment."))
      } else {
        List(pushes, id: \.self) { push in
          VStack(alignment: .leading, spacing: 3) {
            Text([push.app, push.date.map { Dates.day($0, now: now, calendar: calendar) + " " + Dates.time($0, calendar: calendar) }]
              .compactMap { $0 }.joined(separator: " · "))
              .font(.caption).foregroundStyle(.secondary)
            Text(push.title).bold()
            Text(push.body).foregroundStyle(.secondary).lineLimit(4)
          }
          .textSelection(.enabled)
          .padding(.vertical, 2)
        }
        .listStyle(.inset)
      }
    }
  }

  private var status: some View {
    Group {
      if let problem = feed.problem {
        Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
      } else if let updated = feed.updated {
        Text("Read \(updated.formatted(date: .omitted, time: .shortened)) · \(Ledger.payments(feed.pushes).count) payments")
          .foregroundStyle(.secondary)
      }
    }
    .font(.caption)
  }
}
