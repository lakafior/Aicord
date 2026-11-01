//
//  AlertSettings.swift
//  Aicord
//
//  Created by Lakafior on 01/11/2026.
//

import AicordKit
import SwiftUI

/// Aicord's own alerts in Settings → Notifications: ghost pings, keyword and
/// regex rules, and people to watch.
struct AlertSettingsSection: View {
  @AppStorage(AlertRules.ghostPingsKey) private var ghostPings = true
  @AppStorage(AlertRules.watchedUsersKey) private var watchedUsers = ""

  var body: some View {
    Section {
      Toggle("Ghost Pings", isOn: $ghostPings)
      NavigationLink {
        KeywordAlertsView()
      } label: {
        LabeledContent(
          "Keywords and Patterns", value: "\(AlertRules.shared.rules.filter(\.enabled).count)")
      }
      NavigationLink {
        NotificationPeopleList(selection: $watchedUsers)
          .navigationTitle("People to Watch")
      } label: {
        LabeledContent(
          "People to Watch",
          value: "\(watchedUsers.split(separator: ",").count)")
      }
    } header: {
      Text("Aicord Alerts")
    } footer: {
      Text(
        "Ghost pings: a notification when a message that mentioned you, your role or everyone is deleted; the list is under Saved. Keywords and people to watch notify even where Discord stays quiet, muted servers included. Everything is checked on messages Aicord already receives, only on this device."
      )
    }
  }
}

/// The keyword and regex rules, each for everywhere or for chosen places.
struct KeywordAlertsView: View {
  @State private var editing: UUID?

  var body: some View {
    @Bindable var alerts = AlertRules.shared
    Form {
      Section {
        ForEach(alerts.rules) { rule in
          NavigationLink {
            KeywordRuleEditor(id: rule.id)
          } label: {
            ruleLabel(rule)
          }
        }
        .onDelete { alerts.rules.remove(atOffsets: $0) }
        Button("Add Keyword", systemImage: "plus") {
          let rule = AlertRules.KeywordRule()
          alerts.rules.append(rule)
          editing = rule.id
        }
      } footer: {
        Text(
          "A keyword matches whole words, ignoring case. A pattern is a regular expression, also ignoring case."
        )
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Keywords and Patterns")
    .navigationDestination(item: $editing) { id in
      KeywordRuleEditor(id: id)
    }
  }

  private func ruleLabel(_ rule: AlertRules.KeywordRule) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(verbatim: rule.pattern.isEmpty ? "—" : rule.pattern)
        .font(rule.isRegex ? .body.monospaced() : .body)
        .foregroundStyle(rule.enabled ? .primary : .secondary)
      Group {
        let places = rule.placeIDs.count
        if places == 0 {
          Text(rule.isRegex ? "Pattern · Everywhere" : "Keyword · Everywhere")
        } else {
          Text(
            rule.isRegex
              ? "Pattern · ^[\(places) place](inflect: true)"
              : "Keyword · ^[\(places) place](inflect: true)")
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }
}

/// Reads the rule from the store by its ID, so it stays current however it was pushed.
struct KeywordRuleEditor: View {
  let id: UUID

  var body: some View {
    @Bindable var alerts = AlertRules.shared
    if let index = alerts.rules.firstIndex(where: { $0.id == id }) {
      editor($alerts.rules[index])
    }
  }

  private func editor(_ rule: Binding<AlertRules.KeywordRule>) -> some View {
    let value = rule.wrappedValue
    return Form {
      Section {
        TextField(
          value.isRegex ? "Pattern" : "Keyword", text: rule.pattern,
          prompt: Text(value.isRegex ? "e.g. release v\\d+" : "e.g. Aicord"))
          .autocorrectionDisabled()
          #if os(iOS)
            .textInputAutocapitalization(.never)
          #endif
          .font(value.isRegex ? .body.monospaced() : .body)
        Toggle("Regular Expression", isOn: rule.isRegex)
        Toggle("On", isOn: rule.enabled)
      } footer: {
        if value.isRegex, !value.pattern.isEmpty, value.expression == nil {
          Text("This pattern isn't a valid regular expression.")
            .foregroundStyle(.red)
        }
      }
      Section {
        NavigationLink {
          NotificationPlaceList(mode: .selected(selection: rule.places))
        } label: {
          LabeledContent(
            "Servers and Channels",
            value: value.placeIDs.isEmpty
              ? String(localized: "Everywhere") : "\(value.placeIDs.count)")
        }
      } footer: {
        Text(
          "With nothing picked, the rule looks at every server and direct message. A server includes all its channels."
        )
      }
    }
    .formStyle(.grouped)
    .navigationTitle(value.pattern.isEmpty ? String(localized: "New Keyword") : value.pattern)
  }
}
