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

  public init(time: String, app: String, title: String, subtitle: String? = nil, body: String,
              amount: Double? = nil, currency: String? = nil, kzt: Double? = nil,
              merchant: String? = nil, category: String? = nil, error: String? = nil) {
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
  }

  /// A payment is a push a parser understood; everything else (ads, transfers, failed attempts,
  /// formats nobody has a parser for yet) is a raw push.
  public var isPayment: Bool { amount != nil }

  /// `time` carries the phone's offset ("2026-11-20T16:19:56+05:00"); nil for an unreadable line.
  public var date: Date? { Push.parseTime(time) }

  /// The category to show and group by: parse.js leaves unknown merchants with "".
  public var shownCategory: String { (category ?? "").isEmpty ? "other" : category! }

  public static func parseTime(_ text: String) -> Date? {
    try? Date(text, strategy: .iso8601)
  }
}
