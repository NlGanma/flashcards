import SwiftUI
import VocabKit

/// The Markdown-to-flashcards screen: the cards the model has written on the left, the
/// chat that shapes them on the right. Holding on to the studio through the cross-fade
/// keeps the screen from blanking as it leaves, the same way the study screen does.
struct StudioView: View {
    @EnvironmentObject private var app: AppState
    @State private var shown: GenerationStudio?

    var body: some View {
        Group {
            if let studio = app.studio ?? shown {
                StudioContent(studio: studio)
            } else {
                Color.clear
            }
        }
        .onAppear { shown = app.studio }
        .onChange(of: app.studio.map(ObjectIdentifier.init)) { _ in
            if let latest = app.studio { shown = latest }
        }
    }
}

private struct StudioContent: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var studio: GenerationStudio
    @Environment(\.colorScheme) private var scheme
    @State private var confirmingClose = false
    @State private var confirmingStartOver = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 30)
                .padding(.top, 26)
                .padding(.bottom, 18)

            HStack(alignment: .top, spacing: 18) {
                StudioCardsPane(studio: studio)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                StudioChatPanel(studio: studio)
                    .frame(width: 360)
                    .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 24)
        }
        .confirmationDialog("Close without studying these cards?", isPresented: $confirmingClose) {
            Button("Study \(studio.cards.count) Cards") { app.studyStudioCards() }
            Button("Discard Cards", role: .destructive) { app.closeStudio() }
            Button("Keep Working", role: .cancel) {}
        } message: {
            Text("The cards haven't been saved yet.")
        }
        .confirmationDialog("Write every card again from the notes?", isPresented: $confirmingStartOver) {
            Button("Start Over", role: .destructive) { studio.startOver() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The \(studio.cards.count) cards here are replaced. Your instructions so far are kept.")
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 14) {
            Button {
                if studio.hasUnsavedChanges && !studio.cards.isEmpty { confirmingClose = true }
                else { app.closeStudio() }
            } label: {
                Label("Close", systemImage: "chevron.left")
            }
            .buttonStyle(GhostButtonStyle())
            .keyboardShortcut(.cancelAction)
            .help("Leave without saving (Esc)")

            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.violet)
            VStack(alignment: .leading, spacing: 1) {
                Text(studio.title)
                    .font(.rounded(15, .semibold))
                    .foregroundStyle(Color.primaryText(scheme))
                    .lineLimit(1)
                Text("From \(studio.sourceFileName)")
                    .font(.rounded(11, .medium))
                    .foregroundStyle(Color.secondaryText(scheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            ModelStatusButton(studio: studio)

            if !studio.cards.isEmpty {
                Button {
                    confirmingStartOver = true
                } label: {
                    Label("Start Over", systemImage: "arrow.counterclockwise")
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(studio.isWorking)
                .help("Write every card again from the notes, with your instructions so far")
            }

            Button {
                app.studyStudioCards()
            } label: {
                Label(studio.cards.isEmpty ? "Study" : "Study \(studio.cards.count) Cards",
                      systemImage: "play.fill")
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(FilledButtonStyle())
            .layoutPriority(1)
            .disabled(studio.cards.isEmpty || studio.isWorking)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Save these cards as a deck and start studying (⌘↩)")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .panel(corner: 16)
    }
}

// MARK: - Cards

/// The cards so far, grouped under the sections they will study as.
struct StudioCardsPane: View {
    @ObservedObject var studio: GenerationStudio
    @Environment(\.colorScheme) private var scheme

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if studio.cards.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    SnapshotableScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(groups, id: \.title) { group in
                                section(group)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    .onChange(of: studio.lastTouchedCardID) { id in
                        guard let id else { return }
                        withAnimation(Motion.spring) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cards")
                    .font(.rounded(26, .bold))
                    .foregroundStyle(Color.primaryText(scheme))
                if !studio.cards.isEmpty {
                    Text("\(studio.cards.count) card\(studio.cards.count == 1 ? "" : "s") · \(studio.sectionCount) set\(studio.sectionCount == 1 ? "" : "s")")
                        .font(.rounded(13, .medium))
                        .foregroundStyle(Color.secondaryText(scheme))
                        .monospacedDigit()
                }
                Spacer()
            }
            if let progress = studio.progress {
                StudioProgressLine(progress: progress, onStop: studio.cancel)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Motion.quick, value: studio.progress)
    }

    private struct Group { let title: String; let cards: [GeneratedCard] }

    private var groups: [Group] {
        var order: [String] = []
        var cards: [String: [GeneratedCard]] = [:]
        for card in studio.cards {
            if cards[card.section] == nil { order.append(card.section) }
            cards[card.section, default: []].append(card)
        }
        return order.map { Group(title: $0, cards: cards[$0] ?? []) }
    }

    private func section(_ group: Group) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(group.title.isEmpty ? studio.title : group.title)
                    .font(.rounded(13, .bold))
                    .foregroundStyle(Color.primaryText(scheme))
                Text("\(group.cards.count)")
                    .font(.rounded(11, .semibold))
                    .foregroundStyle(Color.secondaryText(scheme))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(scheme == .dark ? 0.10 : 0.06)))
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(group.cards) { card in
                    StudioCardTile(card: card,
                                   isFocused: studio.focusedCardID == card.id,
                                   isFresh: studio.lastTouchedCardID == card.id && studio.isWorking,
                                   isLocked: studio.isWorking,
                                   onFocus: { withAnimation(Motion.spring) { studio.toggleFocus(card) } },
                                   onDelete: { withAnimation(Motion.spring) { studio.delete(card) } })
                        .id(card.id)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
        }
    }

    /// Before the first card: what the model is about to read, so the sections that will
    /// become sets are visible before anything is generated.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Palette.accentGradient).frame(width: 46, height: 46)
                    Image(systemName: studio.isWorking ? "ellipsis" : "rectangle.stack.badge.plus")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(studio.isWorking ? "Writing your first cards…" : "Your cards will appear here")
                        .font(.rounded(17, .bold))
                        .foregroundStyle(Color.primaryText(scheme))
                    Text(studio.isWorking
                         ? "They show up one by one as the model writes them."
                         : "Tell the model what you want on the back of each card, then press Generate.")
                        .font(.rounded(13, .medium))
                        .foregroundStyle(Color.secondaryText(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("Sets from your notes")
                    .font(.rounded(11, .semibold))
                    .foregroundStyle(Color.secondaryText(scheme))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .padding(.bottom, 8)
                ForEach(Array(studio.outline.sections.prefix(12).enumerated()), id: \.offset) { index, section in
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.rounded(11, .bold))
                            .foregroundStyle(Palette.indigo)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Palette.indigo.opacity(scheme == .dark ? 0.18 : 0.10)))
                        Text(section.title)
                            .font(.rounded(13, .semibold))
                            .foregroundStyle(Color.primaryText(scheme))
                            .lineLimit(1)
                        Spacer()
                        Text("\(section.body.split(whereSeparator: \.isWhitespace).count) words")
                            .font(.rounded(12, .medium))
                            .foregroundStyle(Color.secondaryText(scheme))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 7)
                    if index < min(studio.outline.sections.count, 12) - 1 {
                        Divider().opacity(0.4)
                    }
                }
                if studio.outline.sections.count > 12 {
                    Text("and \(studio.outline.sections.count - 12) more")
                        .font(.rounded(12, .medium))
                        .foregroundStyle(Color.secondaryText(scheme))
                        .padding(.top, 8)
                }
            }
            .padding(18)
            .panel(corner: Metric.panelCorner, elevated: false)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// "Reading “Transport” · 2 of 5" with a bar, and the way to stop.
struct StudioProgressLine: View {
    let progress: GenerationStudio.Progress
    var onStop: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var fraction: Double {
        progress.total == 0 ? 0 : (Double(progress.step) - 0.5) / Double(progress.total)
    }

    var body: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(progress.label)
                        .font(.rounded(12, .semibold))
                        .foregroundStyle(Color.primaryText(scheme))
                        .lineLimit(1)
                    if progress.total > 1 {
                        Text("· \(progress.step) of \(progress.total)")
                            .font(.rounded(12, .medium))
                            .foregroundStyle(Color.secondaryText(scheme))
                            .monospacedDigit()
                    }
                }
                ProgressBar(fraction: fraction, height: 5)
            }
            Button("Stop", action: onStop)
                .buttonStyle(SoftButtonStyle(tint: Palette.learningTint(scheme)))
                .controlSize(.small)
                .help("Stop the model. Cards written so far are kept.")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.indigo.opacity(scheme == .dark ? 0.14 : 0.07))
        )
    }
}

/// One card in the preview: both faces at once, so the learner can judge it at a glance.
/// Clicking it points the chat at this card.
struct StudioCardTile: View {
    let card: GeneratedCard
    var isFocused: Bool
    var isFresh: Bool
    var isLocked: Bool
    var onFocus: () -> Void
    var onDelete: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(card.front)
                    .font(.rounded(16, .bold))
                    .foregroundStyle(Color.primaryText(scheme))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if !card.tag.isEmpty {
                    Text(card.tag)
                        .font(.rounded(11, .semibold))
                        .foregroundStyle(scheme == .dark ? Palette.indigoLight : Palette.indigoDeep)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Palette.indigo.opacity(scheme == .dark ? 0.20 : 0.12)))
                }
            }
            Text(card.back)
                .font(.rounded(13, .medium))
                .foregroundStyle(Color.primaryText(scheme).opacity(0.85))
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
            if !card.example.isEmpty || !card.exampleNote.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.indigo)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        if !card.example.isEmpty {
                            Text(card.example).italic()
                        }
                        if !card.exampleNote.isEmpty {
                            Text(card.exampleNote).foregroundStyle(Color.secondaryText(scheme))
                        }
                    }
                    .font(.rounded(12, .regular))
                    .foregroundStyle(Color.primaryText(scheme).opacity(0.75))
                    .lineLimit(2)
                }
            }
            if isFocused {
                Label("The chat is about this card", systemImage: "bubble.left.fill")
                    .font(.rounded(11, .semibold))
                    .foregroundStyle(Palette.indigo)
                    .transition(.opacity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(shape.fill(Color.surface(scheme)))
        .background(shape.fill(isFocused ? Palette.indigo.opacity(scheme == .dark ? 0.16 : 0.07) : .clear))
        .overlay(
            shape.strokeBorder(isFocused ? Palette.indigo
                               : (isFresh ? Palette.violet.opacity(0.7)
                                  : Color.primary.opacity(hovering ? 0.16 : (scheme == .dark ? 0.10 : 0.06))),
                               lineWidth: isFocused ? 2 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if hovering && !isLocked {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.secondaryText(scheme))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.surface(scheme)))
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("Delete this card")
                .offset(x: 8, y: -8)
                .transition(.opacity)
            }
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.3 : (hovering ? 0.10 : 0.05)),
                radius: hovering ? 12 : 6, y: hovering ? 6 : 3)
        .contentShape(shape)
        .onTapGesture { if !isLocked { onFocus() } }
        .hoverCursor($hovering)
        .animation(Motion.quick, value: hovering)
        .animation(Motion.quick, value: isFresh)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.front): \(card.back)")
        .accessibilityHint(isFocused ? "The chat is about this card. Activate to talk about all cards."
                                     : "Activate to ask the model to change just this card.")
        .accessibilityAddTraits(isFocused ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Delete card", onDelete)
    }
}
