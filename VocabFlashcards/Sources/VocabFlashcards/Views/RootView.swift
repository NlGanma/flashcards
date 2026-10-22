import SwiftUI
import UniformTypeIdentifiers

/// Top-level router: draws the ambient background and swaps between the empty, setup,
/// study, summary and generation-studio screens with smooth transitions. Owns the app's sheet and the
/// window-wide file drop.
struct RootView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var dropTargeted = false

    var body: some View {
        ZStack {
            AppBackground()

            content
                .id(app.route)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))

            // The empty state has its own drop affordance; show the full-window overlay
            // only once a file is already loaded. The studio takes no drops at all — a
            // stray file would throw away the cards being written.
            if dropTargeted && app.route != .empty && app.route != .generate {
                dropOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            if (app.route == .study || app.route == .summary), let error = app.errorMessage {
                MessageBanner(kind: .error, text: error) {
                    withAnimation { app.errorMessage = nil }
                }
                .frame(maxWidth: 520)
                .padding(.top, 24)
                .padding(.horizontal, 30)
            }
        }
        // Accept a dropped .xlsx anywhere in the window, not just the empty state.
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted.animation(Motion.quick)) { providers in
            guard app.route != .generate, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { app.handleDrop(url: url) }
            }
            return true
        }
        .sheet(isPresented: $app.showingKnownWords) {
            KnownWordsView(store: app.knownStore)
                .environmentObject(app)
        }
        .sheet(item: $app.editingCard) { card in
            // Keyed by the card so reopening the editor on a different word rebuilds its
            // draft state instead of reusing the previous word's text fields.
            CardEditorView(card: card)
                .id(card.key)
                .environmentObject(app)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch app.route {
        case .empty:   EmptyStateView()
        case .setup:   SetupView()
        case .study:   StudyView()
        case .summary: SummaryView()
        case .generate: StudioView()
        }
    }

    private var dropOverlay: some View {
        ZStack {
            Color.black.opacity(scheme == .dark ? 0.35 : 0.12)
            VStack(spacing: 14) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Palette.indigo)
                Text("Drop to load")
                    .font(.rounded(20, .bold))
                    .foregroundStyle(Color.primaryText(scheme))
            }
            .padding(40)
            .panel(corner: Metric.panelCorner)
        }
        .ignoresSafeArea()
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Palette.indigo, style: StrokeStyle(lineWidth: 3, dash: [12, 8]))
                .padding(10)
        )
        .transition(.opacity)
    }
}
