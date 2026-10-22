import Foundation

/// A deck the model made from Markdown notes, saved as a `.vfdeck` file. It keeps the
/// notes and the chat that shaped it as well as the cards, so the deck can be reopened
/// and refined later without the original file.
public struct GeneratedDeck: Codable, Equatable, Sendable {

    public static let fileExtension = "vfdeck"

    /// One line of the chat beside the cards.
    public struct ChatEntry: Codable, Equatable, Sendable {
        public enum Role: String, Codable, Sendable { case user, assistant }
        public var role: Role
        public var text: String
        /// The card a message was about, when it was about one card.
        public var cardFront: String?

        public init(role: Role, text: String, cardFront: String? = nil) {
            self.role = role
            self.text = text
            self.cardFront = cardFront
        }
    }

    public var version: Int
    public var title: String
    public var sourceFileName: String
    public var sourceMarkdown: String
    /// The standing instructions: every chat message addressed to all cards, in order.
    public var instructions: [String]
    public var chat: [ChatEntry]
    public var cards: [GeneratedCard]
    public var createdAt: Date
    public var updatedAt: Date

    public init(title: String, sourceFileName: String, sourceMarkdown: String,
                instructions: [String] = [], chat: [ChatEntry] = [], cards: [GeneratedCard] = [],
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.version = 1
        self.title = title
        self.sourceFileName = sourceFileName
        self.sourceMarkdown = sourceMarkdown
        self.instructions = instructions
        self.chat = chat
        self.cards = cards
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        title = try container.decode(String.self, forKey: .title)
        sourceFileName = try container.decodeIfPresent(String.self, forKey: .sourceFileName) ?? ""
        sourceMarkdown = try container.decodeIfPresent(String.self, forKey: .sourceMarkdown) ?? ""
        instructions = try container.decodeIfPresent([String].self, forKey: .instructions) ?? []
        chat = try container.decodeIfPresent([ChatEntry].self, forKey: .chat) ?? []
        cards = try container.decode([GeneratedCard].self, forKey: .cards)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    // MARK: - As study material

    /// One practice set per section, in the order the sections first appear.
    public var practiceSets: [PracticeSet] {
        var order: [String] = []
        var items: [String: [VocabItem]] = [:]
        for card in cards {
            let front = TextNormalizer.normalizeWhitespace(card.front)
            guard !front.isEmpty, !card.back.isEmpty else { continue }
            let set = card.section.isEmpty ? title : card.section
            if items[set] == nil { order.append(set) }
            let sense = card.sense
            items[set, default: []].append(VocabItem(english: front, partOfSpeech: sense.partOfSpeech,
                                                     definition: sense.definition, setName: set,
                                                     examples: sense.examples))
        }
        return order.map { PracticeSet(name: $0, items: items[$0] ?? []) }
    }

    public func loadedFile(at url: URL) -> LoadedFile {
        LoadedFile(fileName: title, url: url, sets: practiceSets, origin: .generated)
    }

    // MARK: - Files

    public static func read(from url: URL) throws -> GeneratedDeck {
        let name = url.lastPathComponent
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw VocabError.cannotAccess(fileName: name)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let deck = try? decoder.decode(GeneratedDeck.self, from: data) else {
            throw VocabError.unreadable(fileName: name)
        }
        guard !deck.practiceSets.isEmpty else { throw VocabError.noValidSets }
        return deck
    }

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Where a new deck is saved: Application Support, next to the known-word banks, under
    /// a file name made from its title that doesn't collide with an existing deck.
    public static func newFileURL(title: String, in directory: URL = defaultDirectory()) -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        var base = String(title.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " })
        base = TextNormalizer.normalizeWhitespace(base)
        if base.isEmpty { base = "Deck" }
        base = String(base.prefix(60))
        var url = directory.appendingPathComponent("\(base).\(fileExtension)")
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base) \(number).\(fileExtension)")
            number += 1
        }
        return url
    }

    public static func defaultDirectory() -> URL {
        KnownWordsStore.defaultDirectory().appendingPathComponent("Decks", isDirectory: true)
    }
}
