import SwiftUI
import UniformTypeIdentifiers
import VocabKit

/// The app's central coordinator: owns the loaded file, selection, study session, and
/// navigation between the empty / setup / study / summary screens. All mutation happens
/// on the main actor so `@Published` updates drive the UI safely.
@MainActor
final class AppState: ObservableObject {

    enum Route: Equatable { case empty, setup, study, summary }

    // Navigation
    @Published var route: Route = .empty

    // Loaded content
    @Published var loadedFile: LoadedFile?
    @Published var selectedSetIDs: Set<UUID> = []

    // Study
    @Published var session: StudySession?
    @Published var lastSummary: RoundSummary?
    /// The chosen known-word filter — persisted so the user's preferred mode is the
    /// default across launches instead of resetting every time.
    @Published var pendingFilter: KnownFilter = .excludeKnown {
        didSet { UserDefaults.standard.set(pendingFilter.rawValue, forKey: Self.filterKey) }
    }
    private static let filterKey = "pendingFilter"

    // Sheets & transient messages
    @Published var showingKnownWords = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published var isLoading = false

    // Subtle feedback flag for "just marked known" flourish.
    @Published var lastMarkedKnownID: String?
    private var knownFlashToken = UUID()

    // Direction of the last navigation, so cards slide in from the correct side:
    // forward (next) → in from the right; backward (previous) → in from the left.
    @Published var navigatingForward: Bool = true

    let knownStore: KnownWordsStore
    private let recentStore: RecentFileStore
    private let parser = XLSXVocabParser()
    private let deckBuilder = DeckBuilder()

    init(knownStore: KnownWordsStore = KnownWordsStore(),
         recentStore: RecentFileStore = RecentFileStore()) {
        self.knownStore = knownStore
        self.recentStore = recentStore
        if let raw = UserDefaults.standard.string(forKey: Self.filterKey),
           let saved = KnownFilter(rawValue: raw) {
            pendingFilter = saved
        }
    }

    // MARK: - Bootstrap / file loading

    /// Auto-load the most recently used file, if any is still reachable.
    func bootstrap() {
        if let url = recentStore.resolve() {
            loadFile(at: url, remember: true)
        } else if recentStore.hasRemembered {
            recentStore.clear()
            errorMessage = "Your last file couldn't be found. Please upload it again."
            route = .empty
        } else {
            route = .empty
        }
    }

    func loadFile(at url: URL, remember: Bool) {
        errorMessage = nil
        infoMessage = nil

        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        do {
            let file = try parser.parse(fileURL: url)
            resetKnownFlash()
            withAnimation(Motion.gentleSpring) {
                self.loadedFile = file
                self.selectedSetIDs = Set(file.sets.map(\.id))   // select all by default
                self.session = nil
                self.lastSummary = nil
                self.route = .setup
            }
            if remember { recentStore.save(url: url) }
        } catch let error as VocabError {
            handle(error, url: url)
        } catch {
            errorMessage = "Something went wrong reading that file. Please try another."
            if loadedFile == nil { route = .empty }
        }
    }

    private func handle(_ error: VocabError, url: URL) {
        errorMessage = error.friendlyMessage
        if case .cannotAccess = error { recentStore.clear() }
        // Keep any previously loaded file; otherwise fall back to the empty state.
        if loadedFile == nil { route = .empty }
    }

    /// Present a native open panel to pick a new .xlsx file.
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.prompt = "Open"
        panel.message = "Choose an Excel (.xlsx) vocabulary file"
        var types: [UTType] = []
        if let xlsx = UTType(filenameExtension: "xlsx") { types.append(xlsx) }
        types.append(.spreadsheet)
        panel.allowedContentTypes = types
        if panel.runModal() == .OK, let url = panel.url {
            loadFile(at: url, remember: true)
        }
    }

    /// Handle a dropped file URL (from drag & drop).
    func handleDrop(url: URL) {
        loadFile(at: url, remember: true)
    }

    // MARK: - Set selection

    var selectedSets: [PracticeSet] {
        guard let file = loadedFile else { return [] }
        return file.sets.filter { selectedSetIDs.contains($0.id) }
    }

    var hasSelection: Bool { !selectedSetIDs.isEmpty }

    func toggleSet(_ id: UUID) {
        if selectedSetIDs.contains(id) { selectedSetIDs.remove(id) }
        else { selectedSetIDs.insert(id) }
    }

    func selectAllSets() {
        guard let file = loadedFile else { return }
        selectedSetIDs = Set(file.sets.map(\.id))
    }

    func selectNoSets() { selectedSetIDs.removeAll() }

    /// Count of distinct words in the current selection (for the setup summary line).
    func selectedUniqueWordCount() -> Int {
        Set(selectedSets.flatMap { $0.items.map(\.key) }).count
    }

    // MARK: - Study flow

    /// Number of cards a given filter would produce for the current selection — powers
    /// the inline mode picker on the setup screen.
    func deckCount(for filter: KnownFilter) -> Int {
        deckBuilder.buildOrdered(from: selectedSets, filter: filter,
                                 knownKeys: knownStore.knownKeys).count
    }

    /// Start a run immediately with the current selection and the chosen filter.
    func startStudy(filter: KnownFilter) {
        pendingFilter = filter
        let deck = deckBuilder.build(from: selectedSets, filter: filter,
                                     knownKeys: knownStore.knownKeys)
        guard !deck.isEmpty else {
            infoMessage = emptyDeckMessage(for: filter)
            return
        }
        let newSession = StudySession(cards: deck, filter: filter,
                                      selectedSetNames: selectedSets.map(\.name), roundNumber: 1,
                                      initialKnownKeys: knownStore.knownKeys)
        infoMessage = nil
        resetKnownFlash()
        withAnimation(Motion.gentleSpring) {
            self.session = newSession
            self.lastSummary = nil
            self.route = .study
        }
    }

    private func emptyDeckMessage(for filter: KnownFilter) -> String {
        switch filter {
        case .excludeKnown:
            return "You've already marked every selected word as known. Try “Study Everything” or choose more sets."
        case .onlyKnown:
            return "None of the selected words are marked known yet. Study them first!"
        case .includeKnown:
            return "The selected sets don't contain any words."
        }
    }

    // MARK: - In-study actions

    func flip() {
        Haptics.light()
        withAnimation(Motion.flip) { session?.flip() }
    }

    func markCurrentKnown() {
        guard let card = session?.currentCard else { return }
        session?.markCurrentKnown()
        knownStore.markKnown(key: card.key, display: card.word)
        Haptics.mark()
        let key = card.key
        let token = UUID()
        knownFlashToken = token
        withAnimation(Motion.pop) { lastMarkedKnownID = key }
        // Auto-clear the celebration flag after it has ridden out with the card.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            if self?.knownFlashToken == token { self?.lastMarkedKnownID = nil }
        }
    }

    /// Card-level classification is symmetric: update both sources of truth, then
    /// continue so the same card never appears to undo the user's choice.
    func unmarkCurrentKnown() {
        guard let card = session?.currentCard else { return }
        unmarkKnown(key: card.key)
        advance()
    }

    /// Manager-level removal synchronizes an active/completed session without navigating.
    func unmarkKnown(key: String) {
        session?.unmarkKnown(key: key)
        knownStore.remove(key: key)
        if lastMarkedKnownID == key { resetKnownFlash() }
        refreshSummaryIfNeeded()
    }

    func clearKnownWords() {
        session?.unmarkAllKnown()
        knownStore.removeAll()
        resetKnownFlash()
        refreshSummaryIfNeeded()
    }

    /// Space/Enter behaviour: reveal the back, or advance if already revealed.
    func primaryAction() {
        guard let session else { return }
        if session.isShowingBack {
            advance()
        } else {
            flip()
        }
    }

    func advance() {
        guard let session else { return }
        if session.hasNext {
            navigatingForward = true
            // Snap the flip to the front BEFORE the slide (outside withAnimation) so the
            // outgoing card doesn't visibly flip back — it just slides away on English.
            session.isShowingBack = false
            // Don't clear lastMarkedKnownID here: the just-marked card keeps its
            // celebration flourish as it slides out (the flag self-clears shortly after).
            withAnimation(Motion.spring) { _ = session.goNext() }
        } else {
            finishRound()
        }
    }

    func goPrevious() {
        guard let session, session.hasPrevious else { return }
        resetKnownFlash()
        navigatingForward = false
        session.isShowingBack = false            // instantly show English — no flip-back
        withAnimation(Motion.spring) { session.goPrevious() }
    }

    func markKnownAndAdvance() {
        markCurrentKnown()
        // Advance immediately — the flourish rides the outgoing card's slide-out, so the
        // next card is never held hostage by a timer.
        advance()
    }

    /// K key mirrors the visible card action: classify, persist, and continue.
    func toggleCurrentKnown() {
        guard let session else { return }
        if session.isCurrentKnown {
            unmarkCurrentKnown()
        } else {
            markKnownAndAdvance()
        }
    }

    /// Finish the current round now (also invoked by Escape) — lands on the summary with
    /// whatever progress was made, rather than discarding it.
    func finishRound() {
        guard let session else { return }
        let summary = session.makeSummary()
        Haptics.mark()
        resetKnownFlash()
        withAnimation(Motion.gentleSpring) {
            self.lastSummary = summary
            self.route = .summary
        }
    }

    // MARK: - Summary actions

    /// One-tap continue: replay the unmarked words if any remain, otherwise restart the
    /// whole selection with the same filter. No modal.
    func studyAgain() {
        guard let session else { return }
        let nextCards = (session.remainingCards.isEmpty ? session.cards : session.remainingCards).shuffled()
        guard !nextCards.isEmpty else { return }
        let next = StudySession(cards: nextCards, filter: session.filter,
                                selectedSetNames: session.selectedSetNames,
                                roundNumber: session.roundNumber + 1,
                                initialKnownKeys: knownStore.knownKeys)
        resetKnownFlash()
        withAnimation(Motion.gentleSpring) {
            self.session = next
            self.lastSummary = nil
            self.route = .study
        }
    }

    var summaryHasRemaining: Bool { lastSummary?.hasRemaining ?? false }

    func backToSetup() {
        resetKnownFlash()
        withAnimation(Motion.gentleSpring) {
            self.session = nil
            self.lastSummary = nil
            self.route = .setup
        }
    }

    // MARK: - File replacement

    func changeFile() {
        presentOpenPanel()
    }

    func resetToEmpty() {
        recentStore.clear()
        resetKnownFlash()
        withAnimation(Motion.gentleSpring) {
            self.loadedFile = nil
            self.selectedSetIDs = []
            self.session = nil
            self.lastSummary = nil
            self.errorMessage = nil
            self.route = .empty
        }
    }

    private func refreshSummaryIfNeeded() {
        guard route == .summary, let session else { return }
        lastSummary = session.makeSummary()
    }

    private func resetKnownFlash() {
        knownFlashToken = UUID()
        lastMarkedKnownID = nil
    }
}
