import Foundation

/// Turns selected practice sets into a study deck: applies the known-word filter,
/// merges duplicate English words into single cards, removes duplicate senses, applies
/// stored content (examples, corrections, user edits), and (optionally) shuffles.
public struct DeckBuilder {

    public init() {}

    /// Build a shuffled deck ready for study.
    public func build(from selectedSets: [PracticeSet],
                      filter: KnownFilter,
                      knownKeys: Set<String>,
                      asideKeys: Set<String> = [],
                      resolver: CardContentResolving? = nil) -> [Flashcard] {
        var deck = mergedCards(from: selectedSets, filter: filter,
                               knownKeys: knownKeys, asideKeys: asideKeys, resolver: resolver)
        deck.shuffle()
        return deck
    }

    /// Build a deck in a stable, deterministic order (used by tests).
    public func buildOrdered(from selectedSets: [PracticeSet],
                             filter: KnownFilter,
                             knownKeys: Set<String>,
                             asideKeys: Set<String> = [],
                             resolver: CardContentResolving? = nil) -> [Flashcard] {
        mergedCards(from: selectedSets, filter: filter,
                    knownKeys: knownKeys, asideKeys: asideKeys, resolver: resolver)
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
                let sense = Sense(partOfSpeech: pos, definition: def)
                if seenSenses.insert(sense.meaningSignature).inserted {
                    senses.append(sense)
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
                             knownKeys: Set<String>,
                             asideKeys: Set<String>,
                             resolver: CardContentResolving?) -> [Flashcard] {
        var order: [String] = []
        var accumulators: [String: CardAccumulator] = [:]

        for set in selectedSets {
            for item in set.items {
                let key = item.key
                guard passesFilter(key, filter: filter,
                                   knownKeys: knownKeys, asideKeys: asideKeys) else { continue }

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

        let cards = order.compactMap { accumulators[$0]?.makeCard() }
        guard let resolver else { return cards }
        return cards.map(resolver.resolve)
    }

    /// "Almost Known" words are parked out of the New pool, but they are not known: they
    /// still belong to Study Everything and never to Review Known Words.
    private func passesFilter(_ key: String, filter: KnownFilter,
                              knownKeys: Set<String>, asideKeys: Set<String>) -> Bool {
        switch filter {
        case .includeKnown: return true
        case .excludeKnown: return !knownKeys.contains(key) && !asideKeys.contains(key)
        case .onlyKnown: return knownKeys.contains(key)
        }
    }
}
