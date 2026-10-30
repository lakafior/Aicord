//
//  ScamWarning.swift
//  Aicord
//
//  A warning over a direct message conversation with someone who isn't a
//  friend, when their messages look like a known scam. Checked on the device
//  without a language model; nothing is sent anywhere.
//

import AicordKit
import SwiftUI

struct ScamWarningBanner: View {
  @Environment(\.gateway) var gw
  var vm: ChannelStore

  @AppStorage(IntelligencePreferences.Key.scamWarnings) private var enabled = true
  @State private var dismissed = false

  var body: some View {
    if enabled, !dismissed, let kinds = signals, !kinds.isEmpty {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "exclamationmark.shield.fill")
          .font(.title3)
          .foregroundStyle(.orange)
        VStack(alignment: .leading, spacing: 4) {
          Text("This may be a scam")
            .font(.subheadline.weight(.semibold))
          Text(Self.reason(kinds.first!))
            .font(.caption)
            .foregroundStyle(.secondary)
          Text("Discord never asks for your password or codes, and won't send you here.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        Button {
          withAnimation { dismissed = true }
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Dismiss Warning")
      }
      .padding(12)
      .glassEffect(.regular, in: .rect(cornerRadius: 16))
      .padding(.horizontal)
      .padding(.top, 6)
    }
  }

  /// Signals in the other person's recent messages, for DMs with non-friends only.
  private var signals: [ScamSignals.Kind]? {
    guard let channel = vm.channel, channel.type == .dm,
      let other = channel.recipients?.first,
      gw.user.relationships[other.id]?.type != .friend
    else { return nil }
    var found: [ScamSignals.Kind] = []
    for message in vm.messages.values.suffix(30) where message.author?.id == other.id {
      for kind in ScamSignals.check(message.content) where !found.contains(kind) {
        found.append(kind)
      }
    }
    return found
  }

  static func reason(_ kind: ScamSignals.Kind) -> LocalizedStringKey {
    switch kind {
    case .lookalikeLink: "A link here imitates Discord or Steam."
    case .fakeNitro: "Free Nitro offered through a link is a common scam."
    case .accidentalReport:
      "“I reported you by accident” is a known scam to take over accounts."
    case .fakeGift: "Free Steam gifts through a link are a common scam."
    case .credentialRequest: "Someone is asking for a password, a code or a QR scan."
    }
  }
}
