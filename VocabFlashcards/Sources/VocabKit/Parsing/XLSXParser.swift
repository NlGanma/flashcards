import Foundation
import CoreXLSX

/// Parses an .xlsx workbook laid out as repeated horizontal 3-column vocabulary blocks
/// (English word | part of speech | Chinese definition), tolerating merged cells, blank
/// rows/columns, titles, and stray formatting.
///
/// The parser cares only about cell *values*, never visual styling. Detection is anchored
/// on where "word"-type column headers appear, which makes it robust to spacer columns
/// between blocks and to leading blank rows/columns.
public struct XLSXVocabParser {

    public init() {}

    // MARK: - Header keyword dictionaries (lowercased; matched as labels/tokens)

    private static let wordHeaderKeywords = [
        "英文", "单词", "單詞", "英文单词", "英文單詞", "英语单词", "英語單詞",
        "英语", "英語", "词汇", "詞彙", "生词", "生詞",
        "word", "words", "english", "vocab", "vocabulary", "term", "terms", "spelling"
    ]
    private static let posHeaderKeywords = [
        "词性", "詞性", "词类", "詞類",
        "part of speech", "pos", "speech"
    ]
    private static let defHeaderKeywords = [
        "中文", "释义", "釋義", "中文释义", "中文釋義", "意思", "中文意思",
        "解释", "解釋", "定义", "定義", "中文定义", "中文定義",
        "翻译", "翻譯", "中文翻译", "中文翻譯", "含义", "含義", "词义", "詞義",
        "meaning", "definition", "translation", "chinese", "explanation"
    ]

    // Titles like "Practice 1", "Unit 3", "第1单元", "练习2" — used to avoid mistaking a
    // set title for a vocabulary word in the header-less fallback path.
    private static let titleRegex = try! NSRegularExpression(
        pattern: "^(practice|practise|unit|lesson|list|set|part|chapter|week|day|练习|練習|单元|單元|第)\\s*\\p{Nd}+",
        options: [.caseInsensitive]
    )

    // MARK: - Entry point

    public func parse(fileURL: URL) throws -> LoadedFile {
        let fileName = fileURL.lastPathComponent
        let ext = fileURL.pathExtension.lowercased()
        guard ext == "xlsx" || ext == "xlsm" else {
            throw VocabError.notXLSX(fileName: fileName)
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            throw VocabError.cannotAccess(fileName: fileName)
        }
        guard fm.isReadableFile(atPath: fileURL.path) else {
            throw VocabError.cannotAccess(fileName: fileName)
        }

        guard let file = XLSXFile(filepath: fileURL.path) else {
            throw VocabError.unreadable(fileName: fileName)
        }

        let sharedStrings = try? file.parseSharedStrings()
        let worksheets = worksheetList(in: file)
        guard !worksheets.isEmpty else { throw VocabError.emptyWorkbook }

        // A workbook may contain several sheets (e.g. an "answers" sheet with full
        // word/POS/definition data and a "word list" sheet with words only). We parse
        // every sheet and keep the one that best matches the vocabulary format —
        // strongly preferring a sheet with real headers and parts of speech — while
        // still defaulting to the first sheet when quality is otherwise equal.
        var sawData = false
        var best: (sets: [PracticeSet], score: Int)?
        for worksheet in worksheets {
            let grid = buildGrid(from: worksheet, sharedStrings: sharedStrings)
            if grid.cells.isEmpty { continue }
            sawData = true
            let result = detectSets(in: grid)
            guard !result.sets.isEmpty else { continue }
            let score = qualityScore(result.sets, headerDetected: result.headerDetected)
            if best == nil || score > best!.score {
                best = (result.sets, score)
            }
        }

        guard sawData else { throw VocabError.emptyWorkbook }
        guard let best else { throw VocabError.noValidSets }
        return LoadedFile(fileName: fileName, url: fileURL, sets: best.sets)
    }

    // MARK: - Worksheet selection

    /// All worksheets in workbook (tab) order, de-duplicated. Falls back to raw
    /// relationship paths if the workbook metadata can't be read.
    private func worksheetList(in file: XLSXFile) -> [Worksheet] {
        var paths: [String] = []
        if let workbooks = try? file.parseWorkbooks() {
            for workbook in workbooks {
                if let names = try? file.parseWorksheetPathsAndNames(workbook: workbook) {
                    paths.append(contentsOf: names.map { $0.path })
                }
            }
        }
        if paths.isEmpty {
            paths = (try? file.parseWorksheetPaths()) ?? []
        }
        var seen = Set<String>()
        let ordered = paths.filter { seen.insert($0).inserted }
        return ordered.compactMap { try? file.parseWorksheet(at: $0) }
    }

    /// Ranks a parsed sheet as vocabulary. A detected header row dominates (it means the
    /// canonical "word | part of speech | definition" layout was found), then the number
    /// of items carrying a part of speech, then those carrying a definition.
    private func qualityScore(_ sets: [PracticeSet], headerDetected: Bool) -> Int {
        let items = sets.flatMap { $0.items }
        let withPOS = items.filter { !$0.partOfSpeech.isEmpty }.count
        let withDef = items.filter { !$0.definition.isEmpty }.count
        return (headerDetected ? 1_000_000 : 0) + withPOS * 1_000 + withDef
    }

    // MARK: - Grid extraction

    /// A sparse grid of cleaned cell strings keyed by (1-based Excel row, 0-based column).
    private struct Grid {
        var cells: [Int: [Int: String]] = [:]      // row -> (col -> text)
        var rowNumbers: [Int] = []                 // sorted ascending
        var maxColumn: Int = 0

        func text(row: Int, col: Int) -> String { cells[row]?[col] ?? "" }

        /// Columns (0-based) that contain any non-empty cell across the given rows.
        func usedColumns(inRows rows: [Int]) -> [Int] {
            var cols = Set<Int>()
            for r in rows {
                for (c, v) in cells[r] ?? [:] where !v.isEmpty { cols.insert(c) }
            }
            return cols.sorted()
        }
    }

    private func buildGrid(from worksheet: Worksheet, sharedStrings: SharedStrings?) -> Grid {
        var grid = Grid()
        let rows = worksheet.data?.rows ?? []
        for row in rows {
            for cell in row.cells {
                let text = resolvedText(cell, sharedStrings: sharedStrings)
                let normalized = TextNormalizer.normalizeWhitespace(text)
                guard !normalized.isEmpty else { continue }
                let r = Int(cell.reference.row)
                let c = columnIndex(cell.reference.column)
                guard c >= 0 else { continue }
                grid.cells[r, default: [:]][c] = normalized
                grid.maxColumn = max(grid.maxColumn, c)
            }
        }
        grid.rowNumbers = grid.cells.keys.sorted()
        return grid
    }

    /// Resolve a cell to its best text representation: plain shared string, rich-text
    /// shared string (joined runs), inline string, then raw value.
    private func resolvedText(_ cell: Cell, sharedStrings: SharedStrings?) -> String {
        if let ss = sharedStrings {
            // stringValue() returns nil for rich-text shared strings; fall through to runs.
            if let v = cell.stringValue(ss), !v.isEmpty { return v }
            let rich = cell.richStringValue(ss).compactMap { $0.text }.joined()
            if !rich.isEmpty { return rich }
        }
        if let t = cell.inlineString?.text, !t.isEmpty { return t }
        return cell.value ?? ""
    }

    /// Convert a column reference ("A", "B", "AA") to a 0-based index.
    private func columnIndex(_ column: ColumnReference) -> Int {
        var index = 0
        for scalar in column.value.uppercased().unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90 else { continue } // A...Z
            index = index * 26 + (Int(scalar.value) - 64)
        }
        return index - 1
    }

    // MARK: - Block detection

    private func detectSets(in grid: Grid) -> (sets: [PracticeSet], headerDetected: Bool) {
        let headerInfo = findHeaderRow(in: grid)

        let dataStartRow: Int
        let blockStarts: [Int]
        let titleRow: Int?

        if let header = headerInfo {
            dataStartRow = header.rowNumber + 1
            titleRow = nearestNonEmptyRowAbove(header.rowNumber, in: grid)
            let wordCols = header.wordColumns
            if !wordCols.isEmpty {
                blockStarts = wordCols
            } else {
                // Header row exists but no recognizable "word" column — fall back to triples.
                blockStarts = tripleBlockStarts(in: grid, dataRows: rowsFrom(dataStartRow, in: grid))
            }
        } else {
            // No headers detected at all: treat every row as data, group columns in triples.
            dataStartRow = grid.rowNumbers.first ?? 1
            titleRow = nil
            blockStarts = tripleBlockStarts(in: grid, dataRows: grid.rowNumbers)
        }

        let dataRows = rowsFrom(dataStartRow, in: grid)
        let headerless = (headerInfo == nil)

        var sets: [PracticeSet] = []
        var untitledCounter = 0
        var usedNames = Set<String>()

        for (blockIndex, startCol) in blockStarts.enumerated() {
            let items = extractItems(
                grid: grid,
                dataRows: dataRows,
                wordCol: startCol,
                setNamePlaceholder: "",
                headerless: headerless
            )
            guard !items.isEmpty else { continue }

            // Determine a name for this block.
            var name = detectedTitle(grid: grid, titleRow: titleRow, startCol: startCol)
            if name == nil {
                untitledCounter += 1
                name = "Practice Set \(untitledCounter)"
            }
            var finalName = name!
            var suffix = 2
            while usedNames.contains(finalName) {
                finalName = "\(name!) (\(suffix))"
                suffix += 1
            }
            usedNames.insert(finalName)

            // Re-tag items with the resolved set name.
            let named = items.map {
                VocabItem(english: $0.english, partOfSpeech: $0.partOfSpeech,
                          definition: $0.definition, setName: finalName)
            }
            sets.append(PracticeSet(name: finalName, items: named))
            _ = blockIndex
        }
        return (sets, headerInfo != nil)
    }

    private func rowsFrom(_ start: Int, in grid: Grid) -> [Int] {
        grid.rowNumbers.filter { $0 >= start }
    }

    /// Scan for the row that most looks like a header (most cells matching any header keyword).
    private func findHeaderRow(in grid: Grid) -> (rowNumber: Int, wordColumns: [Int])? {
        var best: (row: Int, score: Int, wordCols: [Int])?
        for row in grid.rowNumbers {
            guard let cells = grid.cells[row] else { continue }
            var score = 0
            var wordCols: [Int] = []
            for (col, text) in cells {
                let isWord = matches(text, Self.wordHeaderKeywords)
                let isPos = matches(text, Self.posHeaderKeywords)
                let isDef = matches(text, Self.defHeaderKeywords)
                if isWord { wordCols.append(col) }
                if isWord || isPos || isDef { score += 1 }
            }
            if score >= 2 {
                if best == nil || score > best!.score || (score == best!.score && row < best!.row) {
                    best = (row, score, wordCols.sorted())
                }
            }
        }
        guard let best else { return nil }
        return (best.row, best.wordCols)
    }

    /// Group used columns into consecutive triples starting from the first used column.
    private func tripleBlockStarts(in grid: Grid, dataRows: [Int]) -> [Int] {
        let used = grid.usedColumns(inRows: dataRows)
        guard let first = used.first, let last = used.last else { return [] }
        var starts: [Int] = []
        var c = first
        while c <= last {
            starts.append(c)
            c += 3
        }
        return starts
    }

    private func nearestNonEmptyRowAbove(_ row: Int, in grid: Grid) -> Int? {
        grid.rowNumbers.filter { $0 < row }.max()
    }

    /// Extract vocabulary items for one block anchored at `wordCol`.
    private func extractItems(grid: Grid, dataRows: [Int], wordCol: Int,
                              setNamePlaceholder: String, headerless: Bool) -> [VocabItem] {
        let posCol = wordCol + 1
        let defCol = wordCol + 2
        var items: [VocabItem] = []

        for row in dataRows {
            let rawWord = grid.text(row: row, col: wordCol)
            let rawPos = grid.text(row: row, col: posCol)
            let rawDef = grid.text(row: row, col: defCol)

            // Skip rows that are empty within this block.
            if rawWord.isEmpty && rawPos.isEmpty && rawDef.isEmpty { continue }

            let english = TextNormalizer.cleanWord(rawWord)
            // English word missing -> incomplete entry, skip.
            guard !english.isEmpty else { continue }

            // Safeguards against picking up stray header/title rows as vocabulary.
            if headerless && isHeaderToken(english) { continue }
            if headerless && looksLikeTitle(english) { continue }

            let pos = TextNormalizer.cleanPartOfSpeech(rawPos)
            let def = TextNormalizer.cleanDefinition(rawDef)
            items.append(VocabItem(english: english, partOfSpeech: pos,
                                   definition: def, setName: setNamePlaceholder))
        }
        return items
    }

    private func detectedTitle(grid: Grid, titleRow: Int?, startCol: Int) -> String? {
        guard let titleRow else { return nil }
        for col in startCol...(startCol + 2) {
            let raw = grid.text(row: titleRow, col: col)
            guard !raw.isEmpty else { continue }
            // Don't treat a header keyword as a title.
            if matches(raw, Self.wordHeaderKeywords)
                || matches(raw, Self.posHeaderKeywords)
                || matches(raw, Self.defHeaderKeywords) { return nil }
            let cleaned = TextNormalizer.cleanWord(raw)
            return cleaned.isEmpty ? nil : cleaned
        }
        return nil
    }

    // MARK: - Matching helpers

    private func matches(_ text: String, _ keywords: [String]) -> Bool {
        let t = text.lowercased()
        guard !t.isEmpty else { return false }
        let textTokens = asciiHeaderTokens(in: t)
        return keywords.contains { keyword in
            // Chinese workbooks commonly combine labels (for example "英文单词"), so their
            // compact keywords remain substring matches. English labels use whole token
            // sequences, keeping "sword", "possible", and "determined" from false matches.
            if !keyword.unicodeScalars.allSatisfy(\.isASCII) {
                return t.contains(keyword)
            }
            let keywordTokens = asciiHeaderTokens(in: keyword)
            return containsTokenSequence(keywordTokens, in: textTokens)
        }
    }

    private func asciiHeaderTokens(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private func containsTokenSequence(_ needle: [String], in haystack: [String]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle { return true }
        }
        return false
    }

    /// True when the word is exactly a header label (e.g. "word", "英文单词", "definition").
    private func isHeaderToken(_ english: String) -> Bool {
        let t = english.lowercased()
        let exact: Set<String> = [
            "word", "words", "english", "english word", "vocabulary", "vocab", "term",
            "part of speech", "pos", "speech",
            "meaning", "definition", "translation", "chinese", "chinese definition",
            "英文", "单词", "英文单词", "英語單詞", "词性", "詞性", "中文", "释义",
            "中文释义", "意思", "翻译", "词汇", "解释"
        ]
        return exact.contains(t)
    }

    private func looksLikeTitle(_ english: String) -> Bool {
        let range = NSRange(english.startIndex..<english.endIndex, in: english)
        return Self.titleRegex.firstMatch(in: english, options: [], range: range) != nil
    }
}
