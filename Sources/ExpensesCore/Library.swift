import Foundation

/// The texts parse.js is given: every data file joined, every edits file joined.
public struct Loaded: Equatable, Sendable {
  public let data: String
  public let edits: String
}

/// Reading the iCloud files the same way on the Mac and the iPhone: coordinated reads (iCloud may
/// be replacing a file at that moment), evicted files asked for first. Never writes.
public enum Library {
  public static func load(_ files: ICloud.Files, presenter: NSFilePresenter? = nil) throws -> Loaded {
    func read(_ urls: [URL]) throws -> String {
      try urls.map { url in
        // A file "Optimize Mac Storage" (or iOS) evicted is only a placeholder until asked for.
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        do {
          return try coordinatedRead(url, presenter: presenter)
        } catch {
          throw LibraryError("Cannot read \(url.lastPathComponent): \(error.localizedDescription)")
        }
      }.joined(separator: "\n")
    }
    return Loaded(data: try read(files.data), edits: try read(files.edits))
  }

  public static func coordinatedRead(_ file: URL, presenter: NSFilePresenter? = nil) throws -> String {
    var result: Result<String, Error> = .failure(CocoaError(.fileReadUnknown))
    var coordination: NSError?
    NSFileCoordinator(filePresenter: presenter).coordinate(readingItemAt: file, options: [], error: &coordination) { url in
      result = Result { try String(contentsOf: url, encoding: .utf8) }
    }
    if let coordination { throw coordination }
    return try result.get()
  }
}

public struct LibraryError: LocalizedError {
  public let errorDescription: String?
  public init(_ message: String) { errorDescription = message }
}
