//
//  ComposerPreferences.swift
//  Aicord
//
//  Local options for what happens to what you type and attach: when the
//  typing indicator is sent, link cleaning, private file names, splitting
//  long messages, the upload service for large files and emoji and stickers
//  without Nitro. Only on this device.
//

import AicordKit
import Foundation
import UniformTypeIdentifiers

enum ComposerPreferences {
  enum Key {
    static let typingIndicator = "Aicord.Composer.TypingIndicator"
    static let cleansLinks = "Aicord.Composer.CleansLinks"
    static let disabledLinkRules = "Aicord.Composer.DisabledLinkRules"
    static let privateFilenames = "Aicord.Composer.PrivateFilenames"
    static let stripsPhotoMetadata = "Aicord.Composer.StripsPhotoMetadata"
    static let splitsLongMessages = "Aicord.Composer.SplitsLongMessages"
    static let uploadService = "Aicord.Composer.UploadService"
    static let litterboxExpiry = "Aicord.Composer.LitterboxExpiry"
    static let s3Bucket = "Aicord.Composer.S3Bucket"
    static let nitroFreeEmoji = "Aicord.Composer.NitroFreeEmoji"
    static let nitroFreeStickers = "Aicord.Composer.NitroFreeStickers"
  }

  enum TypingIndicator: String, CaseIterable, Identifiable {
    case always, directMessagesOnly, never
    var id: String { rawValue }
  }

  enum UploadServiceKind: String, CaseIterable, Identifiable {
    case none, catbox, litterbox, s3
    var id: String { rawValue }
  }

  private static var defaults: UserDefaults { .standard }

  static var typingIndicator: TypingIndicator {
    defaults.string(forKey: Key.typingIndicator).flatMap(TypingIndicator.init) ?? .always
  }

  /// On unless turned off.
  static var cleansLinks: Bool {
    defaults.object(forKey: Key.cleansLinks) as? Bool ?? true
  }

  /// The link rules in force: every rule except the ones turned off.
  static var enabledLinkRules: Set<String> {
    LinkCleaner.defaultRuleIDs.subtracting(disabledLinkRules)
  }

  static var disabledLinkRules: Set<String> {
    get {
      Set((defaults.string(forKey: Key.disabledLinkRules) ?? "").split(separator: ",").map(String.init))
    }
    set { defaults.set(newValue.sorted().joined(separator: ","), forKey: Key.disabledLinkRules) }
  }

  static var privateFilenames: Bool { defaults.bool(forKey: Key.privateFilenames) }
  static var stripsPhotoMetadata: Bool { defaults.bool(forKey: Key.stripsPhotoMetadata) }

  /// On unless turned off; Discord would refuse the message otherwise.
  static var splitsLongMessages: Bool {
    defaults.object(forKey: Key.splitsLongMessages) as? Bool ?? true
  }

  static var nitroFreeEmoji: Bool { defaults.bool(forKey: Key.nitroFreeEmoji) }
  static var nitroFreeStickers: Bool { defaults.bool(forKey: Key.nitroFreeStickers) }

  // MARK: - Text

  /// Pasted text with tracking parameters taken out of its links, when that's on.
  static func cleanedPaste(_ text: String) -> String {
    guard cleansLinks else { return text }
    return LinkCleaner.clean(text: text, enabledRules: enabledLinkRules)
  }

  /// The longest message the account can send.
  static func characterLimit(for premium: DiscordUser.PremiumKind) -> Int {
    switch premium {
    case .nitro, .nitroClassic: 4000
    default: 2000
    }
  }

  // MARK: - Files

  /// The name to upload a file under: random when that's on.
  static func uploadName(for original: String) -> String {
    privateFilenames ? PrivateFilename.random(for: original) : original
  }

  /// A copy of the photo without location and camera details, or nil to send
  /// the original (the option is off, or it isn't a photo we can rewrite).
  static func strippedPhoto(_ data: Data) -> Data? {
    guard stripsPhotoMetadata else { return nil }
    return ImageMetadata.stripped(data)
  }

  /// Same for a file on disk: a stripped copy in the temporary folder.
  static func strippedPhoto(at url: URL) -> URL? {
    guard stripsPhotoMetadata,
      let type = UTType(filenameExtension: url.pathExtension), ImageMetadata.canStrip(type)
    else { return nil }
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    guard let data = try? Data(contentsOf: url), let stripped = ImageMetadata.stripped(data) else {
      return nil
    }
    let copy = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
    let file = copy.appendingPathComponent(url.lastPathComponent)
    guard (try? stripped.write(to: file)) != nil else { return nil }
    return file
  }

  // MARK: - Upload service

  static var uploadServiceKind: UploadServiceKind {
    defaults.string(forKey: Key.uploadService).flatMap(UploadServiceKind.init) ?? .none
  }

  static var litterboxExpiry: ExternalUpload.LitterboxExpiry {
    defaults.string(forKey: Key.litterboxExpiry).flatMap(ExternalUpload.LitterboxExpiry.init) ?? .day
  }

  static var s3Bucket: ExternalUpload.S3Bucket {
    get {
      defaults.data(forKey: Key.s3Bucket)
        .flatMap { try? JSONDecoder().decode(ExternalUpload.S3Bucket.self, from: $0) }
        ?? .init(endpoint: "", bucket: "", region: "auto", publicBaseURL: "")
    }
    set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.s3Bucket) }
  }

  /// The service chosen in Settings, nil when there is none or it's not set up.
  static var uploadService: ExternalUpload.Service? {
    switch uploadServiceKind {
    case .none: return nil
    case .catbox: return .catbox(userHash: UploadKeychain.value(.catboxUserHash))
    case .litterbox: return .litterbox(litterboxExpiry)
    case .s3:
      let bucket = s3Bucket
      guard bucket.isComplete,
        let id = UploadKeychain.value(.s3AccessKeyID), !id.isEmpty,
        let secret = UploadKeychain.value(.s3SecretAccessKey), !secret.isEmpty
      else { return nil }
      return .s3(bucket, .init(accessKeyID: id, secretAccessKey: secret))
    }
  }
}

/// Upload service secrets live in this device's keychain, never in preferences.
enum UploadKeychain {
  enum Item: String {
    case catboxUserHash = "catbox-userhash"
    case s3AccessKeyID = "s3-access-key-id"
    case s3SecretAccessKey = "s3-secret-access-key"
  }

  private static let service = "net.smigi.aicord.upload"

  private static func query(_ item: Item) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: item.rawValue,
    ]
  }

  static func value(_ item: Item) -> String? {
    var request = query(item)
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func set(_ value: String, for item: Item) {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      SecItemDelete(query(item) as CFDictionary)
      return
    }
    let data = Data(trimmed.utf8)
    if SecItemUpdate(query(item) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
      == errSecSuccess
    {
      return
    }
    var add = query(item)
    add[kSecValueData as String] = data
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(add as CFDictionary, nil)
  }
}
