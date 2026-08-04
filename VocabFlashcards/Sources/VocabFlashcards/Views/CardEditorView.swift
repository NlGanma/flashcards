import SwiftUI
import VocabKit

/// Hand-correct a card: its word, every meaning, and the sentence that demonstrates each
/// one. Opened by double-clicking a revealed card (or pressing E).
///
/// Edits are stored locally against the word's key and layered over the spreadsheet, so
/// the original file is never written to and a correction survives reloading it.
struct CardEditorView: View {
    let card: Flashcard
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var word: String
    @State private var senses: [SenseDraft]
    @State private var showRevertConfirm = false

    init(card: Flashcard) {
        self.card = card
        _word = State(initialValue: card.word)
        // A word list with no definition column produces a card with no senses at all.
        // Opening the editor on one has to offer somewhere to type, not an empty form.
        let drafts = card.senses.map(SenseDraft.init)
        _senses = State(initialValue: drafts.isEmpty ? [SenseDraft()] : drafts)
    }

    /// One editable meaning. Identity is synthesized so rows survive reordering and
    /// deletion while the user is typing into them.
    private struct SenseDraft: Identifiable {
        let id = UUID()
        var partOfSpeech: String
        var definition: String
        var english: String
        var chinese: String

        init(_ sense: Sense) {
            partOfSpeech = sense.partOfSpeech
            definition = sense.definition
            english = sense.example?.english ?? ""
            chinese = sense.example?.chinese ?? ""
        }

        init() {
            partOfSpeech = ""
            definition = ""
            english = ""
            chinese = ""
        }

        var trimmedSense: Sense {
            Sense(partOfSpeech: partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines),
                  definition: definition.trimmingCharacters(in: .whitespacesAndNewlines),
                  example: Example(english: english.trimmingCharacters(in: .whitespacesAndNewlines),
                                   chinese: chinese.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        /// Whether this block can be stored: a card sense is identified by its part of
        /// speech and definition, so one of those has to be present.
        var hasMeaning: Bool {
            !definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        /// Whether the user has typed anything at all into this block. A block holding only
        /// a sentence can't be saved, but it must never be silently thrown away either —
        /// it is usually the longest thing they wrote.
        var hasAnything: Bool {
            hasMeaning
                || !english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !chinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        /// Typed a sentence but no meaning to attach it to — the one blocking state.
        var isOrphanedSentence: Bool { hasAnything && !hasMeaning }
    }

    /// Indexes of blocks that hold a sentence with nothing to attach it to.
    private var orphanedSenses: [Int] {
        senses.indices.filter { senses[$0].isOrphanedSentence }
    }

    private var canSave: Bool {
        !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && senses.contains(where: \.hasMeaning)
            && orphanedSenses.isEmpty
    }

    /// Why Save is unavailable, in the user's terms. Nil when it is available.
    private var blockingReason: String? {
        if word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "The word can't be empty." }
        if !orphanedSenses.isEmpty {
            return "Add a part of speech or definition to keep the sentence you wrote."
        }
        if !senses.contains(where: \.hasMeaning) { return "Add at least one meaning." }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            SnapshotableScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    wordField
                    ForEach(Array(senses.enumerated()), id: \.element.id) { index, _ in
                        senseCard(index: index)
                    }
                    addSenseButton
                }
                .padding(20)
            }
            footer
        }
        .frame(width: 580, height: 620)
        .background(Color.surface(scheme))
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Edit Card")
                    .font(.rounded(20, .bold))
                    .foregroundStyle(Color.primaryText(scheme))
                Text(app.editingCardIsEdited
                     ? "This card has been edited. Your version is used everywhere."
                     : "Changes are saved on this Mac — your spreadsheet isn't touched.")
                    .font(.rounded(12, .medium))
                    .foregroundStyle(Color.secondaryText(scheme))
            }
            Spacer(minLength: 12)
            Image(systemName: "square.and.pencil")
                .font(.system(size: 20))
                .foregroundStyle(Palette.indigo)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if app.editingCardIsEdited {
                Button(role: .destructive) {
                    showRevertConfirm = true
                } label: {
                    Label("Revert", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(GhostButtonStyle())
                .help("Discard your edits and go back to the original content")
                .confirmationDialog("Revert this card to the original?",
                                    isPresented: $showRevertConfirm, titleVisibility: .visible) {
                    Button("Revert", role: .destructive) { app.revertCardEdit() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The word, meanings and sentences go back to what the spreadsheet and the built-in examples say.")
                }
            }
            Spacer(minLength: 12)
            if let blockingReason {
                Text(blockingReason)
                    .font(.rounded(11, .medium))
                    .foregroundStyle(Palette.amber)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 220)
                    .transition(.opacity)
            }
            Button("Cancel") { app.editingCard = nil }
                .buttonStyle(SoftButtonStyle())
                .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .buttonStyle(FilledButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
                .help(blockingReason ?? "Save this card")
        }
        .animation(Motion.quick, value: blockingReason)
        .padding(16)
        .background(Color.surface(scheme))
        .overlay(Divider().opacity(0.4), alignment: .top)
    }

    // MARK: - Fields

    private var wordField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Word")
            field("English word", text: $word, font: .rounded(20, .bold))
            Text("Renaming changes what you see. The original spelling stays this card's identity, so your known-word history follows it.")
                .font(.rounded(11, .medium))
                .foregroundStyle(Color.secondaryText(scheme))
        }
    }

    private func senseCard(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(senses.count > 1 ? "Meaning \(index + 1)" : "Meaning")
                    .font(.rounded(13, .bold))
                    .foregroundStyle(scheme == .dark ? Palette.indigoLight : Palette.indigoDeep)
                Spacer()
                Button {
                    withAnimation(Motion.quick) { _ = senses.remove(at: index) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.secondaryText(scheme))
                }
                .buttonStyle(.plain)
                .disabled(senses.count <= 1)
                .opacity(senses.count <= 1 ? 0.3 : 1)
                .help("Remove this meaning")
            }

            HStack(alignment: .top, spacing: 10) {
                labelled("Part of speech") {
                    field("n.", text: $senses[index].partOfSpeech, font: .rounded(14, .semibold))
                }
                .frame(width: 110)

                labelled("Chinese definition") {
                    field("中文释义", text: $senses[index].definition,
                          font: .rounded(15, .semibold), lines: 1...3)
                }
            }

            labelled("Example sentence") {
                field("An SAT-level sentence using the word", text: $senses[index].english,
                      font: .rounded(14), lines: 2...5)
            }

            labelled("Chinese translation") {
                field("句子的中文翻译", text: $senses[index].chinese,
                      font: .rounded(14), lines: 2...4)
            }

            if senses[index].isOrphanedSentence {
                Label("A sentence needs a meaning to sit under. Add a part of speech or a definition, or this block can't be saved.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.rounded(11, .medium))
                    .foregroundStyle(Palette.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Metric.panelCorner, style: .continuous)
                .fill(Color.primary.opacity(scheme == .dark ? 0.05 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metric.panelCorner, style: .continuous)
                .strokeBorder(senses[index].isOrphanedSentence
                              ? Palette.amber.opacity(0.7)
                              : Color.primary.opacity(scheme == .dark ? 0.10 : 0.06),
                              lineWidth: senses[index].isOrphanedSentence ? 1.5 : 1)
        )
        .animation(Motion.quick, value: senses[index].isOrphanedSentence)
    }

    private var addSenseButton: some View {
        Button {
            withAnimation(Motion.quick) { senses.append(SenseDraft()) }
        } label: {
            Label(senses.contains(where: \.hasAnything) ? "Add another meaning" : "Add a meaning",
                  systemImage: "plus.circle.fill")
        }
        .buttonStyle(SoftButtonStyle())
    }

    private func labelled<Content: View>(_ title: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            fieldLabel(title)
            content()
        }
    }

    /// One text box. `ImageRenderer` can't rasterize AppKit-backed text fields, so in
    /// snapshot mode the same box is drawn with its value as static text — otherwise this
    /// whole screen photographs blank and the layout can't be checked at all.
    @ViewBuilder
    private func field(_ placeholder: String, text: Binding<String>,
                       font: Font, lines: ClosedRange<Int>? = nil) -> some View {
        Group {
            if SnapshotConfig.skipIntro {
                Text(text.wrappedValue.isEmpty ? placeholder : text.wrappedValue)
                    .font(font)
                    .foregroundStyle(text.wrappedValue.isEmpty
                                     ? Color.secondaryText(scheme) : Color.primaryText(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let lines {
                TextField(placeholder, text: text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(font)
                    .lineLimit(lines)
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(font)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(fieldBackground)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.rounded(10, .bold))
            .tracking(0.6)
            .foregroundStyle(Color.secondaryText(scheme))
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: Metric.controlCorner, style: .continuous)
            .fill(Color.primary.opacity(scheme == .dark ? 0.09 : 0.05))
            .overlay(
                RoundedRectangle(cornerRadius: Metric.controlCorner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.12 : 0.07), lineWidth: 1)
            )
    }

    /// `canSave` already guarantees no block holds an orphaned sentence, so filtering here
    /// only drops blocks the user never typed into — it can no longer discard their work.
    private func save() {
        guard canSave else { return }
        app.saveCardEdit(word: word, senses: senses.filter(\.hasMeaning).map(\.trimmedSense))
    }
}
