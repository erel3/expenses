@testable import ExpensesCore
import Foundation

// swiftlint:disable line_length
// Fixture lines stay one JSON line each, exactly as the phone writes them.

/// payments.json lines in the shapes the phone writes, with no real data: balances 1 ₸, cards
/// **0000, invoice numbers zeroed. Almaty time (+05:00).
enum Fixtures {
  static let lines = [
    #"{"time":"2026-11-20T19:41:25+05:00","app":"Kaspi.kz","body":"Покупка: 5 572,22 ₸\nWOLT.COM\nДоступно: 1 ₸","title":"Kaspi Gold","subtitle":""}"#,
    #"{"time":"2026-11-20T21:03:24+05:00","app":"Kaspi.kz","body":"Отмена покупки: 204,50 ₸\nWOLT.COM\nДоступно: 1 ₸","title":"Kaspi Gold","subtitle":""}"#,
    #"{"time":"2026-11-20T22:14:25+05:00","app":"Kaspi.kz","body":"Покупка: 95,88 $ (43 674,30 ₸)\nFACEIT\nДоступно: 1 ₸","title":"Kaspi Gold","subtitle":""}"#,
    #"{"time":"2026-11-21T13:58:00+05:00","app":"Kaspi.kz","body":"Покупка: 3 210 ₸\nYANDEX.GO\nДоступно: 1 ₸","title":"Kaspi Gold","subtitle":""}"#,
    #"{"time":"2026-11-23T12:19:39+05:00","app":"Freedom","body":"-18 078 ₸\nДоступно 1 ₸\nСписано с Deposit Card **0000","title":"Списана сумма за заказ Arbuz.kz","subtitle":""}"#,
    #"{"time":"2026-11-23T12:19:40+05:00","app":"Freedom","body":"-18 078 ₸\nДоступно 1 ₸\nСписано с Deposit Card **0000","title":"Списана сумма за заказ Arbuz.kz","subtitle":""}"#,
    #"{"time":"2026-11-23T12:19:42+05:00","app":"Freedom","body":"+1 807,8 ₸\nARBUZ","title":"Кешбэк за покупку","subtitle":""}"#,
    #"{"time":"2026-11-23T13:00:00+05:00","probe":true}"#,
    #"{"time":"2026-11-24T12:39:00+05:00","app":"Kaspi.kz","body":"Покупка: 12 722 ₸\nSOME SHOP\nДоступно: 1 ₸","title":"Kaspi Gold","subtitle":""}"#,
    #"{"time":"2026-10-31T23:59:00+05:00","app":"Kaspi.kz","body":"Покупка: 1 000 ₸\nYANDEX.GO\nДоступно: 1 ₸","title":"Kaspi Gold","subtitle":""}"#,
    #"{"time":"2026-11-21T13:27:00+05:00","app":"Halyk","body":"Tickets are on sale now.","title":"Presale is live","subtitle":""}"#
  ]

  static var text: String { lines.joined(separator: "\n") + "\n" }

  /// The parse.js the app ships: the workspace's expenses-capture checkout.
  static var parseJS: URL {
    URL(filePath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()  // repo root
      .deletingLastPathComponent()  // workspace
      .appending(path: "expenses-capture/parse.js")
  }

  static var almaty: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Almaty")!
    return calendar
  }

  static func date(_ text: String) -> Date { Push.parseTime(text)! }
}
// swiftlint:enable line_length
