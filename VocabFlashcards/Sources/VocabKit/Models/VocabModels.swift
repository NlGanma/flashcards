import Foundation

/// A single vocabulary entry exactly as parsed from one row of a practice-set block.
/// This is the raw unit; duplicate English words are merged later when a deck is built.
public struct VocabItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    /// Cleaned English word or phrase (display form, original casing preserved).
    public let english: String
    /// Cleaned part of speech, e.g. "adj." — may be empty.
    public let partOfSpeech: String
    /// Cleaned Chinese definition — may be empty.
    public let definition: String
    /// Name of the practice set this item came from.
    public let setName: String

    /// Case- and whitespace-insensitive identity based on the English word only.
    public var key: String { TextNormalizer.normalizedKey(english) }

    public init(id: UUID = UUID(), english: String, partOfSpeech: String, definition: String, setName: String) {
        self.id = id
        self.english = english
        self.partOfSpeech = partOfSpeech
        self.definition = definition
        self.setName = setName
    }
}

/// A detected 3-column vocabulary block, named after its title ("Practice 1") or
/// auto-named ("Practice Set 1") when no title is present.
public struct PracticeSet: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let items: [VocabItem]

    public init(id: UUID = UUID(), name: String, items: [VocabItem]) {
        self.id = id
        self.name = name
        self.items = items
    }

    /// Total valid entries in the block.
    public var wordCount: Int { items.count }

    /// Distinct words after case-insensitive de-duplication.
    public var uniqueWordCount: Int { Set(items.map(\.key)).count }
}

/// A successfully parsed spreadsheet: the file itself plus its detected practice sets.
public struct LoadedFile: Identifiable, Sendable {
    public let id: UUID
    public let fileName: String
    public let url: URL
    public let sets: [PracticeSet]

    public init(id: UUID = UUID(), fileName: String, url: URL, sets: [PracticeSet]) {
        self.id = id
        self.fileName = fileName
        self.url = url
        self.sets = sets
    }

    public var totalItems: Int { sets.reduce(0) { $0 + $1.wordCount } }

    public var totalUniqueWords: Int {
        Set(sets.flatMap { $0.items.map(\.key) }).count
    }
}
