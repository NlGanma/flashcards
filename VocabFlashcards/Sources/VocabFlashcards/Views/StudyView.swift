import SwiftUI
import AppKit
import VocabKit

enum StudyControlFocus: Hashable {
    case sets, knownAction, asideAction, previous, next
}

struct StudyView: View {
    @EnvironmentObject private var app: AppState
    /// Leaving study clears `session` in the same transaction as the route, but this view
    /// keeps rendering for the whole cross-fade — without holding on to the session the
    /// card would blank out on its way off screen.
    @State private var shown: StudySession?

    var body: some View {
        Group {
            if let session = app.session ?? shown {
                StudyContent(session: session)
            } else {
                Color.clear
            }
        }
        .onAppear { shown = app.session }
        .onChange(of: app.session.map(ObjectIdentifier.init)) { _ in
            if let latest = app.session { shown = latest }
        }
    }
}

private struct StudyContent: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var session: StudySession
    @Environment(\.colorScheme) private var scheme
    @State private var keyMonitor: Any?
    @State private var cardHovering = false
    @FocusState private var focusedControl: StudyControlFocus?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 30)
                .padding(.top, 26)

            Spacer(minLength: 12)

            VStack(spacing: 16) {
                cardArea
                controls
            }
            .padding(.horizontal, 30)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
        .onChange(of: session.currentIndex) { _ in focusedControl = nil }
        .onChange(of: session.isShowingBack) { showingBack in
            // The card actions only exist on the back — don't leave focus stranded there.
            if !showingBack, focusedControl == .knownAction || focusedControl == .asideAction {
                focusedControl = nil
            }
        }
    }

    // MARK: - Header (progress)

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    app.backToSetup()
                } label: {
                    Label("Sets", systemImage: "chevron.left")
                }
                .buttonStyle(GhostButtonStyle())
                .focused($focusedControl, equals: .sets)

                Spacer()

                if session.roundNumber > 1 {
                    badge(icon: "arrow.triangle.2.circlepath", text: "Round \(session.roundNumber)", tint: Palette.violet)
                }

                Spacer()

                HStack(spacing: 8) {
                    if session.asideCount > 0 {
                        badge(icon: "hourglass", text: "\(session.asideCount) almost",
                              tint: Palette.learning)
                    }
                    badge(icon: "checkmark.seal.fill", text: "\(session.knownCount) known",
                          tint: Palette.success)
                }
            }

            ProgressBar(fraction: session.progressFraction, height: 8)
                .accessibilityLabel("Study progress")
                .accessibilityValue("\(session.position) of \(session.total)")

            HStack {
                Text("\(session.position)")
                    .font(.rounded(14, .bold))
                    .foregroundColor(Color.primaryText(scheme))
                + Text(" / \(session.total)")
                    .font(.rounded(14, .medium))
                    .foregroundColor(Color.secondaryText(scheme))
                Spacer()
                Text(session.modeTitle)
                    .font(.rounded(12, .medium))
                    .foregroundStyle(Color.secondaryText(scheme))
            }
            .monospacedDigit()
        }
    }

    private func badge(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(text).font(.rounded(12, .semibold))
        }
        .foregroundStyle(tint)
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Capsule().fill(tint.opacity(scheme == .dark ? 0.18 : 0.10)))
    }

    // MARK: - Card

    /// The card is centered on its own; when the example panel opens the card shifts left
    /// by an offset instead of being re-laid-out, so the pair reads as one unit sliding
    /// over while the card keeps its slot in the layout for the next/previous transition.
    private var cardArea: some View {
        GeometryReader { geo in
            let layout = SplitLayout(available: geo.size.width, showingPanel: panelVisible)
            ZStack {
                if let card = session.currentCard {
                    FlashcardView(
                        card: card,
                        isShowingBack: session.isShowingBack,
                        isKnownFlash: app.lastMarkedKnownID == card.key,
                        isAsideFlash: app.lastMarkedAsideID == card.key,
                        isCurrentKnown: session.isCurrentKnown,
                        isCurrentAside: session.isCurrentAside,
                        isShowingSentence: panelVisible,
                        // Two thresholds, not one cliff: dropping the key hints alone frees
                        // far more width than opening the panel costs, so the primary
                        // action keeps its full label until the card is genuinely narrow.
                        showsKeyCaps: layout.cardWidth >= 530,
                        usesShortLabels: layout.cardWidth < 470,
                        onFlip: app.flip,
                        onToggleExamples: app.toggleSentence,
                        onEdit: app.beginEditingCurrentCard,
                        onMarkKnown: app.markKnownAndAdvance,
                        onUnmarkKnown: app.unmarkCurrentKnown,
                        onMarkAside: app.markAsideAndAdvance,
                        onUnmarkAside: app.unmarkCurrentAside,
                        actionFocus: $focusedControl
                    )
                    .frame(width: layout.cardWidth)
                    .offset(x: layout.cardOffset)
                    .id(card.key)
                    .transition(cardTransition)
                    .hoverCursor($cardHovering)

                    SentencePanelView(card: card,
                                      onClose: app.toggleSentence,
                                      onEdit: app.beginEditingCurrentCard)
                        // Without an identity of its own the panel's scroll view is reused
                        // across cards, carrying one word's scroll position into the next.
                        .id(card.key)
                        .frame(width: layout.panelWidth, height: Metric.cardHeight)
                        .offset(x: panelVisible ? layout.panelOffset : layout.panelOffset + 30)
                        .opacity(panelVisible ? 1 : 0)
                        .allowsHitTesting(panelVisible)
                        .accessibilityHidden(!panelVisible)
                }
            }
            .frame(width: geo.size.width, height: Metric.cardHeight)
        }
        .frame(height: Metric.cardHeight)
    }

    /// The panel belongs to the revealed definition, so it is only ever on with the back.
    private var panelVisible: Bool { session.isShowingBack && session.isShowingSentence }

    /// Geometry for the card + panel pair. The panel takes a share of the width and the
    /// card gives way to it, shrinking only once there isn't room for both at full size.
    private struct SplitLayout {
        let cardWidth: CGFloat
        let panelWidth: CGFloat
        let cardOffset: CGFloat
        let panelOffset: CGFloat

        init(available: CGFloat, showingPanel: Bool) {
            let gap: CGFloat = 20
            let panel = min(360, max(268, available * 0.36))
            let room = showingPanel ? available - panel - gap : available
            let card = max(280, min(Metric.cardMaxWidth, room))
            self.panelWidth = panel
            self.cardWidth = card
            self.cardOffset = showingPanel ? -(panel + gap) / 2 : 0
            self.panelOffset = (card + gap) / 2
        }
    }

    // Forward navigation: new card enters from the right, old exits left.
    // Backward navigation: new card enters from the left, old exits right.
    private var cardTransition: AnyTransition {
        let incoming: Edge = app.navigatingForward ? .trailing : .leading
        let outgoing: Edge = app.navigatingForward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: incoming).combined(with: .opacity),
            removal: .move(edge: outgoing).combined(with: .opacity)
        )
    }

    // MARK: - Controls

    private enum ArrowStyle { case primary, secondary, finish }

    /// Large navigation arrows, tightly clustered directly under the card.
    /// Forward is the primary (filled) action; back is a quiet outline.
    private var controls: some View {
        HStack(spacing: 18) {
            navArrow(icon: "chevron.left", style: .secondary, disabled: !session.hasPrevious,
                     help: "Previous card (←)") { app.goPrevious() }
            navArrow(icon: session.isOnLastCard ? "flag.checkered" : "chevron.right",
                     style: session.isOnLastCard ? .finish : .primary, disabled: false,
                     help: session.isOnLastCard ? "Finish round (→)" : "Next card (→)") { app.advance() }
        }
    }

    private func navArrow(icon: String, style: ArrowStyle, disabled: Bool,
                          help: String, action: @escaping () -> Void) -> some View {
        let prominent = (style == .primary || style == .finish)
        let gradient = style == .finish ? Palette.successGradient : Palette.accentGradient
        let glow = style == .finish ? Palette.success : Palette.indigo
        let glyph: Color = prominent ? .white
            : (disabled ? Color.secondaryText(scheme).opacity(0.35) : Palette.indigo)
        let ring: Color = prominent ? .clear : Palette.indigo.opacity(disabled ? 0.12 : 0.35)
        let plainFill = Palette.indigo.opacity(scheme == .dark ? 0.14 : 0.07)

        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(glyph)
                .frame(width: 64, height: 64)
                .background(
                    Circle().fill(prominent ? AnyShapeStyle(gradient) : AnyShapeStyle(plainFill))
                )
                .overlay(Circle().strokeBorder(ring, lineWidth: 1.5))
                .shadow(color: prominent ? glow.opacity(0.35) : .clear, radius: prominent ? 12 : 0, y: 6)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focused($focusedControl, equals: style == .secondary ? .previous : .next)
        .disabled(disabled)
        .help(help)
        .accessibilityLabel(style == .secondary ? "Previous card" : (style == .finish ? "Finish round" : "Next card"))
        .accessibilityHint(help)
        .hoverLift(scale: disabled ? 1.0 : 1.06, cursor: !disabled)
    }

    // MARK: - Keyboard handling (local monitor — reliable on macOS 13)

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true if the key was handled (and should be swallowed).
    private func handleKey(_ event: NSEvent) -> Bool {
        // The monitor outlives the study screen: `onDisappear` only fires once the route
        // transition has finished animating. Until then this view is still installed on
        // top of the summary, so without this check a keypress meant for the summary
        // (Return = Study Again) would be swallowed and applied to the finished round.
        if app.route != .study { return false }
        // Don't hijack keys while a sheet or a text field is active.
        if app.showingKnownWords || app.editingCard != nil { return false }
        if NSApp.modalWindow != nil { return false }
        if let responder = NSApp.keyWindow?.firstResponder,
           responder is NSTextView { return false }
        // Ignore modified shortcuts and key-repeats for discrete study actions.
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return false }
        if event.isARepeat { return false }
        // Let focused buttons keep native Space/Return activation and arrow-key focus.
        if focusedControl != nil {
            switch event.keyCode {
            case 49, 36, 76, 123, 124: return false
            default: break
            }
        }
        switch event.keyCode {
        case 49, 36, 76:                     // space, return, keypad enter
            app.primaryAction(); return true
        case 123:                            // left arrow
            app.goPrevious(); return true
        case 124:                            // right arrow
            app.advance(); return true
        case 53:                             // escape — close the panel, else finish the round
            if panelVisible {
                app.toggleSentence()
            } else {
                app.finishRound()
            }
            return true
        default:
            break
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "k": app.toggleCurrentKnown(); return true
        case "a": app.toggleCurrentAside(); return true
        case "f": app.flip(); return true
        case "s": app.toggleSentence(); return true
        case "e": app.beginEditingCurrentCard(); return true
        default: return false
        }
    }
}
