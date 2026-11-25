import Foundation

/// One line of payments.json as expenses-capture's `reparseLines` returns it: the push as received
/// plus, for a payment, the parsed fields. Fields the app does not use are ignored when decoding.
public struct Push: Codable, Hashable, Sendable {
  public var time: String
  public var app: String
  public var title: String
  public var subtitle: String?
  public var body: String
  /// What the payment cost in `currency`: positive for a purchase, negative for a refund.
  public var amount: Double?
  public var currency: String?
  /// The amount in tenge: the amount itself for a tenge payment, the bank's conversion otherwise,
  /// absent when the bank printed none.
  public var kzt: Double?
  public var merchant: String?
  /// "" when parse.js has no category for the merchant.
  public var category: String?
  public var error: String?
  /// A hash of what was received (parse.js `pushId`): what corrections point at.
  public var id: String?
  /// Hidden by a correction: out of every total, listed only on request.
  public var hidden: Bool?
  /// What corrections changed: "category", "amount".
  public var edited: [String]?
  /// No spending, listed greyed: "income" (salary, ATM cash-in, other banks), "own" (the Kaspi
  /// Deposit and own accounts, both ways). Money from a person is no kind: a payback, counted.
  public var kind: String?
  /// A statement row: the bank gives the day, not the time (unless a push was merged into it).
  public var dateOnly: Bool?
  /// What was merged into a statement row: "Kaspi.kz" (its push), "Manual".
  public var merged: [String]?
  /// A statement row's operation: "Покупка", "Перевод", "Разное", "Снятие"…
  public var operation: String?
  /// A transfer to someone: "My own account" applies to these.
  public var transfer: Bool?

  public init(time: String, app: String, title: String, subtitle: String? = nil, body: String,
              amount: Double? = nil, currency: String? = nil, kzt: Double? = nil,
              merchant: String? = nil, category: String? = nil, error: String? = nil,
              id: String? = nil, hidden: Bool? = nil, edited: [String]? = nil, kind: String? = nil,
              dateOnly: Bool? = nil) {
    self.time = time
    self.app = app
    self.title = title
    self.subtitle = subtitle
    self.body = body
    self.amount = amount
    self.currency = currency
    self.kzt = kzt
    self.merchant = merchant
    self.category = category
    self.error = error
    self.id = id
    self.hidden = hidden
    self.edited = edited
    self.kind = kind
    self.dateOnly = dateOnly
  }

  public var isStatement: Bool { app == "Kaspi statement" }
  public var isDateOnly: Bool { dateOnly == true }

  public var isHidden: Bool { hidden == true }
  public var isEdited: Bool { !(edited ?? []).isEmpty }

  /// A payment is a push a parser understood; everything else (ads, transfers, failed attempts,
  /// formats nobody has a parser for yet) is a raw push.
  public var isPayment: Bool { amount != nil && kind == nil }
  /// Listed greyed, never counted: salary, other banks, own accounts and the Kaspi Deposit.
  public var isNotSpending: Bool { amount != nil && kind != nil }

  /// `time` carries the phone's offset ("2026-11-20T16:19:56+05:00"); nil for an unreadable line.
  public var date: Date? { Push.parseTime(time) }

  /// The category to show and group by: parse.js leaves unknown merchants with "".
  public var shownCategory: String { (category ?? "").isEmpty ? "other" : category! }

  public static func parseTime(_ text: String) -> Date? {
    try? Date(text, strategy: .iso8601)
  }
}
