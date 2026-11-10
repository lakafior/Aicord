//
//  ComposerSettings.swift
//  Aicord
//
//  Settings → Chat: typing privacy, link cleaning, private files, long
//  messages, the upload service for large files and emoji and stickers
//  without Nitro. All only on this device.
//

import AicordKit
import SwiftUI

struct ComposerSettings: View {
  typealias Key = ComposerPreferences.Key
  typealias TypingIndicator = ComposerPreferences.TypingIndicator
  typealias ServiceKind = ComposerPreferences.UploadServiceKind

  @Environment(\.gateway) var gw

  @AppStorage(Key.typingIndicator) private var typingIndicator = TypingIndicator.always
  @AppStorage(Key.cleansLinks) private var cleansLinks = true
  @AppStorage(Key.privateFilenames) private var privateFilenames = false
  @AppStorage(Key.stripsPhotoMetadata) private var stripsPhotoMetadata = false
  @AppStorage(Key.splitsLongMessages) private var splitsLongMessages = true
  @AppStorage(Key.uploadService) private var uploadService = ServiceKind.none
  @AppStorage(Key.litterboxExpiry) private var litterboxExpiry = ExternalUpload.LitterboxExpiry.day
  @AppStorage(Key.nitroFreeEmoji) private var nitroFreeEmoji = false
  @AppStorage(Key.nitroFreeStickers) private var nitroFreeStickers = false

  var body: some View {
    Section {
      Picker("Typing Indicator", selection: $typingIndicator) {
        Text("Always").tag(TypingIndicator.always)
        Text("Only in Direct Messages").tag(TypingIndicator.directMessagesOnly)
        Text("Never").tag(TypingIndicator.never)
      }
    } header: {
      Text("Typing")
    } footer: {
      Text(
        "Whether others see “… is typing” while you write. When it's off, Aicord simply doesn't tell Discord you're typing; nothing else changes."
      )
    }

    Section {
      toggle("Clean Links When Pasting", isOn: $cleansLinks)
      if cleansLinks {
        SettingsPageLink("Link Rules") { LinkRulesSettings() }
      }
    } header: {
      Text("Links")
    } footer: {
      Text(
        "Pasted links lose tracking parameters such as utm_…, fbclid and the si of YouTube and Spotify shares. The rest of the link stays as it was."
      )
    }

    Section {
      toggle("Private File Names", isOn: $privateFilenames)
      toggle("Remove Location from Photos", isOn: $stripsPhotoMetadata)
    } header: {
      Text("Attachments")
    } footer: {
      Text(
        "Private names upload files under a random name with the same extension (IMG_2041.HEIC becomes k3v9x0q2m7ab.HEIC); spoiler files stay spoilers. Removing location also takes out the camera, lens and date details of JPEG, HEIC, PNG and TIFF photos, keeping their orientation. Videos are sent as they are."
      )
    }

    Section {
      toggle("Split Long Messages", isOn: $splitsLongMessages)
    } header: {
      Text("Long Messages")
    } footer: {
      Text(
        "Text over \(ComposerPreferences.characterLimit(for: gw.user.premiumKind)) characters goes as several messages, split between paragraphs and sentences and never inside a code block. The field shows how many before you send."
      )
    }

    Section {
      Picker("Service", selection: $uploadService) {
        Text("None").tag(ServiceKind.none)
        Text(verbatim: "catbox.moe").tag(ServiceKind.catbox)
        Text(verbatim: "litterbox.catbox.moe").tag(ServiceKind.litterbox)
        Text("Your S3 or R2 Bucket").tag(ServiceKind.s3)
      }
      switch uploadService {
      case .none:
        EmptyView()
      case .catbox:
        SecretField(title: "User Hash (Optional)", item: .catboxUserHash)
      case .litterbox:
        Picker("Keep For", selection: $litterboxExpiry) {
          Text("1 Hour").tag(ExternalUpload.LitterboxExpiry.hour)
          Text("12 Hours").tag(ExternalUpload.LitterboxExpiry.halfDay)
          Text("1 Day").tag(ExternalUpload.LitterboxExpiry.day)
          Text("3 Days").tag(ExternalUpload.LitterboxExpiry.threeDays)
        }
      case .s3:
        S3BucketSettings()
      }
    } header: {
      Text("Files Too Large for Discord")
    } footer: {
      Text(
        "A file over Discord's limit can go to the service you choose here, and its link goes into your message. Aicord asks before every file, and never uploads anywhere else. Anyone with the link can download the file. catbox keeps files for good (up to 200 MB), litterbox for the time you pick (up to 1 GB)."
      )
    }

    Section {
      toggle("Emoji Without Nitro", isOn: $nitroFreeEmoji)
      toggle("Stickers Without Nitro", isOn: $nitroFreeStickers)
    } header: {
      Text("Without Nitro")
    } footer: {
      Text(
        "Emoji and stickers you can't use without Nitro go into the message as a link to their image, which Discord shows below it. It's an ordinary message with a link, but it works around a paid feature, so it's off unless you turn it on. Lottie stickers can't be sent this way."
      )
    }
  }

  private func toggle(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
    Toggle(title, isOn: isOn)
      #if os(macOS)
        .toggleStyle(.switch)
      #endif
  }
}

/// Every link rule with its own switch.
struct LinkRulesSettings: View {
  @State private var disabled = ComposerPreferences.disabledLinkRules

  var body: some View {
    Form {
      Section {
        ForEach(LinkCleaner.rules) { rule in
          Toggle(isOn: binding(for: rule.id)) {
            VStack(alignment: .leading, spacing: 2) {
              Text(LocalizedStringKey(rule.name))
              Text(verbatim: rule.parameters.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
              if !rule.hosts.isEmpty {
                Text(verbatim: rule.hosts.prefix(4).joined(separator: ", "))
                  .font(.caption2)
                  .foregroundStyle(.tertiary)
              }
            }
          }
          #if os(macOS)
            .toggleStyle(.switch)
          #endif
        }
      } footer: {
        Text("A * matches every parameter starting with the text before it.")
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Link Rules")
  }

  private func binding(for id: String) -> Binding<Bool> {
    Binding(
      get: { !disabled.contains(id) },
      set: { on in
        if on { disabled.remove(id) } else { disabled.insert(id) }
        ComposerPreferences.disabledLinkRules = disabled
      }
    )
  }
}

/// A secret kept in the keychain, saved when the field loses focus or on return.
private struct SecretField: View {
  var title: LocalizedStringKey
  var item: UploadKeychain.Item
  @State private var value = ""

  var body: some View {
    SecureField(title, text: $value)
      .onAppear { value = UploadKeychain.value(item) ?? "" }
      .onSubmit { UploadKeychain.set(value, for: item) }
      .onChange(of: value) { _, new in UploadKeychain.set(new, for: item) }
      .autocorrectionDisabled()
  }
}

private struct S3BucketSettings: View {
  @State private var bucket = ComposerPreferences.s3Bucket

  var body: some View {
    Group {
      TextField("Endpoint", text: $bucket.endpoint, prompt: Text(verbatim: "https://<account>.r2.cloudflarestorage.com"))
      TextField("Bucket", text: $bucket.bucket)
      TextField("Region", text: $bucket.region, prompt: Text(verbatim: "auto"))
      TextField("Public Address", text: $bucket.publicBaseURL, prompt: Text(verbatim: "https://files.example.com"))
      TextField("Folder (Optional)", text: $bucket.prefix, prompt: Text(verbatim: "aicord"))
      SecretField(title: "Access Key ID", item: .s3AccessKeyID)
      SecretField(title: "Secret Access Key", item: .s3SecretAccessKey)
      if !bucket.isComplete {
        Text("Fill in the endpoint, bucket, region and public address, where the files can be read.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .autocorrectionDisabled()
    #if os(iOS)
      .textInputAutocapitalization(.never)
    #endif
    .onChange(of: bucket) { _, new in ComposerPreferences.s3Bucket = new }
  }
}
