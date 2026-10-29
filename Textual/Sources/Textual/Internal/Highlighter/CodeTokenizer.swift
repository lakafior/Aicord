import Foundation

// MARK: - Overview
//
// CodeTokenizer is a lightweight, native pure-Swift lexical syntax tokenizer
// replacing the bundled Prism.js / JavaScriptCore implementation.

struct CodeToken: Hashable, Sendable {
  let content: String
  let type: StructuredText.HighlighterTheme.TokenType
}

actor CodeTokenizer {
  static let shared: CodeTokenizer? = CodeTokenizer()

  init() {}

  func tokenize(code: String, language: String) -> [CodeToken] {
    guard !code.isEmpty else { return [] }
    let lang = language.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

    if lang == "diff" || lang == "patch" {
      return Self.tokenizeDiff(code)
    }

    let rawTokens = Self.scan(code: code, language: lang)
    return Self.coalesce(rawTokens)
  }

  private static func tokenizeDiff(_ code: String) -> [CodeToken] {
    var tokens: [CodeToken] = []
    let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
    for (idx, line) in lines.enumerated() {
      let text = idx < lines.count - 1 ? String(line) + "\n" : String(line)
      guard !text.isEmpty else { continue }
      if line.hasPrefix("+") && !line.hasPrefix("+++") {
        tokens.append(CodeToken(content: text, type: .inserted))
      } else if line.hasPrefix("-") && !line.hasPrefix("---") {
        tokens.append(CodeToken(content: text, type: .deleted))
      } else if line.hasPrefix("@@") {
        tokens.append(CodeToken(content: text, type: .keyword))
      } else {
        tokens.append(CodeToken(content: text, type: .plain))
      }
    }
    return coalesce(tokens)
  }

  private static let keywords: Set<String> = [
    // Swift / C / C++ / Rust / Go / Java / Kotlin / JS / TS / Python / Ruby / Shell
    "actor", "any", "as", "associatedtype", "async", "await", " borrowing", "break", "case",
    "catch", "class", " consuming", "const", "continue", "convenience", "default", "def", "defer",
    "deinit", "del", "do", "dynamic", "elif", "else", "enum", "EXCEPT", "except", "export",
    "extension", "extern", "fallthrough", "fileprivate", "final", "finally", "fn", "for", "from",
    "func", "function", "get", "global", "go", "guard", "if", "impl", "implements", "import", "in",
    "indirect", "infix", "init", "inout", "interface", "internal", "is", "isolated", "lambda",
    "lazy", "let", "local", "loop", "macro", "match", "mod", "mut", "mutating", "namespace", "new",
    "nonisolated", "nonmutating", "nonlocal", "not", "open", "operator", "optional", "or",
    "override", "package", "pass", "postfix", "precedencegroup", "prefix", "private", " package",
    "protocol", "pub", "public", "raise", "ref", "repeat", "required", "rethrows", "return",
    "returns", "select", "self", "Self", "set", "some", "Spawn", "static", "struct", "subscript",
    "super", "switch", "then", "this", "throw", "throws", "trait", "try", "type", "typealias",
    "typedef", "typeof", "union", "unowned", "unsafe", "use", "using", "var", "virtual", "void",
    "volatile", "weak", "where", "while", "with", "yield",
  ]

  private static let booleansAndLiterals: Set<String> = [
    "true", "false", "nil", "null", "None", "True", "False", "undefined", "NaN", "Infinity", "YES",
    "NO",
  ]

  private static let builtins: Set<String> = [
    "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
    "Float", "Double", "Bool", "String", "Character", "Data", "Date", "URL", "UUID", "Array",
    "Dictionary", "Set", "Optional", "Result", "Error", "Any", "AnyObject", "Sendable", "Codable",
    "Encodable", "Decodable", "Hashable", "Equatable", "Identifiable", "Observable", "View",
    "State", "Binding", "Environment", "Task", "MainActor", "print", "debugPrint", "fatalError",
    "precondition", "assert", "sizeof", "alignof", "u8", "u16", "u32", "u64", "u128", "usize",
    "i8", "i16", "i32", "i64", "i128", "isize", "f32", "f64", "str", "Vec", "Box", "Rc", "Arc",
    "Option",
  ]

  private static let hashCommentLanguages: Set<String> = [
    "py", "python", "rb", "ruby", "sh", "bash", "zsh", "shell", "yaml", "yml", "toml", "dockerfile",
    "makefile", "perl", "r", "elixir", "powershell", "ps1", "conf", "ini",
  ]

  private static func scan(code: String, language: String) -> [CodeToken] {
    var tokens: [CodeToken] = []
    let chars = Array(code)
    let count = chars.count
    var i = 0

    let supportsHashComment = hashCommentLanguages.contains(language) || language.isEmpty
    let isMarkup = ["html", "xml", "svg", "plist", "jsx", "tsx"].contains(language)

    while i < count {
      let c = chars[i]

      // 1. Line comments: // or #
      if c == "/", i + 1 < count, chars[i + 1] == "/" {
        let start = i
        let isDoc = (i + 2 < count && (chars[i + 2] == "/" || chars[i + 2] == "!"))
        i += 2
        while i < count && chars[i] != "\n" {
          i += 1
        }
        let text = String(chars[start..<i])
        tokens.append(CodeToken(content: text, type: isDoc ? .docComment : .comment))
        continue
      }

      if c == "#", supportsHashComment {
        let start = i
        i += 1
        while i < count && chars[i] != "\n" {
          i += 1
        }
        tokens.append(CodeToken(content: String(chars[start..<i]), type: .comment))
        continue
      }

      // 2. Preprocessor / compiler directives (#if, #include, #pragma, etc.)
      if c == "#" {
        let start = i
        i += 1
        while i < count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
          i += 1
        }
        if i > start + 1 {
          tokens.append(CodeToken(content: String(chars[start..<i]), type: .directive))
          continue
        } else {
          tokens.append(CodeToken(content: "#", type: .plain))
          continue
        }
      }

      // 3. Block comments: /* ... */ or <!-- ... -->
      if c == "/", i + 1 < count, chars[i + 1] == "*" {
        let start = i
        i += 2
        while i + 1 < count && !(chars[i] == "*" && chars[i + 1] == "/") {
          i += 1
        }
        if i + 1 < count {
          i += 2
        } else {
          i = count
        }
        tokens.append(CodeToken(content: String(chars[start..<i]), type: .blockComment))
        continue
      }

      if isMarkup, c == "<", i + 3 < count, chars[i + 1] == "!", chars[i + 2] == "-",
        chars[i + 3] == "-"
      {
        let start = i
        i += 4
        while i + 2 < count && !(chars[i] == "-" && chars[i + 1] == "-" && chars[i + 2] == ">") {
          i += 1
        }
        if i + 2 < count {
          i += 3
        } else {
          i = count
        }
        tokens.append(CodeToken(content: String(chars[start..<i]), type: .blockComment))
        continue
      }

      // 4. Attributes / Decorators (@MainActor, @Observable, etc.)
      if c == "@" {
        let start = i
        i += 1
        while i < count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
          i += 1
        }
        if i > start + 1 {
          tokens.append(CodeToken(content: String(chars[start..<i]), type: .attribute))
          continue
        } else {
          tokens.append(CodeToken(content: "@", type: .plain))
          continue
        }
      }

      // 5. Strings: "...", '...', `...`, """..."""
      if c == "\"" || c == "'" || c == "`" {
        let quote = c
        let start = i
        if i + 2 < count, chars[i + 1] == quote, chars[i + 2] == quote {
          i += 3
          while i + 2 < count
            && !(chars[i] == quote && chars[i + 1] == quote && chars[i + 2] == quote)
          {
            if chars[i] == "\\" && i + 1 < count {
              i += 2
            } else {
              i += 1
            }
          }
          if i + 2 < count {
            i += 3
          } else {
            i = count
          }
        } else {
          i += 1
          while i < count && chars[i] != quote && chars[i] != "\n" {
            if chars[i] == "\\" && i + 1 < count {
              i += 2
            } else {
              i += 1
            }
          }
          if i < count && chars[i] == quote {
            i += 1
          }
        }
        tokens.append(
          CodeToken(
            content: String(chars[start..<i]),
            type: quote == "'" ? .char : .string
          )
        )
        continue
      }

      // 6. Markup tags (<tag>, </tag>)
      if isMarkup, c == "<" {
        let start = i
        i += 1
        if i < count && chars[i] == "/" { i += 1 }
        while i < count
          && (chars[i].isLetter || chars[i].isNumber || chars[i] == "-" || chars[i] == ":"
            || chars[i] == "_")
        {
          i += 1
        }
        if i > start + 1 {
          tokens.append(CodeToken(content: String(chars[start..<i]), type: .tag))
          continue
        } else {
          tokens.append(CodeToken(content: "<", type: .plain))
          continue
        }
      }

      // 7. Numbers (decimal, hex 0x, binary 0b, floats)
      if c.isNumber || (c == "-" && i + 1 < count && chars[i + 1].isNumber) {
        let start = i
        if c == "-" { i += 1 }
        if i + 1 < count, chars[i] == "0",
          chars[i + 1] == "x" || chars[i + 1] == "X" || chars[i + 1] == "b" || chars[i + 1] == "B"
            || chars[i + 1] == "o" || chars[i + 1] == "O"
        {
          i += 2
          while i < count && (chars[i].isHexDigit || chars[i] == "_") {
            i += 1
          }
        } else {
          while i < count
            && (chars[i].isNumber || chars[i] == "." || chars[i] == "_" || chars[i] == "e"
              || chars[i] == "E")
          {
            i += 1
          }
        }
        tokens.append(CodeToken(content: String(chars[start..<i]), type: .number))
        continue
      }

      // 8. Identifiers, keywords, types, functions
      if c.isLetter || c == "_" || c == "$" {
        let start = i
        i += 1
        while i < count
          && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_" || chars[i] == "$")
        {
          i += 1
        }
        let word = String(chars[start..<i])

        if booleansAndLiterals.contains(word) {
          tokens.append(CodeToken(content: word, type: .boolean))
        } else if keywords.contains(word) {
          tokens.append(CodeToken(content: word, type: .keyword))
        } else if builtins.contains(word) {
          tokens.append(CodeToken(content: word, type: .builtin))
        } else if i < count && chars[i] == "(" {
          if let first = word.first, first.isUppercase {
            tokens.append(CodeToken(content: word, type: .className))
          } else {
            tokens.append(CodeToken(content: word, type: .function))
          }
        } else if let first = word.first, first.isUppercase {
          tokens.append(CodeToken(content: word, type: .className))
        } else if start > 0 && chars[start - 1] == "." {
          tokens.append(CodeToken(content: word, type: .property))
        } else {
          tokens.append(CodeToken(content: word, type: .plain))
        }
        continue
      }

      // 9. Whitespace & punctuation
      let start = i
      i += 1
      while i < count {
        let next = chars[i]
        if next.isLetter || next.isNumber || next == "_" || next == "$" || next == "\""
          || next == "'" || next == "`" || next == "/" || next == "#" || next == "@"
          || (isMarkup && next == "<")
        {
          break
        }
        i += 1
      }
      tokens.append(CodeToken(content: String(chars[start..<i]), type: .plain))
    }

    return tokens
  }

  private static func coalesce(_ tokens: [CodeToken]) -> [CodeToken] {
    guard !tokens.isEmpty else { return [] }
    var merged: [CodeToken] = []
    merged.reserveCapacity(tokens.count)
    for token in tokens {
      if let last = merged.last, last.type == token.type {
        merged[merged.count - 1] = CodeToken(
          content: last.content + token.content,
          type: last.type
        )
      } else {
        merged.append(token)
      }
    }
    return merged
  }
}
