//
//  BitField.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 06/11/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit

extension IntBitField {
  func toStringBitField() -> StringBitField<R> {
    return .init(rawValue: self.rawValue)
  }
}

extension StringBitField {
  func toIntBitField() -> IntBitField<R> {
    return .init(rawValue: self.rawValue)
  }
}
