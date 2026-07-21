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

        app.errorMessage = "That file couldn't be read. Your current round is still here."
        save(RootView().environmentObject(app), size: full,
             name: "46_study_error_dark", dir: dir, dark: true)
        app.errorMessage = nil

        // Summary.
        app.route = .summary
        app.session = nil
        app.lastSummary = RoundSummary(roundNumber: 1, totalStudied: 24, markedKnown: 17, stillUnknown: 7)
        save(RootView().environmentObject(app), size: full, name: "50_summary", dir: dir)

        // Known words manager.
        save(KnownWordsView(store: known).environmentObject(app),
             size: CGSize(width: 460, height: 560), name: "60_known_words", dir: dir)
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
