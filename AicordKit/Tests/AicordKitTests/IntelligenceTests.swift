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

  func testNestedBulletsAndTabs() {
    let points = SummaryParser.points(from: "- - Ola left [2]\n-\tBob stayed [3]\n  •   Done [1]")
    XCTAssertEqual(points.map(\.text), ["Ola left", "Bob stayed", "Done"])
    XCTAssertEqual(points.map(\.refs), [[2], [3], [1]])
  }

  func testQuotedPoints() {
    let points = SummaryParser.points(from: "\"- curl hangs on Windows [2, 3] \"\n“- Fixed tonight [4]”")
    XCTAssertEqual(points.map(\.text), ["curl hangs on Windows", "Fixed tonight"])
    XCTAssertEqual(points.map(\.refs), [[2, 3], [4]])
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
    // local servers default to http
    XCTAssertEqual(url("localhost:11434"), "http://localhost:11434/v1")
    XCTAssertEqual(url("192.168.1.20:1234"), "http://192.168.1.20:1234/v1")
    XCTAssertEqual(url("macbook.local:11434/v1"), "http://macbook.local:11434/v1")
    XCTAssertEqual(url("api.example.com"), "https://api.example.com/v1")
    XCTAssertTrue(OpenAICompatibleClient.isLocalHost("172.20.0.5"))
    XCTAssertFalse(OpenAICompatibleClient.isLocalHost("8.8.8.8"))
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

class ToolAgentTests: XCTestCase {
  typealias Message = OpenAICompatibleClient.Message

  actor Log {
    var toolCounts: [Int] = []
    var runs: [String] = []
    func turn(_ count: Int) { toolCounts.append(count) }
    func run(_ args: String) { runs.append(args) }
  }

  func testAgentCallsToolsThenAnswers() async throws {
    let log = Log()
    let search = ToolAgent.Tool(
      name: "search", description: "Search", parameters: .objectSchema([("text", "string", "Words")])
    ) { args in
      await log.run(args)
      return "[1] Ola: the auction ends Friday"
    }
    let agent = ToolAgent(tools: [search], maxCalls: 3) { messages, tools in
      await log.turn(tools.count)
      if messages.contains(where: { $0.role == "tool" }) {
        return Message(role: "assistant", content: .text("- It ends Friday [1]"))
      }
      return Message(
        role: "assistant", content: .text(""),
        tool_calls: [.init(id: "a", name: "search", arguments: #"{"text":"auction"}"#)])
    }
    let answer = try await agent.answer(instructions: "i", prompt: "When does the auction end?")
    XCTAssertEqual(answer, "- It ends Friday [1]")
    let runs = await log.runs
    XCTAssertEqual(runs, [#"{"text":"auction"}"#])
  }

  func testAgentStopsOfferingToolsAtTheLimit() async throws {
    let log = Log()
    let search = ToolAgent.Tool(name: "search", description: "", parameters: .objectSchema([])) { _ in
      "nothing"
    }
    let agent = ToolAgent(tools: [search], maxCalls: 2) { _, tools in
      await log.turn(tools.count)
      if tools.isEmpty { return Message(role: "assistant", content: .text("gave up")) }
      return Message(
        role: "assistant", content: .text(""),
        tool_calls: [.init(id: UUID().uuidString, name: "search", arguments: "{}")])
    }
    let answer = try await agent.answer(instructions: "", prompt: "")
    XCTAssertEqual(answer, "gave up")
    let counts = await log.toolCounts
    XCTAssertEqual(counts, [1, 1, 0])
  }

  func testUnknownToolAndExtraCallsGetAnExplanation() async throws {
    let agent = ToolAgent(tools: [], maxCalls: 0) { messages, _ in
      if let last = messages.last, last.role == "tool" {
        return Message(role: "assistant", content: .text(last.content.text))
      }
      return Message(
        role: "assistant", content: .text(""),
        tool_calls: [.init(id: "x", name: "deleteEverything", arguments: "{}")])
    }
    let answer = try await agent.answer(instructions: "", prompt: "")
    XCTAssertEqual(answer, ToolAgent.limitReached)
  }

  func testToolCallsRoundTripThroughJSON() throws {
    let reply = """
      {"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"c1","type":"function","function":{"name":"search","arguments":"{\\"text\\":\\"agent\\"}"}}]}}]}
      """
    let decoded = try JSONDecoder().decode(
      OpenAICompatibleClient.ChatResponse.self, from: Data(reply.utf8))
    let call = decoded.choices?.first?.message?.tool_calls?.first
    XCTAssertEqual(call?.function.name, "search")
    XCTAssertEqual(call?.function.arguments, #"{"text":"agent"}"#)

    let definition = OpenAICompatibleClient.ToolDefinition(
      name: "search", description: "Find messages",
      parameters: .objectSchema([("text", "string", "Words")], required: ["text"]))
    let json = String(decoding: try JSONEncoder().encode(definition), as: UTF8.self)
    XCTAssertTrue(json.contains(#""type":"function""#))
    XCTAssertTrue(json.contains(#""required":["text"]"#))

    let toolMessage = String(
      decoding: try JSONEncoder().encode(Message.tool("ok", callID: "c1")), as: UTF8.self)
    XCTAssertTrue(toolMessage.contains(#""tool_call_id":"c1""#))
  }
}

class ContextRankerTests: XCTestCase {
  typealias Candidate = ContextRanker.Candidate

  func testMentionedQuestionOutranksNearbyChatter() {
    let target = Candidate(
      id: "t", authorID: "ania", mentionedIDs: ["tomek"], text: "InPost, around 15 zł", distance: 0)
    let candidates = [
      Candidate(id: "1", authorID: "bob", text: "lol", distance: 0),
      Candidate(id: "2", authorID: "tomek", text: "How much is shipping with InPost?", distance: 5),
      Candidate(id: "3", authorID: "ola", text: "nice jacket", distance: 1),
    ]
    let ranked = ContextRanker.rank(target: target, candidates: candidates)
    XCTAssertEqual(ranked.first?.0.id, "2")
  }

  func testKeywordsSkipShortAndCommonWords() {
    XCTAssertEqual(
      ContextRanker.keywords("What is the shipping price, jest 2024?"), ["shipping", "price"])
  }

  func testVerdictParsing() {
    let known = ContextVerdict.parse(
      "KNOWN\n- This is Ania's reply to Tomek's question about shipping [2].", validRefs: 1...5)
    XCTAssertTrue(known.known)
    XCTAssertEqual(known.refs, [2])
    XCTAssertEqual(known.explanation, "This is Ania's reply to Tomek's question about shipping.")

    let unknown = ContextVerdict.parse("UNKNOWN\nNot enough context.")
    XCTAssertFalse(unknown.known)

    let bare = ContextVerdict.parse("It answers [1] and [3].", validRefs: 1...2)
    XCTAssertTrue(bare.known)
    XCTAssertEqual(bare.refs, [1])
  }
}

class SearchIntentTests: XCTestCase {
  func testParsesFencedJSON() {
    let reply = """
      Sure:
      ```json
      {"keywords": "shipping agent", "author": "@Ola", "daysBack": "7", "has": "link", "channel": "#wts", "server": ""}
      ```
      """
    XCTAssertEqual(
      SearchIntent.parse(reply),
      SearchIntent(
        keywords: "shipping agent", author: "Ola", channel: "wts", daysBack: 7, has: ["link"]))
  }

  func testParsesListsAndDropsNonsense() {
    let intent = SearchIntent.parse(#"{"has": ["Image", "file"], "daysBack": 0, "after": "2026-10-01"}"#)
    XCTAssertEqual(intent?.has, ["image", "file"])
    XCTAssertNil(intent?.daysBack)
    XCTAssertEqual(intent?.after, "2026-10-01")
    XCTAssertNil(SearchIntent.parse("no json here"))
  }

  func testInstructionsCarryToday() {
    let date = ISO8601DateFormatter().date(from: "2026-10-30T12:00:00Z")!
    XCTAssertTrue(SearchIntent.instructions(today: date).contains("2026-10-30"))
  }
}

class ScamSignalsTests: XCTestCase {
  func testFakeNitroWithLookalikeLink() {
    let kinds = ScamSignals.check("Free Nitro for 3 months! Claim here: https://dlscord.gift/abc123")
    XCTAssertEqual(kinds, [.lookalikeLink, .fakeNitro])
  }

  func testAccidentalReportInPolish() {
    XCTAssertEqual(
      ScamSignals.check("Hej, przypadkowo zgłosiłem twoje konto, napisz do admina"),
      [.accidentalReport])
  }

  func testRealLinksAreFine() {
    XCTAssertTrue(ScamSignals.check("Join us https://discord.gg/abc and https://discord.com/x").isEmpty)
    XCTAssertTrue(ScamSignals.check("I got Nitro for my birthday, it's great").isEmpty)
    XCTAssertFalse(ScamSignals.isLookalike("cdn.discordapp.com"))
    XCTAssertFalse(ScamSignals.isLookalike("github.com"))
  }

  func testLookalikes() {
    XCTAssertTrue(ScamSignals.isLookalike("steamcommunlty.com"))
    XCTAssertTrue(ScamSignals.isLookalike("discord-nitro.com"))
    XCTAssertTrue(ScamSignals.isLookalike("disocrd.gift"))
  }
}

class ReplyThreadTests: XCTestCase {
  typealias Node = ReplyThread.Node

  func testLaterRepliesFollowEachOther() {
    let loaded = [
      Node(id: "1", parentID: nil),
      Node(id: "2", parentID: "1"),
      Node(id: "3", parentID: nil),
      Node(id: "4", parentID: "2"),
      Node(id: "5", parentID: "4"),
      Node(id: "6", parentID: "3"),
    ]
    XCTAssertEqual(ReplyThread.laterReplies(to: ["1", "2"], in: loaded), ["4", "5"])
  }

  func testFitKeepsTargetAndAncestorsFirst() {
    // 1 ← 3 ← 5 (target); 2 and 4 reply to 1, closer to the target than 1 is
    let thread = [
      Node(id: "1", parentID: nil),
      Node(id: "2", parentID: "1"),
      Node(id: "3", parentID: "1"),
      Node(id: "4", parentID: "1"),
      Node(id: "5", parentID: "3"),
    ]
    let kept = ReplyThread.fit(thread: thread, target: "5", costs: [10, 10, 10, 10, 10], budget: 30)
    XCTAssertEqual(kept, [0, 2, 4])
    let more = ReplyThread.fit(thread: thread, target: "5", costs: [10, 10, 10, 10, 10], budget: 40)
    XCTAssertEqual(more, [0, 2, 3, 4])
  }

  func testFitAlwaysKeepsTheTarget() {
    let thread = [Node(id: "1", parentID: nil), Node(id: "2", parentID: "1")]
    XCTAssertEqual(ReplyThread.fit(thread: thread, target: "2", costs: [5, 50], budget: 10), [1])
    XCTAssertEqual(ReplyThread.fit(thread: thread, target: "9", costs: [5, 5], budget: 10), [])
  }
}
