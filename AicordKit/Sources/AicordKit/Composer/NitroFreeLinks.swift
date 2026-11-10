//
//  NitroFreeLinks.swift
//  AicordKit
//
//  Emoji and stickers the account can't send, as plain links to Discord's
//  CDN. Discord shows the image under the message. This works around a paid
//  feature, so the app keeps it off unless the user turns it on.
//

import Foundation

public enum NitroFreeLinks {
  /// A custom emoji at chat size, e.g.
  /// `https://cdn.discordapp.com/emojis/123.webp?size=48&name=pog&quality=lossless`.
  public static func emoji(id: String, name: String?, animated: Bool, size: Int = 48) -> String {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "cdn.discordapp.com"
    components.path = "/emojis/\(id).\(animated ? "gif" : "webp")"
    var items = [URLQueryItem(name: "size", value: String(size))]
    if let name, !name.isEmpty { items.append(URLQueryItem(name: "name", value: name)) }
    if !animated { items.append(URLQueryItem(name: "quality", value: "lossless")) }
    components.queryItems = items
    return components.string!
  }

  /// A sticker's file; nil for Lottie stickers, which have no image to link.
  public static func sticker(id: String, format: Sticker.FormatKind, size: Int = 160) -> String? {
    let ext: String
    switch format {
    case .png, .apng: ext = "png"
    case .gif: ext = "gif"
    default: return nil
    }
    return "https://media.discordapp.net/stickers/\(id).\(ext)?size=\(size)"
  }
}
