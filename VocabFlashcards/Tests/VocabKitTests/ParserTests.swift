import XCTest
@testable import VocabKit

final class ParserTests: XCTestCase {

    private let parser = XLSXVocabParser()

    private func fixture(_ name: String) throws -> URL {
        let url = Bundle.module.url(forResource: name, withExtension: "xlsx", subdirectory: "Fixtures")
        return try XCTUnwrap(url, "Missing fixture \(name).xlsx")
    }

    private func keys(_ set: PracticeSet) -> [String] { set.items.map(\.key) }

    // MARK: - Standard canonical layout

    func testStandardLayoutDetectsFourSets() throws {
        let file = try parser.parse(fileURL: fixture("standard"))
        XCTAssertEqual(file.sets.map(\.name), ["Practice 1", "Practice 2", "Practice 3", "Practice 4"])
    }

    func testStandardSkipsBlankAndIncompleteRows() throws {
        let file = try parser.parse(fileURL: fixture("standard"))
        let p1 = file.sets[0]
        // keen, abate, candid, lucid, brisk — blank row and missing-English row skipped.
        XCTAssertEqual(keys(p1), ["keen", "abate", "candid", "lucid", "brisk"])
    }

    func testStandardToleratesMissingPosAndDefinition() throws {
        let file = try parser.parse(fileURL: fixture("standard"))
        let items = file.sets[0].items
        let lucid = try XCTUnwrap(items.first { $0.key == "lucid" })
        XCTAssertEqual(lucid.partOfSpeech, "")            // POS missing but kept
        XCTAssertEqual(lucid.definition, "清晰的")
        let brisk = try XCTUnwrap(items.first { $0.key == "brisk" })
        XCTAssertEqual(brisk.partOfSpeech, "adj.")
        XCTAssertEqual(brisk.definition, "")              // definition missing but kept
    }

    func testStandardNormalizesWhitespaceNoisyCell() throws {
        let file = try parser.parse(fileURL: fixture("standard"))
        let vigor = try XCTUnwrap(file.sets[3].items.first { $0.key == "vigor" })
        XCTAssertEqual(vigor.english, "vigor")
        XCTAssertEqual(vigor.definition, "活力")
    }

    func testStandardDeckMergesDuplicateWords() throws {
        let file = try parser.parse(fileURL: fixture("standard"))
        let deck = DeckBuilder().buildOrdered(from: file.sets, filter: .includeKnown, knownKeys: [])
        XCTAssertEqual(deck.count, 8)                     // distinct words across all sets

        let keen = try XCTUnwrap(deck.first { $0.key == "keen" })
        XCTAssertEqual(keen.word, "keen")
        XCTAssertEqual(keen.senses.count, 3)             // three distinct senses across sets
        XCTAssertEqual(Set(keen.sourceSets), ["Practice 1", "Practice 2", "Practice 3"])

        let abate = try XCTUnwrap(deck.first { $0.key == "abate" })
        XCTAssertEqual(abate.senses.count, 1)            // identical sense de-duplicated

        let candid = try XCTUnwrap(deck.first { $0.key == "candid" })
        XCTAssertEqual(candid.senses.count, 1)
    }

    // MARK: - Alternate / robust layouts

    func testEnglishHeadersAutoNameSets() throws {
        let file = try parser.parse(fileURL: fixture("english_headers"))
        XCTAssertEqual(file.sets.map(\.name), ["Practice Set 1", "Practice Set 2"])
        XCTAssertEqual(keys(file.sets[0]), ["mitigate", "robust"])
    }

    func testSpacerColumnsBetweenBlocks() throws {
        let file = try parser.parse(fileURL: fixture("spacer_columns"))
        XCTAssertEqual(file.sets.map(\.name), ["Practice 1", "Practice 2"])
        XCTAssertEqual(keys(file.sets[0]), ["gregarious", "frugal"])
        XCTAssertEqual(keys(file.sets[1]), ["tenacious", "verbose"])
    }

    func testMessyFormattingStillParses() throws {
        let file = try parser.parse(fileURL: fixture("messy"))
        XCTAssertEqual(file.sets.count, 1)
        let p1 = file.sets[0]
        XCTAssertEqual(p1.name, "Practice 1")
        XCTAssertEqual(keys(p1), ["keen", "abate", "candid"])
        let abate = try XCTUnwrap(p1.items.first { $0.key == "abate" })
        XCTAssertEqual(abate.definition, "减弱 减轻")     // newline collapsed
        let keen = try XCTUnwrap(p1.items.first { $0.key == "keen" })
        XCTAssertEqual(keen.english, "keen")             // bullet + full-width space stripped
    }

    func testPrefersVocabularySheetOverWordList() throws {
        // The workbook has a words-only "List" sheet and a full word|pos|definition
        // "Answers" sheet. The parser must pick the one that actually looks like vocabulary,
        // regardless of sheet order.
        let file = try parser.parse(fileURL: fixture("multi_sheet"))
        XCTAssertEqual(file.sets.map(\.name), ["Unit A", "Unit B"])
        let keen = try XCTUnwrap(file.sets[0].items.first { $0.key == "keen" })
        XCTAssertEqual(keen.partOfSpeech, "adj.")
        XCTAssertEqual(keen.definition, "敏锐的")
        // Ensure it did NOT parse the headerless word-list sheet.
        XCTAssertFalse(file.sets.contains { $0.name.hasPrefix("Practice") })
    }

    func testHeaderlessLayoutFallsBackToTriples() throws {
        let file = try parser.parse(fileURL: fixture("headerless"))
        XCTAssertEqual(file.sets.map(\.name), ["Practice Set 1", "Practice Set 2"])
        XCTAssertEqual(keys(file.sets[0]), ["brave", "quiet"])
        XCTAssertEqual(keys(file.sets[1]), ["rapid", "still"])
    }

    func testKeepsHeaderLikeVocabularyWordsBelowARealHeader() throws {
        let file = try parser.parse(fileURL: fixture("header_like_words"))

        XCTAssertEqual(file.sets.count, 1)
        XCTAssertEqual(keys(file.sets[0]), ["meaning", "term"])
    }

    func testHeaderDetectionDoesNotMatchSubstringsInsideWords() throws {
        let file = try parser.parse(fileURL: fixture("header_substrings"))

        XCTAssertEqual(file.sets.count, 2)
        XCTAssertEqual(keys(file.sets[0]), ["sword", "calm"])
        XCTAssertEqual(keys(file.sets[1]), ["possible", "rapid"])
    }

    // MARK: - Error paths

    func testEmptyWorkbookThrows() throws {
        XCTAssertThrowsError(try parser.parse(fileURL: fixture("empty"))) { error in
            XCTAssertEqual(error as? VocabError, .emptyWorkbook)
        }
    }

    func testNoValidSetsThrows() throws {
        XCTAssertThrowsError(try parser.parse(fileURL: fixture("no_valid"))) { error in
            XCTAssertEqual(error as? VocabError, .noValidSets)
        }
    }

    func testWrongExtensionThrows() {
        let url = URL(fileURLWithPath: "/tmp/not-a-workbook.txt")
        XCTAssertThrowsError(try parser.parse(fileURL: url)) { error in
            XCTAssertEqual(error as? VocabError, .notXLSX(fileName: "not-a-workbook.txt"))
        }
    }

    func testMissingFileThrows() {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).xlsx")
        XCTAssertThrowsError(try parser.parse(fileURL: url)) { error in
            XCTAssertEqual(error as? VocabError, .cannotAccess(fileName: url.lastPathComponent))
        }
    }
}
