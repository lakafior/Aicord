import Foundation
import Testing

@testable import Textual

struct CodeTokenizerTests {
  @Test
  @available(watchOS, unavailable)
  func tokenize() async {
    // given
    let tokenizer = CodeTokenizer()

    // when
    let tokens = await tokenizer.tokenize( code: "let greeting = \"Hello, world!\"", language: "swift" )

    // then
    #expect(
      tokens == [
        // the native tokenizer (it replaced Prism.js) leaves `=` as plain text
        .init(content: "let", type: .keyword),
        .init(content: " greeting = ", type: .plain),
        .init(content: "\"Hello, world!\"", type: .string),
      ]
    )
  }

  @Test
  @available(watchOS, unavailable)
  func tokenizeUnsupportedLanguage() async {
    // given
    let tokenizer = CodeTokenizer()

    // when
    let tokens = await tokenizer.tokenize( code: "let greeting = \"Hello, world!\"", language: "unsupported" )

    // then
    #expect(
      tokens == [
        // unknown languages get the generic keyword and string rules
        .init(content: "let", type: .keyword),
        .init(content: " greeting = ", type: .plain),
        .init(content: "\"Hello, world!\"", type: .string),
      ]
    )
  }
}
