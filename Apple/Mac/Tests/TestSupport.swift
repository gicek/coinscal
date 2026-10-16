import Combine
import Foundation
@testable import Coinscal

/// In-memory settings store, so tests never touch the real UserDefaults.
final class InMemorySettingsStore: SettingsStore {
    var stored: AppSettings?
    private(set) var saveCount = 0

    init(_ settings: AppSettings? = nil) {
        stored = settings
    }

    func load() -> AppSettings? { stored }

    func save(_ settings: AppSettings) {
        stored = settings
        saveCount += 1
    }
}

func catalogCoin(
    _ id: String, _ symbol: String, rank: Int? = nil, status: CoinStatus = .active,
    listed: Bool = true, migratedTo: String? = nil, logoURL: String? = nil
) -> CoinMetadata {
    CoinMetadata(id: id, symbol: symbol, name: id.capitalized, rank: rank, logoURL: logoURL,
                 status: status, listed: listed, migratedTo: migratedTo)
}

/// Test catalog with one tradable, unlisted, migrated and delisted coin each; does not read the bundled file.
@MainActor
func makeTestCatalog() -> CoinCatalog {
    CoinCatalog(coins: [
        catalogCoin("bitcoin", "BTC", rank: 1),
        catalogCoin("ethereum", "ETH", rank: 2),
        catalogCoin("render-token", "RENDER", rank: 80),
        catalogCoin("polygon-ecosystem-token", "POL", rank: 120, listed: false),
        catalogCoin("matic-network", "MATIC", status: .migrated, listed: false, migratedTo: "polygon-ecosystem-token"),
        catalogCoin("monero", "XMR", rank: 14, status: .delisted, listed: false),
    ])
}

/// In-memory key-value storage replacing UserDefaults, so tests leave no preference files on disk.
final class InMemoryDataStorage: SettingsDataStorage {
    private var values: [String: Any] = [:]

    func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }

    func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
}

/// Notification double that only records which alerts fired.
@MainActor
final class SpyNotifier: PriceAlertNotifying {
    struct Call: Equatable {
        let coinId: String
        let alertKind: CoinAlertKind
        let changePercent: Double
    }

    private(set) var calls: [Call] = []

    func sendPriceAlert(
        coin: Coin,
        alertKind: CoinAlertKind,
        threshold: Double,
        changePercent: Double,
        baseCurrency: BaseCurrency,
        usdToTargetRate: Double
    ) {
        calls.append(Call(coinId: coin.id, alertKind: alertKind, changePercent: changePercent))
    }
}

/// Price service double: each request returns a subject the test completes by hand.
final class FakePriceService: PriceServicing {
    struct Request {
        let symbols: [String]
        let currency: BaseCurrency
        let subject: PassthroughSubject<PriceSnapshot, Error>

        func respond(_ prices: [String: Double], rate: Double = 1) {
            subject.send(PriceSnapshot(prices: prices, changes24h: [:], usdToTargetRate: rate))
            subject.send(completion: .finished)
        }
    }

    private(set) var requests: [Request] = []

    func fetchQuotes(symbols: [String], currency: BaseCurrency) -> AnyPublisher<PriceSnapshot, Error> {
        let subject = PassthroughSubject<PriceSnapshot, Error>()
        requests.append(Request(symbols: symbols, currency: currency, subject: subject))
        return subject.eraseToAnyPublisher()
    }
}

/// FX service double with a fixed rate, returned immediately.
struct FixedExchangeRateService: ExchangeRateServicing {
    var rate: Double = 1

    func fetchUSDExchangeRate(to currency: BaseCurrency) -> AnyPublisher<Double, Error> {
        Just(rate).setFailureType(to: Error.self).eraseToAnyPublisher()
    }
}

/// Network double: canned replies matched by URL, recording the request order.
final class StubHTTPClient: HTTPClient {
    enum Reply {
        case status(Int, Data = Data())
        case failure(URLError.Code)
        /// Never completes; simulates a request in flight.
        case pending
    }

    private var routes: [(matches: (URL) -> Bool, reply: Reply)] = []
    private(set) var requestedURLs: [URL] = []

    /// Later rules win, so a test can override a reply midway.
    func on(_ matches: @escaping (URL) -> Bool, reply: Reply) {
        routes.insert((matches, reply), at: 0)
    }

    func dataPublisher(for request: URLRequest) -> AnyPublisher<(data: Data, response: URLResponse), URLError> {
        let url = request.url!
        requestedURLs.append(url)
        let reply = routes.first(where: { $0.matches(url) })?.reply ?? .failure(.notConnectedToInternet)
        switch reply {
        case .status(let code, let data):
            let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
            return Just((data: data, response: response as URLResponse))
                .setFailureType(to: URLError.self)
                .eraseToAnyPublisher()
        case .failure(let code):
            return Fail(error: URLError(code)).eraseToAnyPublisher()
        case .pending:
            return Empty(completeImmediately: false).eraseToAnyPublisher()
        }
    }
}

extension URL {
    var hasQuery: Bool { query?.isEmpty == false }
}

func json(_ string: String) -> Data { Data(string.utf8) }

/// Waits until work already queued on the main queue (`receive(on: DispatchQueue.main)` deliveries) has run.
@MainActor
func drainMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}

/// First value of a publisher; runs on the caller's main actor so the publisher never crosses isolation.
@MainActor
func firstValue<P: Publisher>(_ publisher: P) async throws -> P.Output where P.Output: Sendable {
    for try await value in publisher.values {
        return value
    }
    throw CancellationError()
}

/// Updater double: records checks and holds the automatic-check preference in memory.
@MainActor
final class FakeUpdaterBackend: UpdaterBackend {
    var canCheckForUpdates = true
    var automaticallyChecksForUpdates = true
    private(set) var checkCount = 0

    func checkForUpdates() {
        checkCount += 1
    }
}
