import XCTest
@testable import VocabKit

final class DeckBuilderTests: XCTestCase {

    private let builder = DeckBuilder()

    private func set(_ name: String, _ items: [(String, String, String)]) -> PracticeSet {
        PracticeSet(name: name, items: items.map {
            VocabItem(english: $0.0, partOfSpeech: $0.1, definition: $0.2, setName: name)
        })
    }

    func testMergesDuplicateWordsAcrossSets() {
        let sets = [
            set("A", [("keen", "adj.", "敏锐的"), ("calm", "adj.", "平静的")]),
            set("B", [("Keen", "n.", "挽歌")])   // different casing + new sense
        ]
        let deck = builder.buildOrdered(from: sets, filter: .includeKnown, knownKeys: [])
        XCTAssertEqual(deck.count, 2)
        let keen = deck.first { $0.key == "keen" }!
        XCTAssertEqual(keen.word, "keen")            // first-seen display form
        XCTAssertEqual(keen.senses.count, 2)
        XCTAssertEqual(keen.sourceSets, ["A", "B"])
    }

    func testDeduplicatesIdenticalSenses() {
        let sets = [
            set("A", [("keen", "adj.", "敏锐的")]),
            set("B", [("keen", "adj.", "敏锐的")])   // exact duplicate sense
        ]
        let deck = builder.buildOrdered(from: sets, filter: .includeKnown, knownKeys: [])
        XCTAssertEqual(deck.first!.senses.count, 1)
    }

    func testWordWithNoContentStillProducesCard() {
        let sets = [set("A", [("orphan", "", "")])]
        let deck = builder.buildOrdered(from: sets, filter: .includeKnown, knownKeys: [])
        XCTAssertEqual(deck.count, 1)
        XCTAssertTrue(deck[0].senses.isEmpty)
        XCTAssertFalse(deck[0].hasContent)
    }

    func testExcludeKnownFilter() {
        let sets = [set("A", [("keen", "adj.", "敏锐的"), ("calm", "adj.", "平静的")])]
        let deck = builder.buildOrdered(from: sets, filter: .excludeKnown, knownKeys: ["keen"])
        XCTAssertEqual(deck.map(\.key), ["calm"])
    }

    func testOnlyKnownFilter() {
        let sets = [set("A", [("keen", "adj.", "敏锐的"), ("calm", "adj.", "平静的")])]
        let deck = builder.buildOrdered(from: sets, filter: .onlyKnown, knownKeys: ["keen"])
        XCTAssertEqual(deck.map(\.key), ["keen"])
    }

    func testExcludeKnownWhenAllKnownYieldsEmptyDeck() {
        let sets = [set("A", [("keen", "adj.", "敏锐的")])]
        let deck = builder.buildOrdered(from: sets, filter: .excludeKnown, knownKeys: ["keen"])
        XCTAssertTrue(deck.isEmpty)
    }

    func testExcludeKnownAlsoSkipsAlmostKnownWords() {
        let sets = [set("A", [("keen", "adj.", "敏锐的"), ("calm", "adj.", "平静的"),
                              ("abate", "v.", "减轻")])]
        let deck = builder.buildOrdered(from: sets, filter: .excludeKnown,
                                        knownKeys: ["keen"], asideKeys: ["calm"])
        XCTAssertEqual(deck.map(\.key), ["abate"])
    }

    func testIncludeKnownStillContainsAlmostKnownWords() {
        let sets = [set("A", [("keen", "adj.", "敏锐的"), ("calm", "adj.", "平静的")])]
        let deck = builder.buildOrdered(from: sets, filter: .includeKnown,
                                        knownKeys: [], asideKeys: ["calm"])
        XCTAssertEqual(Set(deck.map(\.key)), ["keen", "calm"])
    }

    func testOnlyKnownIgnoresAlmostKnownWords() {
        let sets = [set("A", [("keen", "adj.", "敏锐的"), ("calm", "adj.", "平静的")])]
        let deck = builder.buildOrdered(from: sets, filter: .onlyKnown,
                                        knownKeys: ["keen"], asideKeys: ["calm"])
        XCTAssertEqual(deck.map(\.key), ["keen"])
    }

    func testShuffledBuildKeepsSameContents() {
        let sets = [set("A", (0..<50).map { ("word\($0)", "n.", "def\($0)") })]
        let ordered = builder.buildOrdered(from: sets, filter: .includeKnown, knownKeys: [])
        let shuffled = builder.build(from: sets, filter: .includeKnown, knownKeys: [])
        XCTAssertEqual(Set(ordered.map(\.key)), Set(shuffled.map(\.key)))
        XCTAssertEqual(shuffled.count, 50)
    }
}
