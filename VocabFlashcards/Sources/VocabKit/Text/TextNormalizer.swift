import Foundation

/// Central place for cleaning up the messy text that comes out of spreadsheet cells:
/// full-width spaces, stray newlines, zero-width characters, wrapping punctuation, etc.
///
/// The guiding principle: be aggressive about *formatting* artifacts, but conservative
/// about *content* — especially Chinese definitions, whose punctuation is meaningful.
public enum TextNormalizer {

    // Zero-width / invisible characters that should simply be deleted.
    private static let zeroWidth = ["\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}"]

    /// Collapse every kind of whitespace — ASCII, tabs, newlines, the full-width
    /// ideographic space (U+3000), non-breaking spaces — into single ASCII spaces,
    /// and trim the ends. Invisible zero-width characters are removed entirely.
    ///
    /// `CharacterSet.whitespacesAndNewlines` already covers the Unicode "Zs" category
    /// (which includes U+3000 and U+00A0) plus newline characters, so splitting on it
    /// handles the exotic spaces for us.
    public static func normalizeWhitespace(_ raw: String) -> String {
        var s = raw
        for zw in zeroWidth {
            if s.contains(zw) { s = s.replacingOccurrences(of: zw, with: "") }
        }
        let pieces = s.components(separatedBy: .whitespacesAndNewlines)
        return pieces.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// True when a cell has no meaningful content after normalization.
    public static func isBlank(_ raw: String?) -> Bool {
        guard let raw else { return true }
        return normalizeWhitespace(raw).isEmpty
    }

    // Punctuation frequently found wrapping a stray English word (quotes, bullets,
    // dashes used as list markers, brackets, trailing separators). Trimmed from the ends only.
    private static let wordEdgeTrim: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.insert(charactersIn: "\"'`“”‘’„‟«»•·・‣▪●○◦*※#>-–—―‐_.,;:！？。，、；：·（）()[]【】「」《》〈〉")
        return set
    }()

    // For definitions and parts of speech we only strip surrounding whitespace and quote
    // characters — internal Chinese punctuation and meaning-bearing symbols are preserved.
    private static let quoteEdgeTrim: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.insert(charactersIn: "\"'`“”‘’„‟")
        return set
    }()

    /// Bracket pairs whose closing half must survive edge-trimming when its opener is
    /// still in the word — otherwise "histrionic (histrionics)" is displayed as
    /// "histrionic (histrionics".
    private static let bracketPairs: [Character: Character] = [
        "(": ")", "（": "）", "[": "]", "【": "】",
        "「": "」", "《": "》", "〈": "〉"
    ]

    /// Clean an English word / phrase: normalize whitespace, then peel off wrapping
    /// punctuation. Internal characters (hyphens in "well-being", apostrophes in "it's")
    /// are left untouched because trimming only affects the ends.
    public static func cleanWord(_ raw: String) -> String {
        let normalized = normalizeWhitespace(raw)
        let trimmed = normalized.trimmingCharacters(in: wordEdgeTrim)
        // A second normalize pass in case edge-trimming exposed new whitespace.
        return normalizeWhitespace(restoringBracketBalance(trimmed, from: normalized))
    }

    /// Edge-trimming is meant to peel list markers and wrapping quotes, not to break a
    /// parenthetical that belongs to the word. If trimming left an opener without its
    /// partner, put back as much of the original tail as it takes to close it.
    private static func restoringBracketBalance(_ trimmed: String, from original: String) -> String {
        guard let unmatched = firstUnmatchedOpener(in: trimmed),
              let closer = bracketPairs[unmatched],
              let span = original.range(of: trimmed),
              let closingIndex = original[span.upperBound...].firstIndex(of: closer)
        else { return trimmed }
        // Extend the trimmed span rightwards only — whatever was peeled off the front
        // (bullets, list dashes) stays peeled.
        return String(original[span.lowerBound...closingIndex])
    }

    /// The opening bracket that has no matching closer, if any.
    private static func firstUnmatchedOpener(in text: String) -> Character? {
        var stack: [Character] = []
        for character in text {
            if bracketPairs[character] != nil {
                stack.append(character)
            } else if let openerIndex = stack.lastIndex(where: { bracketPairs[$0] == character }) {
                stack.removeSubrange(openerIndex...)
            }
        }
        return stack.first
    }

    /// Clean a part-of-speech token. Keeps conventional trailing dots ("n.", "adj.")
    /// but removes wrapping whitespace and quotes.
    public static func cleanPartOfSpeech(_ raw: String) -> String {
        normalizeWhitespace(raw).trimmingCharacters(in: quoteEdgeTrim)
    }

    /// Clean a (usually Chinese) definition. Preserves all internal punctuation and
    /// meaning; only collapses whitespace and strips wrapping quotes.
    public static func cleanDefinition(_ raw: String) -> String {
        normalizeWhitespace(raw).trimmingCharacters(in: quoteEdgeTrim)
    }

    /// The normalized identity used for known-word memory and for merging duplicate
    /// cards. Case-insensitive and whitespace-insensitive, based on the English word only.
    /// "Keen", "keen ", and " KEEN" all map to the same key.
    ///
    /// Deliberately *not* built on `cleanWord`: the key is a persisted identity, so it has
    /// to stay byte-stable. Restoring a trimmed bracket improves what the user reads, but
    /// changing it here would re-key every already-learned word whose source text had a
    /// parenthetical, silently returning it to the new pile.
    public static func normalizedKey(_ english: String) -> String {
        normalizeWhitespace(normalizeWhitespace(english).trimmingCharacters(in: wordEdgeTrim))
            .lowercased()
    }
}
