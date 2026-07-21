import XCTest
@testable import VocabFlashcards
import VocabKit

final class AppStateTests: XCTestCase {

    @MainActor
    func testOnlyKnownStudyStartsWithMatchingSessionState() throws {
        let fixture = try makeFixture(words: ["alpha", "beta"], knownWords: ["alpha", "beta"])
        defer { fixture.cleanup() }

        fixture.app.startStudy(filter: .onlyKnown)

        XCTAssertEqual(fixture.app.session?.total, 2)
        XCTAssertEqual(fixture.app.session?.knownCount, 2)
        XCTAssertTrue(fixture.app.session?.isCurrentKnown == true)
    }

    @MainActor
    func testUnmarkCurrentKnownRemovesWordAndContinues() throws {
        let fixture = try makeFixture(words: ["alpha", "beta"], knownWords: ["alpha", "beta"])
        defer { fixture.cleanup() }

        fixture.app.startStudy(filter: .onlyKnown)
        let firstKey = try XCTUnwrap(fixture.app.session?.currentCard?.key)
        fixture.app.unmarkCurrentKnown()

        XCTAssertFalse(fixture.store.isKnown(firstKey))
        XCTAssertNotEqual(fixture.app.session?.currentCard?.key, firstKey)
        XCTAssertEqual(fixture.app.route, .study)
    }

    @MainActor
    func testKnownShortcutUnmarksPersistedKnownWord() throws {
        let fixture = try makeFixture(words: ["alpha", "beta"], knownWords: ["alpha", "beta"])
        defer { fixture.cleanup() }

        fixture.app.startStudy(filter: .onlyKnown)
        let firstKey = try XCTUnwrap(fixture.app.session?.currentCard?.key)
        fixture.app.toggleCurrentKnown()

        XCTAssertFalse(fixture.store.isKnown(firstKey))
    }

    @MainActor
    func testFinishingEarlySummarizesOnlyVisitedCards() throws {
        let fixture = try makeFixture(words: ["alpha", "beta", "gamma"], knownWords: [])
        defer { fixture.cleanup() }

        fixture.app.startStudy(filter: .includeKnown)
        fixture.app.finishRound()

        XCTAssertEqual(fixture.app.lastSummary?.totalStudied, 1)
        XCTAssertEqual(fixture.app.lastSummary?.stillUnknown, 1)
    }

    @MainActor
    func testStudyAgainRestartsPerfectFocusOnNewRound() throws {
        let fixture = try makeFixture(words: ["alpha", "beta"], knownWords: [])
        defer { fixture.cleanup() }

        fixture.app.startStudy(filter: .excludeKnown)
        fixture.app.markKnownAndAdvance()
        fixture.app.markKnownAndAdvance()
        XCTAssertEqual(fixture.app.route, .summary)

        fixture.app.studyAgain()

        XCTAssertEqual(fixture.app.route, .study)
        XCTAssertEqual(fixture.app.session?.total, 2)
        XCTAssertEqual(fixture.app.session?.roundNumber, 2)
    }

    @MainActor
    func testUnmarkMiddleKnownCardAdvancesAndKeepsRoundActive() throws {
        let fixture = try makeFixture(words: ["alpha", "beta", "gamma"],
                                      knownWords: ["alpha", "beta", "gamma"])
        defer { fixture.cleanup() }

        fixture.app.startStudy(filter: .onlyKnown)
        fixture.app.advance()
        let middleKey = try XCTUnwrap(fixture.app.session?.currentCard?.key)
        fixture.app.session?.showBack()
        fixture.app.unmarkCurrentKnown()

        XCTAssertFalse(fixture.store.isKnown(middleKey))
        XCTAssertEqual(fixture.app.session?.knownCount, 2)
        XCTAssertEqual(fixture.app.session?.currentIndex, 2)
        XCTAssertFalse(fixture.app.session?.isShowingBack ?? true)
        XCTAssertEqual(fixture.app.route, .study)
    }

    @MainActor
    func testUnmarkLastKnownCardFinishesWithCorrectSummary() throws {
        let fixture = try makeFixture(words: ["alpha", "beta", "gamma"],
                                      knownWords: ["alpha", "beta", "gamma"])
        defer { fixture.cleanup() }

        fixture.app.startStudy(filter: .onlyKnown)
        fixture.app.advance()
        fixture.app.advance()
        fixture.app.unmarkCurrentKnown()

        XCTAssertEqual(fixture.app.route, .summary)
        XCTAssertEqual(fixture.app.lastSummary?.totalStudied, 3)
        XCTAssertEqual(fixture.app.lastSummary?.markedKnown, 2)
        XCTAssertEqual(fixture.app.lastSummary?.stillUnknown, 1)
    }

    @MainActor
    func testUnmarkOnlyKnownCardFinishesAsUnknown() throws {
        let fixture = try makeFixture(words: ["alpha"], knownWords: ["alpha"])
        defer { fixture.cleanup() }

        fixture.app.startStudy(filter: .onlyKnown)
        fixture.app.unmarkCurrentKnown()

        XCTAssertEqual(fixture.app.route, .summary)
        XCTAssertEqual(fixture.app.lastSummary?.totalStudied, 1)
        XCTAssertEqual(fixture.app.lastSummary?.markedKnown, 0)
        XCTAssertEqual(fixture.app.lastSummary?.stillUnknown, 1)
    }

    @MainActor
    func testKnownWordsManagerRemovalSynchronizesCompletedSession() throws {
        let fixture = try makeFixture(words: ["alpha", "beta"], knownWords: ["alpha", "beta"])
        defer { fixture.cleanup() }

        fixture.app.startStudy(filter: .onlyKnown)
        fixture.app.advance()
        fixture.app.advance()
        let removedKey = try XCTUnwrap(fixture.app.session?.cards.first?.key)
        fixture.app.unmarkKnown(key: removedKey)

        XCTAssertFalse(fixture.store.isKnown(removedKey))
        XCTAssertEqual(fixture.app.session?.knownCount, 1)
        XCTAssertEqual(fixture.app.lastSummary?.markedKnown, 1)
        XCTAssertEqual(fixture.app.lastSummary?.stillUnknown, 1)
        XCTAssertTrue(fixture.app.session?.remainingCards.map(\.key).contains(removedKey) == true)
    }

    @MainActor
    func testClearKnownWordsSynchronizesActiveSession() throws {
        let fixture = try makeFixture(words: ["alpha", "beta"], knownWords: ["alpha", "beta"])
        defer { fixture.cleanup() }

        fixture.app.startStudy(filter: .onlyKnown)
        fixture.app.clearKnownWords()

        XCTAssertEqual(fixture.store.count, 0)
        XCTAssertEqual(fixture.app.session?.knownCount, 0)
        XCTAssertEqual(fixture.app.session?.remainingCards.count, 2)
    }

    @MainActor
    func testFinishAfterBackNavigationCountsEveryVisitedCardOnce() throws {
        let fixture = try makeFixture(words: ["alpha", "beta", "gamma"], knownWords: [])
        defer { fixture.cleanup() }

        fixture.app.startStudy(filter: .includeKnown)
        fixture.app.advance()
        fixture.app.advance()
        fixture.app.goPrevious()
        fixture.app.finishRound()

        XCTAssertEqual(fixture.app.lastSummary?.totalStudied, 3)
        XCTAssertEqual(fixture.app.lastSummary?.unvisited, 0)
    }

    @MainActor
    func testKnownWordsPersistAcrossDocumentsWithoutStoringWorkbookData() throws {
        let fixture = try makeFixture(words: ["shared"], knownWords: [])
        defer { fixture.cleanup() }

        fixture.app.startStudy(filter: .includeKnown)
        fixture.app.markKnownAndAdvance()
        fixture.store.flush()

        let secondItems = [
            VocabItem(english: "shared", partOfSpeech: "adj.", definition: "same word", setName: "Second"),
            VocabItem(english: "new", partOfSpeech: "adj.", definition: "new word", setName: "Second")
        ]
        let secondSet = PracticeSet(name: "Second", items: secondItems)
        fixture.app.loadedFile = LoadedFile(
            fileName: "second.xlsx",
            url: fixture.directory.appendingPathComponent("second.xlsx"),
            sets: [secondSet]
        )
        fixture.app.selectedSetIDs = [secondSet.id]

        XCTAssertEqual(fixture.app.deckCount(for: .excludeKnown), 1)
        XCTAssertEqual(fixture.app.deckCount(for: .onlyKnown), 1)
        let reloaded = KnownWordsStore(directory: fixture.directory)
        XCTAssertTrue(reloaded.isKnown(word: "SHARED"))
    }

    @MainActor
    func testStartingNextRoundClearsPreviousSuccessFlash() throws {
        let fixture = try makeFixture(words: ["alpha"], knownWords: [])
        defer { fixture.cleanup() }

        fixture.app.startStudy(filter: .includeKnown)
        fixture.app.markKnownAndAdvance()
        XCTAssertEqual(fixture.app.route, .summary)
        fixture.app.studyAgain()

        XCTAssertNil(fixture.app.lastMarkedKnownID)
        XCTAssertEqual(fixture.app.route, .study)
    }

    @MainActor
    private func makeFixture(words: [String], knownWords: Set<String>) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VocabFlashcardsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let store = KnownWordsStore(directory: directory)
        knownWords.forEach { store.markKnown(word: $0) }
        store.flush()

        let suiteName = "VocabFlashcardsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let app = AppState(knownStore: store, recentStore: RecentFileStore(defaults: defaults))
        let items = words.map {
            VocabItem(english: $0, partOfSpeech: "n.", definition: "definition-\($0)", setName: "Test")
        }
        let practiceSet = PracticeSet(name: "Test", items: items)
        app.loadedFile = LoadedFile(
            fileName: "test.xlsx",
            url: directory.appendingPathComponent("test.xlsx"),
            sets: [practiceSet]
        )
        app.selectedSetIDs = [practiceSet.id]

        return Fixture(app: app, store: store, directory: directory,
                       defaults: defaults, suiteName: suiteName)
    }
}

private struct Fixture {
    let app: AppState
    let store: KnownWordsStore
    let directory: URL
    let defaults: UserDefaults
    let suiteName: String

    func cleanup() {
        store.flush()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}
