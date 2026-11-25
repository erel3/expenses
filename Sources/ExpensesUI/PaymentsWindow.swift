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
  /// The categories a correction can pick: parse.js's table, the ones corrections created, other.
  public var categories: [String]
  /// Saves a correction (the app appends it to its edits file and reads again); nil: read only.
  @ObservationIgnored public var apply: ((Correction) -> Void)?

  public init(pushes: [Push] = [], problem: String? = nil, updated: Date? = nil,
              categories: [String] = ["food", "transport", "subscriptions", "other"]) {
    self.pushes = pushes
    self.problem = problem
    self.updated = updated
    self.categories = categories
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
  @State private var showHidden = false
  /// The payment (and scope) a new category is being typed for.
  @State private var naming: Naming?
  @State private var newCategory = ""
  /// The payment whose tenge is being corrected.
  @State private var fixing: Push?
  @State private var amountText = ""

  struct Naming {
    let push: Push
    let everyPayment: Bool
  }

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

  /// One list for the whole tab, the month header and category chips included: on the iPhone a
  /// pull anywhere is the one refresh, and nothing scrolls on its own (the chips once sat in their
  /// own scroll view, which iOS gave a second pull-to-refresh and let drag every way).
  private var payments: some View {
    let all = Ledger.payments(feed.pushes)
    let inMonth = Ledger.inMonth(all, month, calendar: calendar)
    let totals = Ledger.byCategory(inMonth)
    let hiddenInMonth = Ledger.inMonth(Ledger.payments(feed.pushes, includingHidden: true), month, calendar: calendar)
      .filter(\.isHidden)
    let listed = showHidden ? (inMonth + hiddenInMonth) : inMonth
    let shown = category.map { picked in listed.filter { $0.shownCategory == picked } } ?? listed
    return List {
      Section {
        VStack(alignment: .leading, spacing: 12) {
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
          FlowLayout(spacing: 8) {
            ForEach(totals, id: \.category) { total in chip(total) }
          }
          if !hiddenInMonth.isEmpty {
            Toggle("Show hidden (\(hiddenInMonth.count))", isOn: $showHidden)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .listRowSeparator(.hidden)
      }
      if shown.isEmpty {
        ContentUnavailableView("No payments", systemImage: "creditcard",
                               description: Text("Nothing was spent in \(Dates.monthName(month, calendar: calendar)) yet."))
          .listRowSeparator(.hidden)
      }
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
    .onChange(of: month) { category = nil }
    .alert("New category", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
      TextField("Name, e.g. health", text: $newCategory)
      Button("Cancel", role: .cancel) { naming = nil }
      Button("Save") {
        let name = newCategory.trimmingCharacters(in: .whitespaces).lowercased()
        if let naming, !name.isEmpty { setCategory(name, of: naming.push, everyPayment: naming.everyPayment) }
        naming = nil
      }
    } message: {
      Text(naming.map { $0.everyPayment ? "For every \(merchantName($0.push)) payment" : "For this payment only" } ?? "")
    }
    .alert("Fix amount", isPresented: Binding(get: { fixing != nil }, set: { if !$0 { fixing = nil } })) {
      TextField("Tenge", text: $amountText)
      Button("Cancel", role: .cancel) { fixing = nil }
      Button("Save") {
        let value = Double(amountText.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "."))
        if let fixing, let id = fixing.id, let value { feed.apply?(.amount(id: id, value: value)) }
        fixing = nil
      }
    } message: {
      Text(fixing.map { "\(merchantName($0)): \(Money.tenge($0.kzt ?? 0)) now" } ?? "")
    }
  }

  // MARK: Corrections

  private func merchantName(_ push: Push) -> String {
    push.merchant.flatMap { $0.isEmpty ? nil : $0 } ?? push.title
  }

  private func setCategory(_ value: String, of push: Push, everyPayment: Bool) {
    if everyPayment, let merchant = push.merchant, !merchant.isEmpty {
      feed.apply?(.merchantCategory(merchant: merchant.uppercased(), value: value))
    } else if let id = push.id {
      feed.apply?(.category(id: id, value: value))
    }
  }

  /// Right click on the Mac, a long press on the iPhone. Nothing captured is ever changed: each
  /// choice is a correction line, hiding included (undone by Unhide).
  @ViewBuilder
  private func corrections(_ push: Push) -> some View {
    if feed.apply != nil, push.id != nil {
      ForEach([false, true], id: \.self) { every in
        if !every || !(push.merchant ?? "").isEmpty {
          Menu(every ? "Category for every \(merchantName(push))" : "Category for this payment") {
            ForEach(feed.categories, id: \.self) { name in
              Button {
                setCategory(name, of: push, everyPayment: every)
              } label: {
                if name == push.shownCategory { Label(name.capitalized, systemImage: "checkmark") } else { Text(name.capitalized) }
              }
            }
            Divider()
            Button("New category…") {
              newCategory = ""
              naming = Naming(push: push, everyPayment: every)
            }
          }
        }
      }
      Button("Fix amount…") {
        amountText = String(Int((push.kzt ?? 0).rounded()))
        fixing = push
      }
      Divider()
      if push.isHidden {
        Button("Unhide") { if let id = push.id { feed.apply?(.unhide(id: id)) } }
      } else {
        Button("Hide", role: .destructive) { if let id = push.id { feed.apply?(.hide(id: id)) } }
      }
    }
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
        HStack(spacing: 4) {
          if push.isEdited {
            Image(systemName: "pencil").font(.caption2).foregroundStyle(.secondary).help("Corrected in the app")
          }
          Text(Money.tenge(push.kzt ?? 0)).monospacedDigit()
            .strikethrough(push.isHidden)
            .foregroundStyle((push.kzt ?? 0) < 0 ? .green : .primary)
        }
        if let original = Money.original(push) {
          Text(original).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
      }
    }
    .padding(.vertical, 2)
    .opacity(push.isHidden ? 0.45 : 1)
    .contentShape(Rectangle())
    .contextMenu { corrections(push) }
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

/// Lays its children out in rows, wrapping to the next row when one is full: the category chips,
/// which must not scroll on their own.
struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = rows(for: subviews, width: proposal.width ?? .infinity)
    let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
    let width = rows.map(\.width).max() ?? 0
    return CGSize(width: proposal.width ?? width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for row in rows(for: subviews, width: bounds.width) {
      var x = bounds.minX
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  private struct Row {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
    var rows: [Row] = [Row()]
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
      if needed > width && !rows[rows.count - 1].indices.isEmpty {
        rows.append(Row())
      }
      var row = rows[rows.count - 1]
      row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
      row.height = max(row.height, size.height)
      row.indices.append(index)
      rows[rows.count - 1] = row
    }
    return rows.filter { !$0.indices.isEmpty }
  }
}
