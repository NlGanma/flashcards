import Foundation

/// One meaning of a word: a part of speech paired with its definition.
/// Either field may be empty, but a sense with both empty is never created.
public struct Sense: Hashable, Codable, Sendable {
    public let partOfSpeech: String
    public let definition: String

    public init(partOfSpeech: String, definition: String) {
        self.partOfSpeech = partOfSpeech
        self.definition = definition
    }
}

/// A study card: the front shows one English word, the back shows every collected
/// sense for that word (across all selected sets, exact duplicates removed).
public struct Flashcard: Identifiable, Hashable, Sendable {
    /// Stable identity — the normalized key of the English word.
    public let id: String
    /// Display form of the word shown on the front of the card.
    public let word: String
    /// All distinct senses gathered for this word.
    public let senses: [Sense]
    /// Practice sets this word appeared in (kept subtle in the UI).
    public let sourceSets: [String]

    public init(id: String, word: String, senses: [Sense], sourceSets: [String]) {
        self.id = id
        self.word = word
        self.senses = senses
        self.sourceSets = sourceSets
    }

    public var key: String { id }

    /// Whether the card carries any definition/POS content to show on the back.
    public var hasContent: Bool {
        senses.contains { !$0.definition.isEmpty || !$0.partOfSpeech.isEmpty }
    }
}
