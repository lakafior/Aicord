import Foundation

extension Array where Element == (String, String?) {
  public func makeForURLQuery() -> String {
    self.compactMap { key, value in
      value.map { (key, $0) }
    }.makeForURLQuery()
  }
}

extension Array where Element == (String, String) {
  public func makeForURLQuery() -> String {
    if self.isEmpty {
      return ""
    } else {
      return "?"
        + self.compactMap { key, value -> String? in
          let value =
            value.addingPercentEncoding(
              withAllowedCharacters: .urlQueryValueAllowed
            ) ?? value
          return "\(key)=\(value)"
        }.joined(separator: "&")
    }
  }
}

extension CharacterSet {
  /// `.urlQueryAllowed` minus the characters that split query items (`&`, `=`, `+`, `#`),
  /// so a search like "a&b" stays one value.
  static let urlQueryValueAllowed: CharacterSet = {
    var set = CharacterSet.urlQueryAllowed
    set.remove(charactersIn: "&=+#")
    return set
  }()
}
