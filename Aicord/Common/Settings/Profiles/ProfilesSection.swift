//
//  ProfilesSection.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 02/12/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import ImageIO
import AicordKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
  @ViewBuilder
  var profilesSection: some View {
    ProfileEditor()
  }
}

/// Discord's "Profiles" page: the main profile and per-server identities.
struct ProfileEditor: View {
  enum Page: Hashable { case main, server }
  @State var page: Page = .main

  var body: some View {
    Section {
      Picker("Profile", selection: $page) {
        Text("Main Profile").tag(Page.main)
        Text("Server Profiles").tag(Page.server)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
    }
    switch page {
    case .main: MainProfileEditor()
    case .server: ServerProfileEditor()
    }
  }
}

// MARK: - Main profile

struct MainProfileEditor: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState

  @State var loaded = false
  @State var displayName = ""
  @State var pronouns = ""
  @State var bio = ""
  @State var original = (displayName: "", pronouns: "", bio: "")

  @State var photoItem: PhotosPickerItem? = nil
  @State var newAvatar: Data? = nil
  @State var removesAvatar = false
  @State var saving = false

  var user: DiscordUser? { gw.user.currentUser }

  var hasChanges: Bool {
    displayName != original.displayName || pronouns != original.pronouns
      || bio != original.bio || newAvatar != nil || removesAvatar
  }

  var body: some View {
    Section("Preview") {
      ProfilePreview(
        user: user,
        displayName: displayName,
        pronouns: pronouns,
        bio: bio,
        avatar: newAvatar,
        removesAvatar: removesAvatar
      )
    }

    Section {
      TextField("Display Name", text: $displayName, prompt: Text(user?.username ?? ""))
        .limitInput($displayName, to: 32)
      TextField("Pronouns", text: $pronouns)
        .limitInput($pronouns, to: 40)
    } header: {
      Text("Name")
    } footer: {
      Text("Leave the display name empty to show your username.")
    }

    Section {
      TextField("About Me", text: $bio, axis: .vertical)
        .lineLimit(3...8)
        .limitInput($bio, to: 190)
    } header: {
      Text("About Me")
    } footer: {
      Text("\(bio.count)/190 · Markdown and links work here.")
        .monospacedDigit()
    }

    Section("Avatar") {
      PhotosPicker(selection: $photoItem, matching: .images) {
        Label("Choose New Avatar", systemImage: "photo.on.rectangle")
      }
      if user?.avatar != nil || newAvatar != nil {
        Button(role: .destructive) {
          newAvatar = nil
          photoItem = nil
          removesAvatar = user?.avatar != nil
        } label: {
          Label("Remove Avatar", systemImage: "trash")
            .foregroundStyle(.red)
        }
      }
    }
    .onChange(of: photoItem) { _, item in
      guard let item else { return }
      Task {
        if let data = try? await item.loadTransferable(type: Data.self),
          let png = AvatarImage.squarePNG(from: data)
        {
          newAvatar = png
          removesAvatar = false
        }
      }
    }

    if user?.premium_type == nil || user?.premium_type == DiscordUser.PremiumKind.none {
      Section {
        Label("Banner, profile colours and decorations need Nitro.", systemImage: "sparkles")
          .foregroundStyle(.secondary)
      }
    }

    Section {
      HStack {
        Button("Revert") { revert() }
          .disabled(!hasChanges || saving)
        Spacer()
        if saving { ProgressView().controlSize(.small) }
        Button("Save Changes") { save() }
          .buttonStyle(.borderedProminent)
          .disabled(!hasChanges || saving)
      }
    }
    .task { await load() }
  }

  func load() async {
    guard !loaded, let user else { return }
    loaded = true
    displayName = user.global_name ?? ""
    pronouns = user.pronouns ?? ""
    if let res = try? await gw.client.getUserProfile(
      userID: user.id,
      withMutualGuilds: false,
      withMutualFriends: false,
      withMutualFriendsCount: false
    ), let profile = try? res.decode() {
      bio = profile.user_profile?.bio ?? ""
      pronouns = profile.user_profile?.pronouns ?? pronouns
    }
    original = (displayName, pronouns, bio)
  }

  func revert() {
    displayName = original.displayName
    pronouns = original.pronouns
    bio = original.bio
    newAvatar = nil
    photoItem = nil
    removesAvatar = false
  }

  func save() {
    func field(_ value: String, _ old: String) -> String?? {
      guard value != old else { return nil }
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return .some(trimmed.isEmpty ? nil : trimmed)
    }
    var avatar: Payloads.ImageData?? = nil
    if let newAvatar {
      avatar = .some(.init(file: .init(data: newAvatar, filename: "avatar.png")))
    } else if removesAvatar {
      avatar = .some(nil)
    }
    let payload = Payloads.ModifyCurrentUser(
      global_name: field(displayName, original.displayName),
      avatar: avatar,
      pronouns: field(pronouns, original.pronouns),
      bio: field(bio, original.bio)
    )
    saving = true
    Task {
      defer { saving = false }
      do {
        let res = try await gw.client.updateOwnUser(payload: payload)
        try res.guardSuccess()
        let updated = try res.decode()
        gw.user.currentUser = updated
        displayName = updated.global_name ?? ""
        original = (displayName, pronouns, bio)
        newAvatar = nil
        photoItem = nil
        removesAvatar = false
      } catch {
        appState.error = error
      }
    }
  }
}

// MARK: - Server profiles

struct ServerProfileEditor: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState

  @State var guildID: GuildSnowflake? = nil
  @State var nick = ""
  @State var pronouns = ""
  @State var original = (nick: "", pronouns: "")
  @State var saving = false

  var guilds: [Guild] {
    gw.user.guilds.values.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  var member: Guild.Member? {
    guard let guildID, let me = gw.user.currentUser?.id else { return nil }
    return gw.user.guilds[guildID]?.members?.first { $0.user?.id == me }
  }

  var hasChanges: Bool { nick != original.nick || pronouns != original.pronouns }

  var body: some View {
    Section {
      Picker("Server", selection: $guildID) {
        Text("Choose a Server").tag(GuildSnowflake?.none)
        ForEach(guilds, id: \.id) { guild in
          Text(guild.name).tag(Optional(guild.id))
        }
      }
    } footer: {
      Text("Change how you appear on one server. Other servers keep your main profile.")
    }
    .onChange(of: guildID, initial: true) { _, _ in loadMember() }

    if guildID != nil {
      Section("Preview") {
        ProfilePreview(
          user: gw.user.currentUser,
          displayName: nick.isEmpty ? (gw.user.currentUser?.global_name ?? "") : nick,
          pronouns: pronouns.isEmpty ? (gw.user.currentUser?.pronouns ?? "") : pronouns,
          bio: nil,
          avatar: nil,
          removesAvatar: false
        )
      }

      Section {
        TextField(
          "Nickname", text: $nick,
          prompt: Text(gw.user.currentUser?.global_name ?? gw.user.currentUser?.username ?? "")
        )
        .limitInput($nick, to: 32)
        TextField(
          "Pronouns", text: $pronouns,
          prompt: Text(gw.user.currentUser?.pronouns.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Pronouns"))
        )
          .limitInput($pronouns, to: 40)
      } header: {
        Text("Server Identity")
      } footer: {
        Text("Leave a field empty to use your main profile. Server avatars, banners and bios need Nitro.")
      }

      Section {
        HStack {
          Button("Revert") {
            nick = original.nick
            pronouns = original.pronouns
          }
          .disabled(!hasChanges || saving)
          Spacer()
          if saving { ProgressView().controlSize(.small) }
          Button("Save Changes") { save() }
            .buttonStyle(.borderedProminent)
            .disabled(!hasChanges || saving)
        }
      }
    }
  }

  func loadMember() {
    nick = member?.nick ?? ""
    pronouns = member?.pronouns ?? ""
    original = (nick, pronouns)
  }

  func save() {
    guard let guildID else { return }
    func field(_ value: String, _ old: String) -> String?? {
      guard value != old else { return nil }
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return .some(trimmed.isEmpty ? nil : trimmed)
    }
    let payload = Payloads.ModifyCurrentMember(
      nick: field(nick, original.nick),
      pronouns: field(pronouns, original.pronouns)
    )
    saving = true
    Task {
      defer { saving = false }
      do {
        let res = try await gw.client.updateOwnGuildMember(guildId: guildID, payload: payload)
        try res.guardSuccess()
        let updated = try res.decode()
        if let index = gw.user.guilds[guildID]?.members?.firstIndex(where: {
          $0.user?.id == updated.user?.id
        }) {
          gw.user.guilds[guildID]?.members?[index] = updated
        }
        nick = updated.nick ?? ""
        pronouns = updated.pronouns ?? ""
        original = (nick, pronouns)
      } catch {
        appState.error = error
      }
    }
  }
}

// MARK: - Shared pieces

/// A small live preview of how the profile will look.
struct ProfilePreview: View {
  var user: DiscordUser?
  var displayName: String
  var pronouns: String
  var bio: String?
  var avatar: Data?
  var removesAvatar: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Group {
        if let avatar, let image = AvatarImage.image(from: avatar) {
          image
            .resizable()
            .scaledToFill()
            .clipShape(.circle)
        } else if removesAvatar {
          Circle()
            .fill(.secondary.opacity(0.3))
            .overlay {
              Image(systemName: "person.fill")
                .foregroundStyle(.secondary)
            }
        } else {
          Profile.AvatarWithPresence(member: nil, user: user)
            .profileAnimated(false)
            .profileShowsAvatarDecoration()
        }
      }
      .frame(width: 64, height: 64)

      VStack(alignment: .leading, spacing: 3) {
        Text(displayName.isEmpty ? (user?.username ?? "") : displayName)
          .font(.title3.bold())
          .lineLimit(1)
        HStack(spacing: 6) {
          Text(verbatim: "@\(user?.username ?? "")")
          if !pronouns.isEmpty {
            Text(verbatim: "•")
            Text(pronouns)
          }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        if let bio, !bio.isEmpty {
          MarkdownText(content: bio)
            .padding(.top, 4)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 4)
  }
}

enum AvatarImage {
  /// Crops to a centred square and scales to 512 px, which is what Discord stores.
  static func squarePNG(from data: Data, size: Int = 512) -> Data? {
    guard
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: size * 2,
        ] as CFDictionary
      )
    else { return nil }
    let side = min(image.width, image.height)
    let crop = CGRect(
      x: (image.width - side) / 2, y: (image.height - side) / 2,
      width: side, height: side
    )
    guard let square = image.cropping(to: crop),
      let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }
    context.interpolationQuality = .high
    context.draw(square, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let scaled = context.makeImage() else { return nil }
    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, scaled, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return output as Data
  }

  static func image(from data: Data) -> Image? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    return Image(decorative: cgImage, scale: 1)
  }
}

extension View {
  /// Trims typed or pasted text to Discord's length limit.
  func limitInput(_ text: Binding<String>, to limit: Int) -> some View {
    onChange(of: text.wrappedValue) { _, newValue in
      if newValue.count > limit { text.wrappedValue = String(newValue.prefix(limit)) }
    }
  }
}
