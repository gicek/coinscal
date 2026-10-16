import AppKit
import Combine
import os

/// Keeps a local copy of the logo of every watchlist coin that has no bundled asset (docs/COIN_CATALOG.md, "Logos").
/// The catalog lists hundreds of coins but only the top ones ship with a logo; the rest are downloaded once when a coin
/// enters the watchlist, then read from the App Group container by the app, the widget, and the desktop ticker.
@MainActor
final class CoinLogoStore: ObservableObject {
    /// Larger responses are not a coin logo (CoinGecko's "large" images are a few KB to a few dozen KB).
    nonisolated static let maxBytes = 512 * 1024

    /// Ids with a cached logo; views re-render when a download lands.
    @Published private(set) var cachedIDs: Set<String>

    private let cache: CoinLogoCache
    private let client: HTTPClient
    private var inFlight: [String: AnyCancellable] = [:]
    /// Decoded images, so list rows don't read the file on every render.
    private var images: [String: NSImage] = [:]
    private static let logger = Logger(subsystem: "com.gicek.coinscal", category: "CoinLogos")

    init(cache: CoinLogoCache = .appGroup, client: HTTPClient) {
        self.cache = cache
        self.client = client
        cachedIDs = cache.cachedIDs()
    }

    func image(for coinID: String) -> NSImage? {
        guard cachedIDs.contains(coinID) else { return nil }
        if let image = images[coinID] { return image }
        let image = cache.image(for: coinID)
        images[coinID] = image
        return image
    }

    /// Downloads missing logos for the watchlist and deletes cached logos of coins that left it.
    /// Failed downloads are retried at the next sync (launch or watchlist change).
    func sync(watchlist: [CoinMetadata]) {
        let keep = Set(watchlist.map(\.id))
        for coinID in cachedIDs.subtracting(keep) {
            cache.remove(coinID)
            images[coinID] = nil
        }
        cachedIDs.formIntersection(keep)
        for coinID in inFlight.keys where !keep.contains(coinID) {
            inFlight[coinID] = nil
        }
        watchlist.forEach(fetchIfNeeded)
    }

    func fetchIfNeeded(_ meta: CoinMetadata) {
        guard cache.directory != nil,
              meta.logoAssetName == nil,
              !cachedIDs.contains(meta.id),
              inFlight[meta.id] == nil,
              let url = Self.allowedURL(meta.logoURL) else { return }
        let coinID = meta.id
        inFlight[coinID] = client.dataPublisher(for: URLRequest(url: url, timeoutInterval: 15))
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    Self.logger.error("Logo download failed: \(error.localizedDescription, privacy: .public)")
                }
                self?.inFlight[coinID] = nil
            }, receiveValue: { [weak self] data, response in
                self?.save(data, response: response, for: coinID)
            })
    }

    private func save(_ data: Data, response: URLResponse, for coinID: String) {
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              !data.isEmpty, data.count <= Self.maxBytes,
              NSImage(data: data) != nil else { return }
        do {
            try cache.store(data, for: coinID)
            cachedIDs.insert(coinID)
        } catch {
            Self.logger.error("Logo cache write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// HTTPS on a catalog logo host only (the catalog is validated the same way).
    nonisolated static func allowedURL(_ string: String?) -> URL? {
        guard let string, let url = URL(string: string), url.scheme == "https",
              let host = url.host, CoinCatalog.logoHosts.contains(host) else { return nil }
        return url
    }
}
