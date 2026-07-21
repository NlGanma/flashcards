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
    var isCurrentKnown: Bool = false
    var onFlip: () -> Void = {}
    var onMarkKnown: () -> Void = {}
    var onUnmarkKnown: () -> Void = {}
    var actionFocus: FocusState<StudyControlFocus?>.Binding? = nil
    @Environment(\.colorScheme) private var scheme

    private var angle: Double { isShowingBack ? 180 : 0 }

    var body: some View {
        front
            .flip(angle: angle) { back }
            .frame(maxWidth: Metric.cardMaxWidth)
            .frame(height: Metric.cardHeight)
            .overlay {                                   // celebratory border glow
                if isKnownFlash {
                    RoundedRectangle(cornerRadius: Metric.cardCorner, style: .continuous)
                        .strokeBorder(Palette.success, lineWidth: 3)
                        .shadow(color: Palette.success.opacity(0.5), radius: 16)
                        .transition(.opacity)
                }
            }
            .overlay {                                   // springy check-badge pop
                if isKnownFlash {
                    knownBadge.transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .animation(Motion.pop, value: isKnownFlash)
    }

    private var knownBadge: some View {
        ZStack {
            Circle().fill(Palette.successGradient)
                .frame(width: 78, height: 78)
                .shadow(color: Palette.success.opacity(0.5), radius: 16)
            Image(systemName: "checkmark")
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
                    HStack(alignment: .firstTextBaseline) {
                        Text(card.word)
                            .font(.rounded(26, .bold))
                            .tracking(-0.5)
                            .foregroundStyle(Color.primaryText(scheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer(minLength: 8)
                        if !card.sourceSets.isEmpty {
                            Text(card.sourceSets.joined(separator: " · "))
                                .font(.rounded(12, .medium))
                                .foregroundStyle(Color.secondaryText(scheme))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                    Divider().opacity(0.4).padding(.horizontal, 26)

                    backContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onFlip)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Activate to show the word again")
                .accessibilityAddTraits(.isButton)

                knownActionFooter
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var knownActionFooter: some View {
        HStack(spacing: 10) {
            if isCurrentKnown {
                focusedKnownAction(
                    Button(action: onUnmarkKnown) {
                        Label("Mark Unknown & Continue", systemImage: "arrow.uturn.backward.circle.fill")
                            .font(.rounded(15, .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 2)
                    }
                    .buttonStyle(FilledButtonStyle(gradient: Palette.learningGradient, glow: Palette.learning))
                    .help("Move this word back to still learning and continue (K)")
                    .accessibilityLabel("Mark \(card.word) as unknown and continue")
                    .hoverLift(scale: 1.03)
                )
            } else {
                focusedKnownAction(
                    Button(action: onMarkKnown) {
                        Label("Mark Known & Continue", systemImage: "checkmark.circle.fill")
                            .font(.rounded(15, .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 2)
                    }
                    .buttonStyle(FilledButtonStyle(gradient: Palette.successGradient, glow: Palette.success))
                    .help("Mark known and continue (K)")
                    .accessibilityLabel("Mark \(card.word) as known and continue")
                    .hoverLift(scale: 1.03)
                )
            }

            Text("K")
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
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 26)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(Color.primary.opacity(scheme == .dark ? 0.025 : 0.015))
        .overlay(alignment: .top) {
            Divider().opacity(0.4).padding(.horizontal, 26)
        }
    }

    @ViewBuilder
    private func focusedKnownAction<Content: View>(_ content: Content) -> some View {
        if let actionFocus {
            content.focused(actionFocus, equals: .knownAction)
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
