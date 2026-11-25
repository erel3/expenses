import Foundation
import JavaScriptCore

public enum ParserError: Error, CustomStringConvertible {
  case script(String)
  case result(String)

  public var description: String {
    switch self {
    case .script(let message): "parse.js: \(message)"
    case .result(let message): "reparseLines: \(message)"
    }
  }
}

/// expenses-capture's parse.js run in JavaScriptCore. The phone runs the same file inside the
/// shortcut and `just reparse` runs it in node, so all three agree on what a payment is: never
/// port a parser or the duplicate rule to Swift.
public final class Parser {
  private let context: JSContext
  private let reparseLines: JSValue
  private let categoriesFunction: JSValue

  public init(script: String) throws {
    guard let context = JSContext() else { throw ParserError.script("no JavaScript context") }
    var thrown: String?
    context.exceptionHandler = { _, value in thrown = value?.toString() }
    context.evaluateScript(script)
    if let thrown { throw ParserError.script(thrown) }
    guard let function = context.objectForKeyedSubscript("reparseLines"), !function.isUndefined else {
      throw ParserError.script("defines no reparseLines")
    }
    self.context = context
    self.reparseLines = function
    self.categoriesFunction = context.objectForKeyedSubscript("categories")
  }

  /// The parse.js `just app` copies into the bundle's Resources.
  public convenience init(bundle: Bundle = .main) throws {
    guard let url = bundle.url(forResource: "parse", withExtension: "js") else {
      throw ParserError.script("not in the app bundle")
    }
    try self.init(script: String(contentsOf: url, encoding: .utf8))
  }

  /// Every data file's text joined -> every push, oldest first, probes and repeats dropped, the
  /// corrections in `edits` (every edits file's text joined) applied.
  public func reparse(_ text: String, edits: String = "") throws -> [Push] {
    var thrown: String?
    context.exceptionHandler = { _, value in thrown = value?.toString() }
    let result = reparseLines.call(withArguments: [text, edits])
    let json = context.objectForKeyedSubscript("JSON").invokeMethod("stringify", withArguments: [result as Any])
    if let thrown { throw ParserError.result(thrown) }
    guard let json, json.isString, let data = json.toString().data(using: .utf8) else {
      throw ParserError.result("no JSON came back")
    }
    return try JSONDecoder().decode([Push].self, from: data)
  }

  /// Every category in use: parse.js's table, the ones corrections gave, then "other".
  public func categories(edits: String = "") -> [String] {
    categoriesFunction.call(withArguments: [edits])?.toArray()?.compactMap { $0 as? String } ?? ["other"]
  }
}
