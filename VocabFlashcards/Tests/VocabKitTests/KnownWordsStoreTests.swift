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

    // MARK: - Almost Known bank

    /// The guarantee that matters most: a store file written before the bank existed must
    /// still load every known word it contains.
    func testExistingFileWithoutAsideKeyKeepsEveryKnownWord() throws {
        let existingJSON = #"{"v":2,"w":{"abate":"","candid":"Candid","keen":""}}"#
        try Data(existingJSON.utf8).write(to: persistedFileURL)

        let store = KnownWordsStore(directory: tempDir)

        XCTAssertEqual(store.count, 3)
        XCTAssertEqual(store.entries, ["abate": "abate", "candid": "Candid", "keen": "keen"])
        XCTAssertEqual(store.asideCount, 0)
    }

    /// An untouched bank must not change a single byte of the file's shape, so builds that
    /// predate the feature keep reading it exactly as before.
    func testFileShapeIsUnchangedWhileBankIsEmpty() throws {
        let store = KnownWordsStore(directory: tempDir)
        store.markKnown(word: "Keen")

        let compact = try compactJSONObject()
        XCTAssertEqual(Set(compact.keys), ["v", "w"])
        XCTAssertEqual(compact["v"] as? Int, 2)
        XCTAssertNil(compact["a"])
    }

    func testAsideBankRoundTripsAcrossInstances() {
        let store = KnownWordsStore(directory: tempDir)
        store.markAside(word: "Abscond")
        store.markAside(word: "alacrity")
        store.flush()

        let reloaded = KnownWordsStore(directory: tempDir)
        XCTAssertEqual(reloaded.asideKeys, ["abscond", "alacrity"])
        XCTAssertEqual(reloaded.asideEntries["abscond"], "Abscond")
        XCTAssertEqual(reloaded.asideEntries["alacrity"], "alacrity")
        XCTAssertEqual(reloaded.count, 0)
        XCTAssertTrue(reloaded.isAside("abscond"))
    }

    func testMarkingAKnownWordAsideIsRefused() {
        let store = KnownWordsStore(directory: tempDir)
        store.markKnown(word: "keen")

        store.markAside(word: "Keen")

        XCTAssertTrue(store.isKnown("keen"))
        XCTAssertFalse(store.isAside("keen"))
        XCTAssertEqual(store.asideCount, 0)
    }

    func testMarkingKnownPromotesAWordOutOfTheBank() {
        let store = KnownWordsStore(directory: tempDir)
        store.markAside(word: "keen")

        store.markKnown(key: "keen", display: "keen")
        store.flush()

        XCTAssertTrue(store.isKnown("keen"))
        XCTAssertFalse(store.isAside("keen"))
        let reloaded = KnownWordsStore(directory: tempDir)
        XCTAssertTrue(reloaded.isKnown("keen"))
        XCTAssertEqual(reloaded.asideCount, 0)
    }

    func testClearingOneBankLeavesTheOtherIntact() {
        let store = KnownWordsStore(directory: tempDir)
        store.markKnown(word: "keen")
        store.markAside(word: "abscond")

        store.removeAllAside()
        XCTAssertEqual(store.asideCount, 0)
        XCTAssertEqual(store.count, 1)

        store.markAside(word: "abscond")
        store.removeAll()
        XCTAssertEqual(store.count, 0)
        XCTAssertEqual(store.asideCount, 1)
    }

    func testRemoveAsideSendsOneWordBackToNew() {
        let store = KnownWordsStore(directory: tempDir)
        store.markAside(word: "abscond")
        store.markAside(word: "alacrity")

        store.removeAside(key: "abscond")
        store.flush()

        XCTAssertEqual(KnownWordsStore(directory: tempDir).asideKeys, ["alacrity"])
    }

    func testSortedAsideEntries() {
        let store = KnownWordsStore(directory: tempDir)
        ["zebra", "apple", "Mango"].forEach { store.markAside(word: $0) }
        XCTAssertEqual(store.sortedAsideEntries.map(\.display), ["apple", "Mango", "zebra"])
    }

    /// A word can never be in both banks, even if the file on disk claims otherwise.
    func testHandEditedFileCannotPutAWordInBothBanks() throws {
        let conflictingJSON = #"{"v":2,"w":{"keen":""},"a":{"keen":"","abscond":""}}"#
        try Data(conflictingJSON.utf8).write(to: persistedFileURL)

        let store = KnownWordsStore(directory: tempDir)

        XCTAssertTrue(store.isKnown("keen"))
        XCTAssertFalse(store.isAside("keen"))
        XCTAssertEqual(store.asideKeys, ["abscond"])
    }

    func testReconcileDisplaysRepairsAStaleSpellingWithoutRekeying() {
        let store = KnownWordsStore(directory: tempDir)
        store.markKnown(key: "histrionic (histrionic", display: "histrionic (histrionic")
        store.markAside(key: "appraise (appraisal", display: "appraise (appraisal")

        store.reconcileDisplays([
            "histrionic (histrionic": "histrionic (histrionics)",
            "appraise (appraisal": "appraise (appraisal)"
        ])
        store.flush()

        let reloaded = KnownWordsStore(directory: tempDir)
        XCTAssertTrue(reloaded.isKnown("histrionic (histrionic"), "the key must not move")
        XCTAssertEqual(reloaded.entries["histrionic (histrionic"], "histrionic (histrionics)")
        XCTAssertEqual(reloaded.asideEntries["appraise (appraisal"], "appraise (appraisal)")
    }

    func testReconcileDisplaysIgnoresUnknownWordsAndWritesNothingWhenNothingChanged() throws {
        let store = KnownWordsStore(directory: tempDir)
        store.markKnown(word: "keen")
        store.flush()
        let before = try Data(contentsOf: persistedFileURL)

        store.reconcileDisplays(["keen": "keen", "unrelated": "Unrelated"])
        store.flush()

        XCTAssertEqual(store.count, 1)
        XCTAssertFalse(store.isKnown("unrelated"))
        XCTAssertEqual(try Data(contentsOf: persistedFileURL), before)
    }

    func testFirstLaunchBacksUpAnExistingStoreOnce() throws {
        let originalJSON = #"{"v":2,"w":{"abate":""}}"#
        try Data(originalJSON.utf8).write(to: persistedFileURL)

        _ = KnownWordsStore(directory: tempDir)
        let backupURL = tempDir.appendingPathComponent("known_words.backup.json")
        XCTAssertEqual(try String(contentsOf: backupURL), originalJSON)

        // A later launch must not overwrite the original snapshot.
        let store = KnownWordsStore(directory: tempDir)
        store.markKnown(word: "keen")
        store.flush()
        _ = KnownWordsStore(directory: tempDir)
        XCTAssertEqual(try String(contentsOf: backupURL), originalJSON)
    }

    private var persistedFileURL: URL {
        tempDir.appendingPathComponent("known_words.json")
    }

    private func compactJSONObject() throws -> [String: Any] {
        let data = try Data(contentsOf: persistedFileURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
