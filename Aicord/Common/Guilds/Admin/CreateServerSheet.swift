//
//  CreateServerSheet.swift
//  Aicord
//
//  Makes a new server, empty or from a server template link
//  (discord.new/… or discord.com/template/…), and opens it.
//

import AicordKit
import SwiftUI

struct CreateServerSheet: View {
  enum Start: Hashable {
    case scratch, template
  }

  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.dismiss) var dismiss

  @State private var start: Start = .scratch
  @State private var name = ""
  @State private var templateLink = ""
  @State private var template: GuildTemplate?
  @State private var isLookingUp = false
  @State private var isCreating = false
  @State private var error: String?

  /// The template code from a link or a bare code.
  private var templateCode: String? {
    let trimmed = templateLink.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let code = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
    return code.isEmpty ? nil : code
  }

  private var canCreate: Bool {
    let hasName = name.trimmingCharacters(in: .whitespaces).count >= 2
    return start == .scratch ? hasName : hasName && template != nil
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Start", selection: $start) {
            Text("From Scratch").tag(Start.scratch)
            Text("From a Template").tag(Start.template)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
        }

        if start == .template {
          Section {
            TextField("Template Link", text: $templateLink)
              .autocorrectionDisabled()
              #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
              #endif
              .onSubmit { Task { await lookUp() } }
            if isLookingUp {
              ProgressView()
            } else if let template {
              LabeledContent("Template", value: template.name)
              if let description = template.description, !description.isEmpty {
                Text(description)
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
            } else {
              Button("Look Up Template") { Task { await lookUp() } }
                .disabled(templateCode == nil)
            }
          } footer: {
            Text("A link like discord.new/abc123. The template copies its channels, roles and settings, but no messages or members.")
          }
        }

        Section {
          TextField("Server Name", text: $name)
        } footer: {
          Text("Only you are in the new server until you invite someone.")
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Create a Server")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { dismiss() }
        }
      }
      .safeAreaInset(edge: .bottom) {
        OnboardingActionButton(title: "Create Server", isWorking: isCreating, isDisabled: !canCreate) {
          create()
        }
      }
      .onChange(of: templateLink) { template = nil }
      .saveErrorAlert($error)
    }
    #if os(macOS)
      .frame(minWidth: 420, idealWidth: 460, minHeight: 420, idealHeight: 480)
    #endif
  }

  private func lookUp() async {
    guard let templateCode else { return }
    isLookingUp = true
    defer { isLookingUp = false }
    do {
      let found = try await gw.client.getGuildTemplate(code: templateCode).decode()
      template = found
      if name.isEmpty { name = found.serialized_source_guild.name ?? found.name }
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func create() {
    let trimmedName = name.trimmingCharacters(in: .whitespaces)
    let code = templateCode
    let start = start
    isCreating = true
    Task {
      defer { isCreating = false }
      do {
        let guild: Guild
        if start == .template, let code {
          guild = try await gw.client.createGuildFromTemplate(code: code, payload: .init(name: trimmedName))
            .decode()
        } else {
          guild = try await gw.client.createGuild(payload: .init(name: trimmedName)).decode()
        }
        dismiss()
        appState.selectedGuild = guild.id
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}
