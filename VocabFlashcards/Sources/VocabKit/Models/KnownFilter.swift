import Foundation

/// How the known-word memory is applied when building a study deck.
public enum KnownFilter: String, CaseIterable, Identifiable, Sendable {
    /// Study every word in the selected sets.
    case includeKnown
    /// Study only words not yet marked known (the default study mode).
    case excludeKnown
    /// Review only words already marked known.
    case onlyKnown

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .includeKnown: return "Study Everything"
        case .excludeKnown: return "Focus on New Words"
        case .onlyKnown: return "Review Known Words"
        }
    }

    public var subtitle: String {
        switch self {
        case .includeKnown: return "Include every word, known or not."
        case .excludeKnown: return "Skip words you've already marked known."
        case .onlyKnown: return "Practice only the words you know."
        }
    }

    public var systemImage: String {
        switch self {
        case .includeKnown: return "square.stack.3d.up.fill"
        case .excludeKnown: return "sparkles"
        case .onlyKnown: return "checkmark.seal.fill"
        }
    }
}
