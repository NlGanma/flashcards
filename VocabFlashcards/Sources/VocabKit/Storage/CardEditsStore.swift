import Foundation
import Combine

/// What the user typed into the card editor for one word. An edit is a *complete*
/// replacement of the card's content — the word as displayed plus its whole sense list —
/// which is what makes adding and deleting senses possible, and what makes the result
/// stable when the spreadsheet is reloaded.
///
/// The word's identity is not part of the edit: the normalized key of the original English
/// word stays the card's id forever, so known-word memory and the example bank keep
/// matching even after the display text is corrected.
public struct CardEdit: Codable, Hashable, Sendable {
    public var word: String
    public var senses: [Sense]

    public init(word: String, senses: [Sense]) {
        self.word = word
        self.senses = senses
    }

    public var isEmpty: Bool {
        word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && senses.isEmpty
    }
}

/// Local, cross-file memory of hand-edited cards, stored as JSON in Application Support
/// next to the known-word banks. The source spreadsheet is never written to.
public final class CardEditsStore: ObservableObject {

    @Published public private(set) var edits: [String: CardEdit]

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.vocabflashcards.cardedits.io")

    private struct StoredFile: Codable {
        var version: Int
        var cards: [String: CardEdit]

        enum CodingKeys: String, CodingKey {
            case version = "v"
            case cards = "c"
        }
    }

    public init(directory: URL? = nil) {
        let dir = directory ?? KnownWordsStore.defaultDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("card_edits.json")
        self.edits = Self.load(from: fileURL)
    }

    // MARK: - Queries

    public var count: Int { edits.count }

    public func edit(for key: String) -> CardEdit? { edits[key] }

    public func hasEdit(for key: String) -> Bool { edits[key] != nil }

    // MARK: - Mutations

    public func save(_ edit: CardEdit, for key: String) {
        guard !key.isEmpty, !edit.isEmpty else { return }
        guard edits[key] != edit else { return }
        edits[key] = edit
        persist()
    }

    /// Drop the edit for one word — the card goes back to what the spreadsheet and the
    /// curated bank say.
    public func revert(key: String) {
        guard edits[key] != nil else { return }
        edits.removeValue(forKey: key)
        persist()
    }

    public func revertAll() {
        guard !edits.isEmpty else { return }
        edits.removeAll()
        persist()
    }

    // MARK: - Persistence

    private static func load(from url: URL) -> [String: CardEdit] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(StoredFile.self, from: data),
              decoded.version == 1
        else { return [:] }
        return decoded.cards.filter { !$0.key.isEmpty && !$0.value.isEmpty }
    }

    /// Explicit persistence barrier for tests — writes are already synchronous.
    public func flush() { queue.sync {} }

    private func persist() {
        let file = StoredFile(version: 1, cards: edits)
        let url = fileURL
        queue.sync {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            do {
                let data = try encoder.encode(file)
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("VocabFlashcards couldn't save card edits: %@", error.localizedDescription)
            }
        }
    }
}
