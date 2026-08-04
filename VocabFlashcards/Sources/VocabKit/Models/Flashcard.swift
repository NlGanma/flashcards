import Foundation

/// A worked example for one sense: an SAT-level English sentence using the word, paired
/// with a Chinese translation that renders the sense's definition in context.
public struct Example: Hashable, Codable, Sendable {
    public let english: String
    public let chinese: String

    public init(english: String, chinese: String) {
        self.english = english
        self.chinese = chinese
    }

    /// An example with nothing in it is the same as having none.
    public var isEmpty: Bool {
        english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && chinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// One meaning of a word: a part of speech paired with its definition, plus an optional
/// worked example. Either text field may be empty, but a sense with both empty is never
/// created.
public struct Sense: Hashable, Codable, Sendable {
    public let partOfSpeech: String
    public let definition: String
    /// Filled in from the bundled example bank, or by the user's own edit. Nil means this
    /// sense has no sentence yet.
    public let example: Example?

    public init(partOfSpeech: String, definition: String, example: Example? = nil) {
        self.partOfSpeech = partOfSpeech
        self.definition = definition
        self.example = (example?.isEmpty ?? true) ? nil : example
    }

    /// The same sense carrying a different example — used when attaching the bank.
    public func with(example: Example?) -> Sense {
        Sense(partOfSpeech: partOfSpeech, definition: definition, example: example)
    }

    /// Identity for de-duplication: two senses are the same meaning when their part of
    /// speech and definition agree, regardless of which example is attached.
    public var meaningSignature: String {
        "\(partOfSpeech.lowercased())\u{0}\(definition.lowercased())"
    }
}

/// A study card: the front shows one English word, the back shows every collected
/// sense for that word (across all selected sets, exact duplicates removed).
public struct Flashcard: Identifiable, Hashable, Sendable {
    /// Stable identity — the normalized key of the English word. This never changes, even
    /// when the displayed word is edited, because it is what the known-word banks and the
    /// example bank are keyed on.
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

    /// Whether any sense has a sentence to reveal in the example panel.
    public var hasExamples: Bool {
        senses.contains { $0.example != nil }
    }

    /// The same card with different content — used by the editor and the content resolver.
    public func with(word: String? = nil, senses: [Sense]? = nil) -> Flashcard {
        Flashcard(id: id, word: word ?? self.word, senses: senses ?? self.senses,
                  sourceSets: sourceSets)
    }
}
