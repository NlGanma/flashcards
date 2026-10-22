import XCTest
@testable import VocabKit

final class TextNormalizerTests: XCTestCase {

    func testCollapsesAllWhitespaceKinds() {
        XCTAssertEqual(TextNormalizer.normalizeWhitespace("  hello\n\tworld  "), "hello world")
        // Full-width ideographic space (U+3000) and non-breaking space (U+00A0).
        XCTAssertEqual(TextNormalizer.normalizeWhitespace("a\u{3000}b\u{00A0}c"), "a b c")
        // Zero-width characters are removed entirely.
        XCTAssertEqual(TextNormalizer.normalizeWhitespace("wo\u{200B}rd"), "word")
    }

    func testIsBlank() {
        XCTAssertTrue(TextNormalizer.isBlank("   \n\u{3000} "))
        XCTAssertTrue(TextNormalizer.isBlank(nil))
        XCTAssertFalse(TextNormalizer.isBlank(" x "))
    }

    func testCleanWordStripsWrappingPunctuation() {
        XCTAssertEqual(TextNormalizer.cleanWord("•\u{3000}keen"), "keen")
        XCTAssertEqual(TextNormalizer.cleanWord("\"candid\""), "candid")
        XCTAssertEqual(TextNormalizer.cleanWord("  Abate\n"), "Abate")
        XCTAssertEqual(TextNormalizer.cleanWord("- serene"), "serene")
    }

    func testCleanWordPreservesInternalCharacters() {
        XCTAssertEqual(TextNormalizer.cleanWord("well-being"), "well-being")
        XCTAssertEqual(TextNormalizer.cleanWord("it's"), "it's")
        XCTAssertEqual(TextNormalizer.cleanWord("give up"), "give up")
    }

    func testCleanDefinitionPreservesChinesePunctuation() {
        XCTAssertEqual(TextNormalizer.cleanDefinition("敏锐的；渴望的"), "敏锐的；渴望的")
        XCTAssertEqual(TextNormalizer.cleanDefinition(" 减弱\n减轻 "), "减弱 减轻")
        XCTAssertEqual(TextNormalizer.cleanDefinition("挽歌（爱尔兰）"), "挽歌（爱尔兰）")
    }

    func testCleanPartOfSpeechKeepsTrailingDot() {
        XCTAssertEqual(TextNormalizer.cleanPartOfSpeech(" adj. "), "adj.")
        XCTAssertEqual(TextNormalizer.cleanPartOfSpeech("n."), "n.")
    }

    /// Edge-trimming used to eat the closing bracket of a parenthetical, so a real entry
    /// in the user's library read "histrionic (histrionic".
    func testCleanWordKeepsABalancedParenthetical() {
        XCTAssertEqual(TextNormalizer.cleanWord("histrionic (histrionics)"), "histrionic (histrionics)")
        XCTAssertEqual(TextNormalizer.cleanWord("• appraise (appraisal)"), "appraise (appraisal)")
        XCTAssertEqual(TextNormalizer.cleanWord("恒常（héng cháng）"), "恒常（héng cháng）")
    }

    /// Wrapping brackets around the whole word are still peeled — that's the case the
    /// trimming exists for.
    func testCleanWordStillPeelsWrappingBrackets() {
        XCTAssertEqual(TextNormalizer.cleanWord("(keen)"), "keen")
        XCTAssertEqual(TextNormalizer.cleanWord("[keen]"), "keen")
        XCTAssertEqual(TextNormalizer.cleanWord("- keen -"), "keen")
    }

    func testCleanWordLeavesUnopenedClosersTrimmed() {
        XCTAssertEqual(TextNormalizer.cleanWord("keen)"), "keen")
        XCTAssertEqual(TextNormalizer.cleanWord("keen]"), "keen")
    }

    /// The key is a persisted identity: improving the display form must not re-key an
    /// already-learned word, or it silently returns to the new pile.
    func testNormalizedKeyIsUnchangedByTheBracketFix() {
        XCTAssertEqual(TextNormalizer.normalizedKey("histrionic (histrionic)"),
                       "histrionic (histrionic")
        XCTAssertEqual(TextNormalizer.normalizedKey("(keen)"), "keen")
        XCTAssertEqual(TextNormalizer.normalizedKey("Keen"), "keen")
    }

    func testNormalizedKeyIsCaseAndSpaceInsensitive() {
        XCTAssertEqual(TextNormalizer.normalizedKey("Keen"), "keen")
        XCTAssertEqual(TextNormalizer.normalizedKey(" KEEN "), "keen")
        XCTAssertEqual(TextNormalizer.normalizedKey("keen"),
                       TextNormalizer.normalizedKey("  Keen\n"))
    }
}
