//
//  Utilities.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 11/10/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import SwiftUI

extension MessageCell {
  struct AvatarBalancing: View {
    var body: some View {
      Button {
      } label: {
        Text(verbatim: "")
          .frame(width: avatarSize)
      }
      .buttonStyle(.borderless)
      .frame(height: 1)
      .disabled(true)  // btn used for spacing only
    }
  }

  struct ReplyLine: View {
    var body: some View {
      RoundedRectangle(cornerRadius: 5)
        .trim(from: 0.5, to: 0.75)
        .stroke(.gray.opacity(0.4), lineWidth: 2)
        .frame(width: 60, height: 20)
        .padding(.top, 8)
        .padding(.bottom, -12)
        .padding(.trailing, -30)
    }
  }
}
