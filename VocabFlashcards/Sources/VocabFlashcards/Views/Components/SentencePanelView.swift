import SwiftUI
import VocabKit

/// The panel that slides out beside a revealed card: for every sense, the definition on
/// top and an SAT-level sentence beneath it in both languages.
///
/// It repeats the definition deliberately. Once the card has slid left the definition is
/// no longer the thing your eye lands on, and the sentence only teaches anything if the
/// meaning it demonstrates is sitting right above it.
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
            if card.senses.count > 1 {
                Text("\(card.senses.count) meanings")
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

    @ViewBuilder
    private var content: some View {
        if card.hasExamples {
            SnapshotableScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(card.senses.enumerated()), id: \.offset) { index, sense in
                        senseBlock(sense, number: card.senses.count > 1 ? index + 1 : nil)
                        if index < card.senses.count - 1 {
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
            .mask(card.senses.count > 1
                  ? LinearGradient(colors: [.black, .black, .black, .black.opacity(0.15)],
                                   startPoint: .top, endPoint: .bottom)
                  : LinearGradient(colors: [.black, .black], startPoint: .top, endPoint: .bottom))
        } else {
            emptyState
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

    private func senseBlock(_ sense: Sense, number: Int?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                if let number {
                    Text("\(number)")
                        .font(.rounded(10, .bold))
                        .foregroundStyle(.white)
                        .frame(width: 17, height: 17)
                        .background(Circle().fill(Palette.indigo.opacity(0.85)))
                }
                if !sense.partOfSpeech.isEmpty {
                    Text(sense.partOfSpeech)
                        .font(.rounded(11, .semibold))
                        .foregroundStyle(scheme == .dark ? Palette.indigoLight : Palette.indigoDeep)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Palette.indigo.opacity(scheme == .dark ? 0.20 : 0.14)))
                }
            }

            Text(sense.definition.isEmpty ? "—" : sense.definition)
                .font(.rounded(19, .bold))
                .foregroundStyle(Color.primaryText(scheme))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if let example = sense.example {
                VStack(alignment: .leading, spacing: 8) {
                    HighlightedSentence(
                        sentence: example.english,
                        highlights: SentenceHighlighter.englishRanges(in: example.english, word: card.word),
                        size: 14.5,
                        accent: scheme == .dark ? Palette.indigoLight : Palette.indigoDeep,
                        base: Color.primaryText(scheme)
                    )
                    if !example.chinese.isEmpty {
                        HighlightedSentence(
                            sentence: example.chinese,
                            highlights: SentenceHighlighter.chineseRanges(in: example.chinese,
                                                                          definition: sense.definition),
                            size: 13,
                            accent: scheme == .dark ? Palette.indigoLight : Palette.indigoDeep,
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
            } else {
                Text("No sentence for this meaning yet.")
                    .font(.rounded(12, .medium))
                    .foregroundStyle(Color.secondaryText(scheme))
                    .padding(.leading, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
