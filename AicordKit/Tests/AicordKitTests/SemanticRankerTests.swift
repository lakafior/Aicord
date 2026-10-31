import XCTest

@testable import AicordKit

final class SemanticRankerTests: XCTestCase {
  func testTermsFoldCaseDiacriticsAndEndings() {
    let terms = SemanticRanker.terms("Kto polecał Jellyfin na serwerze? Links!")
    XCTAssertTrue(terms.contains("jellyfin"))
    XCTAssertTrue(terms.contains("polecal"))
    XCTAssertGreaterThan(
      SemanticRanker.lexicalScore(query: SemanticRanker.terms("serwer"), document: terms), 0)
    XCTAssertTrue(terms.contains("link"))
    XCTAssertFalse(terms.contains("kto"))
    XCTAssertFalse(terms.contains("na"))
  }

  func testLexicalOrderPutsSharedWordsFirst() {
    let documents = [
      "good morning everyone",
      "anyone tried jellyfin with a shipping agent?",
      "jellyfin is great",
    ]
    let order = SemanticRanker.order(
      query: "who recommended jellyfin shipping agent", documents: documents)
    XCTAssertEqual(order, [1, 2, 0])
  }

  func testTiesKeepTheOriginalOrder() {
    let order = SemanticRanker.order(query: "nothing matches", documents: ["a", "b", "c"])
    XCTAssertEqual(order, [0, 1, 2])
  }

  func testPrefixesCountPartly() {
    let score = SemanticRanker.lexicalScore(
      query: SemanticRanker.terms("jelly"), document: SemanticRanker.terms("jellyfin server"))
    XCTAssertGreaterThan(score, 0)
    XCTAssertLessThan(score, 1)
  }

  func testVectorsOutweighWordsWhenPresent() {
    let documents = ["the cat sat", "completely unrelated words"]
    // the second document's vector points the same way as the query's
    let order = SemanticRanker.order(
      query: "kitten", documents: documents, queryVector: [1, 0],
      documentVectors: [[0, 1], [1, 0.05]])
    XCTAssertEqual(order, [1, 0])
  }

  func testCosine() {
    XCTAssertEqual(SemanticRanker.cosine([1, 0], [1, 0]), 1, accuracy: 0.0001)
    XCTAssertEqual(SemanticRanker.cosine([1, 0], [0, 1]), 0, accuracy: 0.0001)
    XCTAssertEqual(SemanticRanker.cosine([], []), 0)
  }
}
