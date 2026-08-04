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
    /// Whether the example panel is open beside the card. Only meaningful while the back
    /// is showing — the sentence belongs to a definition the user is already looking at.
    @Published public var isShowingSentence: Bool = false
    /// Current known/unknown state for cards in this deck. Seeded from the global store
    /// so Review Known and Study Everything start from the state the UI displays.
    @Published public private(set) var knownKeys: Set<String>
    /// Cards parked in the temporary "Almost Known" bank during (or before) this round.
    @Published public private(set) var asideKeys: Set<String>
    /// Distinct cards that have appeared during this round. This keeps an early Finish
    /// from reporting the entire deck as studied, including after back navigation.
    public private(set) var visitedKeys: Set<String>

    public init(cards: [Flashcard], filter: KnownFilter, selectedSetNames: [String],
                roundNumber: Int = 1, initialKnownKeys: Set<String> = [],
                initialAsideKeys: Set<String> = []) {
        self.cards = cards
        self.filter = filter
        self.selectedSetNames = selectedSetNames
        self.roundNumber = roundNumber
        let deckKeys = Set(cards.map(\.key))
        self.knownKeys = initialKnownKeys.intersection(deckKeys)
        self.asideKeys = initialAsideKeys.intersection(deckKeys).subtracting(initialKnownKeys)
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

    public var asideCount: Int { asideKeys.count }

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

    public var isCurrentAside: Bool {
        guard let card = currentCard else { return false }
        return asideKeys.contains(card.key)
    }

    /// Cards that still need attention: anything not yet visited, plus visited cards that
    /// were neither marked known nor parked in the Almost Known bank. Parked words are
    /// deliberately excluded — the point of parking one is that it stops coming back.
    public var remainingCards: [Flashcard] {
        cards.filter { !visitedKeys.contains($0.key) || !isSettled($0.key) }
    }

    /// Cards seen this round that the user neither knew nor parked — the natural batch to
    /// send to the Almost Known bank from the summary screen.
    public var stillUnknownCards: [Flashcard] {
        cards.filter { visitedKeys.contains($0.key) && !isSettled($0.key) }
    }

    private func isSettled(_ key: String) -> Bool {
        knownKeys.contains(key) || asideKeys.contains(key)
    }

    // MARK: - Actions

    public func flip() {
        isShowingBack.toggle()
        // The panel hangs off the definition; going back to the English side closes it.
        if !isShowingBack { isShowingSentence = false }
    }

    public func showBack() { isShowingBack = true }

    /// Swap in edited content for a card, wherever it sits in the deck. Identity is the
    /// key, so the deck order, the current position, and every bank membership are
    /// untouched.
    public func replaceCard(_ card: Flashcard) {
        guard let index = cards.firstIndex(where: { $0.key == card.key }) else { return }
        cards[index] = card
    }

    public func markCurrentKnown() {
        guard let card = currentCard else { return }
        knownKeys.insert(card.key)
        asideKeys.remove(card.key)
    }

    /// Park the current card. Known words stay known — the store applies the same guard,
    /// so the two never disagree about which bank a word is in.
    public func markCurrentAside() {
        guard let card = currentCard else { return }
        markAside(key: card.key)
    }

    public func markAside(key: String) {
        guard !knownKeys.contains(key) else { return }
        asideKeys.insert(key)
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

    public func unmarkAside(key: String) {
        asideKeys.remove(key)
    }

    public func unmarkAllAside() {
        asideKeys.removeAll()
    }

    /// Advance to the next card. Returns false when the round is finished.
    @discardableResult
    public func goNext() -> Bool {
        guard hasNext else { return false }
        currentIndex += 1
        isShowingBack = false
        isShowingSentence = false
        if let currentCard { visitedKeys.insert(currentCard.key) }
        return true
    }

    public func goPrevious() {
        guard hasPrevious else { return }
        currentIndex -= 1
        isShowingBack = false
        isShowingSentence = false
        if let currentCard { visitedKeys.insert(currentCard.key) }
    }

    // MARK: - Summary

    public func makeSummary() -> RoundSummary {
        let studied = visitedKeys.count
        let knownStudied = knownKeys.intersection(visitedKeys).count
        let asideStudied = asideKeys.intersection(visitedKeys).count
        return RoundSummary(
            roundNumber: roundNumber,
            totalStudied: studied,
            markedKnown: knownStudied,
            stillUnknown: studied - knownStudied - asideStudied,
            unvisited: max(0, total - studied),
            setAside: asideStudied
        )
    }
}
