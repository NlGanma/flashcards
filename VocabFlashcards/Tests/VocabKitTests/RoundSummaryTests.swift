import XCTest
@testable import VocabKit

final class RoundSummaryTests: XCTestCase {

    /// The ring sits directly above a "Still Learning 1" tile, so it must not claim a
    /// clean sweep just because 199/200 rounds up.
    func testPercentNeverReadsOneHundredWhileWordsRemain() {
        let almost = RoundSummary(roundNumber: 1, totalStudied: 200, markedKnown: 199,
                                  stillUnknown: 1)
        XCTAssertEqual(almost.knownPercent, 99)
        XCTAssertFalse(almost.isPerfect)
    }

    func testPercentReadsOneHundredOnACleanSweep() {
        let perfect = RoundSummary(roundNumber: 1, totalStudied: 10, markedKnown: 10,
                                   stillUnknown: 0)
        XCTAssertEqual(perfect.knownPercent, 100)
        XCTAssertTrue(perfect.isPerfect)
    }

    /// The mirror case: one word out of 300 shouldn't round away to "0% known".
    func testPercentNeverReadsZeroOnceSomethingWasLearned() {
        let barely = RoundSummary(roundNumber: 1, totalStudied: 300, markedKnown: 1,
                                  stillUnknown: 299)
        XCTAssertEqual(barely.knownPercent, 1)
    }

    func testPercentIsZeroWhenNothingWasLearned() {
        let none = RoundSummary(roundNumber: 1, totalStudied: 5, markedKnown: 0,
                                stillUnknown: 5)
        XCTAssertEqual(none.knownPercent, 0)
    }

    func testUnvisitedCardsKeepTheRingHonestAfterAnEarlyFinish() {
        let early = RoundSummary(roundNumber: 1, totalStudied: 1, markedKnown: 1,
                                 stillUnknown: 0, unvisited: 99)
        XCTAssertEqual(early.knownPercent, 1)
        XCTAssertFalse(early.isPerfect)
    }

    /// Parked words are not learned words: a round of nothing but "Almost" is not perfect.
    func testParkedWordsNeverCountTowardThePercentage() {
        let parked = RoundSummary(roundNumber: 1, totalStudied: 10, markedKnown: 0,
                                  stillUnknown: 0, unvisited: 0, setAside: 10)
        XCTAssertEqual(parked.knownPercent, 0)
        XCTAssertFalse(parked.isPerfect)
        XCTAssertFalse(parked.hasRemaining)
    }
}
