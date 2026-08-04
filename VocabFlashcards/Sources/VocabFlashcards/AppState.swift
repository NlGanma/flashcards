import SwiftUI
import Combine
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
    /// The card the editor is open on, if any.
    @Published var editingCard: Flashcard?
    /// Which bank the word manager opens on.
    @Published var knownWordsTab: WordBank = .known
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published var isLoading = false

    /// The two persistent banks a word can sit in. New words are in neither.
    enum WordBank: Hashable { case known, aside }

    // Subtle feedback flags for the "just marked" flourish — one per bank so the card
    // can glow in the matching color.
    @Published var lastMarkedKnownID: String?
    @Published var lastMarkedAsideID: String?
    private var knownFlashToken = UUID()

    // Direction of the last navigation, so cards slide in from the correct side:
    // forward (next) → in from the right; backward (previous) → in from the left.
    @Published var navigatingForward: Bool = true

    let knownStore: KnownWordsStore
    let editsStore: CardEditsStore
    private let recentStore: RecentFileStore
    private let parser = XLSXVocabParser()
    private let deckBuilder = DeckBuilder()
    /// Merges curated example sentences and the user's own card edits onto parsed cards.
    private let resolver: CardContentResolver
    private var storeObserver: AnyCancellable?

    init(knownStore: KnownWordsStore = KnownWordsStore(),
         recentStore: RecentFileStore = RecentFileStore(),
         editsStore: CardEditsStore = CardEditsStore(),
         contentBank: ContentBank = .bundled) {
        self.knownStore = knownStore
        self.recentStore = recentStore
        self.editsStore = editsStore
        self.resolver = CardContentResolver(bank: contentBank, edits: editsStore)
        if let raw = UserDefaults.standard.string(forKey: Self.filterKey),
           let saved = KnownFilter(rawValue: raw) {
            pendingFilter = saved
        }
        // Screens read their counts through `app.knownStore` but observe only AppState, so
        // a change to either bank has to be republished here — otherwise removing a single
        // word from the manager leaves every deck count behind it stale until some
        // unrelated AppState change happens to redraw them.
        storeObserver = knownStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
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
            // Repair display forms saved by older cleaning rules, now that we know how
            // every word in this file reads today. No-op once they agree.
            knownStore.reconcileDisplays(
                Dictionary(file.sets.flatMap { $0.items }.map { ($0.key, $0.english) },
                           uniquingKeysWith: { first, _ in first })
            )
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
        // Only forget the auto-load file when it is the one that just failed. Dropping an
        // unreadable workbook used to wipe the bookmark for the file still on screen, so
        // the next launch silently came up empty.
        if case .cannotAccess = error, recentStore.isRemembered(url) { recentStore.clear() }
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
                                 knownKeys: knownStore.knownKeys,
                                 asideKeys: knownStore.asideKeys).count
    }

    // MARK: - Card editing

    /// Open the editor on the card being studied (double-click, or ⌘E).
    func beginEditingCurrentCard() {
        guard isStudying, let card = session?.currentCard else { return }
        editingCard = card
    }

    /// Commit the editor's contents: remembered locally, and swapped into the running
    /// round so the change is visible the moment the sheet closes.
    func saveCardEdit(word: String, senses: [Sense]) {
        guard let card = editingCard else { return }
        let cleanSenses = senses.filter { !$0.definition.isEmpty || !$0.partOfSpeech.isEmpty }
        guard !cleanSenses.isEmpty else { return }
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = trimmed.isEmpty ? card.word : trimmed
        editsStore.save(CardEdit(word: display, senses: cleanSenses), for: card.key)
        session?.replaceCard(card.with(word: display, senses: cleanSenses))
        editingCard = nil
    }

    /// Throw the edit away and go back to the spreadsheet's own content.
    func revertCardEdit() {
        guard let card = editingCard else { return }
        editsStore.revert(key: card.key)
        if let original = curatedCard(for: card.key) { session?.replaceCard(original) }
        editingCard = nil
    }

    var editingCardIsEdited: Bool {
        guard let card = editingCard else { return false }
        return editsStore.hasEdit(for: card.key)
    }

    /// The card as the spreadsheet and the curated bank define it, with any user edit
    /// ignored — what "revert" restores, and what the editor shows as the original.
    func curatedCard(for key: String) -> Flashcard? {
        guard let file = loadedFile else { return nil }
        let raw = deckBuilder.buildOrdered(from: file.sets, filter: .includeKnown, knownKeys: [])
        guard let card = raw.first(where: { $0.key == key }) else { return nil }
        return resolver.curated(card)
    }

    /// Start a run immediately with the current selection and the chosen filter.
    func startStudy(filter: KnownFilter) {
        pendingFilter = filter
        let deck = deckBuilder.build(from: selectedSets, filter: filter,
                                     knownKeys: knownStore.knownKeys,
                                     asideKeys: knownStore.asideKeys,
                                     resolver: resolver)
        guard !deck.isEmpty else {
            infoMessage = emptyDeckMessage(for: filter)
            return
        }
        let newSession = StudySession(cards: deck, filter: filter,
                                      selectedSetNames: selectedSets.map(\.name), roundNumber: 1,
                                      initialKnownKeys: knownStore.knownKeys,
                                      initialAsideKeys: knownStore.asideKeys)
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
            if knownStore.asideCount > 0 {
                return "No new words left here. Try “Study Everything”, choose more sets, or revert your \(knownStore.asideCount) Almost Known word\(knownStore.asideCount == 1 ? "" : "s")."
            }
            return "You've already marked every selected word as known. Try “Study Everything” or choose more sets."
        case .onlyKnown:
            return "None of the selected words are marked known yet. Study them first!"
        case .includeKnown:
            return "The selected sets don't contain any words."
        }
    }

    // MARK: - In-study actions

    /// The round is over the moment we leave the study screen, but the session is kept
    /// alive so the summary can report on it. Every card-level action therefore has to ask
    /// whether it is still legal: the summary is built from a snapshot, so mutating a
    /// finished round silently desynchronizes what the user sees from what is stored — and
    /// `visitedKeys` would grow to include cards that were never actually shown.
    private var isStudying: Bool { route == .study && session != nil }

    func flip() {
        guard isStudying else { return }
        Haptics.light()
        withAnimation(Motion.flip) { session?.flip() }
    }

    /// S: open or close the example panel. The card slides left to make room for it.
    /// Pressed on the English side it reveals the definition too — asking to see the word
    /// in a sentence is asking to see the answer.
    func toggleSentence() {
        guard isStudying, let session else { return }
        Haptics.light()
        if session.isShowingBack {
            withAnimation(Motion.spring) { session.isShowingSentence.toggle() }
        } else {
            withAnimation(Motion.flip) { session.isShowingBack = true }
            withAnimation(Motion.spring) { session.isShowingSentence = true }
        }
    }

    func markCurrentKnown() {
        guard isStudying, let card = session?.currentCard else { return }
        session?.markCurrentKnown()
        knownStore.markKnown(key: card.key, display: card.word)
        Haptics.mark()
        flash(.known, key: card.key)
        refreshSummaryIfNeeded()
    }

    /// Park the current word in the temporary "Almost Known" bank: it leaves the New pool
    /// but never counts as known, and the whole bank can be reverted in one action.
    func markCurrentAside() {
        guard isStudying, let card = session?.currentCard,
              !knownStore.isKnown(card.key) else { return }
        session?.markCurrentAside()
        knownStore.markAside(key: card.key, display: card.word)
        Haptics.light()
        flash(.aside, key: card.key)
        refreshSummaryIfNeeded()
    }

    /// Shared "just marked" flourish. One token drives both banks, so a fresh mark always
    /// supersedes the previous card's glow.
    private func flash(_ bank: WordBank, key: String) {
        let token = UUID()
        knownFlashToken = token
        withAnimation(Motion.pop) {
            lastMarkedKnownID = bank == .known ? key : nil
            lastMarkedAsideID = bank == .aside ? key : nil
        }
        // Auto-clear the celebration flag after it has ridden out with the card.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            if self?.knownFlashToken == token { self?.resetKnownFlash() }
        }
    }

    /// Card-level classification is symmetric: update both sources of truth, then
    /// continue so the same card never appears to undo the user's choice.
    func unmarkCurrentKnown() {
        guard isStudying, let card = session?.currentCard else { return }
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

    /// Card-level un-park: back to New, then continue.
    func unmarkCurrentAside() {
        guard isStudying, let card = session?.currentCard else { return }
        unmarkAside(key: card.key)
        advance()
    }

    /// Send one word from the bank back to New.
    func unmarkAside(key: String) {
        session?.unmarkAside(key: key)
        knownStore.removeAside(key: key)
        if lastMarkedAsideID == key { resetKnownFlash() }
        refreshSummaryIfNeeded()
    }

    /// Open the word manager on a specific bank.
    func showWordManager(_ tab: WordBank) {
        knownWordsTab = tab
        showingKnownWords = true
    }

    /// Empty the bank — every parked word becomes new again. Known words are untouched.
    func revertAllAside() {
        session?.unmarkAllAside()
        knownStore.removeAllAside()
        resetKnownFlash()
        refreshSummaryIfNeeded()
    }

    /// Space/Enter behaviour: reveal the back, or advance if already revealed.
    func primaryAction() {
        guard isStudying, let session else { return }
        if session.isShowingBack {
            advance()
        } else {
            flip()
        }
    }

    func advance() {
        guard isStudying, let session else { return }
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
        guard isStudying, let session, session.hasPrevious else { return }
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

    func markAsideAndAdvance() {
        markCurrentAside()
        advance()
    }

    /// K key mirrors the visible card action: classify, persist, and continue.
    func toggleCurrentKnown() {
        guard isStudying, let session else { return }
        if session.isCurrentKnown {
            unmarkCurrentKnown()
        } else {
            markKnownAndAdvance()
        }
    }

    /// A key mirrors the card's Almost action. Known words are left alone — the bank is
    /// for words still being learned.
    func toggleCurrentAside() {
        guard isStudying, let session, !session.isCurrentKnown else { return }
        if session.isCurrentAside {
            unmarkCurrentAside()
        } else {
            markAsideAndAdvance()
        }
    }

    /// Finish the current round now (also invoked by Escape) — lands on the summary with
    /// whatever progress was made, rather than discarding it. Finishing twice would
    /// re-snapshot an already-frozen round, so this is study-only like the rest.
    func finishRound() {
        guard isStudying, let session else { return }
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
                                initialKnownKeys: knownStore.knownKeys,
                                initialAsideKeys: knownStore.asideKeys)
        resetKnownFlash()
        withAnimation(Motion.gentleSpring) {
            self.session = next
            self.lastSummary = nil
            self.route = .study
        }
    }

    var summaryHasRemaining: Bool { lastSummary?.hasRemaining ?? false }

    /// Words seen this round that were neither known nor already parked. Offered on the
    /// summary as a one-tap way to clear them out of the New pool for a while.
    var stillUnknownCards: [Flashcard] { session?.stillUnknownCards ?? [] }

    func setAsideStillUnknown() {
        guard let session else { return }
        for card in session.stillUnknownCards {
            session.markAside(key: card.key)
            knownStore.markAside(key: card.key, display: card.word)
        }
        Haptics.mark()
        refreshSummaryIfNeeded()
    }

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
        lastMarkedAsideID = nil
    }
}
