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

    /// Clean an English word / phrase: normalize whitespace, then peel off wrapping
    /// punctuation. Internal characters (hyphens in "well-being", apostrophes in "it's")
    /// are left untouched because trimming only affects the ends.
    public static func cleanWord(_ raw: String) -> String {
        let normalized = normalizeWhitespace(raw)
        let trimmed = normalized.trimmingCharacters(in: wordEdgeTrim)
        // A second normalize pass in case edge-trimming exposed new whitespace.
        return normalizeWhitespace(trimmed)
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
    public static func normalizedKey(_ english: String) -> String {
        cleanWord(english).lowercased()
    }
}
