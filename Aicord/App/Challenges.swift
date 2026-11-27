//
//  Challenges.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 18/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import Foundation
import AicordKit

@Observable
@MainActor
final class Challenges {
  // Captcha
  var captchaChallenge: CaptchaChallengeData?
  private var captchaContinuation: CheckedContinuation<CaptchaSubmitData?, Never>?

  // MFA
  var mfaVerification: MFAVerificationData?
  private var mfaContinuation: CheckedContinuation<MFAResponse?, Never>?

  /// Views that can show the challenge sheets, innermost last. Only the last
  /// one presents: a sheet asked for by the window while another sheet (an
  /// invite, Add Friend) is already up never shows, or flashes and closes.
  private(set) var presenters: [UUID] = []

  func register(_ presenter: UUID) {
    presenters.removeAll { $0 == presenter }
    presenters.append(presenter)
  }

  func unregister(_ presenter: UUID) {
    presenters.removeAll { $0 == presenter }
  }

  func presentCaptcha(_ challenge: CaptchaChallengeData) async
    -> CaptchaSubmitData?
  {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        self.captchaChallenge = challenge
        self.captchaContinuation = continuation
      }
    }
  }

  func presentMFA(_ data: MFAVerificationData) async -> MFAResponse? {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        self.mfaVerification = data
        self.mfaContinuation = continuation
      }
    }
  }

  func completeCaptcha(_ submitData: CaptchaSubmitData?) {
    captchaContinuation?.resume(returning: submitData)
    captchaContinuation = nil
    captchaChallenge = nil
  }

  func completeMFA(_ response: MFAResponse?) {
    mfaContinuation?.resume(returning: response)
    mfaContinuation = nil
    mfaVerification = nil
  }
}
