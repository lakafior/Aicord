import DiscordModels
import Logging

import struct Foundation.Data

public enum AuthenticationHeader: Sendable {
  case userToken(Secret)
  case userNone
  case none

  @inlinable
  var id: String? {
    switch self {
    case .userToken(let secret):
      return "u-\(secret.value.hash)"
    case .userNone:
      return "u"
    case .none:
      return nil
    }
  }

  /// Adds an authentication header or throws an error.
  @inlinable
  func addHeader(headers: inout HTTPHeaders, request: DiscordHTTPRequest) throws {
    switch self {
    case .userToken(let secret):
      headers.replaceOrAdd(name: "Authorization", value: secret.value)
    case .userNone, .none:
      throw DiscordHTTPError.authenticationHeaderRequired(request: request)
    }
  }

  @inlinable
  var userMode: Bool {
    switch self {
    case .userNone, .userToken: return true
    default: return false
    }
  }
}
