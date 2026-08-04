import SwiftUI
import VocabKit

/// The panel that slides out beside a revealed card: one SAT-level sentence for each
/// individual gloss in the definition, in both languages.
///
/// A definition like "恶棍，歹徒；不法的，邪恶的" is four separate meanings and gets four
/// sentences. Each is headed by its own gloss rather than by the whole definition — the
/// full definition is already on the card two inches to the left, and repeating it here
/// would just be a second headline competing with the sentences.
struct SentencePanelView: View {
    let card: Flashcard
    var onClose: () -> Void = {}
    var onEdit: () -> Void = {}
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.4).padding(.horizontal, 20)
            content
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Metric.panelCorner, style: .continuous)
                .fill(Color.surface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metric.panelCorner, style: .continuous)
                .strokeBorder(Palette.indigo.opacity(scheme == .dark ? 0.22 : 0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.12), radius: 22, x: 0, y: 14)
        // Same double-click affordance as the card, so the panel you're reading is also
        // the panel you can correct.
        .onTapGesture(count: 2, perform: onEdit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Example sentences for \(card.word)")
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.quote")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.indigo)
            Text("In context")
                .font(.rounded(13, .bold))
                .foregroundStyle(Color.primaryText(scheme))
            // Several meanings won't fit in a 380pt panel, and macOS hides its scrollers
            // until you scroll — so the count is the only thing telling you to look.
            if entries.count > 1 {
                Text("\(entries.count) meanings")
                    .font(.rounded(11, .medium))
                    .foregroundStyle(Color.secondaryText(scheme))
            }
            Spacer(minLength: 4)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.secondaryText(scheme))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(scheme == .dark ? 0.10 : 0.06)))
            }
            .buttonStyle(.plain)
            .help("Close the example panel (S)")
            .accessibilityLabel("Close example panel")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 10, weight: .semibold))
            Text("Double-click to edit")
                .font(.rounded(11, .medium))
        }
        .foregroundStyle(Color.secondaryText(scheme))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .overlay(Divider().opacity(0.4).padding(.horizontal, 20), alignment: .top)
    }

    // MARK: - Senses

    /// One row per gloss that has a sentence, flattened across every sense of the card.
    private struct Entry: Identifiable {
        let id: Int
        let partOfSpeech: String
        let gloss: String
        let example: Example
        /// True for the first entry of each sense, which is where the part of speech goes.
        let startsSense: Bool
    }

    private var entries: [Entry] {
        var result: [Entry] = []
        for sense in card.senses {
            var first = true
            for example in sense.examples {
                result.append(Entry(id: result.count,
                                    partOfSpeech: sense.partOfSpeech,
                                    gloss: example.gloss.isEmpty ? sense.definition : example.gloss,
                                    example: example,
                                    startsSense: first))
                first = false
            }
        }
        return result
    }

    @ViewBuilder
    private var content: some View {
        let rows = entries
        if rows.isEmpty {
            emptyState
        } else {
            SnapshotableScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(rows) { entry in
                        entryBlock(entry, number: rows.count > 1 ? entry.id + 1 : nil)
                        if entry.id < rows.count - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // More than one meaning cannot fit; fade the bottom edge so the cut reads as
            // "there is more below" rather than as the footer's rule.
            .mask(rows.count > 1
                  ? LinearGradient(colors: [.black, .black, .black, .black.opacity(0.15)],
                                   startPoint: .top, endPoint: .bottom)
                  : LinearGradient(colors: [.black, .black], startPoint: .top, endPoint: .bottom))
        }
    }

    /// Most words in a workbook have no curated sentence. Repeating the definitions the
    /// card is already showing, once per sense, spends a third of the window on nothing —
    /// so say plainly that there is no sentence and point at the way to write one.
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Image(systemName: "text.quote")
                .font(.system(size: 26))
                .foregroundStyle(Palette.indigo.opacity(0.5))
            Text("No sentence yet")
                .font(.rounded(15, .semibold))
                .foregroundStyle(Color.primaryText(scheme))
            Text("“\(card.word)” doesn't have an example sentence.\nDouble-click to write one.")
                .font(.rounded(12, .medium))
                .foregroundStyle(Color.secondaryText(scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 22)
    }

    /// One gloss and the sentence that teaches it. The gloss is a compact label, not a
    /// headline — the card already carries the full definition at full size.
    private func entryBlock(_ entry: Entry, number: Int?) -> some View {
        let accent = scheme == .dark ? Palette.indigoLight : Palette.indigoDeep
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                if let number {
                    Text("\(number)")
                        .font(.rounded(10, .bold))
                        .foregroundStyle(.white)
                        .frame(width: 17, height: 17)
                        .background(Circle().fill(Palette.indigo.opacity(0.85)))
                }
                Text(entry.gloss)
                    .font(.rounded(14, .bold))
                    .foregroundStyle(Color.primaryText(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                // The part of speech belongs to the sense, so it is shown once, on the
                // first gloss of each sense, rather than repeated on every row.
                if entry.startsSense, !entry.partOfSpeech.isEmpty {
                    Text(entry.partOfSpeech)
                        .font(.rounded(10, .semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Palette.indigo.opacity(scheme == .dark ? 0.20 : 0.14)))
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HighlightedSentence(
                    sentence: entry.example.english,
                    highlights: SentenceHighlighter.englishRanges(in: entry.example.english,
                                                                  word: card.word),
                    size: 14,
                    accent: accent,
                    base: Color.primaryText(scheme)
                )
                if !entry.example.chinese.isEmpty {
                    HighlightedSentence(
                        sentence: entry.example.chinese,
                        highlights: SentenceHighlighter.chineseRanges(in: entry.example.chinese,
                                                                      definition: entry.gloss),
                        size: 12.5,
                        accent: accent,
                        base: Color.secondaryText(scheme),
                        lineSpacing: 4
                    )
                }
            }
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Palette.indigo.opacity(scheme == .dark ? 0.35 : 0.22))
                    .frame(width: 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
