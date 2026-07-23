import Foundation

/// Remembers the most recently opened workbook so it can be auto-loaded on relaunch.
///
/// A bookmark (security-scoped when the platform allows, otherwise a plain bookmark)
/// is stored alongside the raw path. Bookmarks survive the file being moved/renamed;
/// the raw path is a fallback. Resolution returns `nil` when the file is gone or
/// unreadable, letting the UI show a friendly "please upload again" message.
public final class RecentFileStore {

    private let defaults: UserDefaults
    private let bookmarkKey = "recentFile.bookmark"
    private let scopedKey = "recentFile.scoped"
    private let pathKey = "recentFile.path"
    private let nameKey = "recentFile.name"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var rememberedName: String? { defaults.string(forKey: nameKey) }

    public var hasRemembered: Bool { defaults.data(forKey: bookmarkKey) != nil || defaults.string(forKey: pathKey) != nil }

    /// Whether `url` is the file currently remembered — so a failure to open some *other*
    /// workbook doesn't discard a perfectly good auto-load bookmark.
    public func isRemembered(_ url: URL) -> Bool {
        guard let path = defaults.string(forKey: pathKey) else { return false }
        return URL(fileURLWithPath: path).standardizedFileURL == url.standardizedFileURL
    }

    // MARK: - Save / clear

    public func save(url: URL) {
        var stored = false
        if let data = try? url.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil) {
            defaults.set(data, forKey: bookmarkKey)
            defaults.set(true, forKey: scopedKey)
            stored = true
        } else if let data = try? url.bookmarkData(options: [],
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil) {
            defaults.set(data, forKey: bookmarkKey)
            defaults.set(false, forKey: scopedKey)
            stored = true
        }
        if !stored { defaults.removeObject(forKey: bookmarkKey) }
        defaults.set(url.path, forKey: pathKey)
        defaults.set(url.lastPathComponent, forKey: nameKey)
    }

    public func clear() {
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: scopedKey)
        defaults.removeObject(forKey: pathKey)
        defaults.removeObject(forKey: nameKey)
    }

    // MARK: - Resolve

    /// Resolve the remembered file to a readable URL, or `nil` if it is gone.
    public func resolve() -> URL? {
        if let data = defaults.data(forKey: bookmarkKey) {
            let scoped = defaults.bool(forKey: scopedKey)
            let options: URL.BookmarkResolutionOptions = scoped ? [.withSecurityScope] : []
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data,
                                  options: options,
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &stale) {
                if isReadable(url) {
                    if stale { save(url: url) } // refresh a stale bookmark
                    return url
                }
            }
        }
        if let path = defaults.string(forKey: pathKey) {
            let url = URL(fileURLWithPath: path)
            if isReadable(url) { return url }
        }
        return nil
    }

    private func isReadable(_ url: URL) -> Bool {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return false }
        return FileManager.default.isReadableFile(atPath: url.path)
    }

    // MARK: - Scoped access helpers (no-ops for non-scoped bookmarks)

    @discardableResult
    public func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    public func stopAccessing(_ url: URL, didStart: Bool) {
        if didStart { url.stopAccessingSecurityScopedResource() }
    }
}
