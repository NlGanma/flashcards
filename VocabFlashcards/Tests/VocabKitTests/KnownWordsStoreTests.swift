import XCTest
@testable import VocabKit

final class KnownWordsStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VocabKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testMarkKnownIsCaseInsensitive() {
        let store = KnownWordsStore(directory: tempDir)
        store.markKnown(word: "Keen")
        XCTAssertTrue(store.isKnown("keen"))
        XCTAssertTrue(store.isKnown(word: " KEEN "))
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.entries["keen"], "Keen")   // display form preserved
    }

    func testMarkKnownDoesNotDuplicate() {
        let store = KnownWordsStore(directory: tempDir)
        store.markKnown(word: "keen")
        store.markKnown(word: "keen")
        XCTAssertEqual(store.count, 1)
    }

    func testRemove() {
        let store = KnownWordsStore(directory: tempDir)
        store.markKnown(word: "keen")
        store.remove(key: "keen")
        XCTAssertEqual(store.count, 0)
        XCTAssertFalse(store.isKnown("keen"))
    }

    func testRemovePersistsAcrossInstances() {
        let store = KnownWordsStore(directory: tempDir)
        store.markKnown(word: "keen")
        store.flush()
        store.remove(key: "keen")
        store.flush()

        XCTAssertFalse(KnownWordsStore(directory: tempDir).isKnown("keen"))
    }

    func testRemoveAllPersistsAcrossInstances() {
        let store = KnownWordsStore(directory: tempDir)
        store.markKnown(word: "keen")
        store.markKnown(word: "calm")
        store.flush()
        store.removeAll()
        store.flush()

        XCTAssertEqual(KnownWordsStore(directory: tempDir).count, 0)
    }

    func testPersistenceAcrossInstances() {
        let store = KnownWordsStore(directory: tempDir)
        store.markKnown(word: "keen")
        store.markKnown(word: "Abate")
        store.flush()

        let reloaded = KnownWordsStore(directory: tempDir)
        XCTAssertEqual(reloaded.count, 2)
        XCTAssertTrue(reloaded.isKnown("keen"))
        XCTAssertEqual(reloaded.entries["abate"], "Abate")
    }

    func testLoadsVersionOneAndMigratesItToCompactFormat() throws {
        let legacyJSON = """
        {
          "version": 1,
          "words": [
            { "key": "abate", "display": "Abate" },
            { "key": "keen", "display": "keen" }
          ]
        }
        """
        try Data(legacyJSON.utf8).write(to: persistedFileURL)

        let store = KnownWordsStore(directory: tempDir)

        XCTAssertEqual(store.entries, ["abate": "Abate", "keen": "keen"])
        store.flush()
        let compact = try compactJSONObject()
        XCTAssertEqual(compact["v"] as? Int, 2)
        XCTAssertNil(compact["version"])
        let words = try XCTUnwrap(compact["w"] as? [String: String])
        XCTAssertEqual(words["abate"], "Abate")
        XCTAssertEqual(words["keen"], "")

        let reloaded = KnownWordsStore(directory: tempDir)
        XCTAssertEqual(reloaded.entries, store.entries)
    }

    func testCompactFormatPreservesCasingWithoutPrettyPrintOrWorkbookData() throws {
        let store = KnownWordsStore(directory: tempDir)
        store.markKnown(word: "Keen")
        store.markKnown(word: "calm")

        let data = try Data(contentsOf: persistedFileURL)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("\n"))
        let compact = try compactJSONObject()
        XCTAssertEqual(Set(compact.keys), ["v", "w"])
        let words = try XCTUnwrap(compact["w"] as? [String: String])
        XCTAssertEqual(words["keen"], "Keen")
        XCTAssertEqual(words["calm"], "")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: tempDir.path),
                       ["known_words.json"])

        let reloaded = KnownWordsStore(directory: tempDir)
        XCTAssertEqual(reloaded.entries["keen"], "Keen")
        XCTAssertEqual(reloaded.entries["calm"], "calm")
    }

    func testCompactFormatIsSmallerThanVersionOnePrettyPrintedJSON() throws {
        let store = KnownWordsStore(directory: tempDir)
        let entries = (0..<30).map { String(format: "word%03d", $0) }
        entries.forEach { store.markKnown(word: $0) }

        let compactData = try Data(contentsOf: persistedFileURL)
        let legacyObject: [String: Any] = [
            "version": 1,
            "words": entries.map { ["key": $0, "display": $0] }
        ]
        let legacyData = try JSONSerialization.data(
            withJSONObject: legacyObject,
            options: [.prettyPrinted, .sortedKeys]
        )

        XCTAssertLessThan(compactData.count * 2, legacyData.count)
    }

    func testMutationsAreDurableBeforeTheyReturn() {
        let store = KnownWordsStore(directory: tempDir)

        store.markKnown(word: "keen")
        XCTAssertTrue(KnownWordsStore(directory: tempDir).isKnown("keen"))

        store.remove(key: "keen")
        XCTAssertFalse(KnownWordsStore(directory: tempDir).isKnown("keen"))
    }

    func testSortedEntries() {
        let store = KnownWordsStore(directory: tempDir)
        store.markKnown(word: "zebra")
        store.markKnown(word: "apple")
        store.markKnown(word: "Mango")
        XCTAssertEqual(store.sortedEntries.map(\.display), ["apple", "Mango", "zebra"])
    }

    func testKnownKeysSet() {
        let store = KnownWordsStore(directory: tempDir)
        store.markKnown(word: "keen")
        store.markKnown(word: "calm")
        XCTAssertEqual(store.knownKeys, ["keen", "calm"])
    }

    private var persistedFileURL: URL {
        tempDir.appendingPathComponent("known_words.json")
    }

    private func compactJSONObject() throws -> [String: Any] {
        let data = try Data(contentsOf: persistedFileURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
