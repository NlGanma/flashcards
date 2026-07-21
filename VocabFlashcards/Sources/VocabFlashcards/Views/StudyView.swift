import SwiftUI
import AppKit
import VocabKit

enum StudyControlFocus: Hashable {
    case sets, knownAction, asideAction, previous, next
}

struct StudyView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        Group {
            if let session = app.session {
                StudyContent(session: session)
            } else {
                Color.clear
            }
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

    private var cardArea: some View {
        ZStack {
            if let card = session.currentCard {
                FlashcardView(
                    card: card,
                    isShowingBack: session.isShowingBack,
                    isKnownFlash: app.lastMarkedKnownID == card.key,
                    isAsideFlash: app.lastMarkedAsideID == card.key,
                    isCurrentKnown: session.isCurrentKnown,
                    isCurrentAside: session.isCurrentAside,
                    onFlip: app.flip,
                    onMarkKnown: app.markKnownAndAdvance,
                    onUnmarkKnown: app.unmarkCurrentKnown,
                    onMarkAside: app.markAsideAndAdvance,
                    onUnmarkAside: app.unmarkCurrentAside,
                    actionFocus: $focusedControl
                )
                .id(card.key)
                .transition(cardTransition)
                .hoverCursor($cardHovering)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Metric.cardHeight)
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
        // Don't hijack keys while a sheet or a text field is active.
        if app.showingKnownWords { return false }
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
        case 53:                             // escape — finish the round now
            app.finishRound(); return true
        default:
            break
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "k": app.toggleCurrentKnown(); return true
        case "a": app.toggleCurrentAside(); return true
        case "f": app.flip(); return true
        default: return false
        }
    }
}
