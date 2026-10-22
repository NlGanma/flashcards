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
                        let target = Prompt.targetCardCount(chunk.text)
                        let request = ChatRequest(
                            messages: Prompt.generation(chunk: chunk, of: chunks.count,
                                                        instructions: instructions),
                            temperature: Self.temperature,
                            schema: Prompt.cardSchema(sections: chunk.sections, withIDs: false,
                                                      minCards: max(1, target * 2 / 3)),
                            maxTokens: Self.tokenBudget(cards: target),
                            repeatPenalty: Self.repeatPenalty)
                        // A small model can get stuck repeating a card; one per front is plenty.
                        var seen = Set<String>()
                        for try await card in replyCards(for: request) {
                            guard !Self.isDegenerate(card),
                                  seen.insert(TextNormalizer.normalizedKey(card.front)).inserted else { continue }
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
                            temperature: Self.temperature,
                            schema: Prompt.cardSchema(sections: nil, withIDs: true, minCards: batch.count),
                            maxTokens: Self.tokenBudget(cards: batch.count + 1),
                            repeatPenalty: Self.repeatPenalty)
                        for try await reply in replyCards(for: chat) {
                            guard !Self.isDegenerate(reply) else { continue }
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

    // MARK: - Guards against a looping model

    // Greedy decoding is what falls into loops, so not too cold.
    static let temperature = 0.5
    static let repeatPenalty = 1.1

    /// Room for every card at the schema's longest, plus the JSON around it.
    static func tokenBudget(cards: Int) -> Int {
        200 + max(1, cards) * 260
    }

    /// A card whose text has collapsed into repetition — "the fibrin, the fibrin, the
    /// fibrin…" — is worse than no card. Real prose of any length uses mostly distinct words.
    static func isDegenerate(_ card: ModelCard) -> Bool {
        for text in [card.front, card.back, card.example, card.exampleNote] {
            let words = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            guard words.count >= 24 else { continue }
            if Double(Set(words).count) / Double(words.count) < 0.35 { return true }
        }
        return false
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
/// and every rule here has to survive a 7B model's reading of it. There is deliberately no
/// worked example — given a short section, a 7B model copies the example's cards instead.
enum Prompt {

    static let generationSystem = """
        You turn a learner's study notes into flashcards.

        Make one card for every separate term, concept, fact or idea in the notes that is worth \
        memorising — usually one card per fact. Each card tests one thing. Never copy a whole \
        paragraph onto a card, and never add facts that are not in the notes.

        Fields:
        - front: what the learner recalls from: a term, a name, or a short question. Under 12 words.
        - back: what the learner should recall. Follow the learner's instructions for what goes \
        here. With no instructions, a concise, accurate answer in one or two sentences.
        - tag: a very short label. A part of speech (n., v., adj.) for vocabulary, otherwise a \
        one- or two-word category. "" if nothing fits.
        - example: a natural sentence that uses the front, when the instructions ask for one or \
        the card is vocabulary. Otherwise "".
        - exampleNote: a translation of the example, or a short note on it, when the instructions \
        ask for one. Otherwise "".
        - section: the heading the card's material comes from, copied exactly from the list given.

        Write in the language of the notes unless the instructions say otherwise. Reply with JSON \
        only, in the form {"cards":[{"front":"…","back":"…","tag":"…","example":"…","exampleNote":"…","section":"…"}]}.
        """

    static let revisionSystem = """
        You revise a learner's flashcards. Rewrite every card you are given so that it follows \
        the learner's request; the request matters more than anything else. Change nothing the \
        request doesn't ask you to change.

        Keep every card's id exactly. Keep the front unless the request is about fronts. Keep \
        facts accurate, and consistent with the notes when they are given. Fields: id, front, \
        back, tag, example, exampleNote ("" when empty).

        Return every card you were given, in the same order. Add a card with a new id only if \
        the request asks for more cards. Reply with JSON only, in the form \
        {"cards":[{"id":"c1","front":"…","back":"…","tag":"…","example":"…","exampleNote":"…"}]}.
        """

    /// The learner's standing instructions, last in the prompt: small models weight the
    /// end of a prompt most, and these are what the learner actually cares about.
    static func instructionBlock(_ instructions: [String]) -> String {
        let cleaned = instructions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "The learner gave no instructions, so use the defaults." }
        let list = cleaned.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return "The learner's instructions for every card (when two conflict, the later one wins):\n\(list)"
    }

    static func generation(chunk: MarkdownOutline.Chunk, of count: Int,
                           instructions: [String]) -> [ChatMessage] {
        let sections = chunk.sections.map { "\"\($0)\"" }.joined(separator: ", ")
        let part = count > 1 ? " This is part \(chunk.index + 1) of \(count) of the notes." : ""
        let target = targetCardCount(chunk.text)
        return [
            ChatMessage(.system, generationSystem),
            ChatMessage(.user, """
                <notes>
                \(chunk.text)
                </notes>

                Sections: \(sections).\(part)
                Make about \(target) card\(target == 1 ? "" : "s"), one per fact.

                \(instructionBlock(instructions))
                """)
        ]
    }

    static func revision(_ cards: [(ref: String, card: GeneratedCard)], request: String,
                         instructions: [String], source: String?) -> [ChatMessage] {
        // One card per line, keys in the order the reply must use.
        let json = "[\n" + cards.map { ref, card -> String in
            let value: JSONValue = [
                "id": .string(ref), "front": .string(card.front), "back": .string(card.back),
                "tag": .string(card.tag), "example": .string(card.example),
                "exampleNote": .string(card.exampleNote)
            ]
            return value.jsonText
        }.joined(separator: ",\n") + "\n]"
        // The request goes first and last. Given only the cards and then the request, a
        // small model tends to copy the cards back unchanged.
        var body = "The request: \(request)\n\n"
        if let source, !source.isEmpty {
            body += "<notes>\n\(source)\n</notes>\n\n"
        }
        body += "<cards>\n\(json)\n</cards>\n\n\(instructionBlock(instructions))\n\n"
        let scope = cards.count == 1 ? "the card above" : "each of the \(cards.count) cards above"
        body += "Rewrite \(scope) so that it follows the request: \(request)"
        return [ChatMessage(.system, revisionSystem), ChatMessage(.user, body)]
    }

    /// Roughly one card per fact: sentences and list items in the notes, headings and code
    /// left out. Small models stop after one or two cards unless they are given a number,
    /// and with a schema the lower bound is enforced.
    static func targetCardCount(_ text: String) -> Int {
        var units = 0
        var inFence = false
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle(); continue }
            if inFence || trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let sentences = trimmed.components(separatedBy: CharacterSet(charactersIn: ".!?。！？；;"))
                .filter { $0.unicodeScalars.filter(CharacterSet.letters.contains).count >= 2 }
            units += max(1, sentences.count)
        }
        return min(30, max(1, units))
    }

    /// Grammar-constrained servers enforce this exactly; `strict` requires every field, so
    /// the model writes "" for the ones it leaves empty. A revision carries ids instead of
    /// sections, since a card keeps its section. The floor keeps a small model from stopping
    /// after one card. The caps — on cards, and on every field's length — stop one that
    /// has fallen into a loop from writing until its context is full.
    static func cardSchema(sections: [String]?, withIDs: Bool, minCards: Int = 1) -> JSONValue {
        func text(_ limit: Int) -> JSONValue { ["type": "string", "maxLength": .number(Double(limit))] }
        // The model writes keys in exactly this order: the front before the back it answers.
        var properties: [JSONValue.Member] = []
        var required: [JSONValue] = []
        func field(_ name: String, _ schema: JSONValue) {
            properties.append(JSONValue.Member(name, schema))
            required.append(.string(name))
        }
        if withIDs { field("id", text(8)) }
        // An empty face is the easy way out for a small model asked to rewrite something.
        field("front", ["type": "string", "minLength": 1, "maxLength": 120])
        field("back", ["type": "string", "minLength": 1, "maxLength": 500])
        field("tag", text(24))
        field("example", text(240))
        field("exampleNote", text(240))
        if let sections, !sections.isEmpty {
            field("section", ["type": "string", "enum": .array(sections.map { .string($0) })])
        }
        return [
            "type": "object",
            "properties": [
                "cards": [
                    "type": "array",
                    "minItems": .number(Double(max(1, minCards))),
                    "maxItems": .number(Double(max(40, minCards))),
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
