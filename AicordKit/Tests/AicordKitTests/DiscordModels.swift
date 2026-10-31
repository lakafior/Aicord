import DiscordHTTP
import Foundation
import XCTest

@testable import DiscordModels

class DiscordModelsTests: XCTestCase {

  func testVoiceMessagePayloadEncoding() throws {
    let voiceAttachment = Payloads.Attachment(
      index: 0,
      filename: "voice-message.m4a",
      content_type: "audio/mp4",
      duration_secs: 1.5,
      waveform: "waveform"
    )
    let voiceMessage = Payloads.CreateMessage(
      attachments: [voiceAttachment],
      flags: [.isVoiceMessage],
      enforce_nonce: true
    )
    XCTAssertTrue(voiceMessage.validate().isEmpty)

    let data = try JSONEncoder().encode(voiceMessage)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(json["enforce_nonce"] as? Bool, true)
    let attachment = try XCTUnwrap((json["attachments"] as? [[String: Any]])?.first)
    XCTAssertEqual(attachment["duration_secs"] as? Double, 1.5)
    XCTAssertEqual(attachment["waveform"] as? String, "waveform")
  }

  func testVoiceMessageRejectsInvalidContentAndMetadata() {
    let missingMetadata = Payloads.Attachment(index: 0, filename: "voice-message.m4a")
    XCTAssertFalse(
      Payloads.CreateMessage(attachments: [missingMetadata], flags: [.isVoiceMessage])
        .validate().isEmpty
    )
    XCTAssertFalse(
      Payloads.CreateMessage(content: "text", flags: [.isVoiceMessage]).validate().isEmpty
    )
  }

  func testForwardedMessageRequiresSourceIdentifiers() {
    let reference = DiscordChannel.Message.MessageReference(
      type: .forward,
      message_id: "1",
      channel_id: "2"
    )
    XCTAssertTrue(Payloads.CreateMessage(message_reference: reference).validate().isEmpty)
    XCTAssertFalse(
      Payloads.CreateMessage(message_reference: .init(type: .forward)).validate().isEmpty
    )
  }

  func testEmptyMessageFailsValidation() {
    XCTAssertFalse(Payloads.CreateMessage().validate().isEmpty)
  }

  func testIndirectFieldsKeepOptionalCodingAndValueSemantics() throws {
    let json = #"""
      {"id":"10","channel_id":"20","content":"hi","timestamp":"2024-01-01T00:00:00.000000+00:00",
       "edited_timestamp":null,"tts":false,"mention_everyone":false,"mentions":[],"mention_roles":[],
       "attachments":[],"embeds":[],"pinned":false,"type":0,"poll":null,
       "author":{"id":"30","username":"a","discriminator":"0","global_name":null,"avatar":null}}
      """#
    var message = try JSONDecoder().decode(
      DiscordChannel.Message.self,
      from: Data(json.utf8)
    )
    /// Missing and `null` keys decode to `nil`.
    XCTAssertNil(message.thread)
    XCTAssertNil(message.poll)
    XCTAssertEqual(message.author?.id, "30")

    /// Copies stay independent after a mutation.
    let copy = message
    message.author?.username = "b"
    XCTAssertEqual(copy.author?.username, "a")
    XCTAssertEqual(message.author?.username, "b")
    XCTAssertNotEqual(copy, message)
    message.author?.username = "a"
    XCTAssertEqual(copy, message)
  }

  func testChannelDecodesAppliedTagsAndMessageRequestState() throws {
    let data = Data(
      #"{"id":"1","type":1,"applied_tags":["2"],"is_message_request":true,"is_spam":false}"#.utf8
    )
    let channel = try JSONDecoder().decode(DiscordChannel.self, from: data)
    XCTAssertEqual(channel.applied_tags, ["2"])
    XCTAssertEqual(channel.is_message_request, true)
    XCTAssertEqual(channel.is_spam, false)
  }

  func testPreloadedUserSettingsStatusSettingsGatewayStatus() throws {
    var statusSettings =
      DiscordProtos_DiscordUsers_V1_PreloadedUserSettings.StatusSettings()

    statusSettings.status.value = "online"
    XCTAssertEqual(statusSettings.gatewayStatus, .online)

    statusSettings.status.value = "idle"
    XCTAssertEqual(statusSettings.gatewayStatus, .afk)

    statusSettings.status.value = "dnd"
    XCTAssertEqual(statusSettings.gatewayStatus, .doNotDisturb)

    statusSettings.status.value = "invisible"
    XCTAssertEqual(statusSettings.gatewayStatus, .invisible)

    statusSettings.status.value = "something-new"
    XCTAssertEqual(statusSettings.gatewayStatus, .online)

    let emptySettings =
      DiscordProtos_DiscordUsers_V1_PreloadedUserSettings.StatusSettings()
    XCTAssertNil(emptySettings.gatewayStatus)
  }

  func testPreloadedUserSettingsStatusSettingsGatewayStatusExpiry() throws {
    var statusSettings =
      DiscordProtos_DiscordUsers_V1_PreloadedUserSettings.StatusSettings()
    statusSettings.status.value = "dnd"
    statusSettings.statusExpiresAtMs = 1

    XCTAssertNil(statusSettings.gatewayStatus)

    statusSettings.statusExpiresAtMs = UInt64(
      Date().addingTimeInterval(60).timeIntervalSince1970 * 1_000
    )

    XCTAssertEqual(statusSettings.gatewayStatus, .doNotDisturb)
  }

  func testPreloadedUserSettingsCustomStatusGatewayActivity() throws {
    var customStatus =
      DiscordProtos_DiscordUsers_V1_PreloadedUserSettings.CustomStatus()
    customStatus.text = "writing tests"
    customStatus.emojiID = 123
    customStatus.emojiName = "pencil"

    var statusSettings =
      DiscordProtos_DiscordUsers_V1_PreloadedUserSettings.StatusSettings()
    statusSettings.customStatus = customStatus

    let activity = try XCTUnwrap(
      statusSettings.gatewayCustomStatusActivity(
        now: Date(timeIntervalSince1970: 1_000)
      )
    )

    XCTAssertEqual(activity.name, "Custom Status")
    XCTAssertEqual(activity.type, .custom)
    XCTAssertEqual(activity.state, "writing tests")
    XCTAssertEqual(activity.emoji?.id?.rawValue, "123")
    XCTAssertEqual(activity.emoji?.name, "pencil")
  }

  func testPreloadedUserSettingsCustomStatusGatewayActivityExpiry() throws {
    var customStatus =
      DiscordProtos_DiscordUsers_V1_PreloadedUserSettings.CustomStatus()
    customStatus.text = "expired"
    customStatus.expiresAtMs = 999

    var statusSettings =
      DiscordProtos_DiscordUsers_V1_PreloadedUserSettings.StatusSettings()
    statusSettings.customStatus = customStatus

    XCTAssertNil(
      statusSettings.gatewayCustomStatusActivity(
        now: Date(timeIntervalSince1970: 1)
      )
    )
  }

  func testEventDecode() throws {

    do {
      let text = """
        {
            "t": null,
            "s": null,
            "op": 11,
            "d": null
        }
        """
      let decoded = try JSONDecoder().decode(
        Gateway.Event.self,
        from: Data(text.utf8)
      )
      XCTAssertEqual(decoded.opcode, .heartbeatAccepted)
      XCTAssertEqual(decoded.sequenceNumber, nil)
      XCTAssertEqual(decoded.type, nil)
      XCTAssertTrue(decoded.data == nil)
    }

    do {
      let text = """
        {
        "t": "MESSAGE_CREATE",
        "s": 130,
        "op": 0,
        "d": {
            "type": 0,
            "tts": false,
            "timestamp": "2022-10-07T19:44:07.295000+00:00",
            "referenced_message": null,
            "pinned": false,
            "nonce": "1028029979960541184",
            "mentions": [],
            "mention_roles": [],
            "mention_everyone": false,
            "member": {
                "roles": [
                    "431921695524126722"
                ],
                "premium_since": null,
                "pending": false,
                "nick": null,
                "mute": false,
                "joined_at": "2020-04-18T00:10:04.414000+00:00",
                "flags": 0,
                "deaf": false,
                "communication_disabled_until": null,
                "avatar": null
            },
            "id": "1028029980795478046",
            "flags": 0,
            "embeds": [],
            "edited_timestamp": null,
            "content": "blah bljhshADh blah",
            "components": [],
            "channel_id": "435923868503506954",
            "author": {
                "username": "GoodUser",
                "public_flags": 0,
                "id": "560661188019488714",
                "discriminator": "4443",
                "avatar_decoration": null,
                "avatar": "845407ec1491b55828cc1f91c2436e8b"
            },
            "attachments": [],
            "guild_id": "439103874612675485"
            }
        }
        """
      let decoded = try JSONDecoder().decode(
        Gateway.Event.self,
        from: Data(text.utf8)
      )
      XCTAssertEqual(decoded.opcode, .dispatch)
      XCTAssertEqual(decoded.sequenceNumber, 130)
      XCTAssertEqual(decoded.type, "MESSAGE_CREATE")
      guard case .messageCreate(let message) = decoded.data else {
        XCTFail("Unexpected data: \(String(describing: decoded.data))")
        return
      }
      XCTAssertEqual(message.type, .default)
      XCTAssertEqual(message.tts, false)
      XCTAssertEqual(
        message.timestamp.date.timeIntervalSince1970,
        1665171847.295
      )
      XCTAssertTrue(message.referenced_message == nil)
      XCTAssertEqual(message.pinned, false)
      XCTAssertEqual(message.nonce?.asString, "1028029979960541184")
      XCTAssertTrue(message.mentions.isEmpty)
      XCTAssertEqual(message.mention_roles, [])
      XCTAssertEqual(message.mention_everyone, false)
      let member = try XCTUnwrap(message.member)
      XCTAssertEqual(member.roles, ["431921695524126722"])
      XCTAssertEqual(member.premium_since?.date, nil)
      XCTAssertEqual(member.pending, false)
      XCTAssertEqual(member.nick, nil)
      XCTAssertEqual(member.mute, false)
      XCTAssertEqual(
        member.joined_at?.date.timeIntervalSince1970,
        1587168604.414
      )
      XCTAssertEqual(member.deaf, false)
      XCTAssertEqual(member.communication_disabled_until?.date, nil)
      XCTAssertEqual(member.avatar, nil)
      XCTAssertEqual(message.id, "1028029980795478046")
      XCTAssertEqual(message.flags, [])
      XCTAssertTrue(message.embeds.isEmpty)
      XCTAssertEqual(message.edited_timestamp?.date, nil)
      XCTAssertEqual(message.content, "blah bljhshADh blah")
      XCTAssertTrue(message.components?.legacy?.isEmpty ?? true)
      XCTAssertEqual(message.channel_id, "435923868503506954")
      let author = try XCTUnwrap(message.author)
      XCTAssertEqual(author.username, "GoodUser")
      XCTAssertEqual(author.public_flags, [])
      XCTAssertEqual(author.id, "560661188019488714")
      XCTAssertEqual(author.discriminator, "4443")
      XCTAssertEqual(author.avatar, "845407ec1491b55828cc1f91c2436e8b")
      XCTAssertTrue(message.attachments.isEmpty)
      XCTAssertEqual(message.guild_id, "439103874612675485")

      let channelMessage = DiscordChannel.Message(message)
      XCTAssertEqual(channelMessage.id, message.id)
      XCTAssertEqual(channelMessage.content, message.content)
      XCTAssertEqual(channelMessage.guild_id, message.guild_id)
    }

    do {
      let text = """
        {
            "t": "GUILD_AUDIT_LOG_ENTRY_CREATE",
            "s": 1806139,
            "op": 0,
            "d": {
                "user_id": "159985870458322944",
                "target_id": "981723329457164289",
                "id": "1063214083664511006",
                "changes": [
                    {
                        "old_value": "Online Members: 24",
                        "new_value": "Online Members: 25",
                        "key": "name"
                    }
                ],
                "action_type": 11,
                "guild_id": "964554609010040873"
            }
        }
        """
      let decoded = try JSONDecoder().decode(
        Gateway.Event.self,
        from: Data(text.utf8)
      )
      XCTAssertEqual(decoded.opcode, .dispatch)
      XCTAssertEqual(decoded.sequenceNumber, 1_806_139)
      XCTAssertEqual(decoded.type, "GUILD_AUDIT_LOG_ENTRY_CREATE")
      /// Audit log events are bot-only; the client accepts them without decoding.
      XCTAssertNil(decoded.data)
    }

    do {
      let text = """
        {
            "t": "VOICE_STATE_UPDATE",
            "s": 134275,
            "op": 0,
            "d": {
                "member": {
                    "user": {
                        "username": "djsole18",
                        "public_flags": 0,
                        "id": "984302584959500299",
                        "global_name": null,
                        "display_name": null,
                        "discriminator": "3901",
                        "bot": false,
                        "avatar_decoration": null,
                        "avatar": "561939e4a1550313f5cfdf2bd6dc3732"
                    },
                    "roles": [],
                    "premium_since": null,
                    "pending": false,
                    "nick": null,
                    "mute": false,
                    "joined_at": null,
                    "flags": 16,
                    "deaf": false,
                    "communication_disabled_until": null,
                    "avatar": null
                },
                "user_id": "984302584959500299",
                "suppress": false,
                "session_id": "8876d2ad2842d6d6e318267227de6eec",
                "self_video": false,
                "self_stream": true,
                "self_mute": false,
                "self_deaf": false,
                "request_to_speak_timestamp": null,
                "mute": false,
                "guild_id": "1002085020187492383",
                "deaf": false,
                "channel_id": "1006294105111920822"
            }
        }
        """
      _ = try JSONDecoder().decode(Gateway.Event.self, from: Data(text.utf8))
    }

    do {
      let text =
        #"{"t":"GUILD_AUDIT_LOG_ENTRY_CREATE","s":451,"op":0,"d":{"user_id":"235148962103951360","target_id":"930562427983130635","reason":"Normal reaction role","id":"1170341258422669332","changes":[{"new_value":[{"name":"sahne","id":"1010902088533938188"}],"key":"$add"}],"action_type":25,"guild_id":"922186320275722322"}}"#
      _ = try JSONDecoder().decode(Gateway.Event.self, from: Data(text.utf8))
    }
  }

  //	func testImageData() throws {
  //		typealias ImageData = Payloads.ImageData
  //		let data = ByteBuffer(data: resource(name: "1kb.png"))
  //
  //		do {
  //			let image = ImageData(file: .init(data: data, filename: "1kb.png"))
  //			let string = image.encodeToString()
  //			XCTAssertEqual(string, base64EncodedImageString)
  //		}
  //
  //		do {
  //			let file = ImageData.decodeFromString(base64EncodedImageString)
  //			XCTAssertEqual(file?.data, data)
  //			XCTAssertEqual(file?.extension, "png")
  //		}
  //	}

  func testReaction() throws {
    XCTAssertNoThrow(try Reaction.unicodeEmoji("❤️"))
    XCTAssertNoThrow(try Reaction.unicodeEmoji("✅"))
    XCTAssertNoThrow(try Reaction.unicodeEmoji("🇮🇷"))
    XCTAssertNoThrow(try Reaction.unicodeEmoji("❌"))
    XCTAssertNoThrow(try Reaction.unicodeEmoji("🆔"))
    XCTAssertNoThrow(try Reaction.unicodeEmoji("📲"))
    XCTAssertNoThrow(try Reaction.unicodeEmoji("🛳️"))
    XCTAssertNoThrow(try Reaction.unicodeEmoji("🧂"))
    XCTAssertNoThrow(try Reaction.unicodeEmoji("🌫️"))
    XCTAssertNoThrow(try Reaction.unicodeEmoji("👌🏿"))
    XCTAssertNoThrow(try Reaction.unicodeEmoji("😀"))
    XCTAssertThrowsError(try Reaction.unicodeEmoji("😀a"))
    XCTAssertThrowsError(try Reaction.unicodeEmoji("😀😀"))
  }

  func testMacroCodableConformance() throws {
    do {
      let json = #"{"some":100}"#
      let data = Data(json.utf8)
      let value = try JSONDecoder().decode(CodableContainer.self, from: data)
      XCTAssertEqual(value.some, .h)
    }

    do {
      let json = #"{"some": 12}"#
      let data = Data(json.utf8)
      let value = try JSONDecoder().decode(CodableContainer.self, from: data)
      XCTAssertEqual(value.some, .a)
    }

    do {
      let json = #"{"some":1}"#
      let data = Data(json.utf8)
      let value = try JSONDecoder().decode(CodableContainer.self, from: data)
      XCTAssertEqual(value.some, .__undocumented(1))
    }

    do {
      let json = #"{"some":"12"}"#
      let data = Data(json.utf8)
      XCTAssertThrowsError(
        try JSONDecoder().decode(CodableContainer.self, from: data)
      )
    }
  }

  func testJSONErrorDecodingJSONError() throws {
    let json = """
      {
      "message": "Invalid authentication token",
      "code": 50014
      }
      """
    let data = Data(json.utf8)
    let response = DiscordHTTPResponse(
      host: "discord.com",
      status: .unauthorized,
      version: .http1_1,
      body: data
    )
    let error = try XCTUnwrap(response.asError())
    if case .jsonError(let jsonError) = error {
      XCTAssertEqual(jsonError.message, "Invalid authentication token")
      XCTAssertEqual(jsonError.code, .invalidAuthenticationToken)
    } else {
      XCTFail("\(error) was not a 'jsonError'")
    }

    let jsonError = try response.decodeJSONError()
    XCTAssertEqual(jsonError.message, "Invalid authentication token")
    XCTAssertEqual(jsonError.code, .invalidAuthenticationToken)
  }

  func testJSONErrorDecodingBadStatusCode() throws {
    let json = """
      {
      "some": "thing"
      }
      """
    let data = Data(json.utf8)
    let response = DiscordHTTPResponse(
      host: "discord.com",
      status: .badGateway,
      version: .http1_1,
      body: data
    )
    let error = try XCTUnwrap(response.asError())
    switch error {
    case .badStatusCode: break
    default:
      XCTFail("\(error) was not a 'badStatusCode'")
    }
  }

  func testActionRowDecode() throws {
    let json =
      #"{"t":"INTERACTION_CREATE","s":6,"op":0,"d":{"version":1,"type":5,"token":"aW50ZXJhY3Rpb246MTA5NTY2MTQ0MDk5NzgwNjE3MjpnWXgzbExDQ0FxVjZHbEZVWWJYQkF5Nm1SOGpYR2JVa0Q2NENWMFdwcnNEQ2Z2OUJ4VlBkRnhTM1BVVW1pSFdxNUZCSFBHWVFOVDQ1RldyellZb2QwZTAwTHJuV0tlODk3TUpxY0xvQkZWUk81MHhJZmR4blUzbWlBS0h2UFhmbw","member":{"user":{"username":"Mahdi BM","public_flags":4194304,"id":"290483761559240704","global_name":null,"display_name":null,"discriminator":"0517","avatar_decoration":null,"avatar":"2df0a0198e00ba23bf2dc728c4db94d9"},"roles":["892920753756975144","970723029262942248","970723101044244510"],"premium_since":null,"permissions":"70368744177663","pending":false,"nick":null,"mute":false,"joined_at":"2021-02-09T09:59:16.364000+00:00","is_pending":false,"flags":0,"deaf":false,"communication_disabled_until":null,"avatar":null},"locale":"en-US","id":"1095661440997806172","guild_locale":"en-US","guild_id":"808638139785936919","entitlements":[],"entitlement_sku_ids":[],"data":{"custom_id":"autoPings;add;match","components":[{"type":1,"components":[{"value":"Hello, dad","type":4,"custom_id":"texts"}]}]},"channel_id":"1016614538398937098","channel":{"type":0,"topic":null,"rate_limit_per_user":0,"position":3,"permissions":"70368744177663","parent_id":"808638139785936920","nsfw":false,"name":"penny","last_message_id":"1095658065069605024","id":"1016614538398937098","guild_id":"808638139785936919","flags":0},"application_id":"1016612301262041098","app_permissions":"70368744177663"}}"#
    let data = Data(json.utf8)
    let decoder = JSONDecoder()
    _ = try decoder.decode(Gateway.Event.self, from: data)
  }

  func testResolvedDataDecode() throws {
    let json = """
      {
          "users": {
              "961607141037326386": {
                  "username": "Royale Alchemist",
                  "public_flags": 0,
                  "id": "961607141037326386",
                  "discriminator": "5658",
                  "bot": false,
                  "avatar_decoration": null,
                  "avatar": "c1c960fd53ae185d0741a9d1294539bb"
              }
          },
          "members": {
              "961607141037326386": {
                  "roles": [
                      "892920753756975144"
                  ],
                  "premium_since": null,
                  "permissions": "4398046511103",
                  "pending": false,
                  "nick": null,
                  "joined_at": "2022-04-17T03:04:52.022000+00:00",
                  "is_pending": false,
                  "flags": 0,
                  "communication_disabled_until": null,
                  "avatar": null
              }
          }
      }
      """
    let data = Data(json.utf8)
    // decode-only since the overnight slimming: user accounts never send it
    _ = try JSONDecoder().decode(
      Interaction.ResolvedData.self,
      from: data
    )
  }

  func testCollectionIsNotEmpty() throws {
    let array1: [String]? = nil
    XCTAssertEqual(array1.isNotEmpty, false)

    let array2: [String]? = []
    XCTAssertEqual(array2.isNotEmpty, false)

    let array3: [String]? = ["a"]
    XCTAssertEqual(array3.isNotEmpty, true)

    let array4: [String] = []
    XCTAssertEqual(array4.isNotEmpty, false)

    let array5: [String] = ["a"]
    XCTAssertEqual(array5.isNotEmpty, true)
  }

  func testMemberListData() throws {
    let jsondata = """
        {"t":"GUILD_MEMBER_LIST_UPDATE","s":10529,"op":0,"d":{"ops":[{"op":"UPDATE","item":{"member":{"user":{"username":"koifishxd","public_flags":256,"primary_guild":{"tag":"RESN","identity_guild_id":"1407192325943197706","identity_enabled":true,"badge":"681eca471aa735fe864068f9cc978760"},"id":"366321739787010059","global_name":"koi","display_name_styles":{"font_id":11,"effect_id":4,"colors":[16777215]},"display_name":"koi","discriminator":"0","collectibles":{"nameplate":{"sku_id":"1462116614131548265","palette":"white","label":"COLLECTIBLES_GOTHICA_NEVERMORE_NP_A11Y","expires_at":null,"asset":"nameplates/gothica/nevermore/"}},"bot":false,"avatar_decoration_data":{"sku_id":"1333866045236314327","expires_at":null,"asset":"a_c86b11a49bb8057ce9c974a6f7ad658a"},"avatar":"3f7db8acc85cb1486372354c131abf69"},"roles":["1166731270542340146","1166731273155379220","1166731271943237662"],"presence":{"user":{"id":"366321739787010059"},"status":"dnd","processed_at_timestamp":1769904353437,"game":{"type":2,"timestamps":{"start":1769904239618,"end":1769904406559},"sync_id":"0O4yYsvGWYhznwzgg4493X","state":"YungLex; Lil Boom; Ciscaux","session_id":"adc9fcb08fb034b7c583a3aa8537730d","party":{"id":"spotify:366321739787010059"},"name":"Spotify","id":"spotify:1","flags":48,"details":"Rose","created_at":1769904353437,"assets":{"large_text":"Rose","large_image":"spotify:ab67616d0000b27375bf186f00f7b0b88cf5c5b9"}},"client_status":{"mobile":"dnd","desktop":"dnd"},"activities":[{"type":2,"timestamps":{"start":1769904239618,"end":1769904406559},"sync_id":"0O4yYsvGWYhznwzgg4493X","state":"YungLex; Lil Boom; Ciscaux","session_id":"adc9fcb08fb034b7c583a3aa8537730d","party":{"id":"spotify:366321739787010059"},"name":"Spotify","id":"spotify:1","flags":48,"details":"Rose","created_at":1769904353437,"assets":{"large_text":"Rose","large_image":"spotify:ab67616d0000b27375bf186f00f7b0b88cf5c5b9"}},{"type":0,"timestamps":{"start":1769904111948},"session_id":"adc9fcb08fb034b7c583a3aa8537730d","name":"Arknights:Endfield","id":"ccee1fabaa8a355e","created_at":1769904114554,"application_id":"1461154307171811401"},{"type":3,"timestamps":{"start":1769897827000},"session_id":"h:abaabb202eccfc32ed3cf58e0823","platform":"desktop","name":"YouTube","id":"f7bc0b2997164dfd","flags":192,"details":"Viewing home page","created_at":1769899338296,"assets":{"large_image":"mp:external/rqJdUc_gEj_38ku0G14If-M0XfkyY0CSaGfaWRAydOU/https/cdn.rcd.gg/PreMiD/websites/Y/YouTube/assets/logo.png"},"application_id":"463097721130188830"}]},"premium_since":null,"pending":false,"nick":null,"mute":false,"joined_at":"2024-06-18T21:52:05.463000+00:00","flags":10,"deaf":false,"communication_disabled_until":null,"banner":null,"avatar":null}},"index":18488}],"online_count":50346,"member_count":132112,"id":"3991716185","guild_id":"1015060230222131221","groups":[{"id":"1133790270467604521","count":2},{"id":"1273266391449079858","count":12},{"id":"1244313853357981787","count":3},{"id":"1042507929485586532","count":822},{"id":"1026534353167208489","count":41},{"id":"1193372588819370156","count":1},{"id":"online","count":40693}]}}
      """.data(using: .utf8)!
    let decoder = JSONDecoder()
    XCTAssertNoThrow(try decoder.decode(Gateway.Event.self, from: jsondata))
    print(try decoder.decode(Gateway.Event.self, from: jsondata))
  }
}

private struct CodableContainer: Codable {

  #if Non64BitSystemsCompatibility
    @UnstableEnum<Int64>
  #else
    @UnstableEnum<Int>
  #endif
  enum UnstableEnumCodableTester: Codable {
    case a  // 12
    case h  // 100
    #if Non64BitSystemsCompatibility
      case __undocumented(Int64)
    #else
      case __undocumented(Int)
    #endif
  }

  var some: UnstableEnumCodableTester
}

private let base64EncodedImageString =
  #"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABEAAAAOCAMAAAD+MweGAAADAFBMVEUAAAAAAFUAAKoAAP8AJAAAJFUAJKoAJP8ASQAASVUASaoASf8AbQAAbVUAbaoAbf8AkgAAklUAkqoAkv8AtgAAtlUAtqoAtv8A2wAA21UA26oA2/8A/wAA/1UA/6oA//8kAAAkAFUkAKokAP8kJAAkJFUkJKokJP8kSQAkSVUkSaokSf8kbQAkbVUkbaokbf8kkgAkklUkkqokkv8ktgAktlUktqoktv8k2wAk21Uk26ok2/8k/wAk/1Uk/6ok//9JAABJAFVJAKpJAP9JJABJJFVJJKpJJP9JSQBJSVVJSapJSf9JbQBJbVVJbapJbf9JkgBJklVJkqpJkv9JtgBJtlVJtqpJtv9J2wBJ21VJ26pJ2/9J/wBJ/1VJ/6pJ//9tAABtAFVtAKptAP9tJABtJFVtJKptJP9tSQBtSVVtSaptSf9tbQBtbVVtbaptbf9tkgBtklVtkqptkv9ttgBttlVttqpttv9t2wBt21Vt26pt2/9t/wBt/1Vt/6pt//+SAACSAFWSAKqSAP+SJACSJFWSJKqSJP+SSQCSSVWSSaqSSf+SbQCSbVWSbaqSbf+SkgCSklWSkqqSkv+StgCStlWStqqStv+S2wCS21WS26qS2/+S/wCS/1WS/6qS//+2AAC2AFW2AKq2AP+2JAC2JFW2JKq2JP+2SQC2SVW2Saq2Sf+2bQC2bVW2baq2bf+2kgC2klW2kqq2kv+2tgC2tlW2tqq2tv+22wC221W226q22/+2/wC2/1W2/6q2///bAADbAFXbAKrbAP/bJADbJFXbJKrbJP/bSQDbSVXbSarbSf/bbQDbbVXbbarbbf/bkgDbklXbkqrbkv/btgDbtlXbtqrbtv/b2wDb21Xb26rb2//b/wDb/1Xb/6rb////AAD/AFX/AKr/AP//JAD/JFX/JKr/JP//SQD/SVX/Sar/Sf//bQD/bVX/bar/bf//kgD/klX/kqr/kv//tgD/tlX/tqr/tv//2wD/21X/26r/2////wD//1X//6r////qm24uAAAA1ElEQVR42h1PMW4CQQwc73mlFJGCQChFIp0Rh0RBGV5AFUXKC/KPfCFdqryEgoJ8IX0KEF64q0PPnow3jT2WxzNj+gAgAGfvvDdCQIHoSnGYcGDE2nH92DoRqTYJ2bTcsKgqhIi47VdgAWNmwFSFA1UAAT2sSFcnq8a3x/zkkJrhaHT3N+hD3aH7ZuabGHX7bsSMhxwTJLr3evf1e0nBVcwmqcTZuatKoJaB7dSHjTZdM0G1HBTWefly//q2EB7/BEvk5vmzeQaJ7/xKPImpzv8/s4grhAxHl0DsqGUAAAAASUVORK5CYII="#
