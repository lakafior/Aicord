//
//  GuildMemberList.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 03/02/2026.
//  Copyright © 2026 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

extension MemberSidebarView {
  struct GuildMemberList: View {
    var guildStore: GuildStore
    var channelStore: ChannelStore
    var accumulator: ChannelStore.MemberListAccumulator

    /// The member row that last scrolled into view.
    @State var upperBound: Int? = nil

    var scrollPairs: [IntPair] {
      var pairs: [(Int, Int)] = [(0, 99)]
      guard let upperBound else {
        return pairs.map(IntPair.init)
      }
      let maxIndex = accumulator.rowCount - 1
      guard maxIndex >= 100 else {
        return pairs.map(IntPair.init)
      }
      let currentBlock = upperBound / 100
      let maxBlock = maxIndex / 100
      let clampedBlock = min(currentBlock, maxBlock)
      var blocks: [Int] = []
      for i in stride(
        from: clampedBlock,
        through: max(clampedBlock - 1, 1),
        by: -1
      ) {
        blocks.append(i)
      }
      for block in blocks {
        let start = block * 100
        pairs.insert((start, start + 99), at: 1)
      }
      let mapped = pairs.map(IntPair.init)
      return mapped.count <= 3 ? mapped : [.init(0, 99)]
    }

    /// Each role group with the rows of its members; row indices count the group
    /// headings too, as the gateway does.
    var sections: [(id: RoleSnowflake, header: Int, members: Range<Int>)] {
      var offset = 0
      return accumulator.groups.map { id, group in
        defer { offset += 1 + group.count }
        return (id, offset, (offset + 1)..<(offset + 1 + group.count))
      }
    }

    var body: some View {
      List {
        ForEach(sections, id: \.id) { section in
          Section {
            ForEach(section.members, id: \.self) { itemIndex in
              MemberListCell(
                row: accumulator.row(at: itemIndex),
                accumulator: accumulator,
                guildStore: guildStore
              )
              .environment(\.memberListItemIndex, itemIndex)
              .environment(\.memberListAccumulator, accumulator)
              // rows load as they scroll in; the last one seen picks the ranges to ask for
              .onAppear { upperBound = itemIndex }
              .channelListRow()
            }
          } header: {
            GroupHeaderCell(groupID: section.id, guildStore: guildStore)
              .environment(\.memberListAccumulator, accumulator)
          }
        }
      }
      .channelListStyle()
      .task(id: scrollPairs) {
        do {
          try await Task.sleep(for: .milliseconds(300))
        } catch {
          return
        }
        await channelStore.requestMemberListRange(scrollPairs)
      }
    }
  }

  private struct MemberListCell: View {
    let row: ChannelStore.MemberListRow?
    let accumulator: ChannelStore.MemberListAccumulator
    let guildStore: GuildStore

    var body: some View {
      switch row?.value {
      case .member(let member):
        if let user = member.user {
          MemberRowView(member: member.toPartialMember(), user: user)
        }
      default:
        // not loaded yet: an empty row of the same height, so the scroll bar stays put
        Color.clear
          .frame(height: 32)
          .accessibilityHidden(true)
      }
    }
  }

  private struct GroupHeaderCell: View {
    let groupID: RoleSnowflake
    @Environment(\.memberListAccumulator) var accumulator: ChannelStore.MemberListAccumulator!
    let guildStore: GuildStore

    var body: some View {
      if let group = accumulator.groups[groupID] {
        let text: Text = {
          if let role = guildStore.role(groupID) {
            return Text(verbatim: "\(role.name) — \(group.count)")
          } else {
            let name: String = groupID.rawValue.capitalized
            return Text(verbatim: "\(name) — \(group.count)")
          }
        }()

        text
          .lineLimit(1)
      } else {
        // idk man
        Text(verbatim: "\(groupID.rawValue)")
      }
    }
  }
}

extension EnvironmentValues {
  @Entry var memberListItemIndex: Int?
  @Entry var memberListAccumulator: ChannelStore.MemberListAccumulator?
}
