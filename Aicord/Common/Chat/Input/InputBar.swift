//
//  InputBar.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 17/10/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import PhotosUI
import SwiftUI

extension ChatView {
  struct InputBar: View {
    static var inputVMs: [ChannelSnowflake: InputVM] = [:]
    @Environment(\.appState) var appState
    @Environment(\.gateway) var gw
    @Environment(\.theme) var theme

    /// The accent when it also colours icons, otherwise `fallback`.
    private func iconTint(_ fallback: Color) -> Color {
      Theming.shared.accentTintsChrome ? theme.common.accent : fallback
    }
    var vm: ChannelStore
    @State var inputVM: InputVM
    @State private var isManualUpdate = false

    static func vm(for channel: ChannelStore) -> InputVM {
      if let existingVM = InputBar.inputVMs[channel.channelId] {
        return existingVM
      } else {
        let newVM = InputVM(channelStore: channel)
        InputBar.inputVMs[channel.channelId] = newVM
        return newVM
      }
    }

    init(vm: ChannelStore) {
      self.vm = vm
      self._inputVM = State(initialValue: InputBar.vm(for: vm))
    }

    /// Puts a picked emoji at the end of the message, as Discord's text form.
    func insertEmoji(_ emoji: Emoji) {
      let text: String
      if let id = emoji.id, let name = emoji.name {
        text =
          emoji.animated == true
          ? DiscordUtils.customAnimatedEmoji(name: name, id: id)
          : DiscordUtils.customEmoji(name: name, id: id)
      } else if let name = emoji.name {
        text = name
      } else {
        return
      }
      let separator = inputVM.content.isEmpty || inputVM.content.hasSuffix(" ") ? "" : " "
      inputVM.content += separator + text
    }

    /// Sends a sticker the account can use, or puts its link in the message
    /// when "Stickers Without Nitro" is on.
    func pickSticker(_ sticker: Sticker) {
      switch EmojiPicker.stickerUse(sticker, gw: gw, currentGuildID: vm.guildStore?.guildId) {
      case .send:
        guard let channelId = appState.selectedChannel else { return }
        let message = InputVM(channelStore: vm)
        message.sendsTypingIndicator = false
        message.stickerIDs = [sticker.id]
        if case .reply = inputVM.messageAction {
          message.messageAction = inputVM.messageAction
          inputVM.messageAction = nil
        }
        gw.messageDrain.send(message, in: channelId)
      case .link(let link):
        let separator = inputVM.content.isEmpty || inputVM.content.hasSuffix(" ") ? "" : " "
        inputVM.content += separator + link
      case .locked:
        break
      }
    }

    #if os(iOS)
      struct PickerInteractionProperties {
        var storedKeyboardHeight: CGFloat = 0
        var dragOffset: CGFloat = 0
        var showPhotosPicker: Bool = false
        var showFilePicker: Bool = false
        var showEmojiPicker: Bool = false

        var keyboardHeight: CGFloat {
          storedKeyboardHeight == 0 ? 300 : storedKeyboardHeight
        }

        var pickerShown: Bool {
          showPhotosPicker || showFilePicker || showEmojiPicker
        }

        @MainActor
        var safeArea: UIEdgeInsets {
          if let safeArea = UIApplication.shared.connectedScenes.compactMap({
            ($0 as? UIWindowScene)?.keyWindow
          }).first?.safeAreaInsets {
            return safeArea
          }
          return .zero
        }

        @MainActor
        var screenSize: CGSize {
          if let screen = UIApplication.shared.connectedScenes.compactMap({
            ($0 as? UIWindowScene)?.screen
          }).first {
            return screen.bounds.size
          }
          return .zero
        }

        var animation: Animation {
          .interpolatingSpring(duration: 0.2, bounce: 0, initialVelocity: 0)
        }
      }

      @State private var properties = PickerInteractionProperties()

      @State var pickersClosedWhenChatClosed:
        (photos: Bool, files: Bool, emoji: Bool, keyboardFocused: Bool) = (
          false, false, false, false
        )
      @State var cameraPickerPresented: Bool = false
      @State var emojiPickerSheetHeight: CGFloat = 300
      @State var emojiPickerDetent: PresentationDetent = .height(300)

      func presentEmojiPicker() {
        emojiPickerSheetHeight = properties.keyboardHeight
        emojiPickerDetent = .height(properties.keyboardHeight)
        properties.showEmojiPicker = true
      }
    #else
      @State private var fileImporterPresented: Bool = false
      @State private var showingEmojiPicker: Bool = false
    #endif

    @State private var isFocused: Bool = false
    @State var filesRemovedDuringSelection: Error? = nil

    enum SelectionError: LocalizedError {
      /// `hint` says why the upload service didn't take the file instead.
      case filesPastLimit(limit: Int, hint: String)
      case filesEmpty

      var errorDescription: String? {
        switch self {
        case .filesPastLimit(let limit, let hint):
          let formatter = ByteCountFormatter()
          formatter.allowedUnits = [.useBytes, .useKB, .useMB]
          formatter.countStyle = .file
          let formattedLimit = formatter.string(fromByteCount: Int64(limit))
          let limitText = String(localized: "Please keep files under \(formattedLimit).")
          return hint.isEmpty ? limitText : limitText + "\n\n" + hint
        case .filesEmpty:
          return "Empty files cannot be uploaded."
        }
      }

      /// Why the upload service didn't take the file instead.
      @MainActor
      static func uploadServiceHint(for size: Int) -> String {
        if ComposerPreferences.uploadServiceKind == .none {
          return String(
            localized: "To send larger files, choose an upload service in Settings → Chat → Files Too Large for Discord.")
        }
        guard let service = ComposerPreferences.uploadService else {
          return String(
            localized: "The upload service in Settings → Chat → Files Too Large for Discord isn't fully set up.")
        }
        if let serviceLimit = service.sizeLimit, Int64(size) > serviceLimit {
          let formatted = ByteCountFormatter.string(fromByteCount: serviceLimit, countStyle: .file)
          return String(localized: "It's also over the \(formatted) that \(service.host) takes.")
        }
        return ""
      }
    }

    /// Behind the message field: the chat's own background, so the chat and
    /// the field read as one surface, as in Messages. On iOS the last
    /// messages fade out above it instead of ending at a bar's edge.
    @ViewBuilder
    private var composerBackground: some View {
      #if os(macOS)
        theme.chatBackground
      #else
        let color = theme.chatBackground
        VStack(spacing: 0) {
          LinearGradient(colors: [color.opacity(0), color], startPoint: .top, endPoint: .bottom)
            .frame(height: 16)
          color
        }
        .padding(.top, -16)
        .ignoresSafeArea(edges: .bottom)
      #endif
    }

    var body: some View {
      VStack {
        ZStack(alignment: .top) {
          VStack {
            if inputVM.uploadItems.isEmpty == false {
              AttachmentPreviewBar(inputVM: inputVM)
                .frame(height: 60)
            }

            ExternalUploadProgress(inputVM: inputVM)

            if inputVM.messageAction != nil {
              messageActionBar
                .padding(.bottom, -4)
                .transition(
                  .offset(y: 25)
                    .combined(with: .opacity)
                )
            }

            if let draft = inputVM.slashDraft {
              SlashCommandComposer(draft: draft, channel: vm) {
                inputVM.slashDraft = nil
              }
              .padding([.horizontal, .bottom], 8)
              .transition(.opacity)
            } else {
              if let query = slashQuery {
                SlashCommandSuggestions(channel: vm, query: query) { entry in
                  inputVM.slashDraft = SlashCommandDraft(entry: entry)
                  inputVM.content = ""
                }
              }
              lengthNote
              messageInputBar
            }
          }
          .padding(.top, 4)

          TypingIndicatorBar(vm: vm)
            .background(theme.chatBackground)
            .padding(.top, -18)  // away from bar
        }
        .background { composerBackground }
      }
      #if os(iOS)
        .animation(properties.animation, value: animatedKeyboardHeight)
        .animation(properties.animation, value: inputVM.content.isEmpty)
        .animation(properties.animation, value: inputVM.uploadItems.isEmpty)
      #endif
      .animation(.default, value: inputVM.messageAction.debugDescription)
      .animation(.default, value: inputVM.uploadItems)
      .dropDestination(for: URL.self) { urls, _ in
        inputVM.selectedFiles = filterUploadableURLs(urls)
        return !urls.isEmpty
      }
      .modifier(ExternalUploadModifier(inputVM: inputVM))
    }

    /// "Sends as 3 messages" once the text is over the limit, or a warning
    /// when splitting is off.
    @ViewBuilder
    private var lengthNote: some View {
      let limit = ComposerPreferences.characterLimit(for: gw.user.premiumKind)
      let length = MessageSplitter.length(inputVM.content)
      if length > limit, inputVM.slashDraft == nil {
        let editing: Bool = {
          if case .edit = inputVM.messageAction { return true }
          return false
        }()
        let parts =
          editing ? 1 : MessageDrainStore.parts(of: inputVM.content, premium: gw.user.premiumKind).count
        Group {
          if parts > 1 {
            Label("Sends as \(parts) messages", systemImage: "text.append")
              .foregroundStyle(.secondary)
          } else {
            Label("\(length) / \(limit) characters", systemImage: "exclamationmark.triangle")
              .foregroundStyle(.orange)
          }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 16)
        .transition(.opacity)
      }
    }

    @ViewBuilder
    var messageInputBar: some View {
      HStack(alignment: .bottom, spacing: 8) {
        mediaPickerButton
          .disabled(
            {
              switch inputVM.messageAction {
              case .edit: return true
              default: return false
              }
            }()
          )

        textField
      }
      .padding([.horizontal, .bottom], 8)
      .padding(.top, 4)
      .geometryGroup()
      #if os(iOS)
        .padding(.bottom, animatedKeyboardHeight)
        .onReceive(
          NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillChangeFrameNotification
          )
        ) { userInfo in
          guard isFocused else { return }
          if let keyboardFrame = userInfo.userInfo?[
            UIResponder.keyboardFrameEndUserInfoKey
          ] as? NSValue {
            let height = keyboardFrame.cgRectValue.height
            properties.storedKeyboardHeight = max(
              height - properties.safeArea.bottom,
              0
            )
          }
        }  // get kb height
        .sheet(isPresented: $properties.showPhotosPicker) {
          PhotosPicker(
            "",
            selection: $inputVM.selectedPhotos,
            maxSelectionCount: 10,
            selectionBehavior: .continuous,
            preferredItemEncoding: .compatible
          )
          .photosPickerStyle(.inline)
          .photosPickerDisabledCapabilities([
            .stagingArea, .sensitivityAnalysisIntervention,
          ])
          .presentationDetents([
            .height(properties.keyboardHeight), .large,
          ])
          .presentationBackgroundInteraction(
            .enabled(upThrough: .height(properties.keyboardHeight))
          )  // allow whilst not expanded
        }
        .sheet(isPresented: $properties.showFilePicker) {
          DocumentPickerViewController { urls in
            inputVM.selectedFiles = filterUploadableURLs(urls)
          }
          .presentationBackground(.clear)
          .presentationDetents([
            .height(properties.keyboardHeight), .large,
          ])
          .presentationBackgroundInteraction(
            .enabled(upThrough: .height(properties.keyboardHeight))
          )
        }
        .sheet(isPresented: $properties.showEmojiPicker) {
          EmojiPicker(detent: $emojiPickerDetent)
            .guild(vm.guildStore?.guildId)
            .onPickedEmoji { insertEmoji($0) }
            .onPickedSticker { pickSticker($0) }
          .presentationDetents(
            [.height(emojiPickerSheetHeight), .large],
            selection: $emojiPickerDetent
          )
          .presentationBackgroundInteraction(
            .enabled(upThrough: .height(emojiPickerSheetHeight))
          )
        }
        .fullScreenCover(isPresented: $cameraPickerPresented) {
          CameraPicker { result in
            switch result {
            case .success(let media):
              switch media {
              case .photo(let image):
                onImageCaptured(image)
              case .video(let videoURL):
                onVideoCaptured(videoURL)
              }
            case .failure(let error):
              print("CameraPicker error: \(error)")
            }
          }
          .ignoresSafeArea()
        }
        .onChange(of: isFocused) {
          guard !isManualUpdate else { return }
          if isFocused {
            properties.showPhotosPicker = false
            properties.showFilePicker = false
            properties.showEmojiPicker = false
          }
        }  // dismiss picker when keyboard is activated
        .onChange(of: properties.pickerShown) {
          guard !isManualUpdate else { return }
          if properties.pickerShown {
            isFocused = false
          }
        }  // dismiss keyboard when picker is activated
        .onChange(of: appState.chatOpen) {
          if appState.chatOpen == false {
            pickersClosedWhenChatClosed.photos =
              properties.showPhotosPicker
            pickersClosedWhenChatClosed.files = properties.showFilePicker
            pickersClosedWhenChatClosed.emoji = properties.showEmojiPicker
            pickersClosedWhenChatClosed.keyboardFocused = isFocused
            properties.showPhotosPicker = false
            properties.showFilePicker = false
            properties.showEmojiPicker = false
            isFocused = false
          } else {
            // restore pickers if they were open before chat closed
            if pickersClosedWhenChatClosed.photos {
              properties.showPhotosPicker = true
            }
            if pickersClosedWhenChatClosed.files {
              properties.showFilePicker = true
            }
            if pickersClosedWhenChatClosed.emoji {
              presentEmojiPicker()
            }
            if pickersClosedWhenChatClosed.keyboardFocused {
              isFocused = true
            }
            pickersClosedWhenChatClosed = (false, false, false, false)
          }
        }  // dismiss pickers when chat is closed
      #else
        .fileImporter(
          isPresented: $fileImporterPresented,
          allowedContentTypes: [.content],
          allowsMultipleSelection: true
        ) { result in
          do {
            let urls = try result.get()
            inputVM.selectedFiles = filterUploadableURLs(urls)
          } catch {
            print("Failed to pick files: \(error)")
          }
        }
        .fileDialogImportsUnresolvedAliases(false)
      #endif
      .alert(
        "Some files were not added",
        isPresented: Binding(
          get: { self.filesRemovedDuringSelection != nil },
          set: { newValue in
            if newValue == false {
              self.filesRemovedDuringSelection = nil
            }
          }
        )
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        if let error = filesRemovedDuringSelection {
          Text(error.localizedDescription)
        } else {
          Text("idk bro ur files cooked")
        }
      }  // show errors for removed files
    }

    @Namespace private var mediaPickerNamespace
    @State private var creatingPoll = false
    @State private var composingFormatted = false

    /// What follows a leading `/`, while it can still be a command name.
    private var slashQuery: String? {
      let text = inputVM.content
      guard text.hasPrefix("/"), !text.contains("\n"), text.count <= 64,
        inputVM.uploadItems.isEmpty
      else { return nil }
      if case .edit = inputVM.messageAction { return nil }
      return String(text.dropFirst())
    }
    @State private var voiceRecorder = VoiceMessageRecorder()

    /// Voice messages need Send Voice Messages, and aren't for edits.
    private var canSendVoice: Bool {
      if case .edit = inputVM.messageAction { return false }
      return vm.hasPermission(.sendVoiceMessages)
    }

    /// Polls need Create Polls in servers; DMs and groups always allow them.
    private var canCreatePoll: Bool {
      vm.hasPermission(.sendPolls)
    }

    var mediaPickerButton: some View {
      mediaPickerMenu
        .sheet(isPresented: $creatingPoll) {
          CreatePollSheet(vm: vm)
        }
        .sheet(isPresented: $composingFormatted) {
          FormattedMessageSheet(
            channel: vm,
            initialText: inputVM.content,
            onSend: { text in
              inputVM.content = text
              sendMessage()
            },
            onMoveToField: { inputVM.content = $0 }
          )
        }
    }

    @ViewBuilder
    private var mediaPickerMenu: some View {
      #if os(iOS)
        if properties.pickerShown {
          Button {
            properties.showFilePicker = false
            properties.showPhotosPicker = false
            properties.showEmojiPicker = false
            // refocus keyboard
            isFocused = true
          } label: {
            Image(systemName: "plus")
              .imageScale(.large)
              .padding(7.5)
              .glassEffect(.regular.interactive(), in: .circle)
              .rotationEffect(.degrees(45))
          }
          .buttonStyle(.borderless)
          .tint(iconTint(.primary))
        } else {
          Menu {
            Button {
              properties.showPhotosPicker = false
              properties.showFilePicker = false
              properties.showEmojiPicker = false
              self.cameraPickerPresented = true
            } label: {
              Label("Camera", systemImage: "camera")
            }
            Button {
              properties.showFilePicker = false
              properties.showEmojiPicker = false
              properties.showPhotosPicker = true
            } label: {
              Label("Upload Photos", systemImage: "photo.on.rectangle")
            }
            Button {
              properties.showPhotosPicker = false
              properties.showEmojiPicker = false
              properties.showFilePicker = true
            } label: {
              Label("Upload Files", systemImage: "doc.on.doc")
            }
            if canCreatePoll {
              Button {
                properties.showPhotosPicker = false
                properties.showFilePicker = false
                properties.showEmojiPicker = false
                creatingPoll = true
              } label: {
                Label("Create Poll", systemImage: "chart.bar.xaxis")
              }
            }
            Button {
              properties.showPhotosPicker = false
              properties.showFilePicker = false
              properties.showEmojiPicker = false
              composingFormatted = true
            } label: {
              Label("Formatted Message", systemImage: "textformat")
            }
          } label: {
            Image(systemName: "plus")
              .imageScale(.large)
              .padding(7.5)
              .glassEffect(.regular.interactive(), in: .circle)
          }
          .buttonStyle(.borderless)
          .tint(iconTint(.primary))
        }
      #else
        Menu {
          Button {
            self.fileImporterPresented = true
          } label: {
            Label("Upload Files", systemImage: "doc.on.doc")
          }
          if canCreatePoll {
            Button {
              creatingPoll = true
            } label: {
              Label("Create Poll", systemImage: "chart.bar.xaxis")
            }
          }
          Button {
            composingFormatted = true
          } label: {
            Label("Formatted Message", systemImage: "textformat")
          }
        } label: {
          // a plain symbol beside the field, as in Messages on the Mac
          Image(systemName: "plus.circle.fill")
            .font(.system(size: 20))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 30)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help("Attach files, create a poll or write a formatted message")
      #endif
    }

    @ViewBuilder
    var textField: some View {
      HStack(alignment: .bottom) {
        #if os(iOS)
          PastableTextField(
            placeholder: "Message\(vm.channel?.name.map { " #\($0)" } ?? "")",
            text: $inputVM.content,
            isFocused: $isFocused,
            onPasteFiles: handlePastedFiles
          )
          .padding(.vertical, 7)
          .padding(.horizontal, 12)
        #else
          TextView(
            "Message\(vm.channel?.name.map { " #\($0)" } ?? "")",
            text: $inputVM.content,
            submit: sendMessage,
            onPasteFiles: handlePastedFiles
          )
          .padding(.vertical, 5)
          .padding(.leading, 10)
          if canSendVoice, inputVM.content.isEmpty, inputVM.uploadItems.isEmpty {
            VoiceMessageButton(recorder: voiceRecorder, channel: vm.channelId)
              .padding(.vertical, 4)
          }
        #endif
        Button {
          #if os(iOS)
            isManualUpdate = true
            if !properties.showEmojiPicker {
              presentEmojiPicker()
              isFocused = false
            } else {
              properties.showEmojiPicker = false
              properties.showFilePicker = false
              properties.showPhotosPicker = false
              isFocused = true
            }
            isManualUpdate = false
          #else
            showingEmojiPicker.toggle()
          #endif
        } label: {
          Image(systemName: "face.smiling")
            .imageScale(.large)
            .padding(.trailing, 6)
        }
        .buttonStyle(.borderless)
        .tint(iconTint(.secondary))
        #if os(macOS)
          .padding(.vertical, 4)
        #else
          .padding(.vertical, 6)
        #endif
        #if !os(iOS)
          .popover(isPresented: $showingEmojiPicker, arrowEdge: .bottom) {
            EmojiPicker()
              .guild(vm.guildStore?.guildId)
              .onPickedEmoji { insertEmoji($0) }
            .onPickedSticker { pickSticker($0) }
          }
        #endif
      }
      #if os(macOS)
        // a bordered field on the window's background, like Messages, not a filled pill
        .background(.background.opacity(0.6), in: .rect(cornerRadius: 15, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 15, style: .continuous)
            .strokeBorder(.separator)
        }
        .clipShape(.rect(cornerRadius: 15, style: .continuous))
      #else
        // a glass field floating over the chat, as in Messages
        .clipShape(.rect(cornerRadius: 18))
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
      #endif
      .overlay {
        if voiceRecorder.state != .idle {
          VoiceRecordingBar(recorder: voiceRecorder, channel: vm.channelId)
        }
      }

      #if os(iOS)
        if voiceRecorder.state == .idle
          && (inputVM.content.isEmpty == false || inputVM.uploadItems.isEmpty == false)
        {
          Button(action: sendMessage) {
            Image(systemName: "paperplane.fill")
              .imageScale(.large)
              .padding(5)
              .foregroundStyle(.white)
              .background(theme.common.primaryButton)
              .clipShape(.circle)
          }
          .buttonStyle(.borderless)
          .foregroundStyle(theme.common.primaryButton)
          .transition(
            .move(edge: .trailing).combined(with: .opacity).animation(.default)
          )
        } else if canSendVoice {
          VoiceMessageButton(recorder: voiceRecorder, channel: vm.channelId)
            .padding(.bottom, 1)
        }
      #endif
    }

    #if os(iOS)
      var animatedKeyboardHeight: CGFloat {
        (properties.pickerShown || isFocused)
          ? properties.keyboardHeight : 0
      }
    #endif

    @ViewBuilder
    var messageActionBar: some View {
      HStack {
        if let action = inputVM.messageAction {
          switch action {
          case .reply(let message, _):
            let author: Text = {
              guard let author = message.author else {
                return Text("Unknown User").bold()
              }
              if let member = vm.guildStore?.member(author.id)
                ?? message.member
              {
                return Text(
                  member.nick ?? author.global_name ?? author.username
                ).bold()
              } else {
                return Text(author.global_name ?? author.username).bold()
              }
            }()
            Text("Replying to \(author)")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          case .edit(_):
            Text("Editing Message")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          Spacer()
          if case .reply(let message, let mention) = action {
            Button {
              inputVM.messageAction = .reply(
                message: message,
                mention: !mention
              )
            } label: {
              HStack(spacing: 2) {
                Image(systemName: "at")
                Text(mention ? "ON" : "OFF")
              }
              .font(.headline.bold())
            }
            .buttonStyle(.borderless)
            .tint(mention ? nil : .secondary)
          }

          Button {
            inputVM.messageAction = nil
          } label: {
            Image(systemName: "xmark.circle.fill")
              .imageScale(.large)
          }
          .buttonStyle(.borderless)
          .tint(.secondary)
        }
      }
      .padding(.horizontal, 6)
      .padding(.leading, 4)
      .padding(.vertical, 4)
      .background(.background.secondary.opacity(0.8))
      .clipShape(.capsule)
      .padding(.horizontal, 8)
    }

    private func sendMessage() {
      let msg = inputVM.content.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !msg.isEmpty || inputVM.uploadItems.isEmpty == false else {
        return
      }
      guard let channelId = appState.selectedChannel else { return }
      // create a copy of the vm
      let toSend = inputVM.copy()
      inputVM.reset()
      Task {
        gw.messageDrain.send(toSend, in: channelId)
      }
    }

    private func filterUploadableURLs(_ urls: [URL]) -> [URL] {
      return urls.compactMap { originalURL in
        var url: URL? = originalURL
        let canAccess = url?.startAccessingSecurityScopedResource() ?? false
        defer {
          if canAccess {
            url?.stopAccessingSecurityScopedResource()
          }
        }

        let fileSize =
          (try? url?.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if fileSize == 0 {
          url = nil
          self.filesRemovedDuringSelection = SelectionError.filesEmpty
        }

        let uploadMeta = gw.user.premiumKind.fileUpload(size: fileSize, to: vm)
        if uploadMeta.allowed == false, let tooLarge = url,
          InputVM.externalService(for: fileSize) != nil
        {
          // asked about one by one, then sent to the chosen service
          inputVM.pendingExternalUploads.append(tooLarge)
          url = nil
        } else if uploadMeta.allowed == false {
          url = nil
          self.filesRemovedDuringSelection = SelectionError.filesPastLimit(
            limit: uploadMeta.limit, hint: SelectionError.uploadServiceHint(for: fileSize)
          )
        }

        return url
      }
    }

    private func handlePastedFiles(_ urls: [URL]) {
      let tempDir = FileManager.default.temporaryDirectory
      for url in urls {
        if url.path.hasPrefix(tempDir.path) {
          inputVM.trackTempFile(url)
        }
      }
      inputVM.selectedFiles = filterUploadableURLs(urls)
    }

    #if os(iOS)
      func onImageCaptured(_ image: UIImage) {
        Task {
          let tempDir = FileManager.default.temporaryDirectory
          let fileURL = tempDir.appendingPathComponent(
            UUID().uuidString + ".png"
          )
          if let imageData = image.pngData() {
            do {
              try imageData.write(to: fileURL)
              inputVM.trackTempFile(fileURL)
              inputVM.selectedFiles.append(fileURL)
            } catch {
              print("Failed to save captured image: \(error)")
            }
          }
        }
      }
      func onVideoCaptured(_ videoURL: URL) {
        Task {
          let newVideoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
              UUID().uuidString + ".mov"
            )
          try? FileManager.default.moveItem(
            at: videoURL,
            to: newVideoURL
          )
          inputVM.trackTempFile(newVideoURL)
          inputVM.selectedFiles.append(newVideoURL)
        }
      }
    #endif
  }
}
