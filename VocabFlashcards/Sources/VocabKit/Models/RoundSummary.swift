import Foundation

/// Statistics for one completed round of study, shown on the summary screen.
public struct RoundSummary: Sendable, Equatable {
    public let roundNumber: Int
    public let totalStudied: Int
    public let markedKnown: Int
    public let stillUnknown: Int
    public let unvisited: Int
    /// Studied words parked in the temporary "Almost Known" bank this round.
    public let setAside: Int

    public init(roundNumber: Int, totalStudied: Int, markedKnown: Int, stillUnknown: Int,
                unvisited: Int = 0, setAside: Int = 0) {
        self.roundNumber = roundNumber
        self.totalStudied = totalStudied
        self.markedKnown = markedKnown
        self.stillUnknown = stillUnknown
        self.unvisited = unvisited
        self.setAside = setAside
    }

    /// Whether there are unknown or not-yet-seen words left to study.
    public var hasRemaining: Bool { stillUnknown > 0 || unvisited > 0 }

    /// Fraction of the scheduled round marked known (0...1), for progress visuals.
    /// Unvisited cards stay in the denominator so finishing early cannot show 100%.
    public var knownFraction: Double {
        let scheduled = totalStudied + unvisited
        guard scheduled > 0 else { return 0 }
        return Double(markedKnown) / Double(scheduled)
    }

    /// True when every scheduled word was visited and marked known — a clean sweep.
    /// Parked words don't count: they were set aside, not learned.
    public var isPerfect: Bool { totalStudied > 0 && markedKnown == totalStudied && unvisited == 0 }

    /// Whole-percent form for the summary ring. Never rounds up to 100 on a round that
    /// still has words left (199/200 would), and never rounds down to 0 once something was
    /// learned — either would contradict the tiles shown beside it.
    public var knownPercent: Int {
        let exact = knownFraction * 100
        if exact >= 100 { return 100 }
        return min(99, max(markedKnown > 0 ? 1 : 0, Int(exact.rounded())))
    }
}
