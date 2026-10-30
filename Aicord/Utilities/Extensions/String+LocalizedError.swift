//
//  String+LocalizedError.swift
//  Aicord
//
// Created by Lakhan Lothiyi on 06/09/2025.
// Copyright © 2025 Lakhan Lothiyi.
//

import Foundation

extension String: @retroactive LocalizedError {
  public var errorDescription: String? {
    self
  }
}
