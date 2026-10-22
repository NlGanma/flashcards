import SwiftUI
import VocabKit

/// The conversation that shapes the cards. The first message says what goes on the back
/// of every card; later ones change all the cards, or only the one picked on the left.
struct StudioChatPanel: View {
    @ObservedObject var studio: GenerationStudio
    @Environment(\.colorScheme) private var scheme
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            transcript
            Divider().opacity(0.4)
            composer
        }
        .background(
            RoundedRectangle(cornerRadius: Metric.panelCorner, style: .continuous)
                .fill(Color.surface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metric.panelCorner, style: .continuous)
                .strokeBorder(Palette.indigo.opacity(scheme == .dark ? 0.22 : 0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.10), radius: 22, x: 0, y: 12)
        .onAppear { composerFocused = true }
        .onChange(of: studio.focusedCardID) { _ in composerFocused = true }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.accentGradient)
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Card assistant")
                    .font(.rounded(14, .bold))
                    .foregroundStyle(Color.primaryText(scheme))
                Text("Runs on your Mac. Nothing leaves it.")
                    .font(.rounded(11, .medium))
                    .foregroundStyle(Color.secondaryText(scheme))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            SnapshotableScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(studio.messages) { message in
                        bubble(message).id(message.id)
                    }
                    if studio.isWorking {
                        TypingIndicator().id("typing")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: studio.messages.count) { _ in
                withAnimation(Motion.quick) { proxy.scrollTo(studio.messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: studio.isWorking) { working in
                if working { withAnimation(Motion.quick) { proxy.scrollTo("typing", anchor: .bottom) } }
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func bubble(_ message: GenerationStudio.Message) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                VStack(alignment: .trailing, spacing: 4) {
                    if let front = message.cardFront {
                        Label("About “\(front)”", systemImage: "rectangle.on.rectangle")
                            .font(.rounded(10, .semibold))
                            .foregroundStyle(Color.secondaryText(scheme))
                            .lineLimit(1)
                    }
                    Text(message.text)
                        .font(.rounded(13, .medium))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Palette.accentGradient))
                }
            }
        case .assistant:
            Self.inlineMarkdown(message.text)
                .font(.rounded(13, .regular))
                .foregroundStyle(Color.primaryText(scheme))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.subtleSurface(scheme)))
                .padding(.trailing, 28)
        case .error:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.amber)
                    .padding(.top, 1)
                Self.inlineMarkdown(message.text)
                    .font(.rounded(12, .medium))
                    .foregroundStyle(Color.primaryText(scheme))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Palette.amber.opacity(scheme == .dark ? 0.16 : 0.10)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.amber.opacity(0.3), lineWidth: 1))
        }
    }

    /// The app's own messages use `code` for commands to type. Line breaks are kept; the
    /// learner's messages are shown exactly as typed.
    static func inlineMarkdown(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let attributed = try? AttributedString(markdown: text, options: options) else { return Text(text) }
        return Text(attributed)
    }

    // MARK: - Composer

    /// Starting points that teach what kind of thing to ask for. They fill the field
    /// rather than sending, so they can be edited first.
    private var suggestions: [String] {
        if studio.cards.isEmpty {
            return ["A one-sentence definition",
                    "Definition plus an example sentence",
                    "The Chinese translation, then an example",
                    "A question on the front, the answer on the back"]
        }
        if studio.focusedCard != nil {
            return ["Make it shorter", "Add an example sentence", "Explain it more simply"]
        }
        return ["Make every back shorter", "Add an example sentence to each", "Add the Chinese translation"]
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !studio.isWorking {
                FlowRow(spacing: 6) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            studio.draft = suggestion
                            composerFocused = true
                        } label: {
                            Text(suggestion)
                                .font(.rounded(11, .semibold))
                                .foregroundStyle(scheme == .dark ? Palette.indigoLight : Palette.indigoDeep)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Palette.indigo.opacity(scheme == .dark ? 0.16 : 0.09)))
                        }
                        .buttonStyle(.plain)
                        .hoverLift(scale: 1.04)
                    }
                }
            }

            scopeLine

            HStack(alignment: .bottom, spacing: 8) {
                TextField(placeholder, text: $studio.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.rounded(13, .medium))
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .onSubmit { studio.send() }
                    .disabled(studio.isWorking)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(scheme == .dark ? 0.07 : 0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(composerFocused ? Palette.indigo.opacity(0.6) : Color.primary.opacity(0.08),
                                      lineWidth: 1))

                if studio.isWorking {
                    Button(action: studio.cancel) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(SoftButtonStyle(tint: Palette.learningTint(scheme)))
                    .help("Stop the model. Cards written so far are kept.")
                } else {
                    Button(action: studio.send) {
                        Label(studio.sendTitle, systemImage: studio.cards.isEmpty ? "sparkles" : "arrow.up")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(FilledButtonStyle())
                    .disabled(!studio.canSend)
                    .help(sendHelp)
                }
            }
        }
        .padding(14)
    }

    /// Who the next message is for. Shown only once there are cards to choose between.
    @ViewBuilder
    private var scopeLine: some View {
        if let card = studio.focusedCard {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 10, weight: .bold))
                Text("Only “\(card.front)”")
                    .font(.rounded(11, .semibold))
                    .lineLimit(1)
                Button {
                    withAnimation(Motion.spring) { studio.focusedCardID = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Talk about all the cards again")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Palette.accentGradient))
        } else if !studio.cards.isEmpty {
            Label("All \(studio.cards.count) cards · click a card to talk about just that one",
                  systemImage: "square.stack.3d.up")
                .font(.rounded(11, .medium))
                .foregroundStyle(Color.secondaryText(scheme))
                .lineLimit(1)
        }
    }

    private var placeholder: String {
        if studio.cards.isEmpty { return "What should the back of each card say?" }
        if let card = studio.focusedCard { return "What should change on “\(card.front)”?" }
        return "What should change on every card?"
    }

    private var sendHelp: String {
        if studio.cards.isEmpty { return "Write the cards (Return)" }
        return studio.focusedCard == nil ? "Apply this to every card (Return)" : "Apply this to the picked card (Return)"
    }
}

/// Three dots that pulse while the model is working.
private struct TypingIndicator: View {
    @Environment(\.colorScheme) private var scheme
    @State private var phase = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondaryText(scheme))
                    .frame(width: 6, height: 6)
                    .opacity(phase ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2), value: phase)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.subtleSurface(scheme)))
        .onAppear { phase = true }
        .accessibilityLabel("The model is writing")
    }
}

/// Lays chips out left to right, wrapping onto new lines. (macOS 13 has `Layout` but no
/// built-in flow layout.)
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            for (index, x) in zip(row.indices, row.xs) {
                subviews[index].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y),
                                      proposal: .unspecified)
            }
        }
    }

    private struct Row { var indices: [Int] = []; var xs: [CGFloat] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            let x = row.indices.isEmpty ? 0 : row.width + spacing
            if !row.indices.isEmpty, x + size.width > width {
                let y = row.y + row.height + spacing
                rows.append(Row(y: y))
                row = rows[rows.count - 1]
                row.indices = [index]; row.xs = [0]; row.width = size.width; row.height = size.height
            } else {
                row.indices.append(index); row.xs.append(x); row.width = x + size.width
                row.height = max(row.height, size.height)
            }
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
