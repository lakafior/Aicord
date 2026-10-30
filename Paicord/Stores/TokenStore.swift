//
//  AuthenticationStorage.swift
//  PaiCord
//
// Created by Lakhan Lothiyi on 01/09/2025.
// Copyright © 2025 Lakhan Lothiyi.
//

import Foundation
import AicordKit
import Security

@MainActor
@Observable
final class TokenStore {
  private static let keychainService = "net.smigi.aicord.Accounts"
  private static let currentAccountIDKey = "TokenStore.CurrentAccountID"
  private static let accountDataKey = "AccountData"

  /// If this is nil, there is no logged-in account.
  var currentAccountID: UserSnowflake? {
    get {
      access(keyPath: \.currentAccountID)
      return _currentAccountID
    }
    set {
      withMutation(keyPath: \.currentAccountID) {
        _currentAccountID = newValue
      }
    }
  }

  /// Returns the current account (if one is set)
  var currentAccount: AccountData? {
    get {
      access(keyPath: \.currentAccount)
      guard let id = currentAccountID else { return nil }
      return account(for: id)
    }
    set {
      withMutation(keyPath: \.currentAccount) {
        guard let id = newValue?.user.id else {
          currentAccountID = nil
          return
        }
        currentAccountID = id
        self.updateAccount(for: id, newValue!)
      }
    }
  }

  @ObservationIgnored
  private var _currentAccountID: UserSnowflake? {
    get {
      guard
        let str = UserDefaults.standard.string(
          forKey: Self.currentAccountIDKey)
      else { return nil }
      return UserSnowflake(str)
    }
    set {
      if let newValue = newValue {
        UserDefaults.standard.set(
          newValue.rawValue,
          forKey: Self.currentAccountIDKey
        )
      } else {
        UserDefaults.standard.removeObject(forKey: Self.currentAccountIDKey)
      }
    }
  }

  var accounts: [AccountData] {
    didSet { Self.save(accounts) }  // only works on set, not mutation i think
  }

  init() {
    accounts = Self.load()
    // safeguard against cases where keychain is empty but UserDefaults has an ID
    // this would usually softlock people.
    if accounts.count == 0 {
      currentAccountID = nil
    }
    // this one should kick user back to fallback account picker if their current account doesnt exist
    if let currentID = currentAccountID,
      accounts.first(where: { $0.user.id == currentID }) == nil
    {
      currentAccountID = nil
    }
  }

  func addAccount(token: Secret, user: DiscordUser) {
    accounts.append(AccountData(user: user, token: token))
    currentAccountID = user.id
    Self.save(accounts)
  }

  func removeAccount(_ account: AccountData) {
    accounts.removeAll { $0 == account }
    if currentAccountID == account.user.id {
      currentAccountID = nil  // push to login screen to choose an account or log in
    }
    Self.save(accounts)
  }

  func updateProfile(for id: UserSnowflake, _ data: DiscordUser) {
    guard let index = accounts.firstIndex(where: { $0.user.id == id }) else {
      return
    }
    accounts[index].user = data
  }

  func updateAccount(for id: UserSnowflake, _ account: AccountData) {
    guard let index = accounts.firstIndex(where: { $0.user.id == id }) else {
      return
    }
    accounts[index] = account
    Self.save(accounts)
  }

  func account(for id: UserSnowflake) -> AccountData? {
    accounts.first { $0.user.id == id }
  }

  // MARK: - Persistence

  private static func load() -> [AccountData] {
    let data = getKeychainData(forKey: accountDataKey) ?? Data()
    return
      Array(
        ((try? DiscordGlobalConfiguration.decoder.decode(
          [AccountData].self,
          from: data
        )) ?? []).uniqued(on: \.user.id))
  }

  private static func save(_ data: [AccountData]) {
    // dedupe via id
    let dedupedData = Array(data.uniqued(on: \.user.id))
    guard let encoded = try? DiscordGlobalConfiguration.encoder.encode(dedupedData)
    else { return }
    setKeychainData(encoded, forKey: accountDataKey)
  }

  private static func getKeychainData(forKey key: String) -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess else { return nil }
    return result as? Data
  }

  private static func setKeychainData(_ data: Data, forKey key: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: key,
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: data
    ]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var addQuery = query
      addQuery[kSecValueData as String] = data
      SecItemAdd(addQuery as CFDictionary, nil)
    }
  }

  struct AccountData: Codable, Equatable, Identifiable, Sendable {
    var id: UserSnowflake { user.id }

    var user: DiscordUser
    var token: Secret

    static func == (lhs: AccountData, rhs: AccountData) -> Bool {
      lhs.user.id == rhs.user.id
    }
  }

  // MARK: - Static Helpers
  static func getSelf(token: Secret) async throws -> DiscordUser {
    let client = await DefaultDiscordClient(authentication: .userToken(token))
    let res = try await client.getOwnUser()
    return try res.decode()
  }
}
