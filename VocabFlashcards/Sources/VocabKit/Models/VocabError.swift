import Foundation

/// User-facing, friendly errors. Every failure path in the app maps to one of these
/// so the UI can show a clear message instead of crashing or showing a raw error.
public enum VocabError: LocalizedError, Equatable {
    /// The chosen file is not an .xlsx workbook.
    case notXLSX(fileName: String)
    /// The file can no longer be opened (moved, deleted, or permission lost).
    case cannotAccess(fileName: String)
    /// The file exists but could not be read as a valid spreadsheet.
    case unreadable(fileName: String)
    /// The workbook opened but contained no worksheet data at all.
    case emptyWorkbook
    /// No 3-column vocabulary blocks with valid English words were found.
    case noValidSets

    public var errorDescription: String? {
        switch self {
        case .notXLSX(let name):
            return "“\(name)” isn't an Excel file."
        case .cannotAccess(let name):
            return "Can't open “\(name)”."
        case .unreadable(let name):
            return "“\(name)” couldn't be read."
        case .emptyWorkbook:
            return "This spreadsheet looks empty."
        case .noValidSets:
            return "No vocabulary sets found."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .notXLSX:
            return "Please choose a file that ends in .xlsx."
        case .cannotAccess:
            return "It may have been moved or deleted. Try uploading it again."
        case .unreadable:
            return "It may be corrupted or in an unexpected format. Try another file."
        case .emptyWorkbook:
            return "Add some vocabulary and upload it again."
        case .noValidSets:
            return "Make sure each set has an English word, part of speech, and definition in three columns."
        }
    }

    /// Title + suggestion combined, for compact single-line displays.
    public var friendlyMessage: String {
        [errorDescription, recoverySuggestion].compactMap { $0 }.joined(separator: " ")
    }
}
