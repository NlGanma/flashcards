import Foundation
import Combine
import VocabKit

/// A model server the studio can talk to: it lists its models and streams replies.
protocol ModelServer: ChatStreaming {
    func models(timeout: TimeInterval) async throws -> [String]
}

extension LocalLLMClient: ModelServer {}

/// Everything the studio reaches outside itself for, so tests can swap in a fake model.
struct StudioServices {
    var makeServer: (LLMEndpoint) -> ModelServer
    var discover: () async -> [LLMServerDiscovery.Server]
    var defaults: UserDefaults
    /// Where new decks are saved.
    var decksDirectory: URL = GeneratedDeck.defaultDirectory()

    static let live = StudioServices(
        makeServer: { LocalLLMClient(endpoint: $0) },
        discover: { await LLMServerDiscovery.discover() },
        defaults: .standard)
}

/// The Markdown-to-flashcards workspace: the notes, the cards the model has written so
/// far, and the chat that steers it. The first message says what belongs on the back of
/// every card; later ones refine all the cards, or just the one the learner picked.
@MainActor
final class GenerationStudio: ObservableObject {

    struct Message: Identifiable, Equatable {
        enum Role: Equatable { case user, assistant, error }
        let id = UUID()
        var role: Role
        var text: String
        /// The card a user message was about, when it was about one card.
        var cardFront: String?
    }

    struct Progress: Equatable {
        var step: Int
        var total: Int
        var label: String
    }

    enum Connection: Equatable {
        case unknown
        case checking
        case connected(server: String)
        case unreachable(String)
    }

    // MARK: Source

    let title: String
    let sourceFileName: String
    let markdown: String
    let outline: MarkdownOutline
    /// Where the deck is saved; nil until the first save.
    private(set) var deckURL: URL?
    private let createdAt: Date

    // MARK: State

    @Published private(set) var cards: [GeneratedCard]
    @Published private(set) var messages: [Message]
    /// Every message addressed to all cards, in order: what the back of a card should say.
    @Published private(set) var instructions: [String]
    @Published var draft = ""
    /// The card the next message is about. Nil means all of them.
    @Published var focusedCardID: UUID?
    @Published private(set) var progress: Progress?
    @Published private(set) var isWorking = false
    /// The id of the card the model most recently wrote or rewrote — the preview scrolls to it.
    @Published private(set) var lastTouchedCardID: UUID?

    // MARK: Model server

    @Published var endpoint: LLMEndpoint {
        didSet { saveEndpoint() }
    }
    @Published private(set) var connection: Connection = .unknown
    @Published private(set) var availableModels: [String] = []
    @Published private(set) var discoveredServers: [LLMServerDiscovery.Server] = []

    private let services: StudioServices
    private var work: Task<Void, Never>?
    private var savedSnapshot: [GeneratedCard]

    private static let urlKey = "studio.serverURL"
    private static let modelKey = "studio.model"

    // MARK: - Init

    /// A new studio on Markdown notes.
    init(markdown: String, fileName: String, services: StudioServices = .live) {
        let fallback = (fileName as NSString).deletingPathExtension
        let outline = MarkdownOutline(markdown: markdown, fallbackTitle: fallback.isEmpty ? "Notes" : fallback)
        self.title = outline.title
        self.sourceFileName = fileName
        self.markdown = markdown
        self.outline = outline
        self.createdAt = Date()
        self.cards = []
        self.instructions = []
        self.savedSnapshot = []
        self.services = services
        self.endpoint = Self.savedEndpoint(in: services.defaults)
        let words = markdown.split(whereSeparator: \.isWhitespace).count
        let sectionCount = outline.sections.count
        self.messages = [Message(role: .assistant, text: """
            I read “\(fileName)”: \(sectionCount) section\(sectionCount == 1 ? "" : "s"), \
            about \(words.formatted()) words. Tell me what you want on the back of each card — a \
            definition, a translation, an example sentence, a question to answer — or press \
            Generate for short definitions.
            """)]
    }

    /// Reopen a saved deck to keep refining it.
    init(deck: GeneratedDeck, url: URL, services: StudioServices = .live) {
        self.title = deck.title
        self.sourceFileName = deck.sourceFileName
        self.markdown = deck.sourceMarkdown
        self.outline = MarkdownOutline(markdown: deck.sourceMarkdown, fallbackTitle: deck.title)
        self.deckURL = url
        self.createdAt = deck.createdAt
        self.cards = deck.cards
        self.instructions = deck.instructions
        self.savedSnapshot = deck.cards
        self.services = services
        self.endpoint = Self.savedEndpoint(in: services.defaults)
        var messages = deck.chat.map {
            Message(role: $0.role == .user ? .user : .assistant, text: $0.text, cardFront: $0.cardFront)
        }
        messages.append(Message(role: .assistant, text: """
            Back to “\(deck.title)” — \(deck.cards.count) card\(deck.cards.count == 1 ? "" : "s"). \
            Pick a card to change just that one, or tell me what to change on all of them.
            """))
        self.messages = messages
    }

    // MARK: - Derived

    var focusedCard: GeneratedCard? {
        focusedCardID.flatMap { id in cards.first { $0.id == id } }
    }

    var hasUnsavedChanges: Bool { cards != savedSnapshot }

    var sectionCount: Int { Set(cards.map(\.section)).count }

    /// What pressing Send (or Return) will do, for its label.
    var sendTitle: String {
        if cards.isEmpty { return "Generate" }
        return focusedCard == nil ? "Update All" : "Update Card"
    }

    var canSend: Bool {
        guard !isWorking else { return false }
        // With no cards yet an empty message is fine: it means "use the defaults".
        return cards.isEmpty || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Connecting

    /// Find a server: the saved address first, then (unless the learner just typed one)
    /// each runner's default port. Picks a model when none is chosen or the chosen one is gone.
    func connect(discovering: Bool = true) async {
        connection = .checking
        if await use(endpoint, name: nil) { return }
        guard discovering else {
            availableModels = []
            connection = .unreachable(LLMError.unreachable(Self.address(of: endpoint)).localizedDescription)
            return
        }
        let found = await services.discover()
        discoveredServers = found
        if let first = found.first, await use(first.endpoint, name: first.name, models: first.models) {
            return
        }
        availableModels = []
        connection = .unreachable(LLMError.unreachable(Self.address(of: endpoint)).localizedDescription)
    }

    /// Switch to a server picked from the list or typed in.
    func choose(_ server: LLMServerDiscovery.Server) {
        Task { _ = await use(server.endpoint, name: server.name, models: server.models) }
    }

    private func use(_ candidate: LLMEndpoint, name: String?, models known: [String]? = nil) async -> Bool {
        let models: [String]
        if let known {
            models = known
        } else {
            guard let listed = try? await services.makeServer(candidate).models(timeout: 3) else { return false }
            models = listed
        }
        var chosen = candidate
        if chosen.model.isEmpty || !models.contains(chosen.model) {
            // Keep the learner's choice when this server still offers it.
            chosen.model = models.contains(endpoint.model) ? endpoint.model : (models.first ?? "")
        }
        endpoint = chosen
        availableModels = models
        let label = name ?? Self.knownName(for: chosen.baseURL) ?? Self.address(of: chosen)
        connection = .connected(server: label)
        return true
    }

    // MARK: - Chatting

    /// Send the draft: generate the first cards, or apply it to all cards or the picked one.
    func send() {
        guard canSend else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""

        if cards.isEmpty {
            if !text.isEmpty {
                instructions.append(text)
                messages.append(Message(role: .user, text: text))
            }
            generate(fresh: false)
        } else if let card = focusedCard {
            messages.append(Message(role: .user, text: text, cardFront: card.front))
            revise([card], request: text, source: sourceText(for: card))
        } else {
            instructions.append(text)
            messages.append(Message(role: .user, text: text))
            revise(cards, request: text, source: nil)
        }
    }

    /// Throw the cards away and write them again from the notes, with every instruction so far.
    func startOver() {
        guard !isWorking else { return }
        focusedCardID = nil
        generate(fresh: true)
    }

    func cancel() {
        work?.cancel()
    }

    /// Wait for the current model job, if any, to finish.
    func waitForWork() async {
        await work?.value
    }

    func delete(_ card: GeneratedCard) {
        guard !isWorking else { return }
        cards.removeAll { $0.id == card.id }
        if focusedCardID == card.id { focusedCardID = nil }
    }

    func toggleFocus(_ card: GeneratedCard) {
        guard !isWorking else { return }
        focusedCardID = focusedCardID == card.id ? nil : card.id
    }

    private func generate(fresh: Bool) {
        let instructions = self.instructions
        run(intro: fresh ? "Starting over from the notes." : nil) { generator in
            if fresh { self.cards = [] }
            var made = 0
            for try await event in generator.generate(from: self.outline, instructions: instructions) {
                switch event {
                case .chunkStarted(let index, let count, let sections):
                    self.progress = Progress(step: index + 1, total: count,
                                             label: sections.first.map { "Reading “\($0)”" } ?? "Reading")
                case .card(let card):
                    made += 1
                    self.cards.append(card)
                    self.lastTouchedCardID = card.id
                case .revised:
                    break
                }
            }
            let sets = Set(self.cards.map(\.section)).count
            return "Made \(made) card\(made == 1 ? "" : "s") in \(sets) set\(sets == 1 ? "" : "s"). "
                + "Pick a card to change just that one, or tell me what to change on all of them."
        }
    }

    private func revise(_ targets: [GeneratedCard], request: String, source: String?) {
        let instructions = self.instructions
        let single = targets.count == 1 ? targets.first : nil
        run(intro: nil) { generator in
            var changed = 0
            var added = 0
            for try await event in generator.revise(targets, request: request,
                                                    instructions: instructions, source: source) {
                switch event {
                case .chunkStarted(let index, let count, _):
                    self.progress = Progress(step: index + 1, total: count,
                                             label: single.map { "Rewriting “\($0.front)”" } ?? "Rewriting cards")
                case .revised(let card):
                    guard let index = self.cards.firstIndex(where: { $0.id == card.id }) else { continue }
                    if self.cards[index] != card { changed += 1 }
                    self.cards[index] = card
                    self.lastTouchedCardID = card.id
                case .card(let card):
                    added += 1
                    let anchor = single.flatMap { s in self.cards.firstIndex { $0.id == s.id } }
                    self.cards.insert(card, at: anchor.map { $0 + 1 } ?? self.cards.endIndex)
                    self.lastTouchedCardID = card.id
                }
            }
            var summary: String
            if let single {
                summary = changed > 0 ? "Updated “\(single.front)”." : "The model left “\(single.front)” as it was — try asking more specifically."
            } else {
                summary = changed > 0 ? "Updated \(changed) of \(targets.count) cards." : "The model didn't change any cards — try asking more specifically."
            }
            if added > 0 { summary += " Added \(added) new card\(added == 1 ? "" : "s")." }
            return summary
        }
    }

    /// Run one model job: connect if needed, report progress, and turn the outcome into a
    /// chat message. Cards that arrived before an error or a cancel are kept.
    private func run(intro: String?,
                     _ body: @escaping @MainActor (DeckGenerator) async throws -> String) {
        work?.cancel()
        isWorking = true
        progress = Progress(step: 0, total: 0, label: "Connecting to the model")
        if let intro { messages.append(Message(role: .assistant, text: intro)) }

        work = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isWorking = false
                self.progress = nil
                self.work = nil
            }
            if case .connected = self.connection {} else { await self.connect() }
            guard case .connected = self.connection else {
                self.messages.append(Message(role: .error, text: Self.noServerHelp))
                return
            }
            let generator = DeckGenerator(client: self.services.makeServer(self.endpoint))
            let stopped = Message(role: .assistant, text: "Stopped. The cards so far are kept.")
            do {
                let summary = try await body(generator)
                // A cancelled stream just ends, so a stopped job also arrives here.
                self.messages.append(Task.isCancelled ? stopped : Message(role: .assistant, text: summary))
            } catch {
                if Task.isCancelled || error is CancellationError {
                    self.messages.append(stopped)
                    return
                }
                if case LLMError.unreachable = error { self.connection = .unreachable(error.localizedDescription) }
                self.messages.append(Message(role: .error, text: error.localizedDescription))
            }
        }
    }

    static let noServerHelp = """
        I can't find a model server on this Mac. Start one, then press Send again:
        • LM Studio — load a model, then turn on the server in the Developer tab.
        • Ollama — run `ollama serve` and `ollama pull qwen2.5:7b`.
        • llama.cpp — run `llama-server -m model.gguf --port 8080`.
        An instruction-tuned model such as Qwen 2.5 7B Instruct or Llama 3.1 8B Instruct works best.
        """

    /// The notes behind a card, sent along when it is revised alone. Capped so a long
    /// section still fits a small context window next to the card.
    func sourceText(for card: GeneratedCard) -> String? {
        guard let section = outline.sections.first(where: { $0.title == card.section }) else { return nil }
        var text = section.body
        while MarkdownOutline.estimatedTokens(text) > 1200, !text.isEmpty {
            text = String(text.prefix(text.count * 3 / 4))
        }
        return text
    }

    // MARK: - Saving

    func makeDeck() -> GeneratedDeck {
        let chat = messages.compactMap { message -> GeneratedDeck.ChatEntry? in
            switch message.role {
            case .user: return .init(role: .user, text: message.text, cardFront: message.cardFront)
            case .assistant: return .init(role: .assistant, text: message.text)
            case .error: return nil
            }
        }
        return GeneratedDeck(title: title, sourceFileName: sourceFileName, sourceMarkdown: markdown,
                             instructions: instructions, chat: chat, cards: cards,
                             createdAt: createdAt, updatedAt: Date())
    }

    /// Write the deck where it was last saved, or to a new file named after it.
    @discardableResult
    func save(in directory: URL? = nil) throws -> URL {
        let url = deckURL ?? GeneratedDeck.newFileURL(title: title, in: directory ?? services.decksDirectory)
        try makeDeck().write(to: url)
        deckURL = url
        savedSnapshot = cards
        return url
    }

    /// Put the studio into a given state without a model, for SnapshotRenderer.
    func stage(cards: [GeneratedCard], messages: [Message]? = nil, progress: Progress? = nil,
               working: Bool = false, connection: Connection, models: [String] = [],
               focusedCardID: UUID? = nil, draft: String = "") {
        self.cards = cards
        if let messages { self.messages = messages }
        self.progress = progress
        self.isWorking = working
        self.connection = connection
        self.availableModels = models
        self.focusedCardID = focusedCardID
        self.lastTouchedCardID = working ? cards.last?.id : nil
        self.draft = draft
    }

    func reportSaveFailure(_ error: Error) {
        messages.append(Message(role: .error, text: "Couldn't save the deck: \(error.localizedDescription)"))
    }

    // MARK: - Endpoint memory

    private static func savedEndpoint(in defaults: UserDefaults) -> LLMEndpoint {
        guard let raw = defaults.string(forKey: urlKey), let url = URL(string: raw) else { return .lmStudio }
        return LLMEndpoint(baseURL: url, model: defaults.string(forKey: modelKey) ?? "")
    }

    private func saveEndpoint() {
        services.defaults.set(endpoint.baseURL.absoluteString, forKey: Self.urlKey)
        services.defaults.set(endpoint.model, forKey: Self.modelKey)
    }

    static func address(of endpoint: LLMEndpoint) -> String {
        let host = endpoint.baseURL.host ?? endpoint.baseURL.absoluteString
        return host + (endpoint.baseURL.port.map { ":\($0)" } ?? "")
    }

    static func knownName(for url: URL) -> String? {
        LLMServerDiscovery.knownServers.first { $0.url.port == url.port && $0.url.host == url.host }?.name
    }
}
