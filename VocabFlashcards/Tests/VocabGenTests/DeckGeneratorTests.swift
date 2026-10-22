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
        let model = ScriptedModel([#"""
            {"cards":[{"front":"mitochondria","back":"Make ATP.","tag":"organelle","example":"","exampleNote":"","section":"Cells"},
                      {"front":"DNA","back":"Stores genes.","tag":"molecule","example":"","exampleNote":"","section":"genes"}]}
            """#])
        let events = try await run(DeckGenerator(client: model).generate(from: notes, instructions: []))

        #expect(events.first == .chunkStarted(index: 0, count: 1, sections: ["Cells", "Genes"]))
        #expect(cards(events).map(\.front) == ["mitochondria", "DNA"])
        // A paraphrased section still lands in the right set.
        #expect(cards(events).map(\.section) == ["Cells", "Genes"])
    }

    @Test func theChatInstructionsReachThePromptInOrder() async throws {
        let model = ScriptedModel([#"[{"front":"a","back":"b"}]"#])
        _ = try await run(DeckGenerator(client: model).generate(
            from: notes, instructions: ["Put the Chinese translation on the back", "  ", "Add an example sentence"]))

        let prompt = try #require(model.requests.first?.messages.last?.content)
        #expect(prompt.contains("1. Put the Chinese translation on the back\n2. Add an example sentence"))
        #expect(prompt.contains("Mitochondria make ATP."))
        #expect(prompt.contains(#"Sections in this excerpt: "Cells", "Genes""#))
        #expect(model.requests.first?.messages.first?.role == .system)
    }

    @Test func theSchemaPinsSectionsToTheChunk() throws {
        let schema = Prompt.cardSchema(sections: ["Cells", "Genes"], withIDs: false)
        let data = try JSONEncoder().encode(schema)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains(#""enum":["Cells","Genes"]"#))
        #expect(text.contains(#""maxItems":40"#))
        #expect(!text.contains(#""id""#))
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
        let model = ScriptedModel([#"[{"front":"ATP","back":"x"},{"front":"atp","back":"y"},{"front":"ADP","back":"z"}]"#])
        let events = try await run(DeckGenerator(client: model).generate(from: notes, instructions: []))
        #expect(cards(events).map(\.front) == ["ATP", "ADP"])
    }

    @Test func aReplyWithNoCardsIsAnError() async throws {
        let model = ScriptedModel(["I can't help with that."])
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
        #expect(prompt.contains("The request: Translate the backs into Chinese"))
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
        #expect(model.requests.first?.messages.last?.content.contains("<<<\nThe original paragraph.\n>>>") == true)
    }
}
