import Foundation
import PDFKit

/// A Kaspi Gold statement (PDF) into the Expenses folder: its text through PDFKit, its rows through
/// parse.js `parseStatement`, written as `kaspi-<from>_<to>.json`. The same statement again gives
/// the same file; overlapping ones meet through the rows' ids, and parse.js merges the pushes and
/// manual entries of the days a statement covers (the statement wins).
public enum StatementImport {
  public struct Result: Sendable {
    public let file: URL
    public let rows: Int
    public let from: String
    public let to: String
  }

  public static func text(of pdf: URL) throws -> String {
    guard let document = PDFDocument(url: pdf) else { throw LibraryError("\(pdf.lastPathComponent) is not a PDF") }
    return (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }.joined(separator: "\n")
  }

  /// Writes the statement into `folder` (the Expenses folder). Only the importing device writes it.
  public static func run(_ pdf: URL, parser: Parser, into folder: URL) throws -> Result {
    let lines = try parser.parseStatement(text(of: pdf))
    guard let header = lines.first.flatMap({ try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }),
          let from = header["from"] as? String, let to = header["to"] as? String else {
      throw LibraryError("\(pdf.lastPathComponent): no statement period")
    }
    let file = folder.appending(path: "kaspi-\(from)_\(to).json")
    var coordination: NSError?
    var failure: Error?
    NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordination) { url in
      do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
      } catch {
        failure = error
      }
    }
    if let error = coordination ?? failure { throw error }
    return Result(file: file, rows: lines.count - 1, from: from, to: to)
  }
}
