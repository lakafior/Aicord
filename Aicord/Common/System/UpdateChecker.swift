//
//  UpdateChecker.swift
//  Aicord
//
//  Asks GitHub for the newest release, at most once a day, and shows a banner.
//

import SwiftUI

/// Checks `releases/latest` of the Aicord repository on launch, at most once a
/// day. No token: the public API allows 60 requests an hour per address. Until
/// the first release is published the API answers 404, which means "nothing new".
@MainActor @Observable
final class UpdateChecker {
  static let shared = UpdateChecker()

  static let enabledKey = "Aicord.Updates.Enabled"
  private static let lastCheckKey = "Aicord.Updates.LastCheck"
  private static let dismissedKey = "Aicord.Updates.Dismissed"
  static let latestURL = URL(
    string: "https://api.github.com/repos/lakafior/Aicord/releases/latest")!

  struct Release: Decodable, Equatable {
    var tag_name: String
    var name: String?
    var html_url: URL
    var draft: Bool?
    var prerelease: Bool?

    /// `v0.2.0` → `0.2.0`
    var version: String {
      tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name
    }
  }

  /// A release newer than this build, which the user hasn't dismissed.
  private(set) var available: Release?
  private(set) var lastResult: String?

  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
  }

  static var currentVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
  }

  /// On launch: skip when switched off or checked less than a day ago.
  func checkOnLaunch() async {
    guard Self.isEnabled else { return }
    let defaults = UserDefaults.standard
    if let last = defaults.object(forKey: Self.lastCheckKey) as? Date,
      Date.now.timeIntervalSince(last) < 24 * 3_600
    {
      return
    }
    await check()
  }

  /// One request; any failure only means no banner.
  func check() async {
    UserDefaults.standard.set(Date.now, forKey: Self.lastCheckKey)
    var request = URLRequest(url: Self.latestURL)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("Aicord/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 15
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      guard status == 200 else {
        // 404: no release published yet
        lastResult = status == 404
          ? String(localized: "No releases published yet.")
          : String(localized: "GitHub answered with status \(status).")
        available = nil
        return
      }
      let release = try JSONDecoder().decode(Release.self, from: data)
      guard release.draft != true, release.prerelease != true,
        Self.isNewer(release.version, than: Self.currentVersion)
      else {
        lastResult = String(localized: "Aicord is up to date.")
        available = nil
        return
      }
      lastResult = String(localized: "Aicord \(release.version) is available.")
      let dismissed = UserDefaults.standard.string(forKey: Self.dismissedKey)
      available = dismissed == release.tag_name ? nil : release
    } catch {
      lastResult = error.localizedDescription
    }
  }

  func dismiss() {
    guard let available else { return }
    UserDefaults.standard.set(available.tag_name, forKey: Self.dismissedKey)
    self.available = nil
  }

  /// Compares dotted versions numerically: 0.10.0 is newer than 0.9.1.
  nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
    func parts(_ version: String) -> [Int] {
      version.split(separator: "-").first.map {
        $0.split(separator: ".").map { Int($0) ?? 0 }
      } ?? []
    }
    let a = parts(candidate)
    let b = parts(current)
    for i in 0..<max(a.count, b.count) {
      let x = i < a.count ? a[i] : 0
      let y = i < b.count ? b[i] : 0
      if x != y { return x > y }
    }
    return false
  }
}

/// A small banner at the top while a newer release is waiting.
struct UpdateBanner: View {
  @State private var checker = UpdateChecker.shared
  @Environment(\.openURL) private var openURL

  var body: some View {
    if let release = checker.available {
      HStack(spacing: 10) {
        Image(systemName: "arrow.down.circle.fill")
          .foregroundStyle(.tint)
        Text("Aicord \(release.version) is available")
          .font(.subheadline.weight(.medium))
        Button("Download") { openURL(release.html_url) }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
        Button {
          checker.dismiss()
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Dismiss")
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .glassEffect(.regular, in: .capsule)
      .padding(.top, 6)
      .transition(.move(edge: .top).combined(with: .opacity))
    }
  }
}
