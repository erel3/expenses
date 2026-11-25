import Foundation

public enum Version {
  /// "0.2.0" > "0.1.10" > "0.1.9"; a leading "v" is ignored, a missing part counts as 0.
  public static func isNewer(_ remote: String, than local: String) -> Bool {
    func parts(_ version: String) -> [Int] {
      version.trimmingCharacters(in: CharacterSet(charactersIn: "v")).split(separator: ".").map { Int($0) ?? 0 }
    }
    let lhs = parts(remote), rhs = parts(local)
    for index in 0..<max(lhs.count, rhs.count) {
      let left = index < lhs.count ? lhs[index] : 0, right = index < rhs.count ? rhs[index] : 0
      if left != right { return left > right }
    }
    return false
  }
}
