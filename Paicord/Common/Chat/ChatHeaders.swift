//
//  ChatHeaders.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 07/12/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import SwiftUI

enum ChatHeaders {
  struct WelcomeStartOfChannelHeader: View {
    @Environment(\.theme) var theme
    @Environment(\.channelStore) var channel
    var body: some View {
      VStack(alignment: .leading) {
        Image(systemName: "number")
          .font(.largeTitle)
          .padding(8)
          .background(.quaternary, in: .circle)

        if let channelName = channel?.channel?.name {
          Text("Welcome to the start of #\(channelName)")
            .font(.headline)
        } else {
          Text("Welcome to the start of this channel")
            .font(.headline)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
    }
  }

  struct NoHistoryPermissionHeader: View {
    @Environment(\.theme) var theme
    @Environment(\.channelStore) var channel
    var body: some View {
      VStack(alignment: .leading) {
        Image(systemName: "nosign")
          .font(.largeTitle)
          .padding(8)
          .background(.quaternary, in: .circle)

        if let channelName = channel?.channel?.name {
          Text("You don't have permission to view the message history of #\(channelName).")
            .font(.headline)
        } else {
          Text("You don't have permission to view the message history in this channel.")
            .font(.headline)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
    }
  }
}

#Preview {
  VStack {
    ChatHeaders.NoHistoryPermissionHeader()
    ChatHeaders.WelcomeStartOfChannelHeader()
  }
}
