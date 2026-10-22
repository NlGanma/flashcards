import Foundation
import Testing
@testable import VocabKit

/// End-to-end against a real model server. Off by default; run with the server's API
/// root in VF_LIVE_LLM, e.g. `VF_LIVE_LLM=http://127.0.0.1:8080/v1 swift test --filter Live`.
@Suite("Live model", .serialized, .enabled(if: ProcessInfo.processInfo.environment["VF_LIVE_LLM"] != nil))
struct LiveModelTests {

    let endpoint: LLMEndpoint = {
        let raw = ProcessInfo.processInfo.environment["VF_LIVE_LLM"] ?? ""
        return LLMEndpoint(baseURL: LLMEndpoint.baseURL(from: raw) ?? LLMEndpoint.lmStudio.baseURL,
                           model: ProcessInfo.processInfo.environment["VF_LIVE_MODEL"] ?? "")
    }()

    static let notes = """
        # Cell Biology

        ## Organelles
        The mitochondrion produces ATP through cellular respiration. Ribosomes build proteins
        by translating messenger RNA. The nucleus stores the cell's DNA.

        ## Transport
        Osmosis is the diffusion of water across a semipermeable membrane. Active transport
        moves molecules against their concentration gradient and requires ATP.
        """

    @Test func generatesCardsThenRevisesOne() async throws {
        let client = LocalLLMClient(endpoint: endpoint)
        let generator = DeckGenerator(client: client)
        let outline = MarkdownOutline(markdown: Self.notes, fallbackTitle: "bio")

        var cards: [GeneratedCard] = []
        let started = Date()
        for try await event in generator.generate(from: outline, instructions: [
            "On the back, give a one-sentence definition, then add an example sentence using the term."
        ]) {
            if case .card(let card) = event {
                cards.append(card)
                print("card \(cards.count) after \(Int(Date().timeIntervalSince(started)))s:",
                      card.front, "→", card.back, "| tag:", card.tag, "| ex:", card.example, "| §", card.section)
            }
        }
        #expect(cards.count >= 3)
        #expect(Set(cards.map(\.section)) == ["Organelles", "Transport"])

        let target = try #require(cards.first)
        var revised: [GeneratedCard] = []
        for try await event in generator.revise([target], request: "Translate the back into Chinese.",
                                                instructions: [], source: outline.sections.first?.body) {
            if case .revised(let card) = event { revised.append(card) }
        }
        // Whether the text actually changed is up to the model; print it for a human to judge.
        print("revised:", revised.map { "\($0.front) → \($0.back)" })
        #expect(revised.first?.id == target.id)
        #expect(revised.first?.section == target.section)
    }
}
