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

        app.errorMessage = "That file couldn't be read. Your current round is still here."
        save(RootView().environmentObject(app), size: full,
             name: "46_study_error_dark", dir: dir, dark: true)
        app.errorMessage = nil

        // The setup screen's banner must sit in the fixed chrome — a drop error has to be
        // visible even when the set list is scrolled down.
        let errored = makeApp(known: known)
        errored.loadFile(at: sampleURL, remember: false)
        errored.errorMessage = "“notes.txt” isn't an Excel file. Please choose a file that ends in .xlsx."
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
        return AppState(knownStore: known, recentStore: RecentFileStore(defaults: defaults))
    }

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
