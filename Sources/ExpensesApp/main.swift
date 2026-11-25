import AppKit
import ExpensesCore

// `Expenses --import a.pdf b.pdf`: Kaspi Gold statements into the Expenses folder, no window, then
// exit (the first bulk import; the window's gear menu does the same one at a time).
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--import" {
  do {
    let parser = try Parser()
    for path in arguments.dropFirst() {
      let pdf = URL(filePath: path)
      do {
        let result = try StatementImport.run(pdf, parser: parser, into: ICloud.expenses())
        print("\(pdf.lastPathComponent): \(result.rows) rows, \(result.from) to \(result.to) -> \(result.file.lastPathComponent)")
      } catch {
        print("\(pdf.lastPathComponent): \(error.localizedDescription)")
      }
    }
    exit(0)
  } catch {
    print("\(error)")
    exit(1)
  }
}

// Background app (LSUIElement): no Dock icon while it only feeds the widget. Opening it from
// Finder or Spotlight shows the payments window, and the Dock icon with it.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
