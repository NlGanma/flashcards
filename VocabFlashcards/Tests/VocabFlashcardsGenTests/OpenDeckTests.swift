import Foundation
import Testing
@testable import VocabFlashcards
import VocabKit

/// An AppState whose stores all live in a throwaway directory.
@MainActor
struct AppFixture {
    let app: AppState
    let directory: URL

    init(bank: ContentBank = ContentBank(words: [:]), server: FakeServer = FakeServer(models: nil)) {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VocabFlashcardsGenTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "VocabFlashcardsGenTests-\(UUID().uuidString)")!
        let services = StudioServices(makeServer: { _ in server }, discover: { [] }, defaults: defaults,
                                      decksDirectory: directory.appendingPathComponent("Decks"))
        app = AppState(knownStore: KnownWordsStore(directory: directory),
                       recentStore: RecentFileStore(defaults: defaults),
                       editsStore: CardEditsStore(directory: directory),
                       contentBank: bank, studioServices: services)
    }

    func writeDeck(_ deck: GeneratedDeck, name: String = "bio.vfdeck") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try deck.write(to: url)
        return url
    }
}

@Suite("Opening saved decks")
@MainActor
struct OpenDeckTests {

    let deck = GeneratedDeck(
        title: "Cell Biology", sourceFileName: "bio.md", sourceMarkdown: "## Transport\nOsmosis…",
        cards: [GeneratedCard(front: "osmosis", back: "Water diffusing across a membrane.",
                              example: "Osmosis swells the cell.", section: "Transport"),
                GeneratedCard(front: "abate", back: "To become less intense.", tag: "v.", section: "Words")])

    @Test func aDeckOpensOnTheSetPicker() throws {
        let fixture = AppFixture()
        let url = try fixture.writeDeck(deck)
        fixture.app.loadFile(at: url, remember: false)

        #expect(fixture.app.route == .setup)
        #expect(fixture.app.errorMessage == nil)
        #expect(fixture.app.loadedFile?.origin == .generated)
        #expect(fixture.app.loadedFile?.sets.map(\.name) == ["Transport", "Words"])
        #expect(fixture.app.loadedDeck?.cards == deck.cards)
        #expect(fixture.app.loadedDeckURL == url)
        #expect(fixture.app.selectedSetIDs.count == 2)
    }

    /// The bundled bank knows "abate"; its one-record fallback must not replace the answer
    /// the learner asked the model for.
    @Test func aGeneratedDeckKeepsItsOwnAnswersOverTheCuratedBank() throws {
        let bank = ContentBank(words: ["abate": .init(records: [
            ContentBank.signature("减弱"): .init(definition: "减弱；减轻", partOfSpeech: "v.",
                                               examples: [Example(english: "The storm abated.", chinese: "风暴减弱了。")])
        ])])
        let fixture = AppFixture(bank: bank)
        fixture.app.loadFile(at: try fixture.writeDeck(deck), remember: false)
        fixture.app.startStudy(filter: .includeKnown)

        let cards = try #require(fixture.app.session?.cards)
        let abate = try #require(cards.first { $0.key == "abate" })
        #expect(abate.senses.map(\.definition) == ["To become less intense."])
        let osmosis = try #require(cards.first { $0.key == "osmosis" })
        #expect(osmosis.senses.first?.examples == [Example(english: "Osmosis swells the cell.", chinese: "")])
    }

    @Test func aBrokenDeckLeavesTheCurrentFileOnScreen() throws {
        let fixture = AppFixture()
        fixture.app.loadFile(at: try fixture.writeDeck(deck), remember: false)
        let garbage = fixture.directory.appendingPathComponent("broken.vfdeck")
        try Data("{".utf8).write(to: garbage)
        fixture.app.loadFile(at: garbage, remember: false)

        #expect(fixture.app.errorMessage?.contains("“broken.vfdeck” couldn't be read.") == true)
        #expect(fixture.app.route == .setup)
        #expect(fixture.app.loadedFile?.fileName == "Cell Biology")
    }

    @Test func anUnsupportedFileSaysWhatCanBeOpened() {
        let fixture = AppFixture()
        fixture.app.loadFile(at: fixture.directory.appendingPathComponent("slides.pdf"), remember: false)
        #expect(fixture.app.errorMessage == "“slides.pdf” isn't a file Vocab Flashcards can open. "
                + "Choose an Excel workbook (.xlsx), notes to turn into cards (.md or .txt), or a saved deck (.vfdeck).")
        #expect(fixture.app.route == .empty)
    }

    @Test func goingBackToEmptyForgetsTheDeck() throws {
        let fixture = AppFixture()
        fixture.app.loadFile(at: try fixture.writeDeck(deck), remember: false)
        fixture.app.resetToEmpty()
        #expect(fixture.app.loadedDeck == nil && fixture.app.loadedDeckURL == nil)
    }
}
