import Foundation

/// Curated, read-only content that ships with the app: an SAT-level example sentence for
/// each definition, plus a small number of definition corrections.
///
/// The spreadsheet is the source of truth for *which* words are studied; this bank only
/// enriches what a card shows. Records are matched to a parsed sense by the word's key
/// and the exact definition text, so a word with several meanings gets the right sentence
/// against each one.
///
/// Corrections exist because a few glosses in the source file don't correspond to any
/// sense the word actually has in English. Two safeguards keep that conservative: a
/// correction only applies to the definition text it was written against, and dropping a
/// definition can never empty a card — if every sense of a word were dropped, the
/// original senses are kept instead.
public final class ContentBank {

    /// One curated record, keyed to the original definition it was written for.
    public struct Record: Hashable, Sendable {
        /// Replacement definition, when the original was wrong or partly unsupported.
        public let definition: String?
        /// Replacement part of speech, when the original was wrong.
        public let partOfSpeech: String?
        /// One sentence per gloss of the definition.
        public let examples: [Example]

        public init(definition: String? = nil, partOfSpeech: String? = nil,
                    examples: [Example] = []) {
            self.definition = definition
            self.partOfSpeech = partOfSpeech
            self.examples = examples
        }
    }

    /// Everything curated for one word.
    public struct WordContent: Hashable, Sendable {
        /// Records by normalized original-definition signature.
        public let records: [String: Record]
        /// Signatures of definitions that no dictionary sense supports.
        public let dropped: Set<String>
        /// Replacement display text, for the few entries whose spreadsheet cell is
        /// mangled — "vicarious (vicarious)". The card's identity is unaffected.
        public let word: String?

        public init(records: [String: Record], dropped: Set<String> = [], word: String? = nil) {
            self.records = records
            self.dropped = dropped
            self.word = word
        }
    }

    private let words: [String: WordContent]

    public init(words: [String: WordContent]) {
        self.words = words
    }

    public var wordCount: Int { words.count }

    public var exampleCount: Int {
        words.values.reduce(0) { $0 + $1.records.values.reduce(0) { $0 + $1.examples.count } }
    }

    // MARK: - Resolution

    /// The corrected display text for a word, when the source cell is mangled.
    public func displayWord(forKey key: String) -> String? {
        words[key]?.word
    }

    /// Apply corrections, drops, and examples to a card's parsed senses.
    public func resolvedSenses(forKey key: String, senses: [Sense]) -> [Sense] {
        guard let content = words[key] else { return senses }

        let fallback = soleRecord(in: content, whenSenseCountIs: senses.count)
        var resolved: [Sense] = []
        for sense in senses {
            let signature = Self.signature(sense.definition)
            if content.dropped.contains(signature) { continue }
            guard let record = content.records[signature] ?? fallback else {
                resolved.append(sense)
                continue
            }
            resolved.append(Sense(partOfSpeech: record.partOfSpeech ?? sense.partOfSpeech,
                                  definition: record.definition ?? sense.definition,
                                  examples: record.examples))
        }
        // Never hand back a card with nothing on it. A drop that would blank the word is
        // treated as a curation mistake, not as an instruction to show an empty card.
        return resolved.isEmpty ? senses : resolved
    }

    /// When a word has exactly one sense and exactly one curated record, match them even if
    /// the definition text drifted (a stray character, a re-worded gloss). With more than
    /// one of either, only an exact match is safe.
    private func soleRecord(in content: WordContent, whenSenseCountIs count: Int) -> Record? {
        guard count == 1, content.records.count == 1, content.dropped.isEmpty else { return nil }
        return content.records.values.first
    }

    /// Definition text reduced to a comparison signature: whitespace removed, case folded.
    /// Chinese punctuation is kept — it separates distinct glosses and is meaningful.
    public static func signature(_ definition: String) -> String {
        definition
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .lowercased()
    }

    // MARK: - Bundled content

    /// The curated file shipped inside the app. Loaded once; an unreadable or missing file
    /// degrades to an empty bank rather than failing the launch.
    public static let bundled: ContentBank = {
        guard let url = bundledURL(), let data = try? Data(contentsOf: url) else {
            return ContentBank(words: [:])
        }
        do {
            return try decode(data)
        } catch {
            NSLog("VocabFlashcards couldn't read its example bank: %@", error.localizedDescription)
            return ContentBank(words: [:])
        }
    }()

    private static func bundledURL() -> URL? {
        let name = "curated_content"
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: name, withExtension: "json") { return url }
        if let url = Bundle.module.url(forResource: name, withExtension: "json",
                                       subdirectory: "Resources") { return url }
        #endif
        return Bundle.main.url(forResource: name, withExtension: "json")
    }

    // MARK: - Coding

    /// Compact on-disk shape — this file carries a record per definition, so short keys
    /// keep it a fraction of the size of the spelled-out form.
    private struct StoredFile: Decodable {
        let version: Int
        let words: [String: StoredWord]

        enum CodingKeys: String, CodingKey {
            case version = "v"
            case words = "words"
        }
    }

    private struct StoredWord: Decodable {
        let senses: [StoredSense]?
        let dropped: [String]?
        let word: String?

        enum CodingKeys: String, CodingKey {
            case senses = "s"
            case dropped = "x"
            case word = "w"
        }
    }

    private struct StoredSense: Decodable {
        /// The original definition this record was written against.
        let match: String
        /// Corrected definition / part of speech, when they differ from the original.
        let definition: String?
        let partOfSpeech: String?
        /// One entry per gloss of the definition.
        let examples: [StoredExample]?

        enum CodingKeys: String, CodingKey {
            case match = "m"
            case definition = "d"
            case partOfSpeech = "p"
            case examples = "ex"
        }
    }

    private struct StoredExample: Decodable {
        let gloss: String?
        let english: String?
        let chinese: String?

        enum CodingKeys: String, CodingKey {
            case gloss = "g"
            case english = "en"
            case chinese = "zh"
        }
    }

    public static func decode(_ data: Data) throws -> ContentBank {
        let file = try JSONDecoder().decode(StoredFile.self, from: data)
        var words: [String: WordContent] = [:]
        words.reserveCapacity(file.words.count)
        for (rawKey, stored) in file.words {
            let key = TextNormalizer.normalizedKey(rawKey)
            guard !key.isEmpty else { continue }
            var records: [String: Record] = [:]
            for sense in stored.senses ?? [] {
                let examples = (sense.examples ?? []).map {
                    Example(gloss: $0.gloss ?? "", english: $0.english ?? "", chinese: $0.chinese ?? "")
                }.filter { !$0.isEmpty }
                records[signature(sense.match)] = Record(
                    definition: sense.definition,
                    partOfSpeech: sense.partOfSpeech,
                    examples: examples
                )
            }
            let dropped = Set((stored.dropped ?? []).map(signature))
            let word = stored.word?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !records.isEmpty || !dropped.isEmpty || !(word ?? "").isEmpty else { continue }
            words[key] = WordContent(records: records, dropped: dropped,
                                     word: (word ?? "").isEmpty ? nil : word)
        }
        return ContentBank(words: words)
    }
}
