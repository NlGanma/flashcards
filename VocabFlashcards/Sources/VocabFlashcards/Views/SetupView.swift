import SwiftUI
import VocabKit

/// Shows the loaded file, lets the user pick practice sets and a study mode, and starts
/// a run in a single action.
struct SetupView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 30)
                .padding(.top, 26)
                .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let error = app.errorMessage {
                        MessageBanner(kind: .error, text: error) {
                            withAnimation { app.errorMessage = nil }
                        }
                    }
                    if let info = app.infoMessage {
                        MessageBanner(kind: .info, text: info) {
                            withAnimation { app.infoMessage = nil }
                        }
                    }

                    headerRow

                    if let file = app.loadedFile {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(file.sets) { set in
                                PracticeSetCardView(
                                    set: set,
                                    isSelected: app.selectedSetIDs.contains(set.id),
                                    knownCount: knownCount(in: set),
                                    asideCount: asideCount(in: set)
                                )
                                .onTapGesture {
                                    withAnimation(Motion.spring) { app.toggleSet(set.id) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 120)
            }
        }
        .overlay(alignment: .bottom) { startBar }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.indigo)
            Text(app.loadedFile?.fileName ?? "No file")
                .font(.rounded(15, .semibold))
                .foregroundStyle(Color.primaryText(scheme))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if app.knownStore.asideCount > 0 {
                Button {
                    app.showWordManager(.aside)
                } label: {
                    Label("\(app.knownStore.asideCount) Almost", systemImage: "hourglass")
                }
                .buttonStyle(SoftButtonStyle(tint: Palette.learningTint(scheme)))
                .help("Words parked out of the new pile — revert them any time (⌘⇧A)")
            }
            Button {
                app.showWordManager(.known)
            } label: {
                Label("\(app.knownStore.count) Known", systemImage: "checkmark.seal.fill")
            }
            .buttonStyle(SoftButtonStyle(tint: Palette.success))
            .help("View and manage your known words (⌘⇧K)")

            Button {
                app.changeFile()
            } label: {
                Label("Change File", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(GhostButtonStyle())
            .help("Open a different vocabulary file (⌘O)")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .panel(corner: 16)
    }

    // MARK: - Header + selection controls

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose practice sets")
                    .font(.rounded(26, .bold))
                    .foregroundStyle(Color.primaryText(scheme))
                Text(selectionSummary)
                    .font(.rounded(13, .medium))
                    .foregroundStyle(Color.secondaryText(scheme))
            }
            Spacer()
            HStack(spacing: 4) {
                Button("Select All") { withAnimation(Motion.spring) { app.selectAllSets() } }
                    .buttonStyle(GhostButtonStyle())
                Button("Clear") { withAnimation(Motion.spring) { app.selectNoSets() } }
                    .buttonStyle(GhostButtonStyle())
            }
        }
        .padding(.top, 4)
    }

    private var selectionSummary: String {
        let count = app.selectedSetIDs.count
        guard count > 0 else { return "Select at least one set to begin" }
        let words = app.selectedUniqueWordCount()
        return "\(count) set\(count == 1 ? "" : "s") selected · \(words) unique word\(words == 1 ? "" : "s")"
    }

    // MARK: - Start bar (inline mode picker + one-action start)

    private var canStart: Bool { app.hasSelection && app.deckCount(for: app.pendingFilter) > 0 }

    private var startBar: some View {
        HStack(spacing: 16) {
            modePicker
            Spacer(minLength: 12)
            Button {
                app.startStudy(filter: app.pendingFilter)
            } label: {
                Label("Start Studying", systemImage: "play.fill")
                    .font(.rounded(16, .bold))
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(FilledButtonStyle())
            .disabled(!canStart)
            .opacity(canStart ? 1 : 0.5)
            .keyboardShortcut(.return, modifiers: [])
            .hoverLift(scale: 1.03)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .panel(corner: 18)
        .padding(.horizontal, 30)
        .padding(.bottom, 20)
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            modeSegment(.excludeKnown, "New")
            modeSegment(.includeKnown, "All")
            modeSegment(.onlyKnown, "Known")
        }
        .padding(4)
        .background(Capsule().fill(Color.primary.opacity(scheme == .dark ? 0.06 : 0.04)))
    }

    private func modeSegment(_ filter: KnownFilter, _ title: String) -> some View {
        let selected = app.pendingFilter == filter
        return Button {
            withAnimation(Motion.spring) { app.pendingFilter = filter }
        } label: {
            HStack(spacing: 6) {
                Text(title).font(.rounded(13, .semibold))
                Text("\(app.deckCount(for: filter))")
                    .font(.rounded(12, .semibold))
                    .monospacedDigit()
                    .opacity(0.85)
            }
            .foregroundStyle(selected ? .white : Color.secondaryText(scheme))
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(Capsule().fill(selected ? AnyShapeStyle(Palette.accentGradient) : AnyShapeStyle(Color.clear)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(filter.subtitle)
    }

    private func knownCount(in set: PracticeSet) -> Int {
        let keys = Set(set.items.map(\.key))
        return keys.filter { app.knownStore.isKnown($0) }.count
    }

    private func asideCount(in set: PracticeSet) -> Int {
        let keys = Set(set.items.map(\.key))
        return keys.filter { app.knownStore.isAside($0) }.count
    }
}

/// A selectable card representing one practice set.
struct PracticeSetCardView: View {
    let set: PracticeSet
    let isSelected: Bool
    let knownCount: Int
    var asideCount: Int = 0
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    private var uniqueCount: Int { self.set.uniqueWordCount }
    private var isMastered: Bool { uniqueCount > 0 && knownCount >= uniqueCount }
    private var accent: Color { isMastered ? Palette.success : Palette.indigo }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metric.panelCorner, style: .continuous)
        let lifted = isSelected || hovering
        let borderColor: Color = isSelected
            ? accent
            : Color.primary.opacity(hovering ? 0.16 : (scheme == .dark ? 0.10 : 0.06))
        let selectedWash: Color = isSelected ? accent.opacity(scheme == .dark ? 0.14 : 0.06) : .clear
        let shadowOpacity: Double = scheme == .dark ? 0.35 : (lifted ? 0.13 : 0.06)
        let shadowRadius: CGFloat = lifted ? 15 : 8
        let cardScale: CGFloat = (hovering && !isSelected) ? 1.02 : (isSelected ? 1.0 : 0.995)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(set.name)
                    .font(.rounded(17, .bold))
                    .foregroundStyle(Color.primaryText(scheme))
                    .lineLimit(1)
                Spacer()
                selectionIndicator
            }
            cardStats
            ProgressBar(fraction: progressFraction, height: 6,
                        tint: isMastered ? Palette.successGradient : Palette.accentGradient)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Color.surface(scheme)))
        .background(shape.fill(selectedWash))
        .overlay(shape.strokeBorder(borderColor, lineWidth: isSelected ? 2.5 : 1))
        .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowRadius / 2)
        .contentShape(shape)
        .scaleEffect(cardScale)
        .animation(Motion.quick, value: hovering)
        .hoverCursor($hovering)
    }

    private var progressFraction: Double {
        uniqueCount == 0 ? 0 : Double(knownCount) / Double(uniqueCount)
    }

    @ViewBuilder
    private var cardStats: some View {
        HStack(spacing: 8) {
            statPill(icon: "book.closed.fill",
                     text: "\(uniqueCount) \(uniqueCount == 1 ? "word" : "words")",
                     tint: Palette.indigo, deep: Palette.indigoDeep)
            if isMastered {
                statPill(icon: "checkmark.seal.fill", text: "Mastered",
                         tint: Palette.success, deep: Palette.successDeep)
            } else if knownCount > 0 {
                statPill(icon: "checkmark.seal.fill", text: "\(knownCount) known",
                         tint: Palette.success, deep: Palette.successDeep)
            }
            if asideCount > 0 {
                statPill(icon: "hourglass", text: "\(asideCount) almost",
                         tint: Palette.learning, deep: Palette.learningDeep)
            }
        }
    }

    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .fill(isSelected ? accent : Color.primary.opacity(scheme == .dark ? 0.12 : 0.08))
                .frame(width: 24, height: 24)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    private func statPill(icon: String, text: String, tint: Color, deep: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(text).font(.rounded(12, .semibold))
        }
        .foregroundStyle(scheme == .dark ? tint : deep)   // lighter on dark, deeper on light
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(Capsule().fill(tint.opacity(scheme == .dark ? 0.20 : 0.12)))
    }
}
