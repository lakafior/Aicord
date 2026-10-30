//
//  AboutSection.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 15/11/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import SwiftUI

extension SettingsView {
  static let repositoryURL = URL(string: "https://github.com/lakafior/Aicord")!
  static let licenseURL = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!
  static let upstreamURL = URL(string: "https://github.com/llsc12/Paicord")!

  @ViewBuilder
  var aboutSection: some View {
    Section {
      HStack(spacing: 16) {
        #if os(macOS)
          Image(nsImage: NSImage(named: "AppIcon")!)
            .resizable()
            .scaledToFit()
            .frame(width: 72, height: 72)
        #else
          Image(uiImage: UIImage(named: "AppIcon")!)
            .resizable()
            .scaledToFit()
            .frame(width: 72, height: 72)
        #endif
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: "Aicord")
            .font(.title)
            .bold()
          Text(
            "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"))"
          )
          .foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, 4)
    }

    Section {
      Link(destination: Self.repositoryURL) {
        Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
      }
      Link(destination: Self.licenseURL) {
        LabeledContent {
          Text(verbatim: "GPL-3.0")
        } label: {
          Label("License", systemImage: "doc.text")
        }
      }
    } footer: {
      Text("Aicord is a fork of [Paicord](\(Self.upstreamURL.absoluteString)) by llsc12.")
    }
  }
}
