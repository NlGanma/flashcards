import SwiftUI

/// The first-run / no-file screen: a big, inviting drop zone with a file picker fallback.
struct EmptyStateView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var isTargeted = false
    @State private var appeared = SnapshotConfig.skipIntro

    var body: some View {
        VStack(spacing: 0) {
            BrandHeader()
                .padding(.top, 30)
                .padding(.horizontal, 34)

            Spacer(minLength: 12)

            VStack(spacing: 22) {
                if let error = app.errorMessage {
                    MessageBanner(kind: .error, text: error) {
                        withAnimation { app.errorMessage = nil }
                    }
                    .frame(maxWidth: 460)
                }

                dropZone
                    .frame(maxWidth: 520)

                Text("Your words stay entirely on this Mac — no account, no cloud.")
                    .font(.rounded(12, .medium))
                    .foregroundStyle(Color.secondaryText(scheme))
            }
            .scaleEffect(appeared ? 1 : 0.96)
            .opacity(appeared ? 1 : 0)

            Spacer(minLength: 24)

            formatHint
                .padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { withAnimation(Motion.gentleSpring.delay(0.05)) { appeared = true } }
    }

    private var dropZone: some View {
        FileDropZone(isTargeted: $isTargeted, onDrop: { app.handleDrop(url: $0) }) {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Palette.accentGradient)
                        .frame(width: 92, height: 92)
                        .shadow(color: Palette.indigo.opacity(0.4), radius: 18, y: 8)
                        .scaleEffect(isTargeted ? 1.08 : 1)
                    Image(systemName: isTargeted ? "arrow.down.doc.fill" : "tray.and.arrow.down.fill")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 7) {
                    Text(isTargeted ? "Release to load" : "Drop your vocabulary file")
                        .font(.rounded(22, .bold))
                        .foregroundStyle(Color.primaryText(scheme))
                    Text("Drag an Excel (.xlsx) file here, or choose one below")
                        .font(.rounded(14, .medium))
                        .foregroundStyle(Color.secondaryText(scheme))
                        .multilineTextAlignment(.center)
                }

                Button {
                    app.presentOpenPanel()
                } label: {
                    Label("Choose File…", systemImage: "folder.fill")
                }
                .buttonStyle(FilledButtonStyle())
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 52)
            .padding(.horizontal, 30)
            .background(
                RoundedRectangle(cornerRadius: Metric.cardCorner, style: .continuous)
                    .fill(Color.surface(scheme).opacity(isTargeted ? 1 : 0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metric.cardCorner, style: .continuous)
                    .strokeBorder(
                        isTargeted ? Palette.indigo : Color.primary.opacity(scheme == .dark ? 0.14 : 0.12),
                        style: StrokeStyle(lineWidth: isTargeted ? 2.5 : 1.5, dash: isTargeted ? [] : [8, 7])
                    )
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.08), radius: 24, y: 14)
            .scaleEffect(isTargeted ? 1.01 : 1)
        }
    }

    private var formatHint: some View {
        VStack(spacing: 8) {
            Text("Expected format")
                .font(.rounded(11, .semibold))
                .foregroundStyle(Color.secondaryText(scheme))
                .textCase(.uppercase)
                .tracking(0.6)
            HStack(spacing: 8) {
                hintChip("English word")
                hintChip("Part of speech")
                hintChip("Chinese definition")
            }
            Text("Repeated in 3-column blocks, side by side (Practice 1, Practice 2 …)")
                .font(.rounded(12, .regular))
                .foregroundStyle(Color.secondaryText(scheme))
        }
    }

    private func hintChip(_ text: String) -> some View {
        Text(text)
            .font(.rounded(12, .semibold))
            .foregroundStyle(Palette.indigo)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Capsule().fill(Palette.indigo.opacity(scheme == .dark ? 0.18 : 0.10)))
    }
}

/// Small app wordmark used at the top of the empty/setup screens.
struct BrandHeader: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.accentGradient)
                    .frame(width: 34, height: 34)
                Image(systemName: "character.book.closed.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text("Vocab Flashcards")
                .font(.rounded(19, .bold))
                .foregroundStyle(Color.primaryText(scheme))
            Spacer()
        }
    }
}
