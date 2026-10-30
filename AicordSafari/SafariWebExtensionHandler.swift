//
//  SafariWebExtensionHandler.swift
//  AicordSafari
//
//  Copyright © 2026 Lakhan Lothiyi.
//

import SafariServices

/// The extension only runs its content script; native messages get an empty reply.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
  func beginRequest(with context: NSExtensionContext) {
    context.completeRequest(returningItems: [NSExtensionItem()], completionHandler: nil)
  }
}
