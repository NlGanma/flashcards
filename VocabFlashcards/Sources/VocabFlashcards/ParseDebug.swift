import Foundation
import VocabKit

/// Command-line diagnostics for the parser, enabled via `VF_PARSE=<xlsx>`.
enum ParseDebug {
    static func run(path: String) {
        let url = URL(fileURLWithPath: path)
        print("Parsing: \(url.lastPathComponent)")
        do {
            let file = try XLSXVocabParser().parse(fileURL: url)
            print("Detected \(file.sets.count) sets · \(file.totalItems) items · \(file.totalUniqueWords) unique words\n")
            for set in file.sets {
                print("• \(set.name): \(set.wordCount) items")
                for item in set.items.prefix(2) {
                    print("    - \(item.english) [\(item.partOfSpeech)] \(item.definition)")
                }
            }
        } catch {
            print("ERROR: \(error)")
        }
    }
}
