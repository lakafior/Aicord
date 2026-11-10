//
//  LinkCleaner.swift
//  AicordKit
//
//  Removes tracking parameters from links pasted into the composer
//  (utm_*, fbclid, YouTube's and Spotify's si…). Only the query is touched;
//  the path, fragment and every other parameter stay as they were.
//

import Foundation

public enum LinkCleaner {
  /// A group of parameters removed together, shown as one switch in Settings.
  public struct Rule: Sendable, Identifiable, Equatable {
    public let id: String
    /// Shown in Settings.
    public let name: String
    /// Hosts this rule applies to (a host and its subdomains); empty for every host.
    public let hosts: [String]
    /// Parameter names; a trailing `*` matches every name with that prefix.
    public let parameters: [String]

    public init(id: String, name: String, hosts: [String] = [], parameters: [String]) {
      self.id = id
      self.name = name
      self.hosts = hosts
      self.parameters = parameters
    }

    func applies(to host: String) -> Bool {
      guard !hosts.isEmpty else { return true }
      let host = host.lowercased()
      return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    func matches(parameter name: String) -> Bool {
      let name = name.lowercased()
      return parameters.contains { pattern in
        pattern.hasSuffix("*")
          ? name.hasPrefix(pattern.dropLast())
          : name == pattern
      }
    }
  }

  public static let rules: [Rule] = [
    Rule(
      id: "utm", name: "Campaign tags (utm_…)",
      parameters: ["utm_*", "mtm_*", "pk_campaign", "pk_kwd", "pk_source", "pk_medium"]),
    Rule(
      id: "ads", name: "Ad click IDs (fbclid, gclid…)",
      parameters: [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid",
        "twclid", "ttclid", "li_fat_id", "epik", "rdt_cid", "srsltid",
      ]),
    Rule(
      id: "mail", name: "Newsletter tracking (Mailchimp, HubSpot…)",
      parameters: [
        "mc_cid", "mc_eid", "_hsenc", "_hsmi", "__hssc", "__hstc", "__hsfp", "hsctatracking",
        "mkt_tok", "oly_anon_id", "oly_enc_id", "vero_id", "_kx", "ck_subscriber_id",
      ]),
    Rule(
      id: "youtube", name: "YouTube share IDs (si, pp, feature)",
      hosts: ["youtube.com", "youtu.be", "youtube-nocookie.com"],
      parameters: ["si", "pp", "feature", "embeds_referring_euri", "source_ve_path"]),
    Rule(
      id: "spotify", name: "Spotify share IDs (si, context)",
      hosts: ["spotify.com", "spotify.link"],
      parameters: ["si", "context", "nd", "dlsi", "utm_*"]),
    Rule(
      id: "instagram", name: "Instagram and Threads share IDs",
      hosts: ["instagram.com", "threads.net", "threads.com"],
      parameters: ["igsh", "igshid", "img_index"]),
    Rule(
      id: "x", name: "X and Twitter share IDs (s, t)",
      hosts: ["twitter.com", "x.com", "fxtwitter.com", "vxtwitter.com", "fixupx.com"],
      parameters: ["s", "t", "ref_src", "ref_url"]),
    Rule(
      id: "tiktok", name: "TikTok share IDs",
      hosts: ["tiktok.com"],
      parameters: [
        "_r", "_t", "is_from_webapp", "sender_device", "sender_web_id", "share_app_id",
        "share_item_id", "share_link_id", "social_sharing", "tt_from", "u_code", "web_id",
      ]),
    Rule(
      id: "amazon", name: "Amazon referral tags",
      hosts: [
        "amazon.com", "amazon.de", "amazon.pl", "amazon.co.uk", "amazon.fr", "amazon.it",
        "amazon.es", "amazon.nl", "amazon.se", "amazon.ca", "amazon.co.jp",
      ],
      parameters: ["tag", "ref", "ref_", "pd_rd_*", "pf_rd_*", "psc", "content-id", "linkcode", "creative", "camp"]),
    Rule(
      id: "reddit", name: "Reddit share IDs",
      hosts: ["reddit.com", "redd.it"],
      parameters: ["share_id", "rdt", "$deep_link", "$3p", "correlation_id", "post_fullname", "post_index"]),
  ]

  /// The rule IDs that are on unless the user turns them off.
  public static var defaultRuleIDs: Set<String> { Set(rules.map(\.id)) }

  /// The link without the parameters of the given rules; `nil` when nothing changed
  /// or it isn't a web link.
  public static func clean(_ url: URL, enabledRules: Set<String> = defaultRuleIDs) -> URL? {
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
      let host = url.host,
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let items = components.percentEncodedQueryItems, !items.isEmpty
    else { return nil }
    let active = rules.filter { enabledRules.contains($0.id) && $0.applies(to: host) }
    guard !active.isEmpty else { return nil }
    let kept = items.filter { item in
      let name = item.name.removingPercentEncoding ?? item.name
      return !active.contains { $0.matches(parameter: name) }
    }
    guard kept.count != items.count else { return nil }
    components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
    return components.url
  }

  /// `text` with every web link in it cleaned. Text that isn't a link is left alone.
  public static func clean(text: String, enabledRules: Set<String> = defaultRuleIDs) -> String {
    guard text.contains("?"), !enabledRules.isEmpty,
      let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    else { return text }
    let range = NSRange(text.startIndex..., in: text)
    var result = text
    // from the end, so earlier ranges stay valid
    for match in detector.matches(in: text, range: range).reversed() {
      guard let swiftRange = Range(match.range, in: text) else { continue }
      let original = String(text[swiftRange])
      // the detector adds a scheme to bare domains; only rewrite what was typed
      guard original.lowercased().hasPrefix("http"),
        let url = URL(string: original),
        let cleaned = clean(url, enabledRules: enabledRules)
      else { continue }
      if let resultRange = Range(match.range, in: result) {
        result.replaceSubrange(resultRange, with: cleaned.absoluteString)
      }
    }
    return result
  }
}
