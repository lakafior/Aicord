//
//  SemanticRanker.swift
//  AicordKit
//
//  Orders messages by how well they match a question, on the device: sentence
//  vectors from NLContextualEmbedding when its model is there, and shared words
//  always. Used to rank search results, to pick what fits a small model's
//  window, and by channel indexes.
//

import Foundation
import NaturalLanguage

public enum SemanticRanker {
  /// How much the vector similarity counts against shared words, when both exist.
  public static let vectorWeight = 0.65

  /// Words worth matching: lowercased, without diacritics, three letters or
  /// more, not a common English or Polish filler word, with frequent endings
  /// trimmed so "links" meets "link" and "serwerze" meets "serwer".
  public static func terms(_ text: String) -> Set<String> {
    // ł has no decomposition, so folding alone keeps it
    let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
      .replacingOccurrences(of: "ł", with: "l")
    var result = Set<String>()
    for word in folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
      let word = String(word)
      guard word.count >= 3, !stopWords.contains(word) else { continue }
      result.insert(stem(word))
    }
    return result
  }

  static func stem(_ word: String) -> String {
    for suffix in suffixes where word.count - suffix.count >= 4 && word.hasSuffix(suffix) {
      return String(word.dropLast(suffix.count))
    }
    return word
  }

  /// The share of the query's words the document has; a word also counts when
  /// one is the start of the other ("jelly" and "jellyfin").
  public static func lexicalScore(query: Set<String>, document: Set<String>) -> Double {
    guard !query.isEmpty else { return 0 }
    var matched = 0.0
    for term in query {
      if document.contains(term) {
        matched += 1
      } else if term.count >= 4,
        document.contains(where: { $0.count >= 4 && ($0.hasPrefix(term) || term.hasPrefix($0)) })
      {
        matched += 0.6
      }
    }
    return matched / Double(query.count)
  }

  public static func cosine(_ a: [Float], _ b: [Float]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    var dot: Float = 0
    var normA: Float = 0
    var normB: Float = 0
    for i in a.indices {
      dot += a[i] * b[i]
      normA += a[i] * a[i]
      normB += b[i] * b[i]
    }
    guard normA > 0, normB > 0 else { return 0 }
    return Double(dot / (normA.squareRoot() * normB.squareRoot()))
  }

  /// Scores between 0 and 1 for each document. Without vectors (or for a
  /// document without one) only shared words count.
  public static func scores(
    query: String, documents: [String], queryVector: [Float]? = nil,
    documentVectors: [[Float]?] = []
  ) -> [Double] {
    let queryTerms = terms(query)
    return documents.indices.map { index in
      let lexical = lexicalScore(query: queryTerms, document: terms(documents[index]))
      guard let queryVector, index < documentVectors.count,
        let vector = documentVectors[index]
      else { return lexical }
      // mean-pooled vectors of unrelated sentences still score about 0.7 and
      // related ones about 0.9 (measured on the Latin model), so stretch that range
      let similarity = max(0, min(1, (cosine(queryVector, vector) - 0.65) / 0.3))
      return vectorWeight * similarity + (1 - vectorWeight) * lexical
    }
  }

  /// Document indexes from best to worst match. Ties keep the original order,
  /// which for Discord's search is newest first.
  public static func order(
    query: String, documents: [String], queryVector: [Float]? = nil,
    documentVectors: [[Float]?] = []
  ) -> [Int] {
    let scores = scores(
      query: query, documents: documents, queryVector: queryVector,
      documentVectors: documentVectors)
    return documents.indices.sorted { lhs, rhs in
      scores[lhs] != scores[rhs] ? scores[lhs] > scores[rhs] : lhs < rhs
    }
  }

  /// What a message is matched on: its text, embed titles and file names
  /// (a search for "ipa" should find "Kite.ipa").
  public static func document(for message: DiscordChannel.Message) -> String {
    var parts = [IntelligenceText.clean(message.content)]
    parts += message.embeds.compactMap { [$0.title, $0.description].compactMap { $0 }.joined(separator: " ") }
    parts += message.attachments.map { $0.filename.replacingOccurrences(of: ".", with: " ") }
    return parts.filter { !$0.isEmpty }.joined(separator: "\n")
  }

  /// Orders with sentence vectors from the device when they're available.
  public static func rank(query: String, documents: [String]) async -> [Int] {
    let embedder = SentenceEmbedder.shared
    guard let queryVector = await embedder.vector(for: query) else {
      return order(query: query, documents: documents, queryVector: nil)
    }
    let vectors = await embedder.vectors(for: documents)
    return order(
      query: query, documents: documents, queryVector: queryVector, documentVectors: vectors)
  }

  private static let suffixes = [
    // Polish, longest first
    "owanie", "ami", "ach", "owi", "ego", "emu", "ych", "ymi", "iem", "ów", "om", "ie", "em",
    // English
    "ing", "ers", "ies", "es", "ed", "er", "s",
  ].sorted { $0.count > $1.count }

  private static let stopWords: Set<String> = [
    "the", "and", "for", "with", "that", "this", "from", "what", "who", "when", "where", "which",
    "about", "have", "has", "had", "was", "were", "are", "you", "your", "our", "there", "their",
    "they", "them", "then", "than", "but", "not", "can", "could", "would", "should", "will",
    "did", "does", "how", "why", "any", "all", "some", "into", "out", "get", "got", "just",
    "like", "last", "week", "day", "days", "messages", "message", "someone", "anyone",
    "jak", "jaki", "jaka", "jakie", "kto", "kiedy", "gdzie", "ktory", "ktora", "ktore", "czy",
    "nie", "tak", "ale", "lub", "albo", "oraz", "jest", "sie", "byl", "byla", "bylo", "ten",
    "ta", "to", "tym", "tego", "temu", "tej", "przez", "dla", "przy", "pod", "nad", "jego",
    "jej", "ich", "mnie", "mi", "co", "coś", "cos", "ktos", "wiadomosc", "wiadomosci",
  ]
}

/// Sentence vectors from Apple's contextual embedding model for Latin script,
/// which covers English, Polish and most European languages. The model ships
/// as an on-demand asset; until it's on the device every call returns `nil`
/// and ranking falls back to shared words.
public actor SentenceEmbedder {
  public static let shared = SentenceEmbedder()

  private var embedding: NLContextualEmbedding?
  private var unavailable = false
  private var cache: [String: [Float]] = [:]

  /// Whether vectors can be made now (the model is downloaded and loaded).
  public var isAvailable: Bool {
    get async { await prepared() != nil }
  }

  public func vector(for text: String) async -> [Float]? {
    let text = String(text.prefix(1_000))
    if let cached = cache[text] { return cached }
    guard let embedding = await prepared(),
      let result = try? embedding.embeddingResult(for: text, language: nil)
    else { return nil }
    var sum = [Double](repeating: 0, count: embedding.dimension)
    var count = 0
    result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
      for i in sum.indices where i < vector.count { sum[i] += vector[i] }
      count += 1
      return true
    }
    guard count > 0 else { return nil }
    let mean = sum.map { Float($0 / Double(count)) }
    if cache.count > 2_000 { cache.removeAll(keepingCapacity: true) }
    cache[text] = mean
    return mean
  }

  public func vectors(for texts: [String]) async -> [[Float]?] {
    var result: [[Float]?] = []
    result.reserveCapacity(texts.count)
    for text in texts {
      result.append(text.isEmpty ? nil : await vector(for: text))
    }
    return result
  }

  private func prepared() async -> NLContextualEmbedding? {
    if let embedding { return embedding }
    guard !unavailable, let candidate = NLContextualEmbedding(script: .latin) else {
      unavailable = true
      return nil
    }
    if !candidate.hasAvailableAssets {
      // asks the system for the model once; it downloads like a keyboard dictionary
      let result = await withCheckedContinuation { continuation in
        candidate.requestAssets { result, _ in continuation.resume(returning: result) }
      }
      guard result == .available else {
        unavailable = true
        return nil
      }
    }
    do {
      try candidate.load()
    } catch {
      unavailable = true
      return nil
    }
    embedding = candidate
    return candidate
  }
}
