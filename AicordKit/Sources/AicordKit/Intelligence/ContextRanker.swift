//
//  ContextRanker.swift
//  AicordKit
//
//  "Explain Context": which earlier messages a message most likely answers,
//  scored without a model, so a small one only reads the best few.
//

import Foundation

public enum ContextRanker {
  public struct Candidate: Sendable, Equatable {
    public var id: String
    public var authorID: String
    public var mentionedIDs: Set<String>
    public var text: String
    /// 0 for the message right before the target, counting back.
    public var distance: Int

    public init(id: String, authorID: String, mentionedIDs: Set<String> = [], text: String, distance: Int) {
      self.id = id
      self.authorID = authorID
      self.mentionedIDs = mentionedIDs
      self.text = text
      self.distance = distance
    }
  }

  /// Scores how likely each candidate belongs to the target's conversation:
  /// the people it mentions, its author's own earlier messages, people who
  /// mentioned its author, shared words, and closeness. Best first.
  public static func rank(target: Candidate, candidates: [Candidate]) -> [(Candidate, Double)] {
    let targetWords = keywords(target.text)
    let scored = candidates.map { candidate -> (Candidate, Double) in
      var score = 0.0
      if target.mentionedIDs.contains(candidate.authorID) { score += 3 }
      if candidate.mentionedIDs.contains(target.authorID) { score += 2.5 }
      if candidate.authorID == target.authorID { score += 1.5 }
      let shared = targetWords.intersection(keywords(candidate.text)).count
      score += min(Double(shared), 4) * 1.2
      // the nearer, the likelier; a question is often right above
      score += 2.0 / Double(candidate.distance + 1)
      if candidate.text.contains("?") { score += 0.5 }
      return (candidate, score)
    }
    return scored.sorted { $0.1 > $1.1 }
  }

  /// Lowercased words of four or more letters, without common ones.
  public static func keywords(_ text: String) -> Set<String> {
    let words = text.lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { $0.count >= 4 && !$0.allSatisfy(\.isNumber) }
    return Set(words).subtracting(stopwords)
  }

  static let stopwords: Set<String> = [
    "that", "this", "with", "have", "what", "when", "there", "they", "your", "from", "just",
    "like", "about", "would", "could", "should", "will", "been", "were", "then", "than", "them",
    "also", "some", "only", "here", "know", "think", "yeah", "okay", "really", "does", "dont",
    "jest", "nie", "się", "jak", "tak", "też", "tylko", "jeszcze", "może", "mnie", "było",
    "będzie", "tego", "teraz", "jakby", "wiem", "chyba", "przez", "który", "która", "które",
  ]
}

/// The model's verdict on whether it knows what a message refers to.
public struct ContextVerdict: Sendable, Equatable {
  public var known: Bool
  public var explanation: String
  public var refs: [Int]

  /// The first line is KNOWN or UNKNOWN; the rest explains, citing `[n]`.
  /// Without a verdict line the reply counts as known when it cites anything.
  public static func parse(_ output: String, validRefs: ClosedRange<Int>? = nil) -> ContextVerdict {
    var lines = output.trimmingCharacters(in: .whitespacesAndNewlines)
      .components(separatedBy: .newlines)
    var known: Bool?
    if let first = lines.first?.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
      .uppercased()
    {
      if first.hasPrefix("UNKNOWN") {
        known = false
        lines.removeFirst()
      } else if first.hasPrefix("KNOWN") {
        known = true
        lines.removeFirst()
      }
    }
    let points = SummaryParser.points(from: lines.joined(separator: "\n"), validRefs: validRefs)
    let text = points.map(\.text).joined(separator: " ")
    var refs: [Int] = []
    for ref in points.flatMap(\.refs) where !refs.contains(ref) { refs.append(ref) }
    return ContextVerdict(known: known ?? !refs.isEmpty, explanation: text, refs: refs)
  }
}
