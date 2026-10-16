import AppKit

/// Logos of watchlist coins without a bundled asset, downloaded once by the app (`CoinLogoStore`) into the App Group
/// container so the widget and the desktop ticker can show them too (docs/COIN_CATALOG.md, "Logos").
/// A nil directory (no App Group, e.g. an unsigned build) means no cache: views fall back to the remote URL or a placeholder.
struct CoinLogoCache: Sendable {
    static let folderName = "CoinLogos"

    let directory: URL?

    /// `<App Group container>/CoinLogos`, shared by the app and the widget extension.
    static var appGroup: CoinLogoCache {
        CoinLogoCache(directory: WidgetSnapshotStore.appGroup.directory?.appendingPathComponent(folderName, isDirectory: true))
    }

    /// Ids are catalog ids (`[a-z0-9-]`), safe as file names.
    func fileURL(for coinID: String) -> URL? {
        directory?.appendingPathComponent("\(coinID).img")
    }

    func contains(_ coinID: String) -> Bool {
        fileURL(for: coinID).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    func image(for coinID: String) -> NSImage? {
        guard let url = fileURL(for: coinID), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    func store(_ data: Data, for coinID: String) throws {
        guard let directory, let url = fileURL(for: coinID) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Ids that currently have a cached logo.
    func cachedIDs() -> Set<String> {
        guard let directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return Set(names.filter { $0.hasSuffix(".img") }.map { String($0.dropLast(4)) })
    }

    func remove(_ coinID: String) {
        guard let url = fileURL(for: coinID) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
