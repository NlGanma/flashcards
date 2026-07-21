import Foundation
import Combine

/// Runtime state for one round of studying a deck. A new instance represents a new
/// round; "redo unknown words" builds a fresh session from `remainingCards`.
public final class StudySession: ObservableObject {

    public let filter: KnownFilter
    public let selectedSetNames: [String]
    public let roundNumber: Int

    /// The cards for this round, in the order they'll be shown.
    @Published public private(set) var cards: [Flashcard]
    /// Index of the card currently on screen.
    @Published public private(set) var currentIndex: Int = 0
    /// Whether the back of the current card is showing.
    @Published public var isShowingBack: Bool = false
    /// Current known/unknown state for cards in this deck. Seeded from the global store
    /// so Review Known and Study Everything start from the state the UI displays.
    @Published public private(set) var knownKeys: Set<String>
    /// Distinct cards that have appeared during this round. This keeps an early Finish
    /// from reporting the entire deck as studied, including after back navigation.
    public private(set) var visitedKeys: Set<String>

    public init(cards: [Flashcard], filter: KnownFilter, selectedSetNames: [String],
                roundNumber: Int = 1, initialKnownKeys: Set<String> = []) {
        self.cards = cards
        self.filter = filter
        self.selectedSetNames = selectedSetNames
        self.roundNumber = roundNumber
        let deckKeys = Set(cards.map(\.key))
        self.knownKeys = initialKnownKeys.intersection(deckKeys)
        self.visitedKeys = Set(cards.prefix(1).map(\.key))
    }

    // MARK: - Derived state

    public var currentCard: Flashcard? {
        cards.indices.contains(currentIndex) ? cards[currentIndex] : nil
    }

    public var total: Int { cards.count }

    /// 1-based position, clamped for display.
    public var position: Int { min(currentIndex + 1, max(total, 1)) }

    public var progressFraction: Double {
        guard total > 0 else { return 0 }
        return Double(currentIndex + 1) / Double(total)
    }

    public var knownCount: Int { knownKeys.count }

    /// The original filter describes how round one was assembled. Later rounds replay
    /// a snapshot of cards that still need practice, so keep the header truthful.
    public var modeTitle: String { roundNumber == 1 ? filter.title : "Review Round" }

    public var hasNext: Bool { currentIndex + 1 < total }
    public var hasPrevious: Bool { currentIndex > 0 }
    public var isOnLastCard: Bool { currentIndex == total - 1 }

    public var isCurrentKnown: Bool {
        guard let card = currentCard else { return false }
        return knownKeys.contains(card.key)
    }

    /// Cards that still need attention: anything not yet visited, plus visited cards
    /// currently marked unknown. After a completed round this is simply the unknown set.
    public var remainingCards: [Flashcard] {
        cards.filter { !visitedKeys.contains($0.key) || !knownKeys.contains($0.key) }
    }

    // MARK: - Actions

    public func flip() { isShowingBack.toggle() }

    public func showBack() { isShowingBack = true }

    public func markCurrentKnown() {
        guard let card = currentCard else { return }
        knownKeys.insert(card.key)
    }

    public func unmarkCurrentKnown() {
        guard let card = currentCard else { return }
        unmarkKnown(key: card.key)
    }

    /// Keep an active session synchronized when Known Words is edited from its manager.
    public func unmarkKnown(key: String) {
        knownKeys.remove(key)
    }

    public func unmarkAllKnown() {
        knownKeys.removeAll()
    }

    /// Advance to the next card. Returns false when the round is finished.
    @discardableResult
    public func goNext() -> Bool {
        guard hasNext else { return false }
        currentIndex += 1
        isShowingBack = false
        if let currentCard { visitedKeys.insert(currentCard.key) }
        return true
    }

    public func goPrevious() {
        guard hasPrevious else { return }
        currentIndex -= 1
        isShowingBack = false
        if let currentCard { visitedKeys.insert(currentCard.key) }
    }

    // MARK: - Summary

    public func makeSummary() -> RoundSummary {
        let studied = visitedKeys.count
        let knownStudied = knownKeys.intersection(visitedKeys).count
        return RoundSummary(
            roundNumber: roundNumber,
            totalStudied: studied,
            markedKnown: knownStudied,
            stillUnknown: studied - knownStudied,
            unvisited: max(0, total - studied)
        )
    }
}
