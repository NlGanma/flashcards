import XCTest
@testable import VocabFlashcards

/// The example panel emphasizes the studied word in the English sentence and the matching
/// gloss in the Chinese one. Both use loose matching, so these pin down where it stops.
final class SentenceHighlighterTests: XCTestCase {

    private func matched(_ sentence: String, _ ranges: [Range<String.Index>]) -> [String] {
        ranges.map { String(sentence[$0]) }
    }

    func testEnglishMatchesInflectedForms() {
        let sentence = "Abating slowly, the storm abated only after it had abated the harbor's defenses."
        let ranges = SentenceHighlighter.englishRanges(in: sentence, word: "abate")
        XCTAssertEqual(matched(sentence, ranges), ["Abating", "abated", "abated"])
    }

    func testEnglishDoesNotMatchAnUnrelatedWord() {
        let sentence = "The keeper of the keys was not keen on visitors."
        let ranges = SentenceHighlighter.englishRanges(in: sentence, word: "keen")
        XCTAssertEqual(matched(sentence, ranges), ["keen"])
    }

    func testEnglishMatchesAWholePhrase() {
        let sentence = "Two officials were implicated in the scheme."
        let ranges = SentenceHighlighter.englishRanges(in: sentence, word: "implicated in")
        XCTAssertEqual(matched(sentence, ranges), ["implicated in"])
    }

    func testChineseMatchesTheLongestGlossFirst() {
        let sentence = "她敏锐的洞察力揭穿了这个说法。"
        let ranges = SentenceHighlighter.chineseRanges(in: sentence, definition: "敏锐的，敏锐的洞察力")
        XCTAssertEqual(matched(sentence, ranges), ["敏锐的洞察力"])
    }

    /// A gloss can carry a separator inside its own aside — "没药（一种中药、香料）" — so the
    /// aside has to come off before the gloss is split, or nothing matches at all.
    func testChineseIgnoresParentheticalAsides() {
        let sentence = "商人沿着这些路线运送没药。"
        let ranges = SentenceHighlighter.chineseRanges(in: sentence, definition: "没药（一种中药、香料）")
        XCTAssertEqual(matched(sentence, ranges), ["没药"])
    }

    func testChineseReturnsNothingWhenTheGlossIsAbsent() {
        let sentence = "这句话与释义无关。"
        XCTAssertTrue(SentenceHighlighter.chineseRanges(in: sentence, definition: "敏锐的，渴望的").isEmpty)
    }
}
