import Foundation

/// A worked example: an SAT-level English sentence using the word, paired with a Chinese
/// translation that renders one particular meaning in context.
///
/// A spreadsheet definition is usually several comma-separated glosses — "恶棍，歹徒；不法的，
/// 邪恶的" is four — and one sentence cannot demonstrate all of them. So an example is tied
/// to the single `gloss` it teaches, and a sense carries as many examples as it has glosses.
public struct Example: Hashable, Codable, Sendable {
    /// The gloss this sentence demonstrates, e.g. "恶棍". Empty when the sentence stands for
    /// the whole definition (hand-written examples don't have to be split up).
    public let gloss: String
    public let english: String
    public let chinese: String

    public init(gloss: String = "", english: String, chinese: String) {
        self.gloss = gloss
        self.english = english
        self.chinese = chinese
    }

    /// An example with no sentence in it is the same as having none — a bare gloss is not
    /// worth a row.
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
    /// One example per gloss, in the order the glosses appear in `definition`. Filled in
    /// from the bundled bank or by the user's own edit; empty means no sentences yet.
    public let examples: [Example]

    public init(partOfSpeech: String, definition: String, examples: [Example] = []) {
        self.partOfSpeech = partOfSpeech
        self.definition = definition
        self.examples = examples.filter { !$0.isEmpty }
    }

    /// Convenience for a sense with a single unglossed sentence.
    public init(partOfSpeech: String, definition: String, example: Example?) {
        self.init(partOfSpeech: partOfSpeech, definition: definition,
                  examples: example.map { [$0] } ?? [])
    }

    /// The same sense carrying different examples — used when attaching the bank.
    public func with(examples: [Example]) -> Sense {
        Sense(partOfSpeech: partOfSpeech, definition: definition, examples: examples)
    }

    /// The glosses of this definition, split on Chinese and ASCII separators but never
    /// inside a （parenthetical）— "没药（一种中药、香料）" is one gloss, not two.
    public var glosses: [String] {
        Self.splitGlosses(definition)
    }

    public static func splitGlosses(_ definition: String) -> [String] {
        var result: [String] = []
        var current = ""
        var depth = 0
        for character in definition {
            if character == "（" || character == "(" {
                depth += 1
            } else if character == "）" || character == ")" {
                depth = max(0, depth - 1)
            }
            if depth == 0, "，,；;".contains(character) {
                let piece = current.trimmingCharacters(in: .whitespaces)
                if !piece.isEmpty { result.append(piece) }
                current = ""
            } else {
                current.append(character)
            }
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { result.append(last) }
        return result
    }

    // Version 1 of the card-edit file stored a single `example` per sense. Decode it into
    // the array so a card edited before this change keeps its sentence.
    private enum CodingKeys: String, CodingKey {
        case partOfSpeech, definition, examples, example
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        partOfSpeech = try container.decode(String.self, forKey: .partOfSpeech)
        definition = try container.decode(String.self, forKey: .definition)
        if let list = try container.decodeIfPresent([Example].self, forKey: .examples) {
            examples = list.filter { !$0.isEmpty }
        } else if let single = try container.decodeIfPresent(Example.self, forKey: .example) {
            examples = single.isEmpty ? [] : [single]
        } else {
            examples = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(partOfSpeech, forKey: .partOfSpeech)
        try container.encode(definition, forKey: .definition)
        try container.encode(examples, forKey: .examples)
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
        senses.contains { !$0.examples.isEmpty }
    }

    /// The same card with different content — used by the editor and the content resolver.
    public func with(word: String? = nil, senses: [Sense]? = nil) -> Flashcard {
        Flashcard(id: id, word: word ?? self.word, senses: senses ?? self.senses,
                  sourceSets: sourceSets)
    }
}
