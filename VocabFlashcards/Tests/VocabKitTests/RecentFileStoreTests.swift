import XCTest
@testable import VocabKit

final class RecentFileStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var tempDir: URL!

    override func setUpWithError() throws {
        suiteName = "RecentFileStoreTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecentFileStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testSaveAndResolveRegularFile() throws {
        let file = try makeFile(named: "vocabulary.xlsx")
        let store = RecentFileStore(defaults: defaults)

        store.save(url: file)

        XCTAssertEqual(store.resolve()?.resolvingSymlinksInPath(), file.resolvingSymlinksInPath())
        XCTAssertEqual(store.rememberedName, "vocabulary.xlsx")
        XCTAssertTrue(store.hasRemembered)
    }

    /// Failing to open some other workbook must not discard the remembered one.
    func testIsRememberedDistinguishesTheSavedFileFromAnyOther() throws {
        let remembered = try makeFile(named: "remembered.xlsx")
        let other = try makeFile(named: "other.xlsx")
        let store = RecentFileStore(defaults: defaults)

        store.save(url: remembered)

        XCTAssertTrue(store.isRemembered(remembered))
        XCTAssertFalse(store.isRemembered(other))
    }

    func testIsRememberedIgnoresPathFormatting() throws {
        let file = try makeFile(named: "vocabulary.xlsx")
        let store = RecentFileStore(defaults: defaults)
        store.save(url: file)

        let awkward = file.deletingLastPathComponent()
            .appendingPathComponent(".")
            .appendingPathComponent("vocabulary.xlsx")

        XCTAssertTrue(store.isRemembered(awkward))
    }

    func testIsRememberedIsFalseWhenNothingWasEverSaved() throws {
        let file = try makeFile(named: "vocabulary.xlsx")
        XCTAssertFalse(RecentFileStore(defaults: defaults).isRemembered(file))
    }

    func testResolveRejectsDirectory() {
        let store = RecentFileStore(defaults: defaults)

        store.save(url: tempDir)

        XCTAssertNil(store.resolve())
    }

    func testResolveReturnsNilAfterRememberedFileIsRemoved() throws {
        let file = try makeFile(named: "removed.xlsx")
        let store = RecentFileStore(defaults: defaults)
        store.save(url: file)
        try FileManager.default.removeItem(at: file)

        XCTAssertNil(store.resolve())
    }

    func testResolveFallsBackToPathWhenBookmarkIsInvalid() throws {
        let file = try makeFile(named: "fallback.xlsx")
        defaults.set(Data([0x00, 0x01, 0x02]), forKey: "recentFile.bookmark")
        defaults.set(file.path, forKey: "recentFile.path")
        defaults.set(file.lastPathComponent, forKey: "recentFile.name")
        let store = RecentFileStore(defaults: defaults)

        XCTAssertEqual(store.resolve()?.resolvingSymlinksInPath(), file.resolvingSymlinksInPath())
    }

    func testClearRemovesAllRememberedState() throws {
        let file = try makeFile(named: "clear.xlsx")
        let store = RecentFileStore(defaults: defaults)
        store.save(url: file)

        store.clear()

        XCTAssertFalse(store.hasRemembered)
        XCTAssertNil(store.rememberedName)
        XCTAssertNil(store.resolve())
    }

    private func makeFile(named name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try Data("fixture".utf8).write(to: url)
        return url
    }
}
