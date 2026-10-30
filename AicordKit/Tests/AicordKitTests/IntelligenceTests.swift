import Foundation
import XCTest

@testable import AicordKit

class IntelligenceTests: XCTestCase {

  // MARK: Text

  func testCleanReplacesMentionsEmojiAndSpoilers() {
    let text = IntelligenceText.clean(
      "<@123> look at <#9> <:pog:111> ||secret|| <@&5>\n\nsecond line",
      userNames: ["123": "Ala"],
      channelNames: ["9": "general"],
      roleNames: [:]
    )
    XCTAssertEqual(text, "@Ala look at #general :pog: [spoiler] @role / second line")
  }

  func testLineIsNumberedAndCut() {
    XCTAssertEqual(IntelligenceText.line(ref: 3, author: "Ola", text: "hi"), "[3] Ola: hi")
    let long = IntelligenceText.line(
      ref: 1, author: "A", text: String(repeating: "x", count: 50), maxCharacters: 10)
    XCTAssertEqual(long, "[1] A: xxxxxxxxxx…")
  }

  func testChunksKeepOrderAndBudget() {
    let lines = (1...30).map { "[\($0)] Name: " + String(repeating: "a", count: 40) }
    let chunks = IntelligenceText.chunks(lines, tokenBudget: 100)
    XCTAssertGreaterThan(chunks.count, 1)
    XCTAssertEqual(chunks.flatMap { $0 }, lines)
    for chunk in chunks {
      let tokens = chunk.reduce(0) { $0 + IntelligenceText.estimatedTokens($1) + 1 }
      XCTAssertLessThanOrEqual(tokens, 100)
    }
  }

  func testChunksCutALineTooLongAlone() {
    let chunks = IntelligenceText.chunks([String(repeating: "b", count: 1_000)], tokenBudget: 50)
    XCTAssertEqual(chunks.count, 1)
    XCTAssertLessThanOrEqual(IntelligenceText.estimatedTokens(chunks[0][0]) + 1, 50)
  }

  func testEmptyInputHasNoChunks() {
    XCTAssertTrue(IntelligenceText.chunks([], tokenBudget: 100).isEmpty)
  }

  // MARK: Parsing

  func testPointsWithCitations() {
    let reply = """
      Here is the summary:
      - **Ala** proposed a meeting on Friday [3, 7].
      * Bob shared the build [12]
      2. Release moved to May [4-6]
      • Nothing else [99]
      """
    let points = SummaryParser.points(from: reply, validRefs: 1...20)
    XCTAssertEqual(
      points,
      [
        SummaryPoint(text: "Ala proposed a meeting on Friday.", refs: [3, 7]),
        SummaryPoint(text: "Bob shared the build", refs: [12]),
        SummaryPoint(text: "Release moved to May", refs: [4, 5, 6]),
        SummaryPoint(text: "Nothing else", refs: []),
      ])
  }

  func testPointsFromPlainLinesAndRepeatedRefs() {
    let points = SummaryParser.points(from: "Talked about pizza [1][1; 2]\n\n### Topics:")
    XCTAssertEqual(points, [SummaryPoint(text: "Talked about pizza", refs: [1, 2])])
  }

  func testPointLineRoundTrips() {
    let point = SummaryPoint(text: "Plans for Friday", refs: [2, 9])
    XCTAssertEqual(SummaryParser.points(from: point.line), [point])
  }

  // MARK: Summarizer

  /// A fake model: cites the first message of each piece, or merges by keeping
  /// the first point's citations.
  actor CallLog {
    var prompts: [String] = []
    func add(_ prompt: String) { prompts.append(prompt) }
  }

  func testSummarizerOneCallWhenItFits() async throws {
    let log = CallLog()
    let summarizer = Summarizer(tokenBudget: 1_000, language: "English") { _, prompt in
      await log.add(prompt)
      return "- Everyone said hello [1, 2]\n- Ola left [3]"
    }
    let points = try await summarizer.summarize(
      lines: ["[1] A: hi", "[2] B: hello", "[3] Ola: bye"], context: "#general", maxPoints: 5)
    let calls = await log.prompts.count
    XCTAssertEqual(calls, 1)
    XCTAssertEqual(points.map(\.refs), [[1, 2], [3]])
  }

  func testSummarizerMergesPieces() async throws {
    let log = CallLog()
    let lines = (1...40).map { "[\($0)] Name: " + String(repeating: "word ", count: 10) }
    let progressLog = ProgressLog()
    let summarizer = Summarizer(tokenBudget: 120, language: "Polish") { instructions, prompt in
      await log.add(prompt)
      if instructions.contains("merge") {
        return "- Merged topic [1, 40]"
      }
      let first = prompt.split(separator: "\n").first { $0.hasPrefix("[") }!
      let ref = first.dropFirst().prefix { $0.isNumber }
      return "- Piece starting at \(ref) [\(ref)]"
    }
    let points = try await summarizer.summarize(
      lines: lines, context: "#general", maxPoints: 3,
      progress: { value in Task { await progressLog.add(value) } })
    let prompts = await log.prompts
    XCTAssertGreaterThan(prompts.count, 2)
    XCTAssertEqual(points, [SummaryPoint(text: "Merged topic", refs: [1, 40])])
    XCTAssertTrue(prompts.last!.contains("Partial summaries"))
  }

  actor ProgressLog {
    var values: [Double] = []
    func add(_ value: Double) { values.append(value) }
  }

  func testSummarizerStopsWhenCancelled() async {
    let summarizer = Summarizer(tokenBudget: 40, language: "English") { _, _ in
      try await Task.sleep(for: .seconds(5))
      return "- x [1]"
    }
    let lines = (1...30).map { "[\($0)] Name: some words here" }
    let task = Task { try await summarizer.summarize(lines: lines, context: "", maxPoints: 3) }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("expected cancellation")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
  }

  func testInstructionsNameTheLanguageAndLimit() {
    let text = Summarizer.instructions(maxPoints: 3, language: "Polish")
    XCTAssertTrue(text.contains("at most 3"))
    XCTAssertTrue(text.contains("Write in Polish"))
  }

  // MARK: OpenAI-compatible API

  func testBaseURLNormalization() {
    func url(_ text: String) -> String? {
      OpenAICompatibleClient.normalizedBaseURL(text)?.absoluteString
    }
    XCTAssertEqual(url("https://api.mistral.ai/v1"), "https://api.mistral.ai/v1")
    XCTAssertEqual(url("api.openai.com"), "https://api.openai.com/v1")
    XCTAssertEqual(url("http://localhost:11434/"), "http://localhost:11434/v1")
    XCTAssertEqual(url("https://openrouter.ai/api/v1/"), "https://openrouter.ai/api/v1")
    XCTAssertEqual(
      url("https://api.mistral.ai/v1/chat/completions"), "https://api.mistral.ai/v1")
    XCTAssertNil(url(""))
    XCTAssertNil(url("ftp://example.com"))
  }

  func testRequestCarriesKeyAndJSON() throws {
    let client = OpenAICompatibleClient(
      baseURL: URL(string: "https://example.com/v1")!, apiKey: "k", model: "m")
    let request = client.request(path: "chat/completions", body: Data("{}".utf8))
    XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/chat/completions")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer k")

    let keyless = OpenAICompatibleClient(
      baseURL: URL(string: "http://localhost:1234/v1")!, apiKey: "", model: "m")
    XCTAssertNil(keyless.request(path: "models").value(forHTTPHeaderField: "Authorization"))
  }

  func testDecodesRepliesAndErrors() throws {
    let reply = """
      {"choices":[{"message":{"role":"assistant","content":"<think>hmm</think>\\n- Point [1]"}}]}
      """
    let decoded = try JSONDecoder().decode(
      OpenAICompatibleClient.ChatResponse.self, from: Data(reply.utf8))
    let text = decoded.choices?.first?.message?.content.text ?? ""
    XCTAssertEqual(
      OpenAICompatibleClient.strippingReasoning(text).trimmingCharacters(in: .whitespacesAndNewlines),
      "- Point [1]")

    XCTAssertEqual(
      OpenAICompatibleClient.errorMessage(in: Data(#"{"error":{"message":"bad key"}}"#.utf8)),
      "bad key")
    XCTAssertEqual(
      OpenAICompatibleClient.errorMessage(in: Data(#"{"message":"Unauthorized"}"#.utf8)),
      "Unauthorized")
    XCTAssertNil(OpenAICompatibleClient.errorMessage(in: Data("nope".utf8)))
  }

  func testEncodesImageParts() throws {
    let message = OpenAICompatibleClient.Message(
      role: "user", content: .parts([.text("What is this?"), .image(url: "data:image/png;base64,AA")]))
    let json = String(decoding: try JSONEncoder().encode(message), as: UTF8.self)
    XCTAssertTrue(json.contains(#""type":"image_url""#))
    XCTAssertTrue(json.contains(#""image_url":{"url":"data:image\/png;base64,AA"}"#))
  }

  func testDecodesModelLists() throws {
    let list = try JSONDecoder().decode(
      OpenAICompatibleClient.ModelList.self,
      from: Data(#"{"object":"list","data":[{"id":"b"},{"id":"a"}]}"#.utf8))
    XCTAssertEqual(list.data?.map(\.id), ["b", "a"])
  }
}
