import Foundation

/// A flashcard written by the model from the user's notes. It maps onto the app's own
/// card shape: the front is the word, the back is a single sense, and the example lands
/// in the sentence panel.
public struct GeneratedCard: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var front: String
    public var back: String
    /// A short label shown as a chip above the answer: a part of speech for vocabulary,
    /// a category for anything else. May be empty.
    public var tag: String
    /// A sentence that uses the front. May be empty.
    public var example: String
    /// The example's translation, or a line on why it fits. May be empty.
    public var exampleNote: String
    /// The Markdown section the card came from, which becomes its practice set.
    public var section: String

    public init(id: UUID = UUID(), front: String, back: String, tag: String = "",
                example: String = "", exampleNote: String = "", section: String = "") {
        self.id = id
        self.front = front
        self.back = back
        self.tag = tag
        self.example = example
        self.exampleNote = exampleNote
        self.section = section
    }

    /// Saved decks outlive this version of the app, so every field but the two faces is
    /// optional on the way in.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        front = try container.decode(String.self, forKey: .front)
        back = try container.decode(String.self, forKey: .back)
        tag = try container.decodeIfPresent(String.self, forKey: .tag) ?? ""
        example = try container.decodeIfPresent(String.self, forKey: .example) ?? ""
        exampleNote = try container.decodeIfPresent(String.self, forKey: .exampleNote) ?? ""
        section = try container.decodeIfPresent(String.self, forKey: .section) ?? ""
    }

    /// The card as the study screen shows it.
    public var sense: Sense {
        let examples = example.isEmpty && exampleNote.isEmpty
            ? [] : [Example(english: example, chinese: exampleNote)]
        return Sense(partOfSpeech: tag, definition: back, examples: examples)
    }
}

/// One card as the model wrote it, before it is given an identity. Models don't stick
/// to the field names they were asked for, so the common synonyms are accepted too.
public struct ModelCard: Hashable, Sendable {
    /// The short id a revision request gave the card ("c3"), echoed back so the reply
    /// can be matched to the card it replaces.
    public var ref: String?
    public var front: String
    public var back: String
    public var tag: String
    public var example: String
    public var exampleNote: String
    public var section: String?

    public init(ref: String? = nil, front: String, back: String, tag: String = "",
                example: String = "", exampleNote: String = "", section: String? = nil) {
        self.ref = ref
        self.front = front
        self.back = back
        self.tag = tag
        self.example = example
        self.exampleNote = exampleNote
        self.section = section
    }

    private static let aliases: [String: [String]] = [
        "ref": ["id", "ref"],
        "front": ["front", "term", "word", "question", "prompt"],
        "back": ["back", "definition", "answer", "explanation", "meaning"],
        "tag": ["tag", "partOfSpeech", "part_of_speech", "pos", "category", "type"],
        "example": ["example", "sentence", "exampleSentence", "example_sentence"],
        "exampleNote": ["exampleNote", "example_note", "exampleTranslation",
                        "example_translation", "translation"],
        "section": ["section", "set", "topic"]
    ]

    /// Decode one JSON object, or nil when it has no usable front and back.
    public init?(json data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func field(_ name: String) -> String {
            for key in Self.aliases[name] ?? [] {
                if let text = object[key] as? String { return Self.clean(text) }
                if let number = object[key] as? NSNumber { return number.stringValue }
            }
            return ""
        }
        let front = field("front")
        let back = field("back")
        guard !front.isEmpty, !back.isEmpty else { return nil }
        let ref = field("ref")
        let section = field("section")
        self.init(ref: ref.isEmpty ? nil : ref, front: front, back: back, tag: field("tag"),
                  example: field("example"), exampleNote: field("exampleNote"),
                  section: section.isEmpty ? nil : section)
    }

    /// Card text is shown verbatim, so the Markdown emphasis models like to add would
    /// show up as literal asterisks.
    static func clean(_ text: String) -> String {
        var result = text
        for marker in ["**", "__", "`"] {
            result = result.replacingOccurrences(of: marker, with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
