import SwiftUI
import VocabKit

/// A 3D flip effect driven by an animatable `angle` (0 = front, 180 = back). Because it
/// conforms to `Animatable`, `body` is re-evaluated for every interpolated angle, so the
/// two faces swap exactly at the 90° edge-on point — no mirrored text ever shows.
struct FlipEffect<Back: View>: ViewModifier, Animatable {
    var angle: Double
    let back: Back

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let normalized = angle.truncatingRemainder(dividingBy: 360)
        let showingBack = normalized > 90 && normalized < 270
        ZStack {
            content
                .opacity(showingBack ? 0 : 1)
                .allowsHitTesting(!showingBack)
            back
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(showingBack ? 1 : 0)
                .allowsHitTesting(showingBack)
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
    }
}

extension View {
    func flip<Back: View>(angle: Double, @ViewBuilder back: () -> Back) -> some View {
        modifier(FlipEffect(angle: angle, back: back()))
    }
}

/// The large centered study card. Front shows the English word; back shows every sense.
struct FlashcardView: View {
    let card: Flashcard
    var isShowingBack: Bool
    var isKnownFlash: Bool
    var isAsideFlash: Bool = false
    var isCurrentKnown: Bool = false
    var isCurrentAside: Bool = false
    /// Whether the example panel is currently open beside this card.
    var isShowingSentence: Bool = false
    /// The footer sheds width in two stages as the card gives room to the example panel:
    /// the key hints go first, and only a genuinely narrow card shortens its labels.
    var showsKeyCaps: Bool = true
    var usesShortLabels: Bool = false
    var onFlip: () -> Void = {}
    var onToggleExamples: () -> Void = {}
    var onEdit: () -> Void = {}
    var onMarkKnown: () -> Void = {}
    var onUnmarkKnown: () -> Void = {}
    var onMarkAside: () -> Void = {}
    var onUnmarkAside: () -> Void = {}
    var actionFocus: FocusState<StudyControlFocus?>.Binding? = nil
    @Environment(\.colorScheme) private var scheme

    private var angle: Double { isShowingBack ? 180 : 0 }

    /// Which mark just happened, if any — drives the border glow and badge.
    private var flashTint: Color? {
        if isKnownFlash { return Palette.success }
        if isAsideFlash { return Palette.learning }
        return nil
    }

    var body: some View {
        front
            .flip(angle: angle) { back }
            .frame(maxWidth: Metric.cardMaxWidth)
            .frame(height: Metric.cardHeight)
            .overlay {                                   // celebratory border glow
                if let flashTint {
                    RoundedRectangle(cornerRadius: Metric.cardCorner, style: .continuous)
                        .strokeBorder(flashTint, lineWidth: 3)
                        .shadow(color: flashTint.opacity(0.5), radius: 16)
                        .transition(.opacity)
                }
            }
            .overlay {                                   // springy badge pop
                if isKnownFlash {
                    markBadge(icon: "checkmark", gradient: Palette.successGradient,
                              glow: Palette.success)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                } else if isAsideFlash {
                    markBadge(icon: "hourglass", gradient: Palette.learningGradient,
                              glow: Palette.learning)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .animation(Motion.pop, value: isKnownFlash)
            .animation(Motion.pop, value: isAsideFlash)
    }

    private func markBadge(icon: String, gradient: LinearGradient, glow: Color) -> some View {
        ZStack {
            Circle().fill(gradient)
                .frame(width: 78, height: 78)
                .shadow(color: glow.opacity(0.5), radius: 16)
            Image(systemName: icon)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Faces

    private var front: some View {
        cardSurface(tinted: true) {
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                Text(card.word)
                    .font(.rounded(56, .bold))
                    .tracking(-1)
                    .foregroundStyle(Color.primaryText(scheme))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.4)
                    .lineLimit(3)
                    .padding(.horizontal, 28)
                Spacer(minLength: 0)
                Label("Click or press Space to flip", systemImage: "cursorarrow.rays")
                    .font(.rounded(12, .medium))
                    .foregroundStyle(Color.secondaryText(scheme))
                    .padding(.bottom, 22)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(RoundedRectangle(cornerRadius: Metric.cardCorner, style: .continuous))
        .onTapGesture(perform: onFlip)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Flashcard: \(card.word)")
        .accessibilityHint("Activate to reveal the definition")
        .accessibilityAddTraits(.isButton)
    }

    private var back: some View {
        cardSurface(tinted: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    backHeader
                        .padding(.horizontal, 26)
                        .padding(.top, 18)
                        .padding(.bottom, 12)

                    Divider().opacity(0.4).padding(.horizontal, 26)

                    backContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                // Declared before the single tap so the double-click wins; on this face a
                // single tap only flips back, so the small delay it costs is unnoticeable.
                .onTapGesture(count: 2, perform: onEdit)
                .onTapGesture(perform: onFlip)
                // `.contain`, not `.combine`: the example chip lives in this subtree and
                // combining would fold the only control on the face into a run-on string
                // of the word, its sets and every definition, leaving it unreachable by
                // VoiceOver or Full Keyboard Access. Tap gestures aren't exposed to
                // assistive tech at all, so both are republished as named actions.
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Definition of \(card.word)")
                .accessibilityAction(named: "Show the word again", onFlip)
                .accessibilityAction(named: "Edit this card", onEdit)

                knownActionFooter
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// The word, where it came from, and the way into the example panel. The source line
    /// sits under the word rather than opposite it so the chip owns the right edge — it is
    /// the only thing in this row you can act on.
    private var backHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(card.word)
                    .font(.rounded(26, .bold))
                    .tracking(-0.5)
                    .foregroundStyle(Color.primaryText(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !card.sourceSets.isEmpty {
                    Text(card.sourceSets.joined(separator: " · "))
                        .font(.rounded(11, .medium))
                        .foregroundStyle(Color.secondaryText(scheme))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            exampleChip
        }
    }

    /// Three states, and none of them is "disabled": the panel is still worth opening on a
    /// word with no sentence, because that is where you write one. The unavailable state
    /// therefore gets its own legible neutral treatment rather than a blanket opacity,
    /// which would drop 12pt text below a readable contrast ratio while still accepting
    /// clicks — looking switched off and behaving switched on.
    private var exampleChip: some View {
        let on = isShowingSentence
        let unavailable = !card.hasExamples && !on
        let tint: Color = unavailable
            ? Color.secondaryText(scheme)
            : (scheme == .dark ? Palette.indigoLight : Palette.indigoDeep)
        let fill: AnyShapeStyle = on
            ? AnyShapeStyle(Palette.accentGradient)
            : AnyShapeStyle(unavailable
                            ? Color.primary.opacity(scheme == .dark ? 0.10 : 0.06)
                            : Palette.indigo.opacity(scheme == .dark ? 0.18 : 0.11))

        return Button(action: onToggleExamples) {
            HStack(spacing: 6) {
                Image(systemName: unavailable ? "text.quote" : "text.quote")
                    .font(.system(size: 11, weight: .bold))
                Text(unavailable ? "No sentence" : "Sentence")
                    .font(.rounded(12, .semibold))
                Text("S")
                    .font(.rounded(10, .bold))
                    .frame(width: 16, height: 16)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(on ? 0.18 : (scheme == .dark ? 0.10 : 0.07)))
                    )
            }
            .foregroundStyle(on ? Color.white : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(chipHelp)
        .accessibilityLabel(on ? "Hide sentences"
                               : (unavailable ? "No sentence for \(card.word)"
                                              : "Show sentences"))
        .accessibilityHint(unavailable
                           ? "Opens the panel where you can write one. Shortcut: S"
                           : "Shortcut: S")
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .hoverLift(scale: 1.05)
    }

    private var chipHelp: String {
        if isShowingSentence { return "Hide the sentences (S)" }
        if !card.hasExamples { return "No sentence yet — open the panel and double-click to write one (S)" }
        return "Show this word in a sentence (S)"
    }

    /// Two ways to file a word: the green action commits it to the permanent known list,
    /// the slate one parks it in the temporary Almost Known bank. A word that is already
    /// known shows only the known action — parking it would demote real progress.
    private var knownActionFooter: some View {
        HStack(spacing: 10) {
            if isCurrentKnown {
                focusedAction(.knownAction,
                    Button(action: onUnmarkKnown) {
                        actionLabel(usesShortLabels ? "Mark Unknown" : "Mark Unknown & Continue",
                                    icon: "arrow.uturn.backward.circle.fill")
                    }
                    .buttonStyle(FilledButtonStyle(gradient: Palette.learningGradient, glow: Palette.learning))
                    .help("Move this word back to still learning and continue (K)")
                    .accessibilityLabel("Mark \(card.word) as unknown and continue")
                    .hoverLift(scale: 1.03)
                )
            } else {
                focusedAction(.knownAction,
                    Button(action: onMarkKnown) {
                        actionLabel(usesShortLabels ? "Mark Known" : "Mark Known & Continue",
                                    icon: "checkmark.circle.fill")
                    }
                    .buttonStyle(FilledButtonStyle(gradient: Palette.successGradient, glow: Palette.success))
                    .help("Mark known and continue (K)")
                    .accessibilityLabel("Mark \(card.word) as known and continue")
                    .hoverLift(scale: 1.03)
                )
            }

            if showsKeyCaps { keyCap("K") }

            if !isCurrentKnown {
                // A toggle chip rather than a second swapping label: it keeps one width in
                // both states, so the primary action never has to shrink or truncate.
                focusedAction(.asideAction,
                    Button(action: isCurrentAside ? onUnmarkAside : onMarkAside) {
                        actionLabel("Almost", icon: "hourglass")
                    }
                    .buttonStyle(AlmostButtonStyle(isOn: isCurrentAside))
                    .help(isCurrentAside
                          ? "In Almost Known — press A to send it back to the new pile"
                          : "Almost know it — park this word out of the new pile without marking it known (A)")
                    .accessibilityLabel(isCurrentAside
                                        ? "Move \(card.word) out of Almost Known and continue"
                                        : "Set \(card.word) aside as almost known and continue")
                    .accessibilityAddTraits(isCurrentAside ? [.isSelected] : [])
                    .hoverLift(scale: 1.03)
                )

                if showsKeyCaps { keyCap("A") }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 26)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(Color.primary.opacity(scheme == .dark ? 0.025 : 0.015))
        .overlay(alignment: .top) {
            Divider().opacity(0.4).padding(.horizontal, 26)
        }
    }

    private func actionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.rounded(15, .bold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
    }

    private func keyCap(_ key: String) -> some View {
        Text(key)
            .font(.rounded(11, .bold))
            .foregroundStyle(Color.secondaryText(scheme))
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(scheme == .dark ? 0.10 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.14 : 0.09), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func focusedAction<Content: View>(_ control: StudyControlFocus, _ content: Content) -> some View {
        if let actionFocus {
            content.focused(actionFocus, equals: control)
        } else {
            content
        }
    }

    // The definition is the hero of the back: as large as will fit, vertically centered.
    // Long multi-sense lists scroll with a soft fade at the bottom edge.
    @ViewBuilder
    private var backContent: some View {
        if card.hasContent {
            if card.senses.count > 3 {
                ScrollView { sensesStack }
                    .mask(
                        LinearGradient(colors: [.black, .black, .black, .clear],
                                       startPoint: .top, endPoint: .bottom)
                    )
            } else {
                Spacer(minLength: 0)
                sensesStack
                Spacer(minLength: 0)
            }
        } else {
            Spacer()
            Text("No definition available")
                .font(.rounded(16, .medium))
                .foregroundStyle(Color.secondaryText(scheme))
                .frame(maxWidth: .infinity)
            Spacer()
        }
    }

    /// Size the definition to fill the card — a single short definition is huge; more
    /// senses (or longer text) scale down so everything stays legible and un-clipped.
    private var senseFontSize: CGFloat {
        switch card.senses.count {
        case 1:
            let len = card.senses.first?.definition.count ?? 0
            if len <= 10 { return 46 }
            if len <= 18 { return 38 }
            if len <= 30 { return 30 }
            return 25
        case 2: return 30
        case 3: return 25
        default: return 21
        }
    }

    private var sensesStack: some View {
        let single = card.senses.count == 1
        return VStack(alignment: single ? .center : .leading, spacing: single ? 12 : 20) {
            ForEach(Array(card.senses.enumerated()), id: \.offset) { _, sense in
                senseRow(sense, centered: single)
            }
        }
        .frame(maxWidth: .infinity, alignment: single ? .center : .leading)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        // Merging the part-of-speech chips into the definitions is what you want *here* —
        // it reads as one sentence instead of a stutter of badges and fragments.
        .accessibilityElement(children: .combine)
    }

    private func senseRow(_ sense: Sense, centered: Bool) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 10) {
            if !sense.partOfSpeech.isEmpty {
                Text(sense.partOfSpeech)
                    .font(.rounded(13, .semibold))
                    .foregroundStyle(scheme == .dark ? Palette.indigoLight : Palette.indigoDeep)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Palette.indigo.opacity(scheme == .dark ? 0.20 : 0.14)))
            }
            Text(sense.definition.isEmpty ? "—" : sense.definition)
                .font(.rounded(senseFontSize, .bold))
                .lineSpacing(6)
                .foregroundStyle(Color.primaryText(scheme))
                .multilineTextAlignment(centered ? .center : .leading)
                .minimumScaleFactor(0.4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }

    // MARK: - Shared chrome

    @ViewBuilder
    private func cardSurface<Content: View>(tinted: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: Metric.cardCorner, style: .continuous)
                    .fill(Color.surface(scheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: Metric.cardCorner, style: .continuous)
                            .fill(tinted
                                  ? LinearGradient(colors: [Palette.indigo.opacity(scheme == .dark ? 0.18 : 0.08),
                                                            Palette.violet.opacity(scheme == .dark ? 0.10 : 0.04)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                  : LinearGradient(colors: [.clear, .clear], startPoint: .top, endPoint: .bottom))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metric.cardCorner, style: .continuous)
                    .strokeBorder(Color.white.opacity(scheme == .dark ? 0.10 : 0.6), lineWidth: 1)
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.14), radius: 28, x: 0, y: 18)
    }
}
