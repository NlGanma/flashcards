import Foundation

/// Turns selected practice sets into a study deck: applies the known-word filter,
/// merges duplicate English words into single cards, removes duplicate senses, and
/// (optionally) shuffles.
public struct DeckBuilder {

    public init() {}

    /// Build a shuffled deck ready for study.
    public func build(from selectedSets: [PracticeSet],
                      filter: KnownFilter,
                      knownKeys: Set<String>) -> [Flashcard] {
        var deck = mergedCards(from: selectedSets, filter: filter, knownKeys: knownKeys)
        deck.shuffle()
        return deck
    }

    /// Build a deck in a stable, deterministic order (used by tests).
    public func buildOrdered(from selectedSets: [PracticeSet],
                             filter: KnownFilter,
                             knownKeys: Set<String>) -> [Flashcard] {
        mergedCards(from: selectedSets, filter: filter, knownKeys: knownKeys)
    }

    // MARK: - Merging

    private final class CardAccumulator {
        let key: String
        var word: String
        var senses: [Sense] = []
        var seenSenses = Set<String>()
        var sourceSets: [String] = []
        var seenSets = Set<String>()

        init(key: String, word: String) {
            self.key = key
            self.word = word
        }

        func add(pos: String, def: String, set: String) {
            // A sense is only recorded when it carries some content.
            if !(pos.isEmpty && def.isEmpty) {
                let dedupKey = "\(pos.lowercased())\u{0}\(def.lowercased())"
                if seenSenses.insert(dedupKey).inserted {
                    senses.append(Sense(partOfSpeech: pos, definition: def))
                }
            }
            if !set.isEmpty, seenSets.insert(set).inserted {
                sourceSets.append(set)
            }
        }

        func makeCard() -> Flashcard {
            Flashcard(id: key, word: word, senses: senses, sourceSets: sourceSets)
        }
    }

    private func mergedCards(from selectedSets: [PracticeSet],
                             filter: KnownFilter,
                             knownKeys: Set<String>) -> [Flashcard] {
        var order: [String] = []
        var accumulators: [String: CardAccumulator] = [:]

        for set in selectedSets {
            for item in set.items {
                let key = item.key
                guard passesFilter(key, filter: filter, knownKeys: knownKeys) else { continue }

                let acc: CardAccumulator
                if let existing = accumulators[key] {
                    acc = existing
                } else {
                    acc = CardAccumulator(key: key, word: item.english)
                    accumulators[key] = acc
                    order.append(key)
                }
                acc.add(pos: item.partOfSpeech, def: item.definition, set: item.setName)
            }
        }

        return order.compactMap { accumulators[$0]?.makeCard() }
    }

    private func passesFilter(_ key: String, filter: KnownFilter, knownKeys: Set<String>) -> Bool {
        switch filter {
        case .includeKnown: return true
        case .excludeKnown: return !knownKeys.contains(key)
        case .onlyKnown: return knownKeys.contains(key)
        }
    }
}
