import Foundation
import Combine

/// Global, cross-file memory of words the user has marked known. Identity is the
/// normalized English word only, so "keen" learned in one file counts as known in any
/// other. Persisted as a small JSON file in Application Support.
public final class KnownWordsStore: ObservableObject {

    // key (normalized) -> display form (original casing at time of marking)
    @Published public private(set) var entries: [String: String]

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.vocabflashcards.knownwords.io")

    /// Version 1 used verbose word objects and pretty-printed JSON. Keep these decoder-only
    /// types so existing installations migrate without losing their learned-word history.
    private struct LegacyStoredWord: Codable {
        let key: String
        let display: String
    }
    private struct LegacyStoredFile: Codable {
        var version: Int
        var words: [LegacyStoredWord]
    }

    /// Version 2 is a compact key -> display map. Empty display values mean "same as key",
    /// avoiding duplicate lowercase text while still preserving non-default display casing.
    private struct CompactStoredFile: Codable {
        var version: Int
        var words: [String: String]

        enum CodingKeys: String, CodingKey {
            case version = "v"
            case words = "w"
        }
    }

    private struct LoadResult {
        var entries: [String: String]
        var requiresMigration: Bool
    }

    public init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("known_words.json")
        let loaded = Self.load(from: fileURL)
        self.entries = loaded.entries
        if loaded.requiresMigration { persist() }
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("VocabFlashcards", isDirectory: true)
    }

    // MARK: - Queries

    public var count: Int { entries.count }

    public var knownKeys: Set<String> { Set(entries.keys) }

    public func isKnown(_ key: String) -> Bool { entries[key] != nil }

    public func isKnown(word: String) -> Bool {
        isKnown(TextNormalizer.normalizedKey(word))
    }

    /// Entries sorted alphabetically by display form, for the management screen.
    public var sortedEntries: [(key: String, display: String)] {
        entries
            .map { (key: $0.key, display: $0.value) }
            .sorted { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }
    }

    // MARK: - Mutations

    public func markKnown(word: String) {
        let key = TextNormalizer.normalizedKey(word)
        guard !key.isEmpty else { return }
        let display = TextNormalizer.cleanWord(word)
        if entries[key] == display { return }
        entries[key] = display.isEmpty ? key : display
        persist()
    }

    /// Mark known using an already-known display form (e.g. from a card).
    public func markKnown(key: String, display: String) {
        guard !key.isEmpty else { return }
        if entries[key] != nil { return }
        entries[key] = display.isEmpty ? key : display
        persist()
    }

    public func remove(key: String) {
        guard entries[key] != nil else { return }
        entries.removeValue(forKey: key)
        persist()
    }

    public func removeAll() {
        guard !entries.isEmpty else { return }
        entries.removeAll()
        persist()
    }

    // MARK: - Persistence

    private static func load(from url: URL) -> LoadResult {
        guard let data = try? Data(contentsOf: url) else {
            return LoadResult(entries: [:], requiresMigration: false)
        }
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode(CompactStoredFile.self, from: data),
           decoded.version == 2 {
            return LoadResult(entries: restoredEntries(from: decoded.words), requiresMigration: false)
        }
        guard let decoded = try? decoder.decode(LegacyStoredFile.self, from: data),
              decoded.version == 1 else {
            return LoadResult(entries: [:], requiresMigration: false)
        }
        var result: [String: String] = [:]
        for word in decoded.words where !word.key.isEmpty {
            result[word.key] = word.display.isEmpty ? word.key : word.display
        }
        return LoadResult(entries: result, requiresMigration: true)
    }

    private static func restoredEntries(from words: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, display) in words where !key.isEmpty {
            result[key] = display.isEmpty ? key : display
        }
        return result
    }

    /// Retained for callers that want an explicit persistence barrier. Writes are already
    /// synchronous, so this normally returns as soon as it acquires the serial I/O queue.
    public func flush() {
        queue.sync {}
    }

    private func persist() {
        let snapshot = entries
        let url = fileURL
        let file = CompactStoredFile(
            version: 2,
            words: Dictionary(uniqueKeysWithValues: snapshot.map { key, display in
                (key, display == key ? "" : display)
            })
        )
        queue.sync {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            do {
                let data = try encoder.encode(file)
                try data.write(to: url, options: .atomic)
            } catch {
                // The existing mutation API has no error return. Keep in-memory behavior
                // unchanged, but surface persistence failures to Console instead of silently
                // discarding them.
                NSLog("VocabFlashcards couldn't save known words: %@", error.localizedDescription)
            }
        }
    }
}
