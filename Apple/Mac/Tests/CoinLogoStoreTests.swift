import AppKit
import Foundation
import Testing
@testable import Coinscal

@MainActor
@Suite struct CoinLogoStoreTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CoinLogoStoreTests-\(UUID().uuidString)", isDirectory: true)
    private let client = StubHTTPClient()
    private static let logoURL = "https://coin-images.coingecko.com/coins/images/1/large/x.png"

    private var cache: CoinLogoCache { CoinLogoCache(directory: directory) }

    private func coin(_ id: String, logoURL: String? = Self.logoURL, bundled: Bool = false) -> CoinMetadata {
        var meta = catalogCoin(id, id.uppercased(), logoURL: logoURL)
        meta.logoAssetName = bundled ? "coin-\(id)" : nil
        return meta
    }

    private static func pngData() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    /// Downloads are delivered on the main queue; give them a moment to land.
    private func settle(until done: () -> Bool = { false }) async throws {
        for _ in 0..<50 where !done() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func downloadsMissingLogoOnceAndCachesItOnDisk() async throws {
        client.on({ _ in true }, reply: .status(200, Self.pngData()))
        let store = CoinLogoStore(cache: cache, client: client)

        store.sync(watchlist: [coin("pepe")])
        try await settle { store.cachedIDs.contains("pepe") }

        #expect(store.image(for: "pepe") != nil)
        #expect(cache.contains("pepe"), "written to the shared container for the widget and desktop ticker")
        store.sync(watchlist: [coin("pepe")])
        #expect(client.requestedURLs.count == 1, "a cached logo is not downloaded again")
        #expect(CoinLogoStore(cache: cache, client: client).cachedIDs == ["pepe"], "the cache survives a relaunch")
    }

    @Test func skipsBundledLogosAndUntrustedURLs() async throws {
        client.on({ _ in true }, reply: .status(200, Self.pngData()))
        let store = CoinLogoStore(cache: cache, client: client)

        store.sync(watchlist: [
            coin("bitcoin", bundled: true),
            coin("evil", logoURL: "https://evil.example.com/x.png"),
            coin("plain", logoURL: "http://coin-images.coingecko.com/x.png"),
            coin("none", logoURL: nil),
        ])
        try await settle()

        #expect(client.requestedURLs.isEmpty)
        #expect(store.cachedIDs.isEmpty)
    }

    @Test func rejectsResponsesThatAreNotAnImage() async throws {
        client.on({ _ in true }, reply: .status(200, Data("<html>blocked</html>".utf8)))
        let store = CoinLogoStore(cache: cache, client: client)
        store.sync(watchlist: [coin("html")])
        try await settle()
        #expect(!cache.contains("html"))

        client.on({ _ in true }, reply: .status(404, Self.pngData()))
        store.sync(watchlist: [coin("missing")])
        try await settle()
        #expect(store.cachedIDs.isEmpty)
    }

    @Test func failedDownloadIsRetriedAtTheNextSync() async throws {
        client.on({ _ in true }, reply: .failure(.timedOut))
        let store = CoinLogoStore(cache: cache, client: client)
        store.sync(watchlist: [coin("flaky")])
        try await settle()
        #expect(store.cachedIDs.isEmpty)

        client.on({ _ in true }, reply: .status(200, Self.pngData()))
        store.sync(watchlist: [coin("flaky")])
        try await settle { store.cachedIDs.contains("flaky") }
        #expect(store.cachedIDs == ["flaky"])
    }

    @Test func removingACoinFromTheWatchlistDeletesItsLogo() async throws {
        client.on({ _ in true }, reply: .status(200, Self.pngData()))
        let store = CoinLogoStore(cache: cache, client: client)
        store.sync(watchlist: [coin("keep"), coin("drop")])
        try await settle { store.cachedIDs.count == 2 }

        store.sync(watchlist: [coin("keep")])

        #expect(store.cachedIDs == ["keep"])
        #expect(!cache.contains("drop"))
        #expect(store.image(for: "drop") == nil)
    }

    @Test func noCacheDirectoryMeansNoDownloads() async throws {
        client.on({ _ in true }, reply: .status(200, Self.pngData()))
        let store = CoinLogoStore(cache: CoinLogoCache(directory: nil), client: client)
        store.sync(watchlist: [coin("pepe")])
        try await settle()
        #expect(client.requestedURLs.isEmpty, "unsigned builds have no App Group: views use the remote URL instead")
    }
}
