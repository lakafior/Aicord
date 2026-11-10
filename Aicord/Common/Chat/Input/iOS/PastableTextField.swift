//
//  PastableTextField.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 04/02/2026.
//  Copyright © 2026 Lakhan Lothiyi.
//

import SwiftUI

#if os(iOS)
  extension ChatView.InputBar {

    struct PastableTextField: UIViewRepresentable {
      var placeholder: String
      @Binding var text: String
      @Binding var isFocused: Bool
      var onPasteFiles: (([URL]) -> Void)?
      let maxHeight: CGFloat = 150

      func makeUIView(context: Context) -> PastableUITextView {
        let textView = PastableUITextView()
        textView.delegate = context.coordinator
        textView.onPasteFiles = onPasteFiles
        textView.font = .preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.showsHorizontalScrollIndicator = false
        textView.isScrollEnabled = true
        textView.maxHeight = maxHeight

        return textView
      }

      func updateUIView(_ textView: PastableUITextView, context: Context) {
        if textView.text != text {
          textView.text = text
          textView.invalidateIntrinsicContentSize()
        }

        textView.onPasteFiles = onPasteFiles
        textView.maxHeight = maxHeight

        context.coordinator.updatePlaceholder(
          textView,
          placeholder: placeholder,
          isEmpty: text.isEmpty
        )

        if isFocused {
          textView.becomeFirstResponder()
        } else {
          textView.resignFirstResponder()
        }
      }

      func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: PastableUITextView,
        context: Context
      ) -> CGSize? {
        let targetWidth = proposal.width ?? uiView.bounds.width
        let fittingSize = uiView.sizeThatFits(
          CGSize(width: targetWidth, height: .greatestFiniteMagnitude)
        )

        return CGSize(
          width: targetWidth,
          height: min(fittingSize.height, maxHeight)
        )
      }

      func makeCoordinator() -> Coordinator {
        Coordinator(self)
      }

      class Coordinator: NSObject, UITextViewDelegate {
        var parent: PastableTextField
        var placeholderLabel: UILabel?

        init(_ parent: PastableTextField) {
          self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
          parent.text = textView.text
          updatePlaceholder(
            textView,
            placeholder: parent.placeholder,
            isEmpty: textView.text.isEmpty
          )
          if let textView = textView as? PastableUITextView {
            textView.invalidateIntrinsicContentSize()
          }
        }

        /// Adds Formatting to the system edit menu while text is selected.
        func textView(
          _ textView: UITextView,
          editMenuForTextIn range: NSRange,
          suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
          guard range.length > 0, let textView = textView as? PastableUITextView else {
            return nil
          }
          let actions = MessageFormat.allCases.map { format in
            UIAction(
              title: format.title,
              image: UIImage(systemName: format.systemImage)
            ) { [weak textView] _ in
              textView?.apply(format)
            }
          }
          let formatting = UIMenu(
            title: String(localized: "Formatting"),
            image: UIImage(systemName: "textformat"),
            children: actions
          )
          return UIMenu(children: suggestedActions + [formatting])
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
          if parent.isFocused == false {
            DispatchQueue.main.async {
              self.parent.isFocused = true
            }
          }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
          if parent.isFocused == true {
            DispatchQueue.main.async {
              self.parent.isFocused = false
            }
          }
        }

        func updatePlaceholder(
          _ textView: UITextView,
          placeholder: String,
          isEmpty: Bool
        ) {
          if placeholderLabel == nil {
            let label = UILabel()
            label.text = placeholder
            label.font = textView.font
            label.textColor = .placeholderText
            label.translatesAutoresizingMaskIntoConstraints = false
            textView.addSubview(label)
            NSLayoutConstraint.activate([
              label.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
              label.topAnchor.constraint(equalTo: textView.topAnchor),
            ])
            placeholderLabel = label
          }
          placeholderLabel?.isHidden = !isEmpty
        }
      }

      class PastableUITextView: UITextView {
        var onPasteFiles: (([URL]) -> Void)?
        var maxHeight: CGFloat = 150

        override var intrinsicContentSize: CGSize {
          let fittingSize = sizeThatFits(
            CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
          )
          return CGSize(
            width: UIView.noIntrinsicMetric,
            height: min(fittingSize.height, maxHeight)
          )
        }

        override func layoutSubviews() {
          super.layoutSubviews()
          invalidateIntrinsicContentSize()
        }

        /// Wraps the selection in Discord markdown, as one undoable edit.
        func apply(_ format: MessageFormat) {
          let edit = format.edit(in: text, selection: selectedRange)
          guard
            let start = position(from: beginningOfDocument, offset: edit.range.location),
            let end = position(from: start, offset: edit.range.length),
            let range = textRange(from: start, to: end)
          else { return }
          replace(range, withText: edit.replacement)
          selectedRange = edit.selection
          delegate?.textViewDidChange?(self)
        }

        override var keyCommands: [UIKeyCommand]? {
          let formatting = MessageFormat.allCases.compactMap { format -> UIKeyCommand? in
            guard let key = format.keyEquivalent else { return nil }
            let command = UIKeyCommand(
              title: format.title,
              action: #selector(formatKeyCommand(_:)),
              input: key,
              modifierFlags: format.usesShift ? [.command, .shift] : .command,
              propertyList: format.rawValue
            )
            command.wantsPriorityOverSystemBehavior = true
            return command
          }
          return (super.keyCommands ?? []) + formatting
        }

        @objc func formatKeyCommand(_ sender: UIKeyCommand) {
          guard let raw = sender.propertyList as? String,
            let format = MessageFormat(rawValue: raw)
          else { return }
          apply(format)
        }

        override func canPerformAction(
          _ action: Selector,
          withSender sender: Any?
        ) -> Bool {
          if action == #selector(formatKeyCommand(_:)) {
            // ⌘K without a selection stays the Quick Switcher.
            let raw = (sender as? UIKeyCommand)?.propertyList as? String
            return raw != MessageFormat.link.rawValue || selectedRange.length > 0
          }
          if action == #selector(paste(_:)) {
            if UIPasteboard.general.hasImages {
              return true
            }
          }
          return super.canPerformAction(action, withSender: sender)
        }

        override func paste(_ sender: Any?) {
          let pasteboard = UIPasteboard.general

          if pasteboard.hasImages, let images = pasteboard.images,
            !images.isEmpty
          {
            let urls = images.compactMap { image -> URL? in
              let tempDir = FileManager.default.temporaryDirectory
              let fileURL = tempDir.appendingPathComponent(
                UUID().uuidString + ".png"
              )
              guard let imageData = image.pngData() else { return nil }
              do {
                try imageData.write(to: fileURL)
                return fileURL
              } catch {
                return nil
              }
            }
            if !urls.isEmpty {
              onPasteFiles?(urls)
              return
            }
          }

          // links lose their tracking parameters on the way in
          if let string = pasteboard.string ?? pasteboard.url?.absoluteString {
            let cleaned = ComposerPreferences.cleanedPaste(string)
            if cleaned != string {
              insertText(cleaned)
              return
            }
          }

          super.paste(sender)
        }
      }
    }
  }
#endif
