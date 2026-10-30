//
//  AddFriend.swift
//  Aicord
//
//  Copyright © 2026 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

/// Add Friend by username, from Messages → Friends.
struct AddFriendSheet: View {
  @Environment(\.gateway) var gw
  @Environment(\.dismiss) var dismiss
  @State private var username = ""
  @State private var sending = false
  @State private var result: Result?
  @FocusState private var focused: Bool

  enum Result: Equatable {
    case sent(String)
    case failed(String)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Username", text: $username)
            .autocorrectionDisabled()
            #if os(iOS)
              .textInputAutocapitalization(.never)
              .submitLabel(.send)
            #endif
            .focused($focused)
            .onSubmit(send)
            .onChange(of: username) { result = nil }
        } footer: {
          switch result {
          case .sent(let name):
            Label("Friend request sent to \(name).", systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
          case .failed(let message):
            Label(message, systemImage: "exclamationmark.circle.fill")
              .foregroundStyle(.red)
          case nil:
            Text("You can add friends with their Discord username.")
          }
        }

        Section {
          Button(action: send) {
            HStack {
              Text("Send Friend Request")
              if sending {
                Spacer()
                ProgressView()
              }
            }
          }
          .disabled(trimmed.isEmpty || sending)
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Add Friend")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
      .onAppear { focused = true }
    }
    #if os(macOS)
      .frame(minWidth: 380, idealWidth: 420, minHeight: 260)
    #endif
  }

  private var trimmed: String {
    username.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func send() {
    let input = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
    guard !input.isEmpty, !sending else { return }
    // legacy tags still work: name#1234
    let parts = input.split(separator: "#", maxSplits: 1).map(String.init)
    let name = parts[0].lowercased()
    let discriminator = parts.count == 2 ? parts[1] : nil

    if discriminator == nil, !AddFriend.isValidUsername(name) {
      result = .failed(AddFriend.invalidUsernameText)
      return
    }
    if let known = AddFriend.localFailure(username: name, gw: gw) {
      result = .failed(known)
      return
    }

    sending = true
    Task {
      defer { sending = false }
      do {
        let response = try await gw.client.sendFriendRequest(
          payload: .init(username: name, discriminator: discriminator)
        )
        if let failure = AddFriend.failure(of: response) {
          result = .failed(AddFriend.text(for: failure))
        } else {
          result = .sent(name)
          username = ""
        }
      } catch {
        result = .failed(AddFriend.text(for: error))
      }
    }
  }
}

/// "Add Friend" on a profile, while you aren't friends and no request is pending.
struct AddFriendProfileButton: View {
  @Environment(\.gateway) var gw
  let user: PartialUser
  @State private var sending = false
  @State private var error: String?

  var body: some View {
    let relationship = gw.user.relationships[user.id]?.type
    if user.id != gw.user.currentUser?.id, user.bot != true, relationship != .blocked,
      relationship != .friend
    {
      Group {
        switch relationship {
        case .outgoingRequest:
          Label("Friend Request Sent", systemImage: "clock")
            .foregroundStyle(.secondary)
        case .incomingRequest:
          Button("Accept Friend Request", systemImage: "person.badge.plus", action: send)
        default:
          Button("Add Friend", systemImage: "person.badge.plus", action: send)
        }
      }
      .font(.subheadline.weight(.semibold))
      .buttonStyle(.bordered)
      .disabled(sending)
      .padding(.top, 6)
      .alert(
        "Couldn't Send Request",
        isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(error ?? "")
      }
    }
  }

  /// With no type, Discord sends a request, or accepts the one they sent you.
  private func send() {
    sending = true
    Task {
      defer { sending = false }
      do {
        let response = try await gw.client.createRelationship(
          userID: user.id, payload: .init(type: nil)
        )
        if let failure = AddFriend.failure(of: response) {
          error = AddFriend.text(for: failure)
        }
      } catch {
        self.error = AddFriend.text(for: error)
      }
    }
  }
}

enum AddFriend {
  private static let usernameCharacters = CharacterSet(
    charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_.")

  /// Discord usernames: 2 to 32 lowercase letters, digits, `_` and `.`.
  static func isValidUsername(_ name: String) -> Bool {
    (2...32).contains(name.count) && name.unicodeScalars.allSatisfy(usernameCharacters.contains)
  }

  static var invalidUsernameText: String {
    String(localized: "Usernames are 2 to 32 letters, numbers, underscores or periods.")
  }

  /// Answers we know without asking Discord, from your relationships.
  @MainActor
  static func localFailure(username: String, gw: GatewayStore) -> String? {
    if gw.user.currentUser?.username.lowercased() == username {
      return String(localized: "That's your own username.")
    }
    guard
      let relationship = gw.user.relationships.values.first(where: {
        $0.user.username?.lowercased() == username
      })
    else { return nil }
    switch relationship.type {
    case .friend:
      return String(localized: "You're already friends with \(relationship.displayName).")
    case .outgoingRequest:
      return String(localized: "You already sent \(relationship.displayName) a friend request.")
    case .incomingRequest:
      return String(
        localized: "\(relationship.displayName) already sent you a request. Accept it under Incoming."
      )
    case .blocked:
      return String(localized: "You blocked \(relationship.displayName). Unblock them first.")
    default:
      return nil
    }
  }

  static func failure(of response: DiscordHTTPResponse) -> FriendRequestFailure? {
    guard let error = response.asError() else { return nil }
    switch error {
    case .jsonError(let json):
      return FriendRequestFailure(
        status: Int(response.status.code), code: json.code?.rawValue, message: json.message
      )
    case .badStatusCode(let response):
      return FriendRequestFailure(status: Int(response.status.code), code: nil, message: nil)
    }
  }

  static func text(for error: any Error) -> String {
    if case DiscordHTTPError.rateLimited = error { return text(for: .rateLimited) }
    if error is ValidationError { return invalidUsernameText }
    return error.localizedDescription
  }

  static func text(for failure: FriendRequestFailure) -> String {
    switch failure {
    case .unknownUser:
      String(localized: "Nobody goes by that username. Check the spelling.")
    case .alreadyFriends:
      String(localized: "You're already friends with that user.")
    case .requestsDisabled:
      String(localized: "That user doesn't accept friend requests.")
    case .blocked:
      String(localized: "That user can't receive a request from you.")
    case .yourself:
      String(localized: "That's your own username.")
    case .bot:
      String(localized: "Bots can't have friends.")
    case .friendLimit:
      String(localized: "You've reached the limit of 1,000 friends.")
    case .needsVerification:
      String(localized: "Verify your account's email or phone before sending friend requests.")
    case .rateLimited:
      String(localized: "You're sending requests too quickly. Try again in a moment.")
    case .other(let message):
      message ?? String(localized: "Discord didn't accept the request.")
    }
  }
}
