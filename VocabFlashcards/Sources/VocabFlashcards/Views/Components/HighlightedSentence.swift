import SwiftUI

/// Renders a sentence with the studied word standing out from the rest of it.
///
/// Built by concatenating `Text` runs rather than with `AttributedString`, because
/// `Text` concatenation is the one styling path that behaves identically on macOS 13 and
/// later, and it keeps wrapping and line spacing native.
struct HighlightedSentence: View {
    let sentence: String
    /// Substrings to emphasize. Matching is done by the caller so the two languages can
    /// use different rules.
    let highlights: [Range<String.Index>]
    var size: CGFloat
    var weight: Font.Weight = .medium
    var accent: Color
    var base: Color
    var lineSpacing: CGFloat = 5

    var body: some View {
        segments.reduce(Text("")) { partial, segment in
            partial + Text(segment.text)
                .font(.rounded(size, segment.emphasized ? .heavy : weight))
                .foregroundColor(segment.emphasized ? accent : base)
        }
        .lineSpacing(lineSpacing)
        .fixedSize(horizontal: false, vertical: true)
    }

    private struct Segment {
        let text: String
        let emphasized: Bool
    }

    /// Split the sentence into alternating plain / emphasized runs. Overlapping or
    /// out-of-order ranges are ignored rather than producing scrambled text.
    private var segments: [Segment] {
        let ordered = highlights.sorted { $0.lowerBound < $1.lowerBound }
        var result: [Segment] = []
        var cursor = sentence.startIndex
        for range in ordered {
            guard range.lowerBound >= cursor, range.upperBound <= sentence.endIndex else { continue }
            if cursor < range.lowerBound {
                result.append(Segment(text: String(sentence[cursor..<range.lowerBound]), emphasized: false))
            }
            result.append(Segment(text: String(sentence[range]), emphasized: true))
            cursor = range.upperBound
        }
        if cursor < sentence.endIndex {
            result.append(Segment(text: String(sentence[cursor...]), emphasized: false))
        }
        return result.isEmpty ? [Segment(text: sentence, emphasized: false)] : result
    }
}

/// Where to emphasize inside an example sentence.
enum SentenceHighlighter {

    /// Ranges in an English sentence covering the studied word, including its inflections
    /// ("abate" also matches "abated", "abating", "abatement").
    ///
    /// A prefix match is used rather than an exact one because the sentence should read
    /// naturally, which usually means conjugating the word. The stem is kept long enough
    /// that it cannot collide with an unrelated word in the same sentence.
    static func englishRanges(in sentence: String, word: String) -> [Range<String.Index>] {
        let target = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !sentence.isEmpty else { return [] }

        // Multi-word entries ("in lieu of") are matched whole; a stem match on the first
        // word alone would light up the wrong part of the sentence.
        if target.contains(" ") {
            if let range = sentence.range(of: target, options: [.caseInsensitive]) { return [range] }
            return []
        }

        let stem = stem(of: target)
        var ranges: [Range<String.Index>] = []
        for token in tokens(in: sentence) {
            let text = sentence[token].lowercased()
            guard text.hasPrefix(stem) else { continue }
            ranges.append(token)
        }
        return ranges
    }

    /// Ranges in a Chinese sentence covering the definition as it is used there. The
    /// spreadsheet's glosses are comma-separated alternatives, so each is tried on its
    /// own and the longest ones win — that way "敏锐的" doesn't shadow "敏锐的洞察力".
    static func chineseRanges(in sentence: String, definition: String) -> [Range<String.Index>] {
        guard !sentence.isEmpty, !definition.isEmpty else { return [] }
        let separators = CharacterSet(charactersIn: "，,；;、/／|｜ ")
        // Parentheticals are stripped *before* splitting: a gloss like
        // "没药（一种中药、香料）" carries a separator inside its own aside, and splitting
        // first would leave two fragments that match nothing.
        let clauses = stripParentheticals(definition)
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 2 }
            .sorted { $0.count > $1.count }

        var ranges: [Range<String.Index>] = []
        for clause in clauses {
            guard let range = sentence.range(of: clause) else { continue }
            // Keep only non-overlapping hits so the segments stay well ordered.
            if ranges.contains(where: { $0.overlaps(range) }) { continue }
            ranges.append(range)
        }
        return ranges
    }

    /// Drop "（……）" and "(...)" asides from a gloss, keeping what surrounds them.
    private static func stripParentheticals(_ text: String) -> String {
        var result = ""
        var depth = 0
        for character in text {
            if character == "（" || character == "(" {
                depth += 1
            } else if character == "）" || character == ")" {
                depth = max(0, depth - 1)
            } else if depth == 0 {
                result.append(character)
            }
        }
        return result
    }

    /// Trim likely inflection endings so the match survives conjugation, but never go so
    /// short that the stem stops being distinctive.
    private static func stem(of word: String) -> String {
        let lower = word.lowercased()
        let floor = max(4, lower.count - 3)
        return String(lower.prefix(min(lower.count, floor)))
    }

    /// Word-ish spans: letters plus the punctuation that lives inside English words.
    private static func tokens(in sentence: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var start: String.Index?
        for index in sentence.indices {
            let character = sentence[index]
            let isWordCharacter = character.isLetter || character == "-" || character == "'" || character == "’"
            if isWordCharacter {
                if start == nil { start = index }
            } else if let began = start {
                result.append(began..<index)
                start = nil
            }
        }
        if let began = start { result.append(began..<sentence.endIndex) }
        return result
    }
}
