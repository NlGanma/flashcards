import SwiftUI
import AppKit
import VocabKit

/// When the app is launched with `VF_SNAPSHOT=<output-dir>` (and `VF_SAMPLE=<xlsx>`),
/// it renders each screen offscreen with `ImageRenderer` and exits. This gives a way to
/// visually verify the real UI without a window or screen-recording permission. It has no
/// effect on normal launches.
enum SnapshotConfig {
    /// True in snapshot mode — used to skip intro animations so screens render fully.
    static let skipIntro = ProcessInfo.processInfo.environment["VF_SNAPSHOT"] != nil
}

/// A `ScrollView` that lays its content out plainly while rendering snapshots.
///
/// `ImageRenderer` rasterizes a `ScrollView`'s chrome but not its content, so any screen
/// with a scrollable body would otherwise photograph as an empty box — which makes the
/// snapshots useless exactly where the layout is hardest to get right.
struct SnapshotableScrollView<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        if SnapshotConfig.skipIntro {
            content()
        } else {
            ScrollView { content() }
        }
    }
}

@MainActor
enum SnapshotRenderer {

    static func runIfRequested() -> Bool {
        guard let outDir = ProcessInfo.processInfo.environment["VF_SNAPSHOT"] else { return false }
        let dir = URL(fileURLWithPath: outDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        render(into: dir)
        return true
    }

    private static func render(into dir: URL) {
        let full = CGSize(width: 1040, height: 720)

        // Known store seeded with a few words for realistic screens.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("vf-snap-\(UUID().uuidString)")
        let known = KnownWordsStore(directory: tmp)
        ["abate", "candid", "serene", "robust", "frugal", "humble"].forEach { known.markKnown(word: $0) }

        // Empty state (fresh app).
        let emptyApp = makeApp(known: known)
        save(RootView().environmentObject(emptyApp), size: full, name: "10_empty", dir: dir)
        save(RootView().environmentObject(emptyApp), size: full, name: "11_empty_dark", dir: dir, dark: true)

        // Load the sample workbook, if provided.
        guard let samplePath = ProcessInfo.processInfo.environment["VF_SAMPLE"] else {
            FileHandle.standardError.write("VF_SAMPLE not set; only empty state rendered\n".data(using: .utf8)!)
            return
        }
        let sampleURL = URL(fileURLWithPath: samplePath)

        let app = makeApp(known: known)
        app.loadFile(at: sampleURL, remember: false)

        // Setup / set selection.
        save(RootView().environmentObject(app), size: full, name: "20_setup", dir: dir)
        save(RootView().environmentObject(app), size: full, name: "21_setup_dark", dir: dir, dark: true)

        // Practice-set cards rendered directly (the grid is lazy, so verify the card design).
        if let sets = app.loadedFile?.sets, sets.count >= 3 {
            let cards = HStack(spacing: 16) {
                PracticeSetCardView(set: sets[0], isSelected: true, knownCount: 3)
                PracticeSetCardView(set: sets[1], isSelected: false, knownCount: 0)
                PracticeSetCardView(set: sets[2], isSelected: true, knownCount: 1)
            }
            .padding(24)
            save(cards.environmentObject(app), size: CGSize(width: 900, height: 200),
                 name: "22_set_cards", dir: dir)

            // Three pills on the narrowest card the adaptive grid can produce (240pt),
            // plus a mid-width one — the layout that used to wrap letter-by-letter.
            for (width, name) in [(240.0, "26_pills_min"), (261.0, "27_pills_typical")] {
                let crowded = HStack(spacing: 16) {
                    PracticeSetCardView(set: sets[0], isSelected: true,
                                        knownCount: 35, asideCount: 1)
                    PracticeSetCardView(set: sets[1], isSelected: false,
                                        knownCount: 4, asideCount: 12)
                }
                .frame(width: CGFloat(width) * 2 + 16)
                .padding(20)
                save(crowded.environmentObject(app),
                     size: CGSize(width: CGFloat(width) * 2 + 56, height: 190),
                     name: name, dir: dir)
                save(crowded.environmentObject(app),
                     size: CGSize(width: CGFloat(width) * 2 + 56, height: 190),
                     name: "\(name)_dark", dir: dir, dark: true)
            }
        }

        // A multi-sense card back rendered directly.
        let multi = Flashcard(id: "keen", word: "keen",
                              senses: [Sense(partOfSpeech: "adj.", definition: "敏锐的；渴望的"),
                                       Sense(partOfSpeech: "adj.", definition: "热衷的，热切的"),
                                       Sense(partOfSpeech: "n.", definition: "挽歌（爱尔兰）")],
                              sourceSets: ["Practice 1", "Practice 2"])
        save(FlashcardView(card: multi, isShowingBack: true, isKnownFlash: false)
                .padding(40)
                .frame(width: Metric.cardMaxWidth + 80, height: Metric.cardHeight + 80),
             size: CGSize(width: Metric.cardMaxWidth + 80, height: Metric.cardHeight + 80),
             name: "23_card_back_senses", dir: dir)

        // Study — front and back of a card.
        app.startStudy(filter: .includeKnown)
        save(RootView().environmentObject(app), size: full, name: "40_study_front", dir: dir)
        app.session?.showBack()
        save(RootView().environmentObject(app), size: full, name: "41_study_back", dir: dir)
        save(RootView().environmentObject(app), size: full, name: "42_study_back_dark", dir: dir, dark: true)
        save(RootView().environmentObject(app), size: CGSize(width: 880, height: 640),
             name: "43_study_back_dark_min", dir: dir, dark: true)

        // Focused regression for the revealed-card layout requested by the user.
        let requestedCard = Flashcard(
            id: "capricious",
            word: "capricious",
            senses: [Sense(partOfSpeech: "adj.", definition: "反复无常的，任性的")],
            sourceSets: ["Practice 1"]
        )
        let focusedBack = ZStack {
            AppBackground()
            FlashcardView(card: requestedCard, isShowingBack: true, isKnownFlash: false)
                .padding(.horizontal, 40)
                .padding(.top, 80)
        }
        save(focusedBack, size: CGSize(width: 649, height: 476),
             name: "44_requested_card_dark", dir: dir, dark: true)

        let focusedKnownBack = ZStack {
            AppBackground()
            FlashcardView(card: requestedCard, isShowingBack: true, isKnownFlash: false,
                          isCurrentKnown: true)
                .padding(.horizontal, 40)
                .padding(.top, 80)
        }
        save(focusedKnownBack, size: CGSize(width: 649, height: 476),
             name: "45_known_card_dark", dir: dir, dark: true)

        // Card footer in each bank state — the two mark actions must fit side by side.
        let footerCard = Flashcard(id: "capricious", word: "capricious",
                                   senses: [Sense(partOfSpeech: "adj.", definition: "反复无常的，任性的")],
                                   sourceSets: ["Practice 1"])
        for (mode, isKnown, isAside) in [("new", false, false),
                                         ("almost", false, true),
                                         ("known", true, false)] {
            for dark in [false, true] {
                let view = ZStack {
                    AppBackground()
                    FlashcardView(card: footerCard, isShowingBack: true, isKnownFlash: false,
                                  isCurrentKnown: isKnown, isCurrentAside: isAside)
                        .padding(40)
                }
                save(view, size: CGSize(width: Metric.cardMaxWidth + 80, height: Metric.cardHeight + 80),
                     name: "47_card_\(mode)\(dark ? "_dark" : "")", dir: dir, dark: dark)
            }
        }

        // The "just parked" flourish.
        save(ZStack {
                AppBackground()
                FlashcardView(card: footerCard, isShowingBack: false, isKnownFlash: false,
                              isAsideFlash: true)
                    .padding(40)
             },
             size: CGSize(width: Metric.cardMaxWidth + 80, height: Metric.cardHeight + 80),
             name: "48_aside_flash_dark", dir: dir, dark: true)

        // The example panel: on its own, and open beside a card at full and minimum width.
        for (card, name) in [(exampleCard, "70_panel_single"), (multiExampleCard, "71_panel_multi"),
                             (fourGlossCard, "71b_panel_four_glosses")] {
            for dark in [false, true] {
                save(ZStack {
                        AppBackground()
                        SentencePanelView(card: card).frame(width: 352, height: Metric.cardHeight)
                     },
                     size: CGSize(width: 412, height: Metric.cardHeight + 60),
                     name: "\(name)\(dark ? "_dark" : "")", dir: dir, dark: dark)
            }
        }

        // Study the new words, so the card on screen carries a real curated example
        // straight out of the bundled bank rather than a hand-made one.
        let panelApp = makeApp(known: known)
        panelApp.loadFile(at: sampleURL, remember: false)
        panelApp.startStudy(filter: .excludeKnown)
        // The snapshot's known-word store is a stub, so the shuffled deck can land on a
        // word the curated bank doesn't cover. Pin it to one that it does.
        if let current = panelApp.session?.currentCard,
           let curated = panelApp.curatedCard(for: "keen") {
            panelApp.session?.replaceCard(current.with(word: curated.word, senses: curated.senses))
        }
        panelApp.session?.showBack()
        panelApp.session?.isShowingSentence = true
        save(RootView().environmentObject(panelApp), size: full, name: "72_study_panel", dir: dir)
        save(RootView().environmentObject(panelApp), size: full, name: "73_study_panel_dark",
             dir: dir, dark: true)
        save(RootView().environmentObject(panelApp), size: CGSize(width: 880, height: 640),
             name: "74_study_panel_min", dir: dir)
        // A three-sense card is the tallest thing the panel has to hold. Identity has to
        // stay the current card's, or `replaceCard` swaps some other card in the deck.
        if let current = panelApp.session?.currentCard {
            panelApp.session?.replaceCard(current.with(word: multiExampleCard.word,
                                                       senses: multiExampleCard.senses))
        }
        save(RootView().environmentObject(panelApp), size: full, name: "75_study_panel_multi_dark",
             dir: dir, dark: true)

        // A word the curated bank doesn't cover: the panel must say so once, not reprint
        // the card's definitions with a placeholder under each.
        let bare = Flashcard(id: "suppress", word: "suppress",
                             senses: [Sense(partOfSpeech: "v.", definition: "镇压，压制，隐瞒，查禁")],
                             sourceSets: ["Practice 6"])
        for dark in [false, true] {
            save(ZStack {
                    AppBackground()
                    SentencePanelView(card: bare).frame(width: 352, height: Metric.cardHeight)
                 },
                 size: CGSize(width: 412, height: Metric.cardHeight + 60),
                 name: "78_panel_no_example\(dark ? "_dark" : "")", dir: dir, dark: dark)
        }

        // The editor.
        let editorApp = makeApp(known: known)
        editorApp.loadFile(at: sampleURL, remember: false)
        editorApp.editingCard = exampleCard
        save(CardEditorView(card: exampleCard).environmentObject(editorApp),
             size: CGSize(width: 580, height: 620), name: "76_editor", dir: dir)
        save(CardEditorView(card: multiExampleCard).environmentObject(editorApp),
             size: CGSize(width: 580, height: 620), name: "77_editor_multi_dark", dir: dir, dark: true)

        // A block holding a sentence with no meaning to attach it to: this used to be
        // dropped silently on Save, and now blocks it with a reason instead.
        let orphaned = Flashcard(
            id: "capricious", word: "capricious",
            senses: [Sense(partOfSpeech: "adj.", definition: "反复无常的，任性的",
                           examples: exampleCard.senses[0].examples),
                     Sense(partOfSpeech: "", definition: "",
                           example: Example(english: "A sentence typed with no meaning to attach it to.",
                                            chinese: "一个还没有释义可以依附的句子。"))],
            sourceSets: ["Practice 1"])
        save(CardEditorView(card: orphaned).environmentObject(editorApp),
             size: CGSize(width: 580, height: 760), name: "79_editor_blocked", dir: dir)

        app.errorMessage = "That file couldn't be read. Your current round is still here."
        save(RootView().environmentObject(app), size: full,
             name: "46_study_error_dark", dir: dir, dark: true)
        app.errorMessage = nil

        // The setup screen's banner must sit in the fixed chrome — a drop error has to be
        // visible even when the set list is scrolled down.
        let errored = makeApp(known: known)
        errored.loadFile(at: sampleURL, remember: false)
        errored.errorMessage = VocabError.notXLSX(fileName: "notes.txt").friendlyMessage
        save(RootView().environmentObject(errored), size: full, name: "28_setup_error", dir: dir)
        save(RootView().environmentObject(errored), size: full, name: "29_setup_error_dark",
             dir: dir, dark: true)

        // Study header with both bank badges, and the setup screen once words are parked.
        let banked = makeApp(known: known)
        banked.loadFile(at: sampleURL, remember: false)
        let parkedWords = banked.selectedSets.flatMap { $0.items.map(\.english) }
            .filter { !known.isKnown(word: $0) }
            .prefix(9)
        parkedWords.forEach { known.markAside(word: $0) }
        save(RootView().environmentObject(banked), size: full, name: "24_setup_with_bank", dir: dir)
        save(RootView().environmentObject(banked), size: full, name: "25_setup_with_bank_dark",
             dir: dir, dark: true)
        banked.startStudy(filter: .includeKnown)
        banked.session?.showBack()
        save(RootView().environmentObject(banked), size: CGSize(width: 880, height: 640),
             name: "49_study_min_width_dark", dir: dir, dark: true)
        save(RootView().environmentObject(banked), size: CGSize(width: 880, height: 640),
             name: "49b_study_min_width", dir: dir)

        // A summary with its session still attached, so the bulk set-aside action shows.
        banked.markKnownAndAdvance()
        banked.advance()
        banked.advance()
        banked.finishRound()
        save(RootView().environmentObject(banked), size: full, name: "53_summary_live", dir: dir)
        save(RootView().environmentObject(banked), size: full, name: "54_summary_live_dark",
             dir: dir, dark: true)

        // Summary.
        app.route = .summary
        app.session = nil
        app.lastSummary = RoundSummary(roundNumber: 1, totalStudied: 24, markedKnown: 17, stillUnknown: 7)
        save(RootView().environmentObject(app), size: full, name: "50_summary", dir: dir)

        // Summary including the Almost tile.
        app.lastSummary = RoundSummary(roundNumber: 2, totalStudied: 24, markedKnown: 13,
                                       stillUnknown: 5, unvisited: 0, setAside: 6)
        save(RootView().environmentObject(app), size: full, name: "51_summary_with_almost", dir: dir)
        save(RootView().environmentObject(app), size: full, name: "52_summary_with_almost_dark",
             dir: dir, dark: true)

        // Word manager — both banks.
        save(KnownWordsView(store: known).environmentObject(app),
             size: CGSize(width: 460, height: 560), name: "60_known_words", dir: dir)
        let asideApp = makeApp(known: known)
        asideApp.knownWordsTab = .aside
        save(KnownWordsView(store: known).environmentObject(asideApp),
             size: CGSize(width: 460, height: 560), name: "61_almost_known", dir: dir)
        save(KnownWordsView(store: known).environmentObject(asideApp),
             size: CGSize(width: 460, height: 560), name: "62_almost_known_dark", dir: dir, dark: true)
        let emptyBankApp = makeApp(known: KnownWordsStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("vf-snap-\(UUID().uuidString)")))
        emptyBankApp.knownWordsTab = .aside
        save(KnownWordsView(store: emptyBankApp.knownStore).environmentObject(emptyBankApp),
             size: CGSize(width: 460, height: 560), name: "63_almost_known_empty", dir: dir)
    }

    private static func makeApp(known: KnownWordsStore) -> AppState {
        let defaults = UserDefaults(suiteName: "vf-snapshot-\(UUID().uuidString)")!
        // A throwaway edits store — snapshots must never read or write the real one.
        let edits = CardEditsStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("vf-snap-edits-\(UUID().uuidString)"))
        return AppState(knownStore: known, recentStore: RecentFileStore(defaults: defaults),
                        editsStore: edits)
    }

    /// A card carrying worked examples, for the panel screens. Two glosses, two sentences.
    private static let exampleCard = Flashcard(
        id: "capricious", word: "capricious",
        senses: [Sense(partOfSpeech: "adj.", definition: "反复无常的，任性的", examples: [
            Example(gloss: "反复无常的",
                    english: "The committee's capricious funding decisions left researchers unable to plan beyond a single semester.",
                    chinese: "委员会反复无常的拨款决定，使研究人员无法为一个学期以后做任何规划。"),
            Example(gloss: "任性的",
                    english: "A capricious heir can undo in a decade what three generations spent a century assembling.",
                    chinese: "一个任性的继承人，十年之内就能毁掉三代人用一个世纪积攒的家业。")])],
        sourceSets: ["Practice 1"])

    /// The case the user asked about: one row, one part of speech pair, four glosses.
    private static let fourGlossCard = Flashcard(
        id: "miscreant", word: "miscreant",
        senses: [Sense(partOfSpeech: "n. / adj.", definition: "恶棍，歹徒；不法的，邪恶的", examples: [
            Example(gloss: "恶棍",
                    english: "The night watchman's log named three miscreants who had scaled the fence after curfew.",
                    chinese: "守夜人的记录点名了三个在宵禁后翻越围栏的恶棍。"),
            Example(gloss: "歹徒",
                    english: "Witnesses described the miscreant as unhurried, as though he had rehearsed the escape.",
                    chinese: "目击者形容这名歹徒不慌不忙，仿佛早已演练过逃脱的路线。"),
            Example(gloss: "不法的",
                    english: "The charter was drafted to curb the miscreant practices that had bankrupted two earlier banks.",
                    chinese: "这份章程的起草，是为了遏制曾让两家银行破产的不法的行径。"),
            Example(gloss: "邪恶的",
                    english: "History remembers him less for his talent than for the miscreant uses he put it to.",
                    chinese: "历史记住他，与其说是因为才能，不如说是因为他把才能用在了邪恶的地方。")])],
        sourceSets: ["Practice 15"])

    private static let multiExampleCard = Flashcard(
        id: "keen", word: "keen",
        senses: [Sense(partOfSpeech: "adj.", definition: "敏锐的", examples: [
                    Example(gloss: "敏锐的",
                            english: "Her keen eye for inconsistency exposed the flaw that three earlier reviewers had missed.",
                            chinese: "她对矛盾之处敏锐的眼光，揭露了此前三位审稿人都忽略的缺陷。")]),
                 Sense(partOfSpeech: "adj.", definition: "渴望的，热切的", examples: [
                    Example(gloss: "渴望的",
                            english: "Though keen to publish, the historian withheld the manuscript until the archive could be verified.",
                            chinese: "尽管渴望的心情迫切，这位历史学家仍压下书稿，直到档案得到核实。"),
                    Example(gloss: "热切的",
                            english: "A keen interest in provincial records led her to an archive no one had catalogued.",
                            chinese: "对地方档案热切的兴趣，把她引向了一批从未有人编目的卷宗。")]),
                 Sense(partOfSpeech: "n.", definition: "挽歌（爱尔兰）", examples: [
                    Example(gloss: "挽歌（爱尔兰）",
                            english: "The keen rising from the far end of the village announced the death before any messenger arrived.",
                            chinese: "从村子另一头传来的挽歌，比任何报信人都更早宣告了这场死亡。")])],
        sourceSets: ["Practice 1", "Practice 2"])

    private static func save<V: View>(_ view: V, size: CGSize, name: String, dir: URL, dark: Bool = false) {
        let content = view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.isOpaque = true
        guard let cg = renderer.cgImage else {
            FileHandle.standardError.write("Failed to render \(name)\n".data(using: .utf8)!)
            return
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: dir.appendingPathComponent("\(name).png"))
            print("rendered \(name)")
        }
    }
}
