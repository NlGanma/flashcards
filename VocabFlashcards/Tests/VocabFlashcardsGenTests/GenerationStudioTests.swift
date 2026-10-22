import Foundation
import Testing
@testable import VocabFlashcards
import VocabKit

/// A model server that plays back canned replies. `hang` makes a reply stop after its
/// first card and wait, so cancelling can be tested.
final class FakeServer: ModelServer, @unchecked Sendable {
    private let lock = NSLock()
    var models: [String]?
    var replies: [String]
    var hang = false
    private(set) var requests: [ChatRequest] = []

    init(models: [String]? = ["qwen2.5-7b-instruct"], replies: [String] = []) {
        self.models = models
        self.replies = replies
    }

    func models(timeout: TimeInterval) async throws -> [String] {
        guard let models else { throw LLMError.unreachable("127.0.0.1:1234") }
        return models
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<String, Error> {
        lock.lock()
        requests.append(request)
        let reply = replies.isEmpty ? "[]" : replies.removeFirst()
        let hang = self.hang
        lock.unlock()
        return AsyncThrowingStream { continuation in
            let task = Task {
                if hang, let cut = reply.range(of: "},")?.lowerBound {
                    continuation.yield(String(reply[...cut]))
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    continuation.finish()
                    return
                }
                continuation.yield(reply)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@Suite("Generation studio")
@MainActor
struct GenerationStudioTests {

    static let notes = """
        # Cell Biology
        ## Organelles
        The mitochondrion produces ATP. Ribosomes build proteins.
        ## Transport
        Osmosis moves water across a membrane.
        """

    private func makeStudio(_ server: FakeServer, discovered: [LLMServerDiscovery.Server] = [])
        -> (GenerationStudio, UserDefaults) {
        let defaults = UserDefaults(suiteName: "studio-\(UUID().uuidString)")!
        let services = StudioServices(makeServer: { _ in server }, discover: { discovered }, defaults: defaults)
        return (GenerationStudio(markdown: Self.notes, fileName: "bio.md", services: services), defaults)
    }

    private let organelles = #"[{"front":"mitochondrion","back":"Makes ATP."},{"front":"ribosome","back":"Builds proteins."}]"#
    private let transport = #"[{"front":"osmosis","back":"Water crossing a membrane."}]"#

    @Test func itGreetsWithWhatItRead() {
        let (studio, _) = makeStudio(FakeServer())
        #expect(studio.title == "Cell Biology")
        #expect(studio.messages.first?.text.hasPrefix("I read “bio.md”: 2 sections") == true)
        #expect(studio.sendTitle == "Generate")
        #expect(studio.canSend)   // an empty first message means "use the defaults"
    }

    @Test func theFirstMessageSaysWhatGoesOnTheBack() async throws {
        let server = FakeServer(replies: [organelles, transport])
        let (studio, _) = makeStudio(server)
        studio.draft = "Give a definition and an example sentence"
        studio.send()
        await studio.waitForWork()

        #expect(studio.cards.map(\.front) == ["mitochondrion", "ribosome", "osmosis"])
        #expect(studio.cards.map(\.section) == ["Organelles", "Organelles", "Transport"])
        #expect(studio.instructions == ["Give a definition and an example sentence"])
        #expect(studio.messages.last?.text.hasPrefix("Made 3 cards in 2 sets.") == true)
        #expect(studio.isWorking == false && studio.progress == nil)
        #expect(server.requests.first?.messages.last?.content.hasSuffix("1. Give a definition and an example sentence") == true)
        #expect(studio.endpoint.model == "qwen2.5-7b-instruct")
        #expect(studio.sendTitle == "Update All")
    }

    @Test func aLaterMessageRevisesEveryCardAndBecomesAnInstruction() async throws {
        let server = FakeServer(replies: [organelles, transport])
        let (studio, _) = makeStudio(server)
        studio.send()
        await studio.waitForWork()

        server.replies = [#"[{"id":"c1","front":"mitochondrion","back":"线粒体"},{"id":"c3","front":"osmosis","back":"渗透"}]"#]
        studio.draft = "Translate the backs into Chinese"
        studio.send()
        await studio.waitForWork()

        #expect(studio.cards.map(\.back) == ["线粒体", "Builds proteins.", "渗透"])
        #expect(studio.instructions == ["Translate the backs into Chinese"])
        #expect(studio.messages.last?.text == "Updated 2 of 3 cards.")
    }

    @Test func aMessageAboutOneCardChangesOnlyThatCard() async throws {
        let server = FakeServer(replies: [organelles, transport])
        let (studio, _) = makeStudio(server)
        studio.send()
        await studio.waitForWork()

        let ribosome = try #require(studio.cards.first { $0.front == "ribosome" })
        studio.toggleFocus(ribosome)
        #expect(studio.sendTitle == "Update Card")
        server.replies = [#"[{"id":"c1","front":"ribosome","back":"Reads mRNA to build proteins."}]"#]
        studio.draft = "Mention mRNA"
        studio.send()
        await studio.waitForWork()

        #expect(studio.cards.first { $0.id == ribosome.id }?.back == "Reads mRNA to build proteins.")
        #expect(studio.instructions.isEmpty)
        #expect(studio.messages.last { $0.role == .user }?.cardFront == "ribosome")
        #expect(studio.messages.last?.text == "Updated “ribosome”.")
        // The card's own section goes along as context.
        #expect(server.requests.last?.messages.last?.content.contains("The mitochondrion produces ATP.") == true)
    }

    @Test func withNoServerItSaysHowToStartOne() async {
        let (studio, _) = makeStudio(FakeServer(models: nil))
        studio.send()
        await studio.waitForWork()

        #expect(studio.cards.isEmpty)
        #expect(studio.messages.last?.role == .error)
        #expect(studio.messages.last?.text.contains("LM Studio") == true)
        if case .unreachable = studio.connection {} else { Issue.record("expected unreachable, got \(studio.connection)") }
    }

    @Test func itFallsBackToAServerItCanFind() async {
        let server = FakeServer(models: nil)
        let ollama = LLMServerDiscovery.Server(
            name: "Ollama", endpoint: LLMEndpoint(baseURL: URL(string: "http://127.0.0.1:11434/v1")!),
            models: ["llama3.1:8b"])
        let (studio, defaults) = makeStudio(server, discovered: [ollama])
        await studio.connect()

        #expect(studio.connection == .connected(server: "Ollama"))
        #expect(studio.endpoint == LLMEndpoint(baseURL: URL(string: "http://127.0.0.1:11434/v1")!, model: "llama3.1:8b"))
        #expect(defaults.string(forKey: "studio.model") == "llama3.1:8b")
    }

    @Test func stoppingKeepsTheCardsSoFar() async throws {
        let server = FakeServer(replies: [organelles, transport])
        server.hang = true
        let (studio, _) = makeStudio(server)
        studio.send()
        while studio.cards.isEmpty { await Task.yield() }
        studio.cancel()
        await studio.waitForWork()

        #expect(studio.cards.map(\.front) == ["mitochondrion"])
        #expect(studio.messages.last?.text == "Stopped. The cards so far are kept.")
        #expect(studio.isWorking == false)
    }

    @Test func savingAndReopeningKeepsCardsChatAndInstructions() async throws {
        let server = FakeServer(replies: [organelles, transport])
        let (studio, defaults) = makeStudio(server)
        studio.draft = "Keep it short"
        studio.send()
        await studio.waitForWork()
        #expect(studio.hasUnsavedChanges)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("studio-\(UUID().uuidString)")
        let url = try studio.save(in: directory)
        #expect(url.lastPathComponent == "Cell Biology.vfdeck")
        #expect(!studio.hasUnsavedChanges)

        let deck = try GeneratedDeck.read(from: url)
        let reopened = GenerationStudio(deck: deck, url: url,
                                        services: StudioServices(makeServer: { _ in server }, discover: { [] },
                                                                 defaults: defaults))
        #expect(reopened.cards == studio.cards)
        #expect(reopened.instructions == ["Keep it short"])
        #expect(reopened.messages.contains { $0.role == .user && $0.text == "Keep it short" })
        #expect(reopened.messages.last?.text.hasPrefix("Back to “Cell Biology” — 3 cards.") == true)
        #expect(reopened.markdown == Self.notes)
        // Saving again writes to the same file rather than a copy.
        #expect(try reopened.save(in: directory) == url)
    }

    @Test func deletingACardClearsItsFocus() async throws {
        let (studio, _) = makeStudio(FakeServer(replies: [organelles, transport]))
        studio.send()
        await studio.waitForWork()
        let first = try #require(studio.cards.first)
        studio.toggleFocus(first)
        studio.delete(first)
        #expect(studio.focusedCardID == nil)
        #expect(studio.cards.count == 2)
    }
}
