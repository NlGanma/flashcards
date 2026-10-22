import Foundation

/// A Markdown document cut along its headings — the shape a local model needs to turn
/// notes into cards. Each top-level section becomes a practice set, and is sent to the
/// model on its own, in pieces small enough to fit a modest context window.
///
/// This is deliberately not a Markdown renderer: the model reads Markdown fine, so the
/// text is passed through as written. The outline only has to find the section
/// boundaries, and to not mistake a `#` comment in a code block for a heading.
public struct MarkdownOutline: Hashable, Sendable {

    /// One top-level section: the heading it sits under and everything until the next
    /// heading at the same level, sub-headings included.
    public struct Section: Hashable, Sendable {
        public let title: String
        public let body: String

        public init(title: String, body: String) {
            self.title = title
            self.body = body
        }
    }

    /// The document's own title: its lone leading `#` heading, otherwise the file name.
    public let title: String
    /// Sections with content, in document order. A document with no headings is one
    /// section named after the title.
    public let sections: [Section]

    public init(markdown: String, fallbackTitle: String) {
        let lines = Self.cleanLines(markdown)
        let headings = Self.headings(in: lines)

        // A single H1 at the very top is the document's name, not a set: notes almost
        // always open with one, and making it a set would swallow every other section.
        var title = fallbackTitle
        var setHeadings = headings
        var bodyStart = 0
        if let first = headings.first, first.level == 1,
           headings.filter({ $0.level == 1 }).count == 1,
           lines[..<first.line].allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            title = first.text
            setHeadings.removeFirst()
            bodyStart = first.line + 1
        }
        self.title = title

        guard let setLevel = setHeadings.map(\.level).min() else {
            let body = Self.joined(lines[bodyStart...])
            self.sections = body.isEmpty ? [] : [Section(title: title, body: body)]
            return
        }

        let boundaries = setHeadings.filter { $0.level == setLevel }
        var sections: [Section] = []

        // Text between the title and the first section is usually an introduction worth
        // studying too; it gets the document's title.
        if let firstBoundary = boundaries.first, bodyStart < firstBoundary.line {
            let intro = Self.joined(lines[bodyStart..<firstBoundary.line])
            if !intro.isEmpty { sections.append(Section(title: title, body: intro)) }
        }

        for (index, heading) in boundaries.enumerated() {
            let end = index + 1 < boundaries.count ? boundaries[index + 1].line : lines.count
            let body = Self.joined(lines[(heading.line + 1)..<end])
            guard !body.isEmpty else { continue }
            sections.append(Section(title: heading.text, body: body))
        }
        self.sections = Self.uniquingTitles(sections)
    }

    // MARK: - Chunking

    /// A piece of the document sent to the model in one request: one section, or one
    /// part of a long one. Sections are never packed together — asked to sort cards from
    /// several sections, a 7B model files them under the wrong one, and the section is the
    /// card's practice set.
    public struct Chunk: Hashable, Sendable {
        public let index: Int
        /// Titles of the sections in this chunk. Never empty.
        public let sections: [String]
        /// Markdown handed to the model, under the section's `##` heading.
        public let text: String
    }

    /// One chunk per section, a section larger than `maxTokens` (estimated) split between
    /// paragraphs, each piece keeping its heading.
    public func chunks(maxTokens: Int = 1500) -> [Chunk] {
        var chunks: [Chunk] = []
        for section in sections {
            let heading = "## \(section.title)\n\n"
            for part in Self.split(section.body, maxTokens: max(1, maxTokens - Self.estimatedTokens(heading))) {
                chunks.append(Chunk(index: chunks.count, sections: [section.title], text: heading + part))
            }
        }
        return chunks
    }

    /// A rough token count that holds for both scripts: English runs about four
    /// characters to a token, while Chinese and Japanese are close to one each.
    public static func estimatedTokens(_ text: String) -> Int {
        // Counted in 25ths of a token so the sum stays exact: 7/25 is 0.28.
        var total = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF00...0xFFEF:
                total += 25
            default:
                total += 7
            }
        }
        return (total + 24) / 25
    }

    // MARK: - Parsing helpers

    private struct Heading {
        let line: Int
        let level: Int
        let text: String
    }

    /// Lines with front matter and HTML comments removed. Line positions are what the
    /// heading scan and the section slicing share, so nothing else is changed here.
    private static func cleanLines(_ markdown: String) -> [String] {
        var text = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        text = text.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "",
                                         options: .regularExpression)
        var lines = text.components(separatedBy: "\n")
        // YAML front matter: a `---` fence on the first line, closed by `---` or `...`.
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let close = lines.dropFirst().firstIndex(where: {
               let t = $0.trimmingCharacters(in: .whitespaces)
               return t == "---" || t == "..."
           }) {
            lines.removeSubrange(0...close)
        }
        return lines
    }

    private static let headingRegex = try! NSRegularExpression(
        pattern: "^ {0,3}(#{1,6})[ \\t]+(.+?)[ \\t]*(?:[ \\t]#+[ \\t]*)?$"
    )

    /// ATX headings outside fenced code blocks.
    private static func headings(in lines: [String]) -> [Heading] {
        var result: [Heading] = []
        var fence: String?
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if trimmed.hasPrefix(open) { fence = nil }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                continue
            }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = headingRegex.firstMatch(in: line, range: range),
                  let hashes = Range(match.range(at: 1), in: line),
                  let body = Range(match.range(at: 2), in: line) else { continue }
            let text = plainHeading(String(line[body]))
            guard !text.isEmpty else { continue }
            result.append(Heading(line: index, level: line[hashes].count, text: text))
        }
        return result
    }

    /// Heading text without the emphasis and link syntax that would otherwise end up in
    /// a set name: `**Cells** and [ATP](x)` reads as "Cells and ATP".
    private static func plainHeading(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1",
                                            options: .regularExpression)
        text = text.replacingOccurrences(of: "[*_`]", with: "", options: .regularExpression)
        return TextNormalizer.normalizeWhitespace(text)
    }

    private static func joined(_ lines: ArraySlice<String>) -> String {
        lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Two sections called "Examples" would merge into one practice set and lose track of
    /// which part of the notes each came from, so later duplicates get a number.
    private static func uniquingTitles(_ sections: [Section]) -> [Section] {
        var seen: [String: Int] = [:]
        return sections.map { section in
            let key = section.title.lowercased()
            let count = (seen[key] ?? 0) + 1
            seen[key] = count
            return count == 1 ? section : Section(title: "\(section.title) (\(count))", body: section.body)
        }
    }

    /// Split a section body into pieces under the budget, cutting only between
    /// paragraphs (never inside a code fence). A single paragraph larger than the budget
    /// is cut between lines.
    private static func split(_ body: String, maxTokens: Int) -> [String] {
        guard estimatedTokens(body) > maxTokens else { return [body] }

        var paragraphs: [String] = []
        var current: [String] = []
        var inFence = false
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle() }
            if trimmed.isEmpty && !inFence {
                if !current.isEmpty { paragraphs.append(current.joined(separator: "\n")) }
                current = []
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { paragraphs.append(current.joined(separator: "\n")) }

        var pieces: [String] = []
        var piece: [String] = []
        var used = 0
        for paragraph in paragraphs.flatMap({ splitOversized($0, maxTokens: maxTokens) }) {
            let cost = estimatedTokens(paragraph)
            if used > 0, used + cost > maxTokens {
                pieces.append(piece.joined(separator: "\n\n"))
                piece = []
                used = 0
            }
            piece.append(paragraph)
            used += cost
        }
        if !piece.isEmpty { pieces.append(piece.joined(separator: "\n\n")) }
        return pieces
    }

    private static func splitOversized(_ paragraph: String, maxTokens: Int) -> [String] {
        guard estimatedTokens(paragraph) > maxTokens else { return [paragraph] }
        var parts: [String] = []
        var lines: [String] = []
        var used = 0
        for line in paragraph.components(separatedBy: "\n") {
            let cost = estimatedTokens(line) + 1
            if used > 0, used + cost > maxTokens {
                parts.append(lines.joined(separator: "\n"))
                lines = []
                used = 0
            }
            lines.append(line)
            used += cost
        }
        if !lines.isEmpty { parts.append(lines.joined(separator: "\n")) }
        return parts
    }
}
