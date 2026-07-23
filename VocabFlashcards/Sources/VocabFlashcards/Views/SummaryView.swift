import SwiftUI
import VocabKit

/// End-of-round summary: an animated progress ring, stat tiles, and next-step actions.
struct SummaryView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var appeared = SnapshotConfig.skipIntro

    /// The last real result this screen showed. Leaving the summary clears `lastSummary`
    /// in the same transaction as the route, and this view keeps rendering for the whole
    /// cross-fade — without a remembered value the user's result would visibly collapse to
    /// zeros on its way out.
    @State private var shown: RoundSummary?

    private var summary: RoundSummary {
        app.lastSummary ?? shown
            ?? RoundSummary(roundNumber: 1, totalStudied: 0, markedKnown: 0, stillUnknown: 0)
    }

    var body: some View {
        ZStack {
            if summary.markedKnown > 0 {
                ConfettiView()
                    .id(summary.roundNumber)          // re-fire for each round
            }

            VStack(spacing: 26) {
                ring
                    .padding(.top, 8)

                VStack(spacing: 6) {
                    Text(headline)
                        .font(.rounded(28, .bold))
                        .foregroundStyle(Color.primaryText(scheme))
                        .multilineTextAlignment(.center)
                    Text(subheadline)
                        .font(.rounded(14, .medium))
                        .foregroundStyle(Color.secondaryText(scheme))
                }

                HStack(spacing: 14) {
                    statTile(value: summary.markedKnown, label: "Known", tint: Palette.success, icon: "checkmark.seal.fill")
                    statTile(value: summary.stillUnknown, label: "Still Learning", tint: Palette.learning, icon: "arrow.triangle.2.circlepath")
                    if summary.setAside > 0 {
                        statTile(value: summary.setAside, label: "Almost", tint: Palette.learning, icon: "hourglass")
                    }
                    statTile(value: summary.totalStudied, label: "Studied", tint: Palette.indigo, icon: "rectangle.stack.fill")
                }

                actions
                    .padding(.top, 4)
            }
            .frame(maxWidth: 560)
            .padding(36)
            .panel(corner: Metric.cardCorner)
            .padding(30)
            .scaleEffect(appeared ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            shown = app.lastSummary
            withAnimation(Motion.gentleSpring) { appeared = true }
            if !SnapshotConfig.skipIntro { Haptics.mark() }
        }
        .onChange(of: app.lastSummary) { latest in
            if let latest { shown = latest }
        }
    }

    // MARK: - Ring

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(scheme == .dark ? 0.12 : 0.08), lineWidth: 16)
            Circle()
                .trim(from: 0, to: appeared ? max(0.001, summary.knownFraction) : 0)
                .stroke(Palette.successGradient,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.gentleSpring.delay(0.1), value: appeared)
            VStack(spacing: 2) {
                if summary.isPerfect {
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(Palette.success)
                } else {
                    Text("\(knownPercent)%")
                        .font(.rounded(38, .bold))
                        .foregroundStyle(Color.primaryText(scheme))
                        .monospacedDigit()
                }
                Text("known")
                    .font(.rounded(13, .medium))
                    .foregroundStyle(Color.secondaryText(scheme))
            }
        }
        .frame(width: 170, height: 170)
    }

    private var knownPercent: Int { summary.knownPercent }

    // MARK: - Stat tile

    private func statTile(value: Int, label: String, tint: Color, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
            Text("\(value)")
                .font(.rounded(28, .bold))
                .foregroundStyle(Color.primaryText(scheme))
                .monospacedDigit()
            Text(label)
                .font(.rounded(11, .medium))
                .foregroundStyle(Color.secondaryText(scheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(scheme == .dark ? 0.14 : 0.08))
        )
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 10) {
            // One primary action: replay the unmarked words, or restart on a clean sweep.
            Button {
                app.studyAgain()
            } label: {
                Label(studyAgainTitle, systemImage: summary.hasRemaining ? "arrow.counterclockwise" : "play.fill")
                    .font(.rounded(16, .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
            }
            .buttonStyle(FilledButtonStyle())
            .keyboardShortcut(.return, modifiers: [])
            .hoverLift(scale: 1.02)

            // One tap to clear this round's leftovers out of the new pile without
            // pretending they're known.
            if stillUnknownCount > 0 {
                Button {
                    withAnimation(Motion.spring) { app.setAsideStillUnknown() }
                } label: {
                    Label("Set Aside \(stillUnknownCount) as Almost Known", systemImage: "hourglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AlmostButtonStyle())
                .help("Park the words you didn't know out of the new pile — revert them any time")
            }

            HStack(spacing: 10) {
                Button {
                    app.backToSetup()
                } label: {
                    Label("Back to Sets", systemImage: "square.grid.2x2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftButtonStyle(tint: Palette.indigo))

                Button {
                    app.showWordManager(.known)
                } label: {
                    Label("Known Words", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftButtonStyle(tint: Palette.success))
            }
        }
    }

    /// Only offered for cards actually seen this round — unvisited cards were never judged.
    private var stillUnknownCount: Int { app.stillUnknownCards.count }

    private var studyAgainTitle: String {
        guard summary.hasRemaining else { return "Study Again" }
        let count = app.session?.remainingCards.count ?? (summary.stillUnknown + summary.unvisited)
        return "Study \(count) Remaining"
    }

    // MARK: - Copy

    private var headline: String {
        if summary.isPerfect { return "Flawless round!" }
        switch summary.knownFraction {
        case 0.7...: return "Great progress!"
        case 0.3..<0.7: return "Nice work — keep going!"
        default: return "Every rep counts."
        }
    }

    private var subheadline: String {
        if summary.isPerfect {
            return "All \(summary.totalStudied) words are marked as known."
        }
        if summary.unvisited > 0 {
            return "\(summary.unvisited) card\(summary.unvisited == 1 ? "" : "s") still waiting in this round."
        }
        if summary.hasRemaining {
            return "Ready for another pass at the ones still to master?"
        }
        return "Round \(summary.roundNumber) complete."
    }
}
