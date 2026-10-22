import Foundation
import Testing
@testable import VocabKit

@Suite("Generated decks")
struct GeneratedDeckTests {

    let deck = GeneratedDeck(
        title: "Cell Biology", sourceFileName: "bio.md", sourceMarkdown: "# Cell Biology\n…",
        instructions: ["Add an example sentence"],
        chat: [.init(role: .user, text: "Add an example sentence"),
               .init(role: .assistant, text: "Made 3 cards."),
               .init(role: .user, text: "Shorter please", cardFront: "ATP")],
        cards: [
            GeneratedCard(front: "osmosis", back: "Water diffusing across a membrane.", tag: "process",
                          example: "Osmosis swells the cell.", section: "Transport"),
            GeneratedCard(front: "ATP", back: "The cell's energy currency.", tag: "molecule", section: "Energy"),
            GeneratedCard(front: "diffusion", back: "Movement down a gradient.", section: "Transport"),
            GeneratedCard(front: "  ", back: "orphan", section: "Energy"),
            GeneratedCard(front: "cell", back: "The unit of life.")
        ])

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vf-deck-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func sectionsBecomeSetsInFirstAppearanceOrder() {
        let sets = deck.practiceSets
        #expect(sets.map(\.name) == ["Transport", "Energy", "Cell Biology"])
        #expect(sets[0].items.map(\.english) == ["osmosis", "diffusion"])
        // A card with no front is skipped; one with no section falls under the title.
        #expect(sets[1].items.map(\.english) == ["ATP"])
        #expect(sets[2].items.map(\.english) == ["cell"])
    }

    @Test func aGeneratedDeckStudiesWithItsOwnExamplesAndNoCuratedBank() {
        let file = deck.loadedFile(at: URL(fileURLWithPath: "/tmp/x.vfdeck"))
        #expect(file.origin == .generated)
        #expect(file.fileName == "Cell Biology")

        let cards = DeckBuilder().buildOrdered(from: file.sets, filter: .includeKnown, knownKeys: [],
                                               resolver: CardContentResolver(bank: nil, edits: nil))
        let osmosis = try! #require(cards.first { $0.word == "osmosis" })
        #expect(osmosis.senses == [Sense(partOfSpeech: "process", definition: "Water diffusing across a membrane.",
                                         examples: [Example(english: "Osmosis swells the cell.", chinese: "")])])
        #expect(osmosis.sourceSets == ["Transport"])
    }

    @Test func aSpreadsheetIsStillASpreadsheet() {
        #expect(LoadedFile(fileName: "a.xlsx", url: URL(fileURLWithPath: "/a.xlsx"), sets: []).origin == .spreadsheet)
        #expect(VocabItem(english: "a", partOfSpeech: "", definition: "b", setName: "s").examples.isEmpty)
    }

    @Test func roundTripsThroughAFile() throws {
        let url = temporaryDirectory().appendingPathComponent("bio.vfdeck")
        try deck.write(to: url)
        let read = try GeneratedDeck.read(from: url)
        #expect(read.cards == deck.cards)
        #expect(read.chat == deck.chat)
        #expect(read.instructions == deck.instructions)
        #expect(abs(read.createdAt.timeIntervalSince(deck.createdAt)) < 1)
    }

    @Test func badFilesFailWithFriendlyErrors() throws {
        let dir = temporaryDirectory()
        #expect(throws: VocabError.cannotAccess(fileName: "missing.vfdeck")) {
            try GeneratedDeck.read(from: dir.appendingPathComponent("missing.vfdeck"))
        }
        let garbage = dir.appendingPathComponent("garbage.vfdeck")
        try Data("not json".utf8).write(to: garbage)
        #expect(throws: VocabError.unreadable(fileName: "garbage.vfdeck")) { try GeneratedDeck.read(from: garbage) }

        let empty = dir.appendingPathComponent("empty.vfdeck")
        try GeneratedDeck(title: "t", sourceFileName: "", sourceMarkdown: "").write(to: empty)
        #expect(throws: VocabError.noValidSets) { try GeneratedDeck.read(from: empty) }
    }

    @Test func newFilesGetUniqueReadableNames() throws {
        let dir = temporaryDirectory()
        let first = GeneratedDeck.newFileURL(title: "Bio: Cells/Energy?", in: dir)
        #expect(first.lastPathComponent == "Bio Cells Energy.vfdeck")
        try Data().write(to: first)
        #expect(GeneratedDeck.newFileURL(title: "Bio: Cells/Energy?", in: dir).lastPathComponent
                == "Bio Cells Energy 2.vfdeck")
        #expect(GeneratedDeck.newFileURL(title: "???", in: dir).lastPathComponent == "Deck.vfdeck")
        #expect(GeneratedDeck.newFileURL(title: "细胞生物学", in: dir).lastPathComponent == "细胞生物学.vfdeck")
    }
}
