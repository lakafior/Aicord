//
//  GroupDMsMemberList.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 03/02/2026.
//  Copyright © 2026 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

extension MemberSidebarView {

  struct GroupDMsMemberList: View {
    var channelStore: ChannelStore
    var recipients: [DiscordUser]
    var body: some View {
      List(recipients) { recipient in
        MemberRowView(user: recipient)
          .channelListRow()
      }
      .channelListStyle()
    }
  }
}
