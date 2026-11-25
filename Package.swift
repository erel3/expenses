// swift-tools-version:6.2
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
  name: "Expenses",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "ExpensesCore", targets: ["ExpensesCore"]),
    .executable(name: "ExpensesApp", targets: ["ExpensesApp"]),
    .executable(name: "ExpensesWidget", targets: ["ExpensesWidget"])
  ],
  targets: [
    // Payments, the JavaScriptCore bridge to expenses-capture's parse.js, sums, the widget's store.
    .target(name: "ExpensesCore", path: "Sources/ExpensesCore", swiftSettings: swift6),
    // Views the app and the widget share.
    .target(name: "ExpensesUI", dependencies: ["ExpensesCore"], path: "Sources/ExpensesUI", swiftSettings: swift6),
    // The background app; `just app` wraps it and the widget into dist/Expenses.app.
    .executableTarget(
      name: "ExpensesApp",
      dependencies: ["ExpensesCore", "ExpensesUI"],
      path: "Sources/ExpensesApp",
      swiftSettings: swift6
    ),
    // The WidgetKit extension's binary. Extensions may only use extension-safe API.
    .executableTarget(
      name: "ExpensesWidget",
      dependencies: ["ExpensesCore", "ExpensesUI"],
      path: "Sources/ExpensesWidget",
      swiftSettings: swift6 + [.unsafeFlags(["-application-extension"])],
      // Xcode links every extension with entry point _NSExtensionMain: it sets up ExtensionFoundation,
      // then runs the @main Widget. Entered at main directly, the widget traps at launch (Batteries).
      linkerSettings: [.unsafeFlags(["-Xlinker", "-application_extension", "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]
    ),
    .testTarget(name: "ExpensesCoreTests", dependencies: ["ExpensesCore"], path: "Tests/ExpensesCoreTests", swiftSettings: swift6),
    .testTarget(name: "ExpensesUITests", dependencies: ["ExpensesUI"], path: "Tests/ExpensesUITests", swiftSettings: swift6)
  ]
)
