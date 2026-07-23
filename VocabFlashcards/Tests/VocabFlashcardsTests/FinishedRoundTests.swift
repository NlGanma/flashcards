import XCTest
import Combine
@testable import VocabFlashcards
import VocabKit

/// Once a round ends the session is kept alive so the summary can report on it, but it
/// must be frozen: the study screen's key monitor outlives the route transition, so a
/// stray keypress used to land on the finished round. That silently undid the mark the
/// user had just made on the last card, and grew `visitedKeys` to include cards that were
/// never shown — which the summary's bulk "Set Aside" then parked for real.
final class FinishedRoundTests: XCTestCase {

    // MARK: - The reported bug: marking the last word didn't stick

    @MainActor
    func testStrayAlmostKeyAfterTheLastCardCannotUndoTheMark() throws {
        let f = try makeFixture(words: ["alpha"])
        defer { f.cleanup() }

        f.app.startStudy(filter: .excludeKnown)
        f.app.markAsideAndAdvance()                     // last card → round finishes
        XCTAssertEqual(f.app.route, .summary)

        f.app.toggleCurrentAside()                      // stray "A" during the transition

        XCTAssertEqual(f.store.asideCount, 1)
        XCTAssertTrue(f.store.isAside(word: "alpha"))
    }

    @MainActor
    func testStrayKnownKeyAfterTheLastCardCannotUndoTheMark() throws {
        let f = try makeFixture(words: ["alpha"])
        defer { f.cleanup() }

        f.app.startStudy(filter: .excludeKnown)
        f.app.markKnownAndAdvance()
        XCTAssertEqual(f.app.route, .summary)

        f.app.toggleCurrentKnown()                      // stray "K"

        XCTAssertEqual(f.store.count, 1)
        XCTAssertTrue(f.store.isKnown(word: "alpha"))
    }

    // MARK: - Stray navigation must not touch a finished round

    @MainActor
    func testNavigationKeysAfterAnEarlyFinishCannotVisitUnseenCards() throws {
        let f = try makeFixture(words: ["alpha", "beta", "gamma"])
        defer { f.cleanup() }

        f.app.startStudy(filter: .excludeKnown)
        f.app.finishRound()                             // Escape on card 1
        XCTAssertEqual(f.app.route, .summary)
        XCTAssertEqual(f.app.stillUnknownCards.count, 1)

        f.app.advance()                                 // stray → arrow
        f.app.primaryAction()                           // stray space
        f.app.goPrevious()                              // stray ← arrow

        XCTAssertEqual(f.app.session?.visitedKeys.count, 1,
                       "a finished round must not record cards the user never saw")
        XCTAssertEqual(f.app.stillUnknownCards.count, 1)
        XCTAssertEqual(f.app.lastSummary?.totalStudied, 1)
    }

    /// The consequence that made the above dangerous: the bulk action parked real words.
    @MainActor
    func testBulkSetAsideAfterStrayKeysOnlyParksWordsTheUserSaw() throws {
        let f = try makeFixture(words: ["alpha", "beta", "gamma", "delta"])
        defer { f.cleanup() }

        f.app.startStudy(filter: .excludeKnown)
        let seen = try XCTUnwrap(f.app.session?.currentCard?.key)
        f.app.finishRound()
        f.app.advance()
        f.app.advance()

        f.app.setAsideStillUnknown()

        XCTAssertEqual(f.store.asideKeys, [seen])
        XCTAssertEqual(f.store.asideCount, 1)
    }

    @MainActor
    func testFinishingAnAlreadyFinishedRoundKeepsTheOriginalSummary() throws {
        let f = try makeFixture(words: ["alpha", "beta", "gamma"])
        defer { f.cleanup() }

        f.app.startStudy(filter: .excludeKnown)
        f.app.finishRound()
        let first = f.app.lastSummary

        f.app.finishRound()                             // stray Escape

        XCTAssertEqual(f.app.lastSummary, first)
    }

    @MainActor
    func testFlipDoesNothingOnAFinishedRound() throws {
        let f = try makeFixture(words: ["alpha", "beta"])
        defer { f.cleanup() }

        f.app.startStudy(filter: .excludeKnown)
        f.app.finishRound()
        f.app.flip()

        XCTAssertFalse(f.app.session?.isShowingBack ?? true)
    }

    /// Actions must also be inert on the setup screen, where the session is nil but the
    /// store is not — Back to Sets then a stray key used to reach the same paths.
    @MainActor
    func testStudyActionsAreInertOnTheSetupScreen() throws {
        let f = try makeFixture(words: ["alpha", "beta"])
        defer { f.cleanup() }

        f.app.startStudy(filter: .excludeKnown)
        f.app.markKnownAndAdvance()
        f.app.backToSetup()

        f.app.toggleCurrentKnown()
        f.app.toggleCurrentAside()
        f.app.advance()

        XCTAssertEqual(f.store.count, 1)
        XCTAssertEqual(f.store.asideCount, 0)
        XCTAssertEqual(f.app.route, .setup)
    }

    // MARK: - The summary can never contradict the store

    @MainActor
    func testSummaryStaysConsistentWithTheStoreAfterAnEarlyFinish() throws {
        let f = try makeFixture(words: ["alpha", "beta", "gamma"])
        defer { f.cleanup() }

        f.app.startStudy(filter: .excludeKnown)
        f.app.finishRound()
        f.app.toggleCurrentKnown()                      // stray "K" on the summary

        let summary = try XCTUnwrap(f.app.lastSummary)
        XCTAssertEqual(summary.markedKnown, f.store.count,
                       "the tiles must agree with what is actually stored")
        XCTAssertEqual(summary.markedKnown, 0)
    }

    // MARK: - Views must see bank changes immediately

    /// Screens read their counts through `app.knownStore` but observe only AppState, so
    /// AppState has to republish when either bank changes. Without that, reverting a single
    /// word left every count on the setup screen stale until an unrelated redraw.
    @MainActor
    func testRemovingOneWordRepublishesAppState() throws {
        let f = try makeFixture(words: ["alpha", "beta"])
        defer { f.cleanup() }

        f.store.markKnown(word: "alpha")
        f.app.route = .setup
        XCTAssertEqual(f.app.deckCount(for: .excludeKnown), 1)

        var published = 0
        let token = f.app.objectWillChange.sink { _ in published += 1 }
        defer { token.cancel() }

        f.app.unmarkKnown(key: "alpha")

        XCTAssertGreaterThan(published, 0, "the setup screen would not have redrawn")
        XCTAssertEqual(f.app.deckCount(for: .excludeKnown), 2)
    }

    @MainActor
    func testParkingOneWordRepublishesAppState() throws {
        let f = try makeFixture(words: ["alpha", "beta"])
        defer { f.cleanup() }

        f.store.markAside(word: "alpha")
        f.app.route = .setup

        var published = 0
        let token = f.app.objectWillChange.sink { _ in published += 1 }
        defer { token.cancel() }

        f.app.unmarkAside(key: "alpha")

        XCTAssertGreaterThan(published, 0)
        XCTAssertEqual(f.app.deckCount(for: .excludeKnown), 2)
    }

    // MARK: - Fixture

    @MainActor
    private func makeFixture(words: [String]) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinishedRound-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = KnownWordsStore(directory: directory)
        let suiteName = "FinishedRound-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let app = AppState(knownStore: store, recentStore: RecentFileStore(defaults: defaults))
        let items = words.map {
            VocabItem(english: $0, partOfSpeech: "n.", definition: "def-\($0)", setName: "Test")
        }
        let practiceSet = PracticeSet(name: "Test", items: items)
        app.loadedFile = LoadedFile(fileName: "test.xlsx",
                                    url: directory.appendingPathComponent("test.xlsx"),
                                    sets: [practiceSet])
        app.selectedSetIDs = [practiceSet.id]
        return Fixture(app: app, store: store, directory: directory,
                       defaults: defaults, suiteName: suiteName)
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
}
