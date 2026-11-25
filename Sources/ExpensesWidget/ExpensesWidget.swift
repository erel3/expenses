import ExpensesCore
import ExpensesUI
import SwiftUI
import WidgetKit

// The widget never reads iCloud itself: the sandbox would not let it. It draws the payments the app
// copies into the App Group container, and works out today and this month on its own, so a new
// day or month needs no app.

struct Entry: TimelineEntry {
  let date: Date
  let payments: [Push]
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> Entry {
    let now = Date.now
    func push(_ minutesAgo: Double, _ merchant: String, _ category: String, _ kzt: Double) -> Push {
      let time = now.addingTimeInterval(-minutesAgo * 60).formatted(.iso8601.timeZone(separator: .colon))
      return Push(time: time, app: "Kaspi.kz", title: "Kaspi Gold", body: "", amount: kzt, currency: "₸",
                  kzt: kzt, merchant: merchant, category: category)
    }
    return Entry(date: now, payments: [
      push(30, "YANDEX.GO", "transport", 2480), push(90, "WOLT.COM", "food", 6567),
      push(600, "ARBUZ", "food", 18078), push(2000, "APPLE.COM/BILL", "subscriptions", 1490)
    ])
  }

  func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : current())
  }

  /// New entries come from the app when a payment arrives; on its own the widget redraws at
  /// midnight (today resets) or within an hour, whichever is first.
  func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    let entry = current()
    let midnight = Calendar.current.startOfDay(for: entry.date).addingTimeInterval(86_400 + 5)
    completion(Timeline(entries: [entry], policy: .after(min(midnight, entry.date.addingTimeInterval(3600)))))
  }

  private func current() -> Entry {
    Entry(date: .now, payments: Snapshot.load(from: Store.snapshotURL).payments)
  }
}

struct EntryView: View {
  @Environment(\.widgetFamily) private var family
  let entry: Entry

  var body: some View {
    ExpensesWidgetView(payments: entry.payments, family: family, now: entry.date)
      // Other apps' widgets cannot get macOS 27's Liquid Glass; materials and translucent colours
      // come out the same grey (Batteries, 2026-11-21). The system's own background it is.
      .containerBackground(for: .widget) { Color.clear }
  }
}

@main
struct SpendingWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "com.akim.expenses.widget", provider: Provider()) { entry in
      EntryView(entry: entry)
    }
    .configurationDisplayName("Expenses")
    .description("What was spent today and this month, by category.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
