import XCTest
@testable import VocabKit

final class StudySessionTests: XCTestCase {

    func testReplayRoundUsesNeutralModeTitle() {
        let replayCards = [card("a"), card("b")]
        let first = StudySession(cards: replayCards, filter: .excludeKnown,
                                 selectedSetNames: ["Set"], roundNumber: 1)
        let replay = StudySession(cards: replayCards, filter: .excludeKnown,
                                  selectedSetNames: ["Set"], roundNumber: 2)

        XCTAssertEqual(first.modeTitle, KnownFilter.excludeKnown.title)
        XCTAssertEqual(replay.modeTitle, "Review Round")
    }

    private func card(_ word: String) -> Flashcard {
        Flashcard(id: word, word: word,
                  senses: [Sense(partOfSpeech: "n.", definition: "def-\(word)")],
                  sourceSets: ["A"])
    }

    private func makeSession() -> StudySession {
        StudySession(cards: [card("a"), card("b"), card("c")],
                     filter: .excludeKnown, selectedSetNames: ["A"])
    }

    func testNavigationBounds() {
        let s = makeSession()
        XCTAssertEqual(s.currentCard?.key, "a")
        XCTAssertTrue(s.hasNext)
        XCTAssertFalse(s.hasPrevious)

        XCTAssertTrue(s.goNext())
        XCTAssertEqual(s.currentCard?.key, "b")
        XCTAssertTrue(s.goNext())
        XCTAssertEqual(s.currentCard?.key, "c")
        XCTAssertTrue(s.isOnLastCard)
        XCTAssertFalse(s.goNext())            // past the end -> round finished
        XCTAssertEqual(s.currentCard?.key, "c")

        s.goPrevious()
        XCTAssertEqual(s.currentCard?.key, "b")
    }

    func testFlipResetsOnAdvance() {
        let s = makeSession()
        s.flip()
        XCTAssertTrue(s.isShowingBack)
        _ = s.goNext()
        XCTAssertFalse(s.isShowingBack)       // new card starts on its front
    }

    func testMarkKnownAndRemaining() {
        let s = makeSession()
        s.markCurrentKnown()                  // a
        _ = s.goNext()
        _ = s.goNext()
        s.markCurrentKnown()                  // c
        XCTAssertEqual(s.knownCount, 2)
        XCTAssertEqual(s.remainingCards.map(\.key), ["b"])
    }

    func testUnmarkKnown() {
        let s = makeSession()
        s.markCurrentKnown()
        XCTAssertTrue(s.isCurrentKnown)
        s.unmarkCurrentKnown()
        XCTAssertFalse(s.isCurrentKnown)
    }

    func testSummaryCounts() {
        let s = makeSession()
        s.markCurrentKnown()                  // a
        _ = s.goNext(); _ = s.goNext()
        let summary = s.makeSummary()
        XCTAssertEqual(summary.totalStudied, 3)
        XCTAssertEqual(summary.markedKnown, 1)
        XCTAssertEqual(summary.stillUnknown, 2)
        XCTAssertTrue(summary.hasRemaining)
        XCTAssertFalse(summary.isPerfect)
    }

    func testPerfectRound() {
        let s = makeSession()
        s.markCurrentKnown(); _ = s.goNext()
        s.markCurrentKnown(); _ = s.goNext()
        s.markCurrentKnown()
        let summary = s.makeSummary()
        XCTAssertTrue(summary.isPerfect)
        XCTAssertFalse(summary.hasRemaining)
        XCTAssertTrue(s.remainingCards.isEmpty)
    }

    func testInitialKnownKeysAreScopedToDeck() {
        let s = StudySession(cards: [card("a"), card("b")], filter: .onlyKnown,
                             selectedSetNames: ["A"],
                             initialKnownKeys: ["a", "b", "outside"])
        XCTAssertEqual(s.knownKeys, ["a", "b"])
        XCTAssertEqual(s.knownCount, 2)
        XCTAssertTrue(s.isCurrentKnown)
    }

    func testUnmarkByKeyAndClearSynchronizeAnyCard() {
        let s = StudySession(cards: [card("a"), card("b"), card("c")], filter: .onlyKnown,
                             selectedSetNames: ["A"], initialKnownKeys: ["a", "b", "c"])
        s.unmarkKnown(key: "c")
        XCTAssertEqual(s.knownKeys, ["a", "b"])
        s.unmarkAllKnown()
        XCTAssertEqual(s.knownCount, 0)
    }

    func testEarlySummaryCountsVisitedAndUnvisitedSeparately() {
        let s = makeSession()
        s.markCurrentKnown()
        let summary = s.makeSummary()
        XCTAssertEqual(summary.totalStudied, 1)
        XCTAssertEqual(summary.markedKnown, 1)
        XCTAssertEqual(summary.stillUnknown, 0)
        XCTAssertEqual(summary.unvisited, 2)
        XCTAssertEqual(summary.knownFraction, 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertFalse(summary.isPerfect)
        XCTAssertEqual(s.remainingCards.count, 2)
    }

    func testBackNavigationDoesNotForgetPreviouslyVisitedCards() {
        let s = makeSession()
        _ = s.goNext()
        _ = s.goNext()
        s.goPrevious()
        let summary = s.makeSummary()
        XCTAssertEqual(summary.totalStudied, 3)
        XCTAssertEqual(summary.unvisited, 0)
    }

    // MARK: - Almost Known bank

    func testParkedCardsDropOutOfRemaining() {
        let s = makeSession()
        s.markCurrentAside()                  // a
        _ = s.goNext()
        _ = s.goNext()
        s.markCurrentKnown()                  // c
        XCTAssertEqual(s.asideCount, 1)
        XCTAssertEqual(s.knownCount, 1)
        XCTAssertEqual(s.remainingCards.map(\.key), ["b"])
        XCTAssertEqual(s.stillUnknownCards.map(\.key), ["b"])
    }

    func testSummarySplitsKnownAlmostAndStillUnknown() {
        let s = makeSession()
        s.markCurrentKnown()                  // a
        _ = s.goNext()
        s.markCurrentAside()                  // b
        _ = s.goNext()                        // c left alone
        let summary = s.makeSummary()
        XCTAssertEqual(summary.totalStudied, 3)
        XCTAssertEqual(summary.markedKnown, 1)
        XCTAssertEqual(summary.setAside, 1)
        XCTAssertEqual(summary.stillUnknown, 1)
        XCTAssertFalse(summary.isPerfect)
    }

    /// Parking every card is not a clean sweep — none of them were learned.
    func testParkingEveryCardIsNotAPerfectRound() {
        let s = makeSession()
        s.markCurrentAside(); _ = s.goNext()
        s.markCurrentAside(); _ = s.goNext()
        s.markCurrentAside()
        let summary = s.makeSummary()
        XCTAssertFalse(summary.isPerfect)
        XCTAssertFalse(summary.hasRemaining)
        XCTAssertEqual(summary.setAside, 3)
        XCTAssertTrue(s.remainingCards.isEmpty)
    }

    func testKnownWordsAreNeverDemotedIntoTheBank() {
        let s = makeSession()
        s.markCurrentKnown()
        s.markCurrentAside()
        XCTAssertTrue(s.isCurrentKnown)
        XCTAssertFalse(s.isCurrentAside)
    }

    func testMarkingKnownPullsACardOutOfTheBank() {
        let s = makeSession()
        s.markCurrentAside()
        XCTAssertTrue(s.isCurrentAside)
        s.markCurrentKnown()
        XCTAssertTrue(s.isCurrentKnown)
        XCTAssertFalse(s.isCurrentAside)
        XCTAssertEqual(s.asideCount, 0)
    }

    func testInitialAsideKeysAreScopedToDeckAndNeverOverlapKnown() {
        let s = StudySession(cards: [card("a"), card("b")], filter: .includeKnown,
                             selectedSetNames: ["A"],
                             initialKnownKeys: ["a"],
                             initialAsideKeys: ["a", "b", "outside"])
        XCTAssertEqual(s.knownKeys, ["a"])
        XCTAssertEqual(s.asideKeys, ["b"])
    }

    func testUnmarkAsideSynchronizesAnyCard() {
        let s = StudySession(cards: [card("a"), card("b")], filter: .includeKnown,
                             selectedSetNames: ["A"], initialAsideKeys: ["a", "b"])
        s.unmarkAside(key: "b")
        XCTAssertEqual(s.asideKeys, ["a"])
        s.unmarkAllAside()
        XCTAssertEqual(s.asideCount, 0)
    }

    func testUnvisitedKnownCardsRemainAvailableAfterEarlyFinish() {
        let s = StudySession(cards: [card("a"), card("b"), card("c")], filter: .onlyKnown,
                             selectedSetNames: ["A"], initialKnownKeys: ["a", "b", "c"])
        let summary = s.makeSummary()
        XCTAssertEqual(summary.markedKnown, 1)
        XCTAssertEqual(summary.unvisited, 2)
        XCTAssertTrue(summary.hasRemaining)
        XCTAssertFalse(summary.isPerfect)
        XCTAssertEqual(s.remainingCards.map(\.key), ["b", "c"])
    }
}
