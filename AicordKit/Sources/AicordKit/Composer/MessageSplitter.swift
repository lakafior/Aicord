//
//  MessageSplitter.swift
//  AicordKit
//
//  Splits text longer than Discord's message limit into several messages:
//  between paragraphs first, then lines, sentences and words, and never
//  inside a code block unless the block alone is too long. Then it is cut
//  between its lines and each part closes and reopens the block.
//

import Foundation

public enum MessageSplitter {
  /// Length as Discord counts it, conservatively: Unicode scalars, so an
  /// emoji made of several never makes a part too long.
  public static func length(_ text: some StringProtocol) -> Int {
    text.unicodeScalars.count
  }

  /// The parts to send, in order, each at most `limit` long. Text within the
  /// limit comes back as one part; whitespace around parts is trimmed.
  public static func split(_ text: String, limit: Int) -> [String] {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return [] }
    guard length(text) > limit else { return [text] }
    // too small to fit a fence and a line: cut hard
    guard limit >= 16 else { return hardChunks(text, limit: limit) }

    var parts: [String] = []
    var rest = Array(text)
    while !rest.isEmpty {
      if length(String(rest)) <= limit {
        parts.append(String(rest))
        break
      }
      let cut = findCut(rest, limit: limit)
      guard cut.index > 0 else {
        parts += hardChunks(String(rest), limit: limit)
        break
      }
      var chunk = String(rest[..<cut.index])
      var remainder = Array(rest[cut.index...])
      if let fence = cut.openFence {
        // inside a code block: close it here and open it again in the next part
        if !chunk.hasSuffix("\n") { chunk += "\n" }
        chunk += "```"
        remainder = Array("```" + fence + "\n") + remainder
      } else {
        chunk = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = remainder.first, first.isWhitespace { remainder.removeFirst() }
      }
      if !chunk.isEmpty { parts.append(chunk) }
      guard remainder.count < rest.count else {
        // reopening the block costs more than the cut saved
        parts += hardChunks(String(remainder), limit: limit)
        break
      }
      rest = remainder
    }
    return parts
  }

  private struct Cut {
    var index: Int
    /// The language of the code block the cut falls in, "" for none given;
    /// nil when the cut is outside code.
    var openFence: String?
  }

  /// Where to end the first part of `chars`.
  private static func findCut(_ chars: [Character], limit: Int) -> Cut {
    // positions: a cut at i keeps chars[0..<i]
    var scalars = 0
    var maxIndex = 0  // the furthest cut within the limit
    var inFence = false
    var fenceLanguage = ""
    var fenceStart = 0
    var best: (index: Int, quality: Int) = (0, 0)
    var bestEarly: (index: Int, quality: Int) = (0, 0)
    var lastNewlineInFence: Int?
    var lastFenceBudgetIndex = 0  // furthest cut that leaves room to close a fence
    let early = limit / 3

    var i = 0
    while i < chars.count {
      // a cut before chars[i]
      if i > 0, !inFence {
        let quality = boundaryQuality(chars, at: i)
        if quality > 0 {
          if i >= early {
            if quality >= best.quality { best = (i, quality) }
          } else if quality >= bestEarly.quality {
            bestEarly = (i, quality)
          }
        }
      }

      // a fence toggles on three backticks
      if chars[i] == "`", i + 2 < chars.count, chars[i + 1] == "`", chars[i + 2] == "`" {
        let fenceScalars = 3
        if scalars + fenceScalars > limit { break }
        scalars += fenceScalars
        i += 3
        if inFence {
          inFence = false
        } else {
          inFence = true
          lastNewlineInFence = nil
          fenceLanguage = language(chars, from: i)
          // the first cut inside the block is after its first line
          fenceStart = i + fenceLanguage.count + 1
          lastFenceBudgetIndex = i
        }
        maxIndex = i
        continue
      }

      let size = chars[i].unicodeScalars.count
      if scalars + size > limit { break }
      scalars += size
      // inside a fence the part must still have room for "\n```"
      i += 1
      maxIndex = i
      if inFence, scalars + 4 <= limit {
        lastFenceBudgetIndex = i
        if chars[i - 1] == "\n", i > fenceStart { lastNewlineInFence = i }
      }
    }

    if inFence {
      // the limit falls inside a code block; end before the block if possible
      if best.index > 0 { return Cut(index: best.index, openFence: nil) }
      if bestEarly.index > 0 { return Cut(index: bestEarly.index, openFence: nil) }
      if let line = lastNewlineInFence, line <= lastFenceBudgetIndex, line > fenceStart {
        return Cut(index: line, openFence: fenceLanguage)
      }
      return Cut(index: max(lastFenceBudgetIndex, fenceStart + 1), openFence: fenceLanguage)
    }
    // a boundary right at the limit counts too
    if maxIndex < chars.count {
      let quality = boundaryQuality(chars, at: maxIndex)
      if quality > 0, quality >= best.quality { best = (maxIndex, quality) }
    }
    if best.index > 0 { return Cut(index: best.index, openFence: nil) }
    if bestEarly.index > 0 { return Cut(index: bestEarly.index, openFence: nil) }
    return Cut(index: max(maxIndex, 1), openFence: nil)
  }

  /// 4 between paragraphs, 3 between lines, 2 after a sentence, 1 between words.
  private static func boundaryQuality(_ chars: [Character], at i: Int) -> Int {
    guard i > 0, i <= chars.count else { return 0 }
    let previous = chars[i - 1]
    if previous == "\n" {
      return i > 1 && chars[i - 2] == "\n" ? 4 : 3
    }
    if previous == " " || previous == "\t" {
      if i > 1, ".!?…".contains(chars[i - 2]) { return 2 }
      return 1
    }
    return 0
  }

  /// The language after an opening fence, when the line names one.
  private static func language(_ chars: [Character], from start: Int) -> String {
    var name = ""
    var i = start
    while i < chars.count, chars[i] != "\n" {
      let c = chars[i]
      guard c.isLetter || c.isNumber || c == "+" || c == "-" || c == "#" || c == "_" else {
        return ""
      }
      name.append(c)
      i += 1
    }
    return i < chars.count ? name : ""
  }

  private static func hardChunks(_ text: String, limit: Int) -> [String] {
    var parts: [String] = []
    var current = ""
    for character in text {
      if length(current) + character.unicodeScalars.count > max(limit, 1), !current.isEmpty {
        parts.append(current)
        current = ""
      }
      current.append(character)
    }
    if !current.isEmpty { parts.append(current) }
    return parts
  }
}
