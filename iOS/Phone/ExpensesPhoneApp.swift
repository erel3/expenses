import AppIntents
import ExpensesCore
import ExpensesUI
import SwiftUI
import UniformTypeIdentifiers

@main
struct ExpensesPhoneApp: App {
  @Environment(\.scenePhase) private var phase
  private let model = PhoneModel.shared

  var body: some Scene {
    WindowGroup {
      RootView(model: model)
        .onChange(of: phase) { _, now in
          if now == .active { model.read() }
        }
    }
  }
}

struct RootView: View {
  let model: PhoneModel
  @State private var picking = false
  @State private var importing = false
  @State private var imported: String?
  @Environment(\.openURL) private var openURL

  var body: some View {
    NavigationStack {
      Group {
        if model.needsFolder {
          ContentUnavailableView {
            Label("Choose the Shortcuts folder", systemImage: "folder")
          } description: {
            Text("Payments live in iCloud Drive → Shortcuts. Pick that folder once; Expenses only reads it.")
          } actions: {
            Button("Choose folder") { picking = true }.buttonStyle(.borderedProminent)
          }
        } else {
          PaymentsWindow(feed: model.feed) {
            Button {
              openURL(URL(string: "shortcuts://run-shortcut?name=Log%20Expense")!)
            } label: {
              Label("Add expense", systemImage: "plus")
            }
            Menu {
              Button("Import Kaspi statements…") { importing = true }
              Button("Choose another folder") { picking = true }
            } label: {
              Image(systemName: "ellipsis.circle")
            }
          }
        }
      }
      .navigationTitle("Expenses")
      .navigationBarTitleDisplayMode(.inline)
    }
    .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
      if case .success(let folder) = result { model.choose(folder) }
    }
    // A second importer on its own view: two on one view would share one presentation.
    .background(EmptyView().fileImporter(isPresented: $importing, allowedContentTypes: [.pdf],
                                         allowsMultipleSelection: true) { result in
      if case .success(let pdfs) = result, !pdfs.isEmpty { imported = model.importStatements(pdfs) }
    })
    // "Open in Expenses" from the share sheet (a statement PDF saved from Kaspi).
    .onOpenURL { url in
      if url.isFileURL, url.pathExtension.lowercased() == "pdf" { imported = model.importStatements([url]) }
    }
    .alert("Imported", isPresented: Binding(get: { imported != nil }, set: { if !$0 { imported = nil } })) {
      Button("OK") { imported = nil }
    } message: {
      Text(imported ?? "")
    }
    .refreshable { model.read() }
  }
}

/// What the shortcuts run after writing a line, so the widget shows a payment seconds later
/// without the app being opened. Runs in the background.
struct RefreshExpensesIntent: AppIntent {
  static let title: LocalizedStringResource = "Refresh Expenses"
  static let description = IntentDescription("Reads the payments again and updates the Expenses widget.")
  static let openAppWhenRun = false

  @MainActor
  func perform() async throws -> some IntentResult {
    PhoneModel.shared.read()
    return .result()
  }
}
