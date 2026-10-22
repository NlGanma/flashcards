import Foundation
import Combine

/// Global, cross-file memory of words the user has marked known. Identity is the
/// normalized English word only, so "keen" learned in one file counts as known in any
/// other. Persisted as a small JSON file in Application Support.
///
/// Alongside the permanent known list the store keeps a second, temporary bank — the
/// "Almost Known" words. Those are parked out of the New pool without ever counting as
/// known, and the whole bank can be reverted to New in one action. A key is never in
/// both banks at once.
public final class KnownWordsStore: ObservableObject {

    // key (normalized) -> display form (original casing at time of marking)
    @Published public private(set) var entries: [String: String]

    /// The temporary "Almost Known" bank, same key -> display shape as `entries`.
    @Published public private(set) var asideEntries: [String: String]

    private let fileURL: URL
    private let backupURL: URL
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
    ///
    /// The Almost Known bank was added later as the optional `"a"` map. It is deliberately
    /// an *additive* change rather than a version bump: a file written by this build still
    /// reads correctly in builds that predate the bank (they ignore the unknown key and
    /// keep every known word), and a file written before it loads here with an empty bank.
    /// `aside` stays nil when the bank is empty, so the on-disk bytes are unchanged for
    /// anyone who never uses the feature.
    private struct CompactStoredFile: Codable {
        var version: Int
        var words: [String: String]
        var aside: [String: String]?

        enum CodingKeys: String, CodingKey {
            case version = "v"
            case words = "w"
            case aside = "a"
        }
    }

    private struct LoadResult {
        var entries: [String: String]
        var asideEntries: [String: String]
        var requiresMigration: Bool
    }

    public init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("known_words.json")
        self.backupURL = dir.appendingPathComponent("known_words.backup.json")
        Self.backUpOnce(from: fileURL, to: backupURL)
        let loaded = Self.load(from: fileURL)
        self.entries = loaded.entries
        self.asideEntries = loaded.asideEntries
        if loaded.requiresMigration { persist() }
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("VocabFlashcards", isDirectory: true)
    }

    /// One-time snapshot of the store as it was before this build first ran, kept as a
    /// safety net for the known-word history. Never overwritten once written.
    private static func backUpOnce(from source: URL, to destination: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path), !fm.fileExists(atPath: destination.path) else { return }
        try? fm.copyItem(at: source, to: destination)
    }

    // MARK: - Queries

    public var count: Int { entries.count }

    public var knownKeys: Set<String> { Set(entries.keys) }

    public func isKnown(_ key: String) -> Bool { entries[key] != nil }

    public func isKnown(word: String) -> Bool {
        isKnown(TextNormalizer.normalizedKey(word))
    }

    public var asideCount: Int { asideEntries.count }

    public var asideKeys: Set<String> { Set(asideEntries.keys) }

    public func isAside(_ key: String) -> Bool { asideEntries[key] != nil }

    public func isAside(word: String) -> Bool {
        isAside(TextNormalizer.normalizedKey(word))
    }

    /// Entries sorted alphabetically by display form, for the management screen.
    public var sortedEntries: [(key: String, display: String)] {
        Self.sorted(entries)
    }

    public var sortedAsideEntries: [(key: String, display: String)] {
        Self.sorted(asideEntries)
    }

    private static func sorted(_ map: [String: String]) -> [(key: String, display: String)] {
        map
            .map { (key: $0.key, display: $0.value) }
            .sorted { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }
    }

    // MARK: - Mutations

    public func markKnown(word: String) {
        let key = TextNormalizer.normalizedKey(word)
        guard !key.isEmpty else { return }
        let display = TextNormalizer.cleanWord(word)
        if entries[key] == display && asideEntries[key] == nil { return }
        entries[key] = display.isEmpty ? key : display
        asideEntries.removeValue(forKey: key)     // knowing a word promotes it out of the bank
        persist()
    }

    /// Mark known using an already-known display form (e.g. from a card).
    public func markKnown(key: String, display: String) {
        guard !key.isEmpty else { return }
        if entries[key] != nil && asideEntries[key] == nil { return }
        if entries[key] == nil { entries[key] = display.isEmpty ? key : display }
        asideEntries.removeValue(forKey: key)
        persist()
    }

    public func remove(key: String) {
        guard entries[key] != nil else { return }
        entries.removeValue(forKey: key)
        persist()
    }

    /// Clears the permanent known list only — the Almost Known bank is left alone.
    public func removeAll() {
        guard !entries.isEmpty else { return }
        entries.removeAll()
        persist()
    }

    /// Park a word in the temporary bank. Words already known stay known: the bank is for
    /// words still being learned, and this guard keeps a stray keypress from quietly
    /// demoting real progress.
    public func markAside(key: String, display: String) {
        guard !key.isEmpty, entries[key] == nil else { return }
        if asideEntries[key] != nil { return }
        asideEntries[key] = display.isEmpty ? key : display
        persist()
    }

    public func markAside(word: String) {
        let key = TextNormalizer.normalizedKey(word)
        markAside(key: key, display: TextNormalizer.cleanWord(word))
    }

    /// Send one word back to New.
    public func removeAside(key: String) {
        guard asideEntries[key] != nil else { return }
        asideEntries.removeValue(forKey: key)
        persist()
    }

    /// Send the whole bank back to New. Known words are untouched.
    public func removeAllAside() {
        guard !asideEntries.isEmpty else { return }
        asideEntries.removeAll()
        persist()
    }

    /// Refresh the stored display forms from the words as they read today. Keys are the
    /// identity and never change here — this only repairs how an already-learned word is
    /// spelled in the manager, e.g. one saved before bracket-balanced cleaning existed.
    /// Writes nothing when everything already matches.
    public func reconcileDisplays(_ displays: [String: String]) {
        var changed = false
        for (key, display) in displays where !display.isEmpty {
            if let current = entries[key], current != display {
                entries[key] = display
                changed = true
            }
            if let current = asideEntries[key], current != display {
                asideEntries[key] = display
                changed = true
            }
        }
        if changed { persist() }
    }

    // MARK: - Persistence

    private static func load(from url: URL) -> LoadResult {
        guard let data = try? Data(contentsOf: url) else {
            return LoadResult(entries: [:], asideEntries: [:], requiresMigration: false)
        }
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode(CompactStoredFile.self, from: data),
           decoded.version == 2 {
            let known = restoredEntries(from: decoded.words)
            var aside = restoredEntries(from: decoded.aside ?? [:])
            // Enforce the "never in both banks" invariant even against a hand-edited file.
            known.keys.forEach { aside.removeValue(forKey: $0) }
            return LoadResult(entries: known, asideEntries: aside, requiresMigration: false)
        }
        guard let decoded = try? decoder.decode(LegacyStoredFile.self, from: data),
              decoded.version == 1 else {
            return LoadResult(entries: [:], asideEntries: [:], requiresMigration: false)
        }
        var result: [String: String] = [:]
        for word in decoded.words where !word.key.isEmpty {
            result[word.key] = word.display.isEmpty ? word.key : word.display
        }
        return LoadResult(entries: result, asideEntries: [:], requiresMigration: true)
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
        let asideSnapshot = asideEntries
        let url = fileURL
        let file = CompactStoredFile(
            version: 2,
            words: Self.compacted(snapshot),
            aside: asideSnapshot.isEmpty ? nil : Self.compacted(asideSnapshot)
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

    private static func compacted(_ map: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: map.map { key, display in
            (key, display == key ? "" : display)
        })
    }
}
