//
//  MessageFormatting.swift
//  Aicord
//
//  Discord markdown around the selection in the message field.
//

import Foundation

/// A Discord markdown style the message field can put around a selection.
enum MessageFormat: String, CaseIterable, Identifiable {
  case bold, italic, underline, strikethrough, spoiler, code, link

  var id: String { rawValue }

  var title: String {
    switch self {
    case .bold: String(localized: "Bold")
    case .italic: String(localized: "Italic")
    case .underline: String(localized: "Underline")
    case .strikethrough: String(localized: "Strikethrough")
    case .spoiler: String(localized: "Spoiler")
    case .code: String(localized: "Code")
    case .link: String(localized: "Link")
    }
  }

  var systemImage: String {
    switch self {
    case .bold: "bold"
    case .italic: "italic"
    case .underline: "underline"
    case .strikethrough: "strikethrough"
    case .spoiler: "eye.slash"
    case .code: "chevron.left.forwardslash.chevron.right"
    case .link: "link"
    }
  }

  /// The key used with ⌘ (and ⇧ for strikethrough) on a hardware keyboard.
  var keyEquivalent: String? {
    switch self {
    case .bold: "b"
    case .italic: "i"
    case .underline: "u"
    case .strikethrough: "x"
    case .link: "k"
    case .spoiler, .code: nil
    }
  }

  var usesShift: Bool { self == .strikethrough }

  /// Markers on each side; code with a line break becomes a code block.
  func markers(for selection: String) -> (String, String) {
    switch self {
    case .bold: ("**", "**")
    case .italic: ("*", "*")
    case .underline: ("__", "__")
    case .strikethrough: ("~~", "~~")
    case .spoiler: ("||", "||")
    case .code: selection.contains("\n") ? ("```\n", "\n```") : ("`", "`")
    case .link: ("[", "]()")
    }
  }

  /// One edit of the text: replace `range` with `replacement`, then select `selection`.
  struct Edit: Equatable {
    var range: NSRange
    var replacement: String
    var selection: NSRange
  }

  /// Wraps the selection in the markers, or unwraps it when it's already wrapped
  /// (markers inside the selection or right around it). Ranges are UTF-16, as in
  /// `NSString`, `UITextView` and `NSTextView`.
  func edit(in text: String, selection: NSRange) -> Edit {
    let ns = text as NSString
    let selected = ns.substring(with: selection)

    if self == .link {
      // A selected address becomes the target; anything else becomes the label.
      if let url = URL(string: selected.trimmingCharacters(in: .whitespaces)),
        url.scheme?.hasPrefix("http") == true
      {
        let replacement = "[](\(selected))"
        return Edit(
          range: selection, replacement: replacement,
          selection: NSRange(location: selection.location + 1, length: 0))
      }
      let replacement = "[\(selected)](https://)"
      let urlStart = selection.location + (selected as NSString).length + 3
      return Edit(
        range: selection, replacement: replacement,
        selection: NSRange(location: urlStart, length: ("https://" as NSString).length))
    }

    let (open, close) = markers(for: selected)
    let openLength = (open as NSString).length
    let closeLength = (close as NSString).length

    // Already wrapped inside the selection: unwrap.
    if selected.hasPrefix(open), selected.hasSuffix(close),
      (selected as NSString).length >= openLength + closeLength,
      !isLongerMarker(open, inside: selected)
    {
      let inner = (selected as NSString).substring(
        with: NSRange(
          location: openLength,
          length: (selected as NSString).length - openLength - closeLength))
      return Edit(
        range: selection, replacement: inner,
        selection: NSRange(location: selection.location, length: (inner as NSString).length))
    }

    // Wrapped right around the selection: remove the markers outside it.
    if selection.location >= openLength,
      selection.location + selection.length + closeLength <= ns.length
    {
      let before = ns.substring(
        with: NSRange(location: selection.location - openLength, length: openLength))
      let after = ns.substring(
        with: NSRange(location: selection.location + selection.length, length: closeLength))
      if before == open, after == close,
        !isLongerMarker(open, before: selection.location - openLength, in: ns)
      {
        return Edit(
          range: NSRange(
            location: selection.location - openLength,
            length: selection.length + openLength + closeLength),
          replacement: selected,
          selection: NSRange(location: selection.location - openLength, length: selection.length))
      }
    }

    return Edit(
      range: selection, replacement: open + selected + close,
      selection: NSRange(location: selection.location + openLength, length: selection.length))
  }

  /// Italic `*` is part of bold `**`: don't treat `**x**` as italic.
  private func isLongerMarker(_ open: String, inside selected: String) -> Bool {
    self == .italic && selected.hasPrefix("**") && !selected.hasPrefix("***")
  }

  private func isLongerMarker(_ open: String, before location: Int, in ns: NSString) -> Bool {
    guard self == .italic, location > 0 else { return false }
    let previous = ns.substring(with: NSRange(location: location - 1, length: 1))
    return previous == "*"
  }
}
