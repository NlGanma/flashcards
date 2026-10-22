import Foundation

/// What a generation run reports, in order.
public enum GenerationEvent: Equatable, Sendable {
    /// The model has started reading chunk `index` (0-based) of `count`.
    case chunkStarted(index: Int, count: Int, sections: [String])
    /// A new card.
    case card(GeneratedCard)
    /// A replacement for the existing card with the same id.
    case revised(GeneratedCard)
}

public enum GenerationError: Error, LocalizedError, Equatable {
    /// The notes had no text to make cards from.
    case emptyNotes
    /// The model answered, but nothing it said could be read as a card.
    case noCards

    public var errorDescription: String? {
        switch self {
        case .emptyNotes:
            return "That Markdown file doesn't have any text to make cards from."
        case .noCards:
            return "The model replied, but not with flashcards. Try again, or try a larger or more capable model."
        }
    }
}

/// Turns Markdown notes into flashcards with a local model, and revises cards on
/// request. The learner's chat messages are the instructions: they say what goes on
/// the back of every card, and later messages refine earlier ones.
public struct DeckGenerator: Sendable {

    public let client: ChatStreaming
    /// Notes per request, in estimated tokens. Small enough for a 4K-context model to
    /// read the excerpt and still have room to write its cards.
    public var chunkTokens: Int
    /// Cards per revision request, for the same reason.
    public var revisionBatch: Int

    public init(client: ChatStreaming, chunkTokens: Int = 1500, revisionBatch: Int = 10) {
        self.client = client
        self.chunkTokens = chunkTokens
        self.revisionBatch = revisionBatch
    }

    // MARK: - Generating

    public func generate(from outline: MarkdownOutline,
                         instructions: [String]) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let chunks = outline.chunks(maxTokens: chunkTokens)
                    guard !chunks.isEmpty else { throw GenerationError.emptyNotes }
                    var total = 0
                    for chunk in chunks {
                        try Task.checkCancellation()
                        continuation.yield(.chunkStarted(index: chunk.index, count: chunks.count,
                                                         sections: chunk.sections))
                        let request = ChatRequest(
                            messages: Prompt.generation(chunk: chunk, of: chunks.count,
                                                        instructions: instructions),
                            schema: Prompt.cardSchema(sections: chunk.sections, withIDs: false))
                        // A small model can get stuck repeating a card; one per front is plenty.
                        var seen = Set<String>()
                        for try await card in replyCards(for: request) {
                            guard seen.insert(TextNormalizer.normalizedKey(card.front)).inserted else { continue }
                            total += 1
                            continuation.yield(.card(GeneratedCard(
                                front: card.front, back: card.back, tag: card.tag,
                                example: card.example, exampleNote: card.exampleNote,
                                section: Self.matchSection(card.section, in: chunk.sections))))
                        }
                    }
                    if total == 0 { throw GenerationError.noCards }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Revising

    /// Apply one chat request to existing cards — all of them, or the one the learner
    /// picked. Each card keeps its id and section; a card the model adds alongside is new.
    /// `source` is the notes the cards came from, when short enough to send.
    public func revise(_ cards: [GeneratedCard], request: String, instructions: [String],
                       source: String? = nil) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var returned = 0
                    let batches = stride(from: 0, to: cards.count, by: max(1, revisionBatch)).map {
                        Array(cards[$0..<min($0 + revisionBatch, cards.count)])
                    }
                    for (index, batch) in batches.enumerated() {
                        try Task.checkCancellation()
                        let sections = Array(Set(batch.map(\.section))).sorted()
                        continuation.yield(.chunkStarted(index: index, count: batches.count, sections: sections))
                        let refs = batch.indices.map { "c\($0 + 1)" }
                        let byRef = Dictionary(uniqueKeysWithValues: zip(refs, batch))
                        let chat = ChatRequest(
                            messages: Prompt.revision(Array(zip(refs, batch)), request: request,
                                                      instructions: instructions, source: source),
                            schema: Prompt.cardSchema(sections: nil, withIDs: true))
                        for try await reply in replyCards(for: chat) {
                            returned += 1
                            if let ref = reply.ref, let original = byRef[ref] {
                                continuation.yield(.revised(GeneratedCard(
                                    id: original.id, front: reply.front, back: reply.back, tag: reply.tag,
                                    example: reply.example, exampleNote: reply.exampleNote,
                                    section: original.section)))
                            } else {
                                continuation.yield(.card(GeneratedCard(
                                    front: reply.front, back: reply.back, tag: reply.tag,
                                    example: reply.example, exampleNote: reply.exampleNote,
                                    section: batch[0].section)))
                            }
                        }
                    }
                    if returned == 0, !cards.isEmpty { throw GenerationError.noCards }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Plumbing

    /// The model's reply, parsed into cards as they complete.
    private func replyCards(for request: ChatRequest) -> AsyncThrowingStream<ModelCard, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var parser = CardStreamParser()
                    for try await piece in client.stream(request) {
                        for card in parser.consume(piece) { continuation.yield(card) }
                    }
                    for card in parser.finish() { continuation.yield(card) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The model is asked to copy a section title; without a schema to hold it to the
    /// list it may paraphrase, so match loosely and fall back to the chunk's first.
    static func matchSection(_ proposed: String?, in sections: [String]) -> String {
        guard let proposed = proposed?.lowercased(), !proposed.isEmpty else { return sections.first ?? "" }
        return sections.first { $0.lowercased() == proposed }
            ?? sections.first { $0.lowercased().contains(proposed) || proposed.contains($0.lowercased()) }
            ?? sections.first ?? ""
    }
}

// MARK: - Prompts

/// The text the model sees. Kept short and literal: the models this runs on are small,
/// and every rule here has to survive a 7B model's reading of it.
enum Prompt {

    static let generationSystem = """
        You turn a learner's study notes into flashcards.

        Make one card for each distinct term, concept, fact or idea in the excerpt that is \
        worth memorising. Skip filler, and never add facts that are not in the excerpt.

        Fields:
        - front: what the learner recalls from: a term, a name, or a short question. Under 12 words.
        - back: what the learner should recall. Follow the learner's instructions for what goes \
        here. With no instructions, give a concise, accurate answer in one or two sentences.
        - tag: a very short label. A part of speech (n., v., adj.) for vocabulary, otherwise a \
        one- or two-word category. "" if nothing fits.
        - example: a natural sentence that uses the front, when the instructions ask for one or \
        the card is vocabulary. Otherwise "".
        - exampleNote: a translation of the example, or a short note on it, when the instructions \
        ask for one. Otherwise "".
        - section: the heading the card's material comes from, copied exactly from the list given.

        Write in the language of the notes unless the instructions say otherwise.
        Reply with JSON only, in the form {"cards":[{"front":"…","back":"…","tag":"…","example":"…","exampleNote":"…","section":"…"}]}.
        """

    static let revisionSystem = """
        You revise a learner's flashcards. Apply the learner's request to the cards you are \
        given, and change nothing the request doesn't ask you to change.

        Keep every card's id exactly. Keep the front unless the request is about fronts. Keep \
        facts accurate, and consistent with the source notes when they are given. The same \
        fields apply: front, back, tag, example, exampleNote ("" when empty).

        Return every card you were given, in the same order. Add a card with a new id only if \
        the request asks for more cards.
        Reply with JSON only, in the form {"cards":[{"id":"c1","front":"…","back":"…","tag":"…","example":"…","exampleNote":"…"}]}.
        """

    static func instructionBlock(_ instructions: [String]) -> String {
        let cleaned = instructions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "The learner's instructions: none, so use the defaults." }
        let list = cleaned.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return "The learner's instructions for every card (when they conflict, the later one wins):\n\(list)"
    }

    static func generation(chunk: MarkdownOutline.Chunk, of count: Int,
                           instructions: [String]) -> [ChatMessage] {
        let sections = chunk.sections.map { "\"\($0)\"" }.joined(separator: ", ")
        let part = count > 1 ? " (part \(chunk.index + 1) of \(count))" : ""
        return [
            ChatMessage(.system, generationSystem),
            ChatMessage(.user, """
                \(instructionBlock(instructions))

                Sections in this excerpt: \(sections)

                Notes\(part):
                <<<
                \(chunk.text)
                >>>
                """)
        ]
    }

    static func revision(_ cards: [(ref: String, card: GeneratedCard)], request: String,
                         instructions: [String], source: String?) -> [ChatMessage] {
        let list = cards.map { ref, card -> JSONValue in
            ["id": .string(ref), "front": .string(card.front), "back": .string(card.back),
             "tag": .string(card.tag), "example": .string(card.example),
             "exampleNote": .string(card.exampleNote)]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = (try? encoder.encode(JSONValue.array(list))).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        var body = "\(instructionBlock(instructions))\n\nThe request: \(request)\n\n"
        if let source, !source.isEmpty {
            body += "Source notes:\n<<<\n\(source)\n>>>\n\n"
        }
        body += "Cards:\n\(json)"
        return [ChatMessage(.system, revisionSystem), ChatMessage(.user, body)]
    }

    /// Grammar-constrained servers enforce this exactly; `strict` requires every field, so
    /// the model writes "" for the ones it leaves empty. A revision carries ids instead of
    /// sections, since a card keeps its section. The cap stops a small model that has
    /// fallen into a loop from writing cards until its context is full.
    static func cardSchema(sections: [String]?, withIDs: Bool) -> JSONValue {
        var properties: [String: JSONValue] = [
            "front": ["type": "string"], "back": ["type": "string"], "tag": ["type": "string"],
            "example": ["type": "string"], "exampleNote": ["type": "string"]
        ]
        var required: [JSONValue] = ["front", "back", "tag", "example", "exampleNote"]
        if withIDs {
            properties["id"] = ["type": "string"]
            required.insert("id", at: 0)
        }
        if let sections, !sections.isEmpty {
            properties["section"] = ["type": "string", "enum": .array(sections.map { .string($0) })]
            required.append("section")
        }
        return [
            "type": "object",
            "properties": [
                "cards": [
                    "type": "array",
                    "maxItems": 40,
                    "items": [
                        "type": "object",
                        "properties": .object(properties),
                        "required": .array(required),
                        "additionalProperties": false
                    ]
                ]
            ],
            "required": ["cards"],
            "additionalProperties": false
        ]
    }
}
