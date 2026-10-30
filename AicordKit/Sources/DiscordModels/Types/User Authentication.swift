//
//  User Authentication.swift
//  AicordKit
//
// Created by Lakhan Lothiyi on 03/09/2025.
// Copyright © 2025 Lakhan Lothiyi.
//

// only logins have a unique mfa verification process. otherwise its like captchas

public struct UserAuthenticationSessions: Sendable, Decodable {
  public var user_sessions: [Session]

  public struct Session: Sendable, Decodable, Identifiable {
    public var id: String { id_hash }
    public var id_hash: String
    public var approx_last_used_time: DiscordTimestamp
    public var client_info: ClientInfo

    public struct ClientInfo: Sendable, Decodable {
      public var os: String?
      public var platform: String?
      public var location: String?
    }
  }
}

public struct UserAuthentication: Sendable, Decodable {
  public var user_id: UserSnowflake?  // only sent on login, not verifyMFALogin
  public var token: Secret?
  public var ticket: Secret?

  public var totp: Bool?
  public var sms: Bool?
  public var mfa: Bool?
  public var backup: Bool?
}

public struct FingerprintExperiments: Sendable, Decodable {
  public var fingerprint: String?
  //  public var assignments
  //  public var guild_experiments
}

public struct UserAuthenticationMFASMS: Sendable, Decodable {
  public var phone: String
}
