//
//  ProfileView.swift
//  PaiCord
//
// Created by Lakhan Lothiyi on 31/08/2025.
// Copyright © 2025 Lakhan Lothiyi.
//

import PaicordLib
import SwiftUI

struct ProfileView: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.colorScheme) var systemColorScheme
  @State var colorScheme: ColorScheme? = nil

  var user: PartialUser? {
    gw.user.currentUser?.toPartialUser()
  }

  @State var profile: DiscordUser.Profile? = nil

  var bio: String? {
    let meta = profile?.user_profile?.bio
    return (meta?.isEmpty ?? true) ? nil : meta
  }

  var hasThemeColors: Bool {
    profile?.user_profile?.theme_colors?.isEmpty == false
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(alignment: .leading, spacing: 0) {
            bannerView
            profileBody
              .padding()
          }
          .listRowInsets(EdgeInsets())

          ProfileBar.CustomStatusRow()
        }

        ProfileBar.StatusSection()

        if let bio {
          Section("About Me") {
            MarkdownText(content: bio)
          }
        }

        ProfileBar.ActivitySection()
        ProfileBar.AccountInfoSection()
        ProfileBar.AccountsSection()
      }
      .task(fetchProfile)
      .task(grabColor)  // way faster than profile fetch
      .scrollContentBackground(hasThemeColors ? .hidden : .automatic)
      .background(
        Profile.ThemeColorsBackground(
          colors: profile?.user_profile?.theme_colors
        )
      )
      .environment(\.colorScheme, colorScheme ?? systemColorScheme)
    }
  }

  @ViewBuilder
  var bannerView: some View {
    Utils.UserBannerURL(
      user: user,
      profile: profile,
      mainProfileBanner: true,
      animated: true
    ) { bannerURL in
      Color.clear
        .aspectRatio(3, contentMode: .fit)
        .overlay {
          let color =
            profile?.user_profile?.theme_colors?.first
            ?? profile?.user_profile?.accent_color
            ?? user?.accent_color
          NukeImage(url: bannerURL) {
            Rectangle()
              .foregroundStyle(color?.asColor() ?? accentColor)
          }
          .resizable()
          .scaledToFill()
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .reverseMask(alignment: .bottomLeading) {
        Circle()
          .frame(width: 80, height: 80)
          .padding(.leading, 16)
          .scaleEffect(1.15)
          .offset(x: -1, y: 40)
      }
      .overlay(alignment: .bottomLeading) {
        Profile.AvatarWithPresence(
          user: user
        )
        .profileAnimated()
        .profileShowsAvatarDecoration()
        .frame(width: 80, height: 80)
        .padding(.leading, 16)
        .offset(y: 40)
      }
      .padding(.bottom, 30)

    }
  }

  @ViewBuilder
  var profileBody: some View {
    VStack(alignment: .leading, spacing: 4) {
      let profileMeta: DiscordUser.Profile.Metadata? = profile?.user_profile
      Text(
        user?.global_name ?? user?.username ?? "Unknown User"
      )
      .font(.title2)
      .bold()
      .lineLimit(1)
      .minimumScaleFactor(0.5)

      FlowLayout(xSpacing: 8, ySpacing: 2) {
        Group {
          Text(verbatim: "@\(user?.username ?? "unknown")")
          if let pronouns = profileMeta?.pronouns
            ?? user?.pronouns,
            !pronouns.isEmpty
          {
            Text(verbatim: "•")
            Text(pronouns)
          }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)

        HStack(spacing: 4) {
          let badges = profile?.badges ?? []
          ForEach(badges) { badge in
            Profile.Badge(badge: badge)
          }
        }
        .frame(maxHeight: 16)
      }

    }
  }

  @Sendable
  func fetchProfile() async {
    guard profile == nil else { return }
    guard let user else { return }
    let res = try? await gw.client.getUserProfile(
      userID: user.id,
      withMutualGuilds: false,
      withMutualFriends: false,
      withMutualFriendsCount: false
    )
    do {
      // ensure request was successful
      try res?.guardSuccess()
      let profile = try res?.decode()
      self.profile = profile
    } catch {
      if let error = res?.asError() {
        appState.error = error
      } else {
        appState.error = error
      }
    }
  }

  @State var accentColor = Color.clear

  @Sendable
  func grabColor() async {
    // shares the pipeline with every NukeImage on screen, so the avatar is usually
    // already warm in memory by the time this runs
    guard
      let avatarURL = Utils.fetchUserAvatarURL(
        user: user,
        animated: false
      ),
      let image = try? await ImagePipeline.shared.image(for: avatarURL),
      let extractedColor = image.extractAccentColor()
    else {
      return
    }
    await MainActor.run { self.accentColor = extractedColor }
  }
}
