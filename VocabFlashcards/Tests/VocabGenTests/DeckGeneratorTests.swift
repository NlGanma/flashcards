import Foundation
import Testing
@testable import VocabKit

/// Plays back one canned reply per request and keeps what it was asked.
final class ScriptedModel: ChatStreaming, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [String]
    private(set) var requests: [ChatRequest] = []
    var failure: Error?

    init(_ replies: [String]) { self.replies = replies }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<String, Error> {
        lock.lock()
        requests.append(request)
        let reply = replies.isEmpty ? "" : replies.removeFirst()
        let failure = self.failure
        lock.unlock()
        return AsyncThrowingStream { continuation in
            // Split mid-object so the generator sees cards complete across pieces.
            var rest = Substring(reply)
            while !rest.isEmpty {
                continuation.yield(String(rest.prefix(9)))
                rest = rest.dropFirst(9)
            }
            if let failure { continuation.finish(throwing: failure) } else { continuation.finish() }
        }
    }
}

@Suite("Deck generator")
struct DeckGeneratorTests {

    private func run(_ stream: AsyncThrowingStream<GenerationEvent, Error>) async throws -> [GenerationEvent] {
        var events: [GenerationEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    private func cards(_ events: [GenerationEvent]) -> [GeneratedCard] {
        events.compactMap { if case .card(let card) = $0 { return card } else { return nil } }
    }

    let notes = MarkdownOutline(markdown: "# Bio\n## Cells\nMitochondria make ATP.\n## Genes\nDNA stores genes.",
                                fallbackTitle: "bio")

    @Test func cardsAreTaggedWithTheirSection() async throws {
        let model = ScriptedModel([
            #"{"cards":[{"front":"mitochondria","back":"Make ATP.","tag":"organelle","example":"","exampleNote":"","section":"Genes"}]}"#,
            #"{"cards":[{"front":"DNA","back":"Stores genes.","tag":"molecule","example":"","exampleNote":""}]}"#
        ])
        let events = try await run(DeckGenerator(client: model).generate(from: notes, instructions: []))

        #expect(events.first == .chunkStarted(index: 0, count: 2, sections: ["Cells"]))
        #expect(cards(events).map(\.front) == ["mitochondria", "DNA"])
        // The section comes from the request, not from what the model claims.
        #expect(cards(events).map(\.section) == ["Cells", "Genes"])
    }

    @Test func theChatInstructionsReachThePromptInOrder() async throws {
        let model = ScriptedModel([#"[{"front":"a","back":"b"}]"#, #"[{"front":"c","back":"d"}]"#])
        _ = try await run(DeckGenerator(client: model).generate(
            from: notes, instructions: ["Put the Chinese translation on the back", "  ", "Add an example sentence"]))

        let prompt = try #require(model.requests.first?.messages.last?.content)
        #expect(prompt.contains("1. Put the Chinese translation on the back\n2. Add an example sentence"))
        #expect(prompt.contains("Mitochondria make ATP."))
        #expect(prompt.contains(#"Sections: "Cells"."#))
        #expect(prompt.contains("<notes>\n## Cells"))
        // The learner's instructions come last, where a small model weights them most.
        #expect(prompt.hasSuffix("2. Add an example sentence"))
        #expect(model.requests.first?.messages.first?.role == .system)
    }

    @Test func theSchemaPinsSectionsToTheChunk() throws {
        let text = Prompt.cardSchema(sections: ["Cells", "Genes"], withIDs: false).jsonText
        #expect(text.contains(#""enum":["Cells","Genes"]"#))
        #expect(text.contains(#""maxItems":40"#))
        #expect(!text.contains(#""id""#))
    }

    @Test func theCardTargetCountsFactsNotHeadingsOrCode() throws {
        #expect(Prompt.targetCardCount("## Cells\nMitochondria make ATP. Ribosomes build proteins.\n- the nucleus") == 3)
        #expect(Prompt.targetCardCount("```\nlet a = 1; let b = 2\n```\nOne fact.") == 1)
        #expect(Prompt.targetCardCount("线粒体产生能量。核糖体合成蛋白质。") == 2)
        #expect(Prompt.targetCardCount(String(repeating: "A fact. ", count: 100)) == 30)

        let schema = Prompt.cardSchema(sections: nil, withIDs: true, minCards: 3).jsonText
        #expect(schema.contains(#""minItems":3"#))
    }

    @Test func aCardThatCollapsedIntoRepetitionIsDropped() async throws {
        let loop = Array(repeating: "the fibrin filaments,", count: 20).joined(separator: " ")
        let model = ScriptedModel([#"[{"front":"ER","back":"\#(loop)"},{"front":"ATP","back":"The energy currency of the cell."}]"#, "[]"])
        let events = try await run(DeckGenerator(client: model).generate(from: notes, instructions: []))
        #expect(cards(events).map(\.front) == ["ATP"])

        let prose = ModelCard(front: "osmosis", back: """
            Osmosis is the net movement of water molecules through a selectively permeable membrane \
            from a region of lower solute concentration to a region of higher solute concentration, \
            which equalises the concentrations on both sides.
            """)
        #expect(!DeckGenerator.isDegenerate(prose))
    }

    @Test func requestsCarryLengthCapsAndATokenBudget() async throws {
        let model = ScriptedModel([#"[{"front":"a","back":"b"}]"#, "[]"])
        _ = try await run(DeckGenerator(client: model).generate(from: notes, instructions: []))
        let request = try #require(model.requests.first)
        #expect(request.maxTokens == DeckGenerator.tokenBudget(cards: Prompt.targetCardCount("Mitochondria make ATP.")))
        #expect(request.repeatPenalty == 1.1)
        let schema = try #require(request.schema).jsonText
        #expect(schema.contains(#""back":{"type":"string","minLength":1,"maxLength":500}"#))
    }

    /// llama.cpp writes keys in schema order; a model made to write the back first swaps the faces.
    @Test func theSchemaAsksForTheFrontBeforeTheBack() throws {
        let schema = Prompt.cardSchema(sections: ["Cells"], withIDs: true)
        let item = try #require(schema["properties"]?["cards"]?["items"])
        guard case .object(let fields)? = item["properties"] else { Issue.record("no properties"); return }
        #expect(fields.map(\.key) == ["id", "front", "back", "tag", "example", "exampleNote", "section"])
        #expect(item["required"] == .array(["id", "front", "back", "tag", "example", "exampleNote", "section"]))
    }

    @Test func revisionCardsAreListedFrontFirst() {
        let prompt = Prompt.revision([("c1", GeneratedCard(front: "f", back: "b"))], request: "r",
                                     instructions: [], source: nil).last!.content
        #expect(prompt.contains(#"{"id":"c1","front":"f","back":"b","tag":"","example":"","exampleNote":""}"#))
    }

    @Test func eachChunkIsItsOwnRequest() async throws {
        let long = (1...3).map { "## Part \($0)\n" + Array(repeating: "fact", count: 400).joined(separator: " ") }
            .joined(separator: "\n")
        let outline = MarkdownOutline(markdown: long, fallbackTitle: "f")
        let model = ScriptedModel((1...3).map { #"[{"front":"f\#($0)","back":"b"}]"# })
        let events = try await run(DeckGenerator(client: model, chunkTokens: 200).generate(from: outline, instructions: []))

        let starts = events.compactMap { event -> Int? in
            if case .chunkStarted(let index, _, _) = event { return index } else { return nil }
        }
        #expect(model.requests.count == starts.count)
        #expect(starts == Array(0..<starts.count))
        #expect(cards(events).count == 3)
    }

    @Test func aLoopingModelsRepeatsAreDropped() async throws {
        let model = ScriptedModel([#"[{"front":"ATP","back":"x"},{"front":"atp","back":"y"},{"front":"ADP","back":"z"}]"#, "[]"])
        let events = try await run(DeckGenerator(client: model).generate(from: notes, instructions: []))
        #expect(cards(events).map(\.front) == ["ATP", "ADP"])
    }

    @Test func aReplyWithNoCardsIsAnError() async throws {
        let model = ScriptedModel(["I can't help with that.", "Nor that."])
        await #expect(throws: GenerationError.noCards) {
            try await run(DeckGenerator(client: model).generate(from: notes, instructions: []))
        }
    }

    @Test func emptyNotesAreAnError() async throws {
        let model = ScriptedModel([])
        await #expect(throws: GenerationError.emptyNotes) {
            try await run(DeckGenerator(client: model).generate(
                from: MarkdownOutline(markdown: "# Only a title", fallbackTitle: "f"), instructions: []))
        }
        #expect(model.requests.isEmpty)
    }

    @Test func cardsArrivedBeforeAFailureAreKept() async throws {
        let model = ScriptedModel([#"[{"front":"a","back":"b"},{"front":"c""#])
        model.failure = LLMError.unreachable("127.0.0.1:1234")
        var seen: [GeneratedCard] = []
        await #expect(throws: LLMError.unreachable("127.0.0.1:1234")) {
            for try await event in DeckGenerator(client: model).generate(from: notes, instructions: []) {
                if case .card(let card) = event { seen.append(card) }
            }
        }
        #expect(seen.map(\.front) == ["a"])
    }

    @Test func aRevisionKeepsIdentityAndSection() async throws {
        let osmosis = GeneratedCard(front: "osmosis", back: "water moves", section: "Cells")
        let atp = GeneratedCard(front: "ATP", back: "energy", section: "Energy")
        let model = ScriptedModel([#"""
            {"cards":[{"id":"c2","front":"ATP","back":"能量货币","tag":"","example":"","exampleNote":""},
                      {"id":"c1","front":"osmosis","back":"水的扩散","tag":"","example":"","exampleNote":""}]}
            """#])
        let events = try await run(DeckGenerator(client: model).revise(
            [osmosis, atp], request: "Translate the backs into Chinese", instructions: ["Keep it short"]))

        let revised = events.compactMap { event -> GeneratedCard? in
            if case .revised(let card) = event { return card } else { return nil }
        }
        #expect(revised.map(\.id) == [atp.id, osmosis.id])
        #expect(revised.map(\.back) == ["能量货币", "水的扩散"])
        #expect(revised.map(\.section) == ["Energy", "Cells"])

        let prompt = try #require(model.requests.first?.messages.last?.content)
        #expect(prompt.hasPrefix("The request: Translate the backs into Chinese"))
        #expect(prompt.hasSuffix("Rewrite each of the 2 cards above so that it follows the request: Translate the backs into Chinese"))
        #expect(prompt.contains(#""id":"c1""#) && prompt.contains("1. Keep it short"))
    }

    @Test func aRevisionCanAddACard() async throws {
        let card = GeneratedCard(front: "osmosis", back: "water moves", section: "Cells")
        let model = ScriptedModel([#"[{"id":"c1","front":"osmosis","back":"b"},{"id":"c9","front":"diffusion","back":"d"}]"#])
        let events = try await run(DeckGenerator(client: model).revise([card], request: "add a related card",
                                                                       instructions: []))
        #expect(cards(events).map(\.front) == ["diffusion"])
        #expect(cards(events).first?.section == "Cells")
    }

    @Test func revisionsAreBatched() async throws {
        let many = (1...25).map { GeneratedCard(front: "w\($0)", back: "b") }
        let model = ScriptedModel(Array(repeating: #"[{"id":"c1","front":"x","back":"y"}]"#, count: 3))
        _ = try await run(DeckGenerator(client: model, revisionBatch: 10).revise(many, request: "r", instructions: []))
        #expect(model.requests.count == 3)
    }

    @Test func theSourceNotesAreIncludedForASingleCard() async throws {
        let model = ScriptedModel([#"[{"id":"c1","front":"a","back":"b"}]"#])
        _ = try await run(DeckGenerator(client: model).revise([GeneratedCard(front: "a", back: "b")],
                                                              request: "more detail", instructions: [],
                                                              source: "The original paragraph."))
        #expect(model.requests.first?.messages.last?.content.contains("<notes>\nThe original paragraph.\n</notes>") == true)
    }
}
