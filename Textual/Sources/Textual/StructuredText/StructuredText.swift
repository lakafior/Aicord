import SwiftUI

/// A view that displays rich, structured text.
///
/// `StructuredText` renders block elements like paragraphs, headings, lists, block quotes, code
/// blocks, and tables from a markup string. The markup is parsed with a ``MarkupParser`` into an
/// `AttributedString` that Textual can lay out and display.
///
/// The simplest way to create a `StructuredText` view is to pass Markdown:
///
/// ```swift
/// let markdown = """
/// ## Getting Started
///
/// Before making changes, check a few things:
///
/// - Skim recent commits
/// - Run the tests
/// - Make your changes
///
/// Leave a note if something needs attention later.
/// """
///
/// var body: some View {
///   StructuredText(markdown: markdown)
/// }
/// ```
///
/// ### Customizing Text Appearance
///
/// `StructuredText` supports standard SwiftUI text modifiers like `.font()`, `.foregroundStyle()`,
/// and `.multilineTextAlignment()`. Note that `.lineLimit()` is explicitly disabled to prevent
/// per-block truncation, which would break the document layout.
///
/// ```swift
/// StructuredText(markdown: "## Hello\n\nThis is a paragraph.")
///   .font(.callout)
///   .foregroundStyle(.blue)
///   .multilineTextAlignment(.center)
/// ```
///
/// ### Styling Structured Text
///
/// You can apply a full style preset using the ``TextualNamespace/structuredTextStyle(_:)`` modifier.
///
/// ```swift
/// StructuredText(markdown: markdown)
///   .textual.structuredTextStyle(.discord)
/// ```
///
/// For more control, you can customize individual block and inline styles. Inline styles
/// apply to spans like emphasis and links. Block styles apply to structural elements:
///
/// - ``TextualNamespace/headingStyle(_:)``, ``TextualNamespace/paragraphStyle(_:)``,
///   ``TextualNamespace/blockQuoteStyle(_:)``, ``TextualNamespace/thematicBreakStyle(_:)``
/// - ``TextualNamespace/listItemStyle(_:)``, ``TextualNamespace/unorderedListMarker(_:)``,
///   ``TextualNamespace/orderedListMarker(_:)``
/// - ``TextualNamespace/codeBlockStyle(_:)``, ``TextualNamespace/highlighterTheme(_:)``
///
/// Code blocks may overflow horizontally. You can choose between scrolling and
/// wrapping with ``TextualNamespace/overflowMode(_:)``.
///
/// ```swift
/// StructuredText(markdown: markdown)
///   .textual.overflowMode(.wrap)
/// ```
///
/// ### Interaction
///
/// When the markup contains links, `StructuredText` uses SwiftUI’s `openURL` environment. Provide a
/// custom `OpenURLAction` to intercept them (for example, to route in-app or to scroll to anchors).
///
/// You can enable text selection with ``TextualNamespace/textSelection(_:)`` to let users select
/// text in a platform-appropriate way.
///
/// ```swift
/// StructuredText(markdown: markdown)
///   .environment(
///     \.openURL,
///     OpenURLAction { url in
///       print("Open \(url)")
///       return .handled
///     }
///   )
///   .textual.textSelection(.enabled)
/// ```
///
/// ### Images, links, and relative URLs
///
/// If your Markdown includes relative image URLs or links, provide a `baseURL`. To render images,
/// configure an attachment loader using the ``TextualNamespace/imageAttachmentLoader(_:)``
/// modifier.
///
/// ```swift
/// let baseURL = URL(string: "https://example.com/repo/")!
///
/// StructuredText(markdown: readme, baseURL: baseURL)
///   .textual.imageAttachmentLoader(.image(relativeTo: baseURL))
/// ```
///
/// When you need to parse something other than Markdown, use ``init(_:parser:)`` with a custom
/// ``MarkupParser`` implementation.
public struct StructuredText: View {
  @State private var attributedString = AttributedString()

  private let markup: String
  private let parser: any MarkupParser
  private let revision: AnyHashable
  private let cachesParsedContent: Bool

  /// Creates a structured-text view by parsing `markup` with a custom parser.
  ///
  /// Use this initializer when you want to provide your own `MarkupParser` implementation.
  ///
  /// - Parameter revision: Re-parses `markup` whenever this value changes, even if `markup`
  ///   itself doesn't — useful when your `parser` depends on external state (for example,
  ///   `syntaxExtensions` capturing a value that changed) that doesn't show up as a difference
  ///   in the source string. Updates `markup`'s existing parsed content in place instead of
  ///   resetting the view's identity (as `.id(_:)` would), so the displayed content doesn't
  ///   momentarily collapse while re-parsing.
  /// - Parameter cachesParsedContent: Keeps the parsed result in a shared cache keyed by
  ///   `markup` and `revision`, and shows it from the view's first layout. Only for callers
  ///   whose `revision` covers everything the parser's output depends on besides `markup`:
  ///   two views with the same markup and revision get the same content. Without it the view
  ///   is first laid out empty and parsed afterwards, which in a lazy list means every row
  ///   changes height right after it appears, and is parsed again each time it comes back.
  public init(
    _ markup: String,
    parser: any MarkupParser,
    revision: some Hashable = 0,
    cachesParsedContent: Bool = false
  ) {
    self.markup = markup
    self.parser = parser
    self.revision = AnyHashable(revision)
    self.cachesParsedContent = cachesParsedContent
  }

  public var body: some View {
    WithAttachments(content) {
      BlockContent(content: $0)
        .modifier(TextSelectionInteraction())
        .modifier(TextSelectionCoordination())
    }
    .coordinateSpace(.textContainer)
    .onChange(of: markup, initial: true) {
      markupDidChange(markup)
    }
    .onChange(of: revision) {
      markupDidChange(markup)
    }
    // Disable line limit to avoid per-fragment truncation
    .lineLimit(nil)
  }

  private var content: AttributedString {
    guard cachesParsedContent else { return attributedString }
    return ParsedMarkupCache.content(markup: markup, revision: revision) {
      (try? parser.attributedString(for: markup)) ?? .init()
    }
  }

  private func markupDidChange(_ markup: String) {
    guard !cachesParsedContent else { return }
    self.attributedString = (try? parser.attributedString(for: markup)) ?? .init()
  }
}

/// Parsed content of views created with `cachesParsedContent`.
private enum ParsedMarkupCache {
  private final class Key: NSObject {
    let markup: String
    let revision: AnyHashable

    init(markup: String, revision: AnyHashable) {
      self.markup = markup
      self.revision = revision
    }

    override var hash: Int {
      var hasher = Hasher()
      hasher.combine(markup)
      hasher.combine(revision)
      return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
      guard let other = object as? Key else { return false }
      return markup == other.markup && revision == other.revision
    }
  }

  private final class Entry {
    let content: AttributedString
    init(_ content: AttributedString) { self.content = content }
  }

  nonisolated(unsafe) private static let storage: NSCache<Key, Entry> = {
    let cache = NSCache<Key, Entry>()
    cache.countLimit = 3000
    return cache
  }()

  static func content(
    markup: String, revision: AnyHashable, parse: () -> AttributedString
  ) -> AttributedString {
    let key = Key(markup: markup, revision: revision)
    if let entry = storage.object(forKey: key) { return entry.content }
    let content = parse()
    storage.setObject(Entry(content), forKey: key)
    return content
  }
}

extension StructuredText {
  /// Creates a structured-text view from a Markdown string.
  ///
  /// This is a convenience initializer that uses Textual’s Markdown parser. To render other
  /// markup formats, use ``init(_:parser:)`` with a custom ``MarkupParser``.
  ///
  /// - Parameters:
  ///   - markdown: The Markdown source to render.
  ///   - baseURL: A base URL used to resolve relative links and image URLs.
  ///   - syntaxExtensions: Custom syntax extensions applied after markdown parsing.
  ///   - revision: Re-parses `markdown` whenever this value changes, even if `markdown` itself
  ///     doesn't — see ``init(_:parser:revision:)``.
  ///
  /// Math expressions are supported when you include `.math` in `syntaxExtensions`:
  ///
  /// ```swift
  /// StructuredText(
  ///   markdown: "The area is $A = \\pi r^2$.",
  ///   syntaxExtensions: [.math]
  /// )
  /// ```
  public init(
    markdown: String,
    baseURL: URL? = nil,
    syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = [],
    revision: some Hashable = 0
  ) {
    self.init(
      markdown,
      parser: .markdown(
        baseURL: baseURL,
        syntaxExtensions: syntaxExtensions
      ),
      revision: revision
    )
  }
}

@available(tvOS, unavailable)
@available(watchOS, unavailable)
#Preview(traits: .fixedLayout(width: 400, height: 600)) {
  @Previewable @State var width: CGFloat = 200

  VStack {
    GroupBox {
      HStack {
        Text("Width")
        Slider(value: $width, in: 100...320)
      }
    }
    Spacer()

    StructuredText(
      markdown: """
        Morty, do you know what _“wubba lubba dub dub”_ means?

        ![Hamster in Butt World](https://rickandmortyapi.com/api/character/avatar/153.jpeg)

        I mean, why would a [Pop-Tart](https://en.wikipedia.org/wiki/Pop-Tarts) \
        want to live inside a toaster, Rick? I mean, that would be like the \
        scariest place for them to live. You know what I mean?
        """
    )
    .frame(width: width)
    .border(Color.red)
    .environment(
      \.openURL,
      OpenURLAction { url in
        print("Opening \(url)")
        return .handled
      }
    )
    .padding()
    .textual.textSelection(.enabled)

    Spacer()
  }
}

#Preview("Custom Emoji") {
  let emoji: Set<Emoji> = [
    Emoji(shortcode: "dog", url: URL(string: "https://picsum.photos/id/237/32/32")!),
    Emoji(shortcode: "cat", url: URL(string: "https://picsum.photos/id/1025/32/32")!),
  ]

  ScrollView {
    StructuredText(
      markdown: """
        # Working with Custom Emoji

        You can substitute shortcodes with inline images. For example, :dog: and :cat: render \
        as small inline attachments that flow with the surrounding text.
        """,
      syntaxExtensions: [.emoji(emoji)]
    )
    .padding()
  }
}
