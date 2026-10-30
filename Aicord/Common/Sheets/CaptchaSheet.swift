//
//  CaptchaSheet.swift
//  PaiCord
//
//  Created by Lakhan Lothiyi on 10/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI
import WebKit

#if os(iOS)
  private typealias ViewControllerRepresentable = UIViewControllerRepresentable
#elseif os(macOS)
  private typealias ViewControllerRepresentable = NSViewControllerRepresentable
#endif

struct CaptchaSheet: ViewControllerRepresentable {
  let challenge: CaptchaChallengeData
  let onToken: (CaptchaSubmitData?) -> Void

  @Environment(\.colorScheme) private var colorScheme

  func makeCoordinator() -> Coordinator {
    Coordinator(challenge: challenge, onToken: onToken)
  }

  #if os(iOS)
    func makeUIViewController(context: Context) -> UIViewController {
      let controller = UIViewController()
      controller.view.backgroundColor = .clear
      let webView = context.coordinator.makeWebView(
        theme: colorScheme == .dark ? "dark" : "light"
      )
      webView.translatesAutoresizingMaskIntoConstraints = false
      controller.view.addSubview(webView)
      NSLayoutConstraint.activate([
        webView.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
        webView.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
        webView.topAnchor.constraint(equalTo: controller.view.topAnchor),
        webView.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
      ])
      return controller
    }

    func updateUIViewController(
      _ uiViewController: UIViewController,
      context: Context
    ) {}
  #else
    func makeNSViewController(context: Context) -> NSViewController {
      let controller = NSViewController()
      let rootView = NSView()
      rootView.wantsLayer = true
      rootView.layer?.backgroundColor = .clear
      controller.view = rootView

      let webView = context.coordinator.makeWebView(
        theme: colorScheme == .dark ? "dark" : "light"
      )
      webView.translatesAutoresizingMaskIntoConstraints = false
      rootView.addSubview(webView)
      NSLayoutConstraint.activate([
        webView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
        webView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
        webView.topAnchor.constraint(equalTo: rootView.topAnchor),
        webView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
      ])
      return controller
    }

    func updateNSViewController(
      _ nsViewController: NSViewController,
      context: Context
    ) {}
  #endif

  final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let challenge: CaptchaChallengeData
    let onToken: (CaptchaSubmitData?) -> Void
    private weak var webView: WKWebView?
    private var didFinish = false

    init(
      challenge: CaptchaChallengeData,
      onToken: @escaping (CaptchaSubmitData?) -> Void
    ) {
      self.challenge = challenge
      self.onToken = onToken
    }

    func makeWebView(theme: String) -> WKWebView {
      let contentController = WKUserContentController()
      contentController.add(self, name: "hcaptcha")

      let config = WKWebViewConfiguration()
      config.userContentController = contentController
      config.websiteDataStore = .nonPersistent()

      let webView = WKWebView(frame: .zero, configuration: config)
      webView.navigationDelegate = self
      #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
      #else
        webView.setValue(false, forKey: "drawsBackground")
      #endif
      self.webView = webView

      guard let siteKey = challenge.captchaSiteKey else {
        DispatchQueue.main.async { [onToken] in onToken(nil) }
        return webView
      }

      let html = Self.buildHTML(
        siteKey: siteKey,
        rqdata: challenge.captchaRqdata,
        theme: theme
      )
      let baseURL = URL(string: "https://\(siteKey).react-native.hcaptcha.com")
        ?? URL(string: "https://discord.com")!
      webView.loadHTMLString(html, baseURL: baseURL)
      return webView
    }

    func userContentController(
      _ userContentController: WKUserContentController,
      didReceive message: WKScriptMessage
    ) {
      guard !didFinish, let body = message.body as? [String: Any] else { return }

      if let token = body["token"] as? String, !token.isEmpty {
        didFinish = true
        userContentController.removeScriptMessageHandler(forName: "hcaptcha")
        onToken(CaptchaSubmitData(challenge: challenge, token: token))
      } else if body["error"] != nil {
        didFinish = true
        userContentController.removeScriptMessageHandler(forName: "hcaptcha")
        onToken(nil)
      }
    }

    private static func buildHTML(
      siteKey: String,
      rqdata: String?,
      theme: String
    ) -> String {
      let configDict: [String: String] = [
        "sitekey": siteKey,
        "rqdata": rqdata ?? "",
        "theme": theme,
      ]
      let configJSON =
        (try? JSONSerialization.data(withJSONObject: configDict))
        .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

      return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no"/>
          <style>
            * { box-sizing: border-box; margin: 0; padding: 0; }
            html, body {
              width: 100%;
              height: 100%;
              background: transparent;
              display: flex;
              align-items: center;
              justify-content: center;
            }
          </style>
          <script type="text/javascript">
            const config = \(configJSON);
            function post(payload) {
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.hcaptcha) {
                window.webkit.messageHandlers.hcaptcha.postMessage(payload);
              }
            }
            window.onHCaptchaLoad = function() {
              try {
                const widgetId = window.hcaptcha.render("hcaptcha-container", {
                  sitekey: config.sitekey,
                  theme: config.theme || "dark",
                  size: "invisible",
                  callback: function(token) {
                    post({ token: token });
                  },
                  "error-callback": function(err) {
                    post({ error: String(err || "error") });
                  },
                  "close-callback": function() {
                    post({ error: "closed" });
                  },
                  "expired-callback": function() {
                    post({ error: "expired" });
                  },
                  "chalexpired-callback": function() {
                    post({ error: "chalexpired" });
                  }
                });
                if (config.rqdata && config.rqdata.length > 0) {
                  window.hcaptcha.setData(widgetId, { rqdata: config.rqdata });
                }
                window.hcaptcha.execute(widgetId);
              } catch (e) {
                post({ error: String(e) });
              }
            };
          </script>
          <script src="https://js.hcaptcha.com/1/api.js?onload=onHCaptchaLoad&render=explicit&recaptchacompat=off&host=\(siteKey).react-native.hcaptcha.com" async defer onerror="post({ error: 'network' })"></script>
        </head>
        <body>
          <div id="hcaptcha-container"></div>
        </body>
        </html>
        """
    }
  }
}
