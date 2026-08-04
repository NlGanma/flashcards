import Foundation

/// Applies stored content to a freshly parsed card. Kept as a protocol so `DeckBuilder`
/// stays independent of where content comes from.
public protocol CardContentResolving {
    func resolve(_ card: Flashcard) -> Flashcard
}

/// The app's resolver: the user's own edit wins outright; otherwise the curated bank
/// supplies example sentences and the handful of definition corrections.
public struct CardContentResolver: CardContentResolving {

    private let bank: ContentBank?
    private let edits: CardEditsStore?

    public init(bank: ContentBank?, edits: CardEditsStore?) {
        self.bank = bank
        self.edits = edits
    }

    /// Content as the curated bank alone would present it — what "revert to original"
    /// restores, and the baseline the editor compares against.
    public func curated(_ card: Flashcard) -> Flashcard {
        guard let bank else { return card }
        return card.with(word: bank.displayWord(forKey: card.key),
                         senses: bank.resolvedSenses(forKey: card.key, senses: card.senses))
    }

    public func resolve(_ card: Flashcard) -> Flashcard {
        guard let edit = edits?.edit(for: card.key) else { return curated(card) }
        // A saved edit with no senses left would blank the card; fall back to curated
        // content rather than showing nothing.
        guard !edit.senses.isEmpty else { return curated(card) }
        let word = edit.word.trimmingCharacters(in: .whitespacesAndNewlines)
        return card.with(word: word.isEmpty ? card.word : word, senses: edit.senses)
    }
}
