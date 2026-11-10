//
//  MessageDrainStore.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 31/10/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import Foundation
import AicordKit
import PhotosUI
import SwiftUI

@MainActor
@Observable
class MessageDrainStore: DiscordDataStore {
  var gateway: GatewayStore?
  var eventTask: Task<Void, Never>?

  init() {}

  // MARK: - Protocol Methods

  func setupEventHandling() {
    guard let gateway = gateway?.gateway else { return }
    let events = gateway.events
    eventTask = Task {
      for await event in events {
        switch event.data {
        case .messageCreate(let message):
          // when a message is created, we check if its in pendingMessages, and its nonce matches.
          // the nonce of the message received will match a key of pendingMessages if its one we sent.
          if let nonce = message.nonce?.asString,
            let messageNonceSnowflake = Optional(
              MessageSnowflake(nonce))
          {
            // remove from pending as its been sent successfully
            //            var transaction = Transaction()
            //            transaction.disablesAnimations = true
            //            _ = withTransaction(transaction) {
            pendingMessages[message.channel_id, default: [:]]
              .removeValue(
                forKey: messageNonceSnowflake
              )
            //            }
            // also remove from failed messages if it was there
            failedMessages.removeValue(
              forKey: messageNonceSnowflake)
            // also remove from message tasks if it was there
            messageTasks.removeValue(
              forKey: messageNonceSnowflake)
          }
          break
        default:
          break
        }
      }
    }
  }

  // Messages get sent innit, but heres how it works.
  // If a message is in the pendingMessages dict, it wil lexist in all of the dictionaries below.
  // When a message is sent, it has a temporary snowflake assigned to it which is a generated nonce with the current timestamp.
  // When the message is successfully sent, it is removed from all dictionaries.
  // If a failure occurs, it is kept in pendingMessages and an error is added to failedMessages.
  // when a message send does fail, the messageTasks queue is halted, and all remaining messages stay in limbo until the failed message is retried.
  // If a message is retried, the error is removed from failedMessages and the send task is re-executed.

  var pendingMessages = [
    ChannelSnowflake: OrderedDictionary<
      MessageSnowflake, Payloads.CreateMessage
    >
  ]()
  var failedMessages: [MessageSnowflake: Error] = [:]
  var messageSendQueueTask: Task<Void, Never>?
  var messageTasks: [MessageSnowflake: @MainActor () async throws -> Void] = [:]

  func startQueueIfNeeded() {
    guard messageSendQueueTask == nil else { return }
    setupQueueTask()
  }

  func setupQueueTask() {
    messageSendQueueTask?.cancel()
    messageSendQueueTask = Task { [weak self] in
      guard let self else { return }
      defer { self.messageSendQueueTask = nil }
      guard !self.messageTasks.isEmpty else { return }
      let (id, task) = self.messageTasks.first!
      do {
        try await task()
        self.messageTasks.removeValue(forKey: id)
        self.failedMessages.removeValue(forKey: id)

        // continue to next message
        self.setupQueueTask()
      } catch {
        // halt the queue on first failure.
        print(
          "[MessageDrainStore Queue] Halting queue due to failure on nonce:",
          id
        )
        return
      }
    }
  }

  // key methods

  func send(_ vm: ChatView.InputBar.InputVM, in channel: ChannelSnowflake) {
    if case .edit = vm.messageAction {
      _editMessage(vm, in: channel)
      return
    }
    let parts = Self.parts(of: vm.content, premium: gateway?.user.premiumKind ?? .none)
    guard parts.count > 1 else {
      _enqueueMessage(vm, in: channel)
      return
    }
    // a long message goes as several, in order: the reply is the first,
    // the files come with the last
    for (index, text) in parts.enumerated() {
      let part = ChatView.InputBar.InputVM(channelStore: vm.channelStore)
      part.sendsTypingIndicator = false
      part.content = text
      if index == 0 { part.messageAction = vm.messageAction }
      if index == parts.count - 1 {
        part.isResetting = true
        part.uploadItems = vm.uploadItems
        part.isResetting = false
        part.adoptTempFiles(from: vm)
      }
      _enqueueMessage(part, in: channel)
    }
  }

  /// The messages `content` is sent as: one, or several when it's over the
  /// account's limit and splitting is on.
  static func parts(of content: String, premium: DiscordUser.PremiumKind) -> [String] {
    let limit = ComposerPreferences.characterLimit(for: premium)
    guard ComposerPreferences.splitsLongMessages, MessageSplitter.length(content) > limit else {
      return [content]
    }
    let parts = MessageSplitter.split(content, limit: limit)
    return parts.isEmpty ? [content] : parts
  }

  // MARK: - Attachments

  /// A file as it will be uploaded: its final name, bytes and size.
  struct PreparedUpload: Sendable {
    enum Payload: Sendable {
      case data(Data)
      case file(URL)
    }
    var filename: String
    var payload: Payload
    var size: Int
    /// A stripped copy made for this upload, removed once it's sent.
    var temporaryCopy: URL?

    func discardCopy() {
      if let temporaryCopy {
        try? FileManager.default.removeItem(at: temporaryCopy.deletingLastPathComponent())
      }
    }
  }

  /// Names each file (randomly when that's on) and takes location and camera
  /// details out of photos when that's on.
  nonisolated static func prepareUploads(
    _ items: [ChatView.InputBar.InputVM.UploadItem]
  ) async throws -> [PreparedUpload] {
    var prepared: [PreparedUpload] = []
    for item in items {
      switch item {
      case .pickerItem(_, let pickerItem):
        guard var data = try await pickerItem.loadTransferable(type: Data.self) else {
          throw "Failed to load picker item data."
        }
        let fileExt =
          pickerItem.supportedContentTypes.first?.preferredFilenameExtension ?? "png"
        if let stripped = ComposerPreferences.strippedPhoto(data) { data = stripped }
        let name = "\(pickerItem.itemIdentifier ?? UUID().uuidString).\(fileExt)"
        prepared.append(
          .init(
            filename: ComposerPreferences.uploadName(for: name), payload: .data(data),
            size: data.count))
      case .file(_, let url, let size):
        let name = ComposerPreferences.uploadName(for: url.lastPathComponent)
        if let copy = ComposerPreferences.strippedPhoto(at: url) {
          let copySize = (try? copy.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
          prepared.append(
            .init(filename: name, payload: .file(copy), size: copySize, temporaryCopy: copy))
        } else {
          prepared.append(.init(filename: name, payload: .file(url), size: Int(size)))
        }
      #if os(iOS)
        case .cameraPhoto(_, let image):
          // PNG from the camera carries no location
          guard let data = image.pngData() else { throw "Failed to encode the photo." }
          prepared.append(
            .init(filename: "\(UUID().uuidString).png", payload: .data(data), size: data.count))
        case .cameraVideo(_, let url):
          let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
          prepared.append(
            .init(
              filename: ComposerPreferences.uploadName(for: url.lastPathComponent),
              payload: .file(url), size: size))
      #endif
      }
    }
    return prepared
  }

  /// Text as sent, with emoticons turned into emoji when Discord's setting is on.
  private func outgoing(_ content: String) -> String {
    gateway?.settings.convertsEmoticons == true ? Emoticons.convert(content) : content
  }

  private func _editMessage(_ vm: ChatView.InputBar.InputVM, in channel: ChannelSnowflake) {
    guard let gateway = gateway?.gateway else { return }
    guard case .edit(let origMessage) = vm.messageAction else { return }
    let message = Payloads.EditMessage.init(content: outgoing(vm.content))

    Task {
      do {
        try await gateway.client.updateMessage(
          channelId: channel, messageId: origMessage.id,
          payload: message
        )
        .guardSuccess()
      } catch {
        print(
          "[MessageDrainStore EditMessage] Failed to edit message:",
          error)
      }
    }
  }

  private func _enqueueMessage(_ vm: ChatView.InputBar.InputVM, in channel: ChannelSnowflake) {
    // the message instance will die inside the task
    guard let gatewayStore = gateway, let gateway = gatewayStore.gateway else { return }

    // the swiftui side inits the message with a nonce already btw
    // set our message up
    let nonce: MessageSnowflake = try! .makeFake(date: .now)
    var message = Payloads.CreateMessage(
      content: outgoing(vm.content),
      nonce: .string(nonce.rawValue)
    )
    if !vm.stickerIDs.isEmpty {
      message.sticker_ids = vm.stickerIDs.map(\.rawValue)
      if vm.content.isEmpty { message.content = nil }
    }
    if case .reply(let replyMsg, let mention) = vm.messageAction {
      message.message_reference = .init(
        type: .reply,
        message_id: replyMsg.id,
        channel_id: replyMsg.channel_id,
        guild_id: replyMsg.guild_id
      )
      if !mention {
        message.allowed_mentions = .init(replied_user: false)
      }
    }
    let task: @MainActor () async throws -> Void = { [weak self] in
      guard let self else { return }
      do {
        print("[SendTask] Starting send for nonce:", nonce)
        print("[SendTask] Channel:", channel)

        var message = self.pendingMessages[channel, default: [:]][nonce]!
        message.attachments = []  // nil by default, allows appends

        print("[SendTask] Initial content:", message.content ?? "<nil>")
        if vm.uploadItems.isEmpty == false {
          print("[SendTask] Upload item count:", vm.uploadItems.count)
        }

        if !vm.uploadItems.isEmpty {
          print(
            "[SendTask Attachments] Preparing upload attachment metadata"
          )

          // names, stripped photos and sizes are settled first: Discord is told
          // each file's size before it's uploaded
          let prepared = try await Self.prepareUploads(vm.uploadItems)
          defer { prepared.forEach { $0.discardCopy() } }
          let uploadAttachments = prepared.enumerated().map { index, upload in
            Payloads.CreateAttachments.UploadAttachment(
              id: .init(String(index)),
              filename: upload.filename,
              file_size: upload.size
            )
          }

          print(
            "[SendTask Attachments] Creating attachments via Discord API"
          )

          let createdAttachmentsReq = try await self
            .gateway!.client
            .createAttachments(
              channelID: channel,
              payload: .init(files: uploadAttachments)
            )

          try createdAttachmentsReq.guardSuccess()

          let createdAttachments: [Int: Gateway.CloudAttachment] =
            try createdAttachmentsReq.decode()
            .attachments
            .reduce(into: [:]) { partialResult, attachment in
              let index = Int(attachment.id!.rawValue)!
              partialResult[index] = attachment
            }

          print(
            "[SendTask Attachments] Discord returned \(createdAttachments.count) upload URLs"
          )

          let uploadedFiles = try await withThrowingTaskGroup(
            of: (Int, Payloads.Attachment).self,
            returning: [Payloads.Attachment].self
          ) { group in
            for (index, attachment) in createdAttachments {
              let upload = prepared[index]
              group.addTask {
                var req = URLRequest(url: URL(string: attachment.upload_url)!)
                req.httpMethod = "PUT"
                let response: URLResponse
                switch upload.payload {
                case .data(let data):
                  (_, response) = try await URLSession.shared.upload(for: req, from: data)
                case .file(let fileURL):
                  let access = fileURL.startAccessingSecurityScopedResource()
                  defer { if access { fileURL.stopAccessingSecurityScopedResource() } }
                  (_, response) = try await URLSession.shared.upload(for: req, fromFile: fileURL)
                }
                print(
                  "[SendTask Upload] attachment id=\(index) status:",
                  (response as? HTTPURLResponse)?.statusCode ?? -1
                )

                let payloadAttachment = Payloads.Attachment(
                  index: index,
                  filename: upload.filename,
                  uploaded_filename: attachment.upload_filename
                )
                return (index, payloadAttachment)
              }
            }

            var attachmentsResult: [Payloads.Attachment] = []
            for try await (_, attachment) in group {
              attachmentsResult.append(attachment)
            }
            return attachmentsResult
          }
          message.attachments?.append(contentsOf: uploadedFiles)

          print(
            "[SendTask Attachments] Final attachment payload count:",
            message.attachments?.count ?? 0
          )
        }

        print("[SendTask] Sending message payload")
        if vm.uploadItems.isEmpty == false {
          print("[SendTask] Attachments:", message.attachments ?? [])
        }

        try await gateway.client.createMessage(
          channelId: channel,
          payload: message
        ).guardSuccess()

        print("[SendTask] Message send SUCCESS nonce:", nonce)

        // remove from pending and failed
        //        var transaction = Transaction()
        //        transaction.disablesAnimations = true
        //        _ = withTransaction(transaction) {
        self.pendingMessages[channel, default: [:]].removeValue(
          forKey: nonce)
        //        }
        self.failedMessages.removeValue(forKey: nonce)
        self.messageTasks.removeValue(forKey: nonce)

        vm.cleanupAllTempFiles()
      } catch {
        print("[SendTask] Message send FAILED nonce:", nonce)
        print("[SendTask] Error:", error)
        self.failedMessages[nonce] = error
        throw error
      }
    }

    // store in pending
    pendingMessages[channel, default: [:]]
      .updateValue(message, forKey: nonce)
    // store task
    messageTasks[nonce] = task

    // notify ui to scroll to the newly pending message
    gatewayStore.getChannelStore(for: channel).requestScrollToBottom()

    startQueueIfNeeded()
  }

  /// Removes an enqueued message from all tracking dictionaries, usually used to give up on a message.
  /// - Parameters:
  ///   - nonce: The nonce of the message to remove.
  ///   - channel: The channel the message is in.
  func removeEnqueuedMessage(
    nonce: MessageSnowflake,
    in channel: ChannelSnowflake
  ) {
    // remove from all dicts
    //    var transaction = Transaction()
    //    transaction.disablesAnimations = true
    //    _ = withTransaction(transaction) {
    pendingMessages[channel]?.removeValue(forKey: nonce)
    //    }
    failedMessages.removeValue(forKey: nonce)
    messageTasks.removeValue(forKey: nonce)
  }
}
