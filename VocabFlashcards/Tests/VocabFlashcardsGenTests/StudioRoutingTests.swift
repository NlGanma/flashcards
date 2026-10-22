import Foundation
import Testing
@testable import VocabFlashcards
import VocabKit

@Suite("Studio routing")
@MainActor
struct StudioRoutingTests {

    let notes = "# Cell Biology\n## Organelles\nThe mitochondrion produces ATP.\n## Transport\nOsmosis moves water."

    private func writeNotes(_ fixture: AppFixture, _ text: String, name: String = "bio.md") throws -> URL {
        let url = fixture.directory.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test(arguments: ["bio.md", "bio.markdown", "bio.txt"])
    func notesOpenTheStudio(name: String) throws {
        let fixture = AppFixture()
        fixture.app.loadFile(at: try writeNotes(fixture, notes, name: name), remember: false)

        #expect(fixture.app.route == .generate)
        #expect(fixture.app.studio?.title == "Cell Biology")
        #expect(fixture.app.studio?.sourceFileName == name)
        #expect(fixture.app.errorMessage == nil)
    }

    @Test func emptyNotesSayWhy() throws {
        let fixture = AppFixture()
        fixture.app.loadFile(at: try writeNotes(fixture, "  \n\n"), remember: false)
        #expect(fixture.app.route == .empty)
        #expect(fixture.app.studio == nil)
        #expect(fixture.app.errorMessage == "“bio.md” is empty. Write some notes in it first, then open it again.")
    }

    @Test func studyingSavesTheDeckAndOpensItOnTheSetPicker() async throws {
        let server = FakeServer(replies: [#"[{"front":"mitochondrion","back":"Makes ATP."}]"#,
                                          #"[{"front":"osmosis","back":"Water crossing a membrane."}]"#])
        let fixture = AppFixture(server: server)
        fixture.app.loadFile(at: try writeNotes(fixture, notes), remember: false)
        let studio = try #require(fixture.app.studio)
        studio.send()
        await studio.waitForWork()
        fixture.app.studyStudioCards()

        #expect(fixture.app.route == .setup)
        #expect(fixture.app.studio == nil)
        #expect(fixture.app.loadedFile?.origin == .generated)
        #expect(fixture.app.loadedFile?.sets.map(\.name) == ["Organelles", "Transport"])
        let url = try #require(fixture.app.loadedDeckURL)
        #expect(url.deletingLastPathComponent().lastPathComponent == "Decks")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func refiningALoadedDeckReopensItsCardsAndSavesInPlace() async throws {
        let server = FakeServer(replies: [#"[{"front":"mitochondrion","back":"Makes ATP."}]"#,
                                          #"[{"front":"osmosis","back":"Water crossing a membrane."}]"#])
        let fixture = AppFixture(server: server)
        fixture.app.loadFile(at: try writeNotes(fixture, notes), remember: false)
        fixture.app.studio?.send()
        await fixture.app.studio?.waitForWork()
        fixture.app.studyStudioCards()
        let url = try #require(fixture.app.loadedDeckURL)

        fixture.app.refineLoadedDeck()
        #expect(fixture.app.route == .generate)
        let studio = try #require(fixture.app.studio)
        #expect(studio.cards.map(\.front) == ["mitochondrion", "osmosis"])
        studio.delete(studio.cards[1])
        fixture.app.studyStudioCards()

        #expect(fixture.app.loadedDeckURL == url)
        #expect(fixture.app.loadedFile?.sets.map(\.name) == ["Organelles"])
    }

    @Test func closingGoesBackWhereTheLearnerCameFrom() throws {
        let fixture = AppFixture()
        fixture.app.loadFile(at: try writeNotes(fixture, notes), remember: false)
        fixture.app.closeStudio()
        #expect(fixture.app.route == .empty)
        #expect(fixture.app.studio == nil)

        let deckURL = fixture.directory.appendingPathComponent("d.vfdeck")
        try GeneratedDeck(title: "D", sourceFileName: "d.md", sourceMarkdown: "x",
                          cards: [GeneratedCard(front: "a", back: "b")]).write(to: deckURL)
        fixture.app.loadFile(at: deckURL, remember: false)
        fixture.app.loadFile(at: try writeNotes(fixture, notes), remember: false)
        fixture.app.closeStudio()
        #expect(fixture.app.route == .setup)
        #expect(fixture.app.loadedFile?.fileName == "D")
    }

    @Test func studyingNeedsCards() throws {
        let fixture = AppFixture()
        fixture.app.loadFile(at: try writeNotes(fixture, notes), remember: false)
        fixture.app.studyStudioCards()
        #expect(fixture.app.route == .generate)
    }
}
