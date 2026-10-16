import Foundation
import Combine

protocol ExchangeRateServicing {
    func fetchUSDExchangeRate(to currency: BaseCurrency) -> AnyPublisher<Double, Error>
}

/// USD → fiat rates: public sources tried in order, the whole table cached (TTL in Constants) in memory and in
/// `cacheStore`, so a relaunch or another widget process within the TTL makes no request.
/// USDT is treated as USD; USD returns 1.0 without a request.
final class ExchangeRateService: ExchangeRateServicing {
    /// Pause for a source that answered HTTP 429 without `Retry-After` (ExchangeRate-API blocks for 20 minutes).
    static let rateLimitBackoff: TimeInterval = 20 * 60

    private let client: HTTPClient
    private let providers: [ExchangeRateProvider]
    private let cacheStore: ExchangeRateCacheStore
    /// Cache and request coalescing are main-thread only (polling and callbacks run on the main thread).
    private var cachedRates: [String: Double] = [:]
    private var cacheTimestamp: Date?
    /// Concurrent subscribers share the request in flight.
    private var inFlight: AnyPublisher<[String: Double], Error>?
    /// Provider index → when its rate limit is expected to be over.
    private var rateLimitedUntil: [Int: Date] = [:]

    private let now: () -> Date

    init(
        client: HTTPClient = URLSession.liveData,
        providers: [ExchangeRateProvider] = ExchangeRateService.defaultProviders,
        cacheStore: ExchangeRateCacheStore = ExchangeRateCacheStore(directory: nil),
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.providers = providers
        self.cacheStore = cacheStore
        self.now = now
        loadStoredRates()
    }

    /// Takes the stored table when it is newer than the one in memory (the other process may have refreshed it).
    private func loadStoredRates() {
        guard let stored = cacheStore.load(), stored.fetchedAt > (cacheTimestamp ?? .distantPast) else { return }
        cachedRates = stored.rates
        cacheTimestamp = stored.fetchedAt
    }

    private var isCacheFresh: Bool {
        guard let cacheTimestamp else { return false }
        return now().timeIntervalSince(cacheTimestamp) < Constants.API.exchangeRateCacheTTL
    }

    static let defaultProviders: [ExchangeRateProvider] = [
        ERAPIRateProvider(),
        CurrencyAPIRateProvider(urlString: Constants.API.jsDelivrRatesURL),
        CurrencyAPIRateProvider(urlString: Constants.API.currencyApiPagesRatesURL),
    ]

    func fetchUSDExchangeRate(to currency: BaseCurrency) -> AnyPublisher<Double, Error> {
        if currency == .usd {
            return Just(1.0).setFailureType(to: Error.self).eraseToAnyPublisher()
        }

        if !isCacheFresh { loadStoredRates() }
        if isCacheFresh, let rate = cachedRates[currency.rawValue] {
            return Just(rate).setFailureType(to: Error.self).eraseToAnyPublisher()
        }

        let stale = cachedRates[currency.rawValue]
        return fetchRateTable()
            .tryMap { rates -> Double in
                guard let rate = rates[currency.rawValue] else { throw URLError(.cannotParseResponse) }
                return rate
            }
            .catch { error -> AnyPublisher<Double, Error> in
                // When every source fails, fall back to the stale cached rate so prices keep showing.
                if let stale {
                    return Just(stale).setFailureType(to: Error.self).eraseToAnyPublisher()
                }
                return Fail(error: error).eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    private func fetchRateTable() -> AnyPublisher<[String: Double], Error> {
        if let inFlight {
            return inFlight
        }
        let publisher = fetchRates(attempt: 0)
            .receive(on: DispatchQueue.main)
            .handleEvents(
                receiveOutput: { [weak self] rates in
                    guard let self else { return }
                    let fetchedAt = self.now()
                    self.cachedRates = rates
                    self.cacheTimestamp = fetchedAt
                    self.cacheStore.save(ExchangeRateCacheStore.Entry(rates: rates, fetchedAt: fetchedAt))
                },
                receiveCompletion: { [weak self] _ in
                    self?.inFlight = nil
                },
                // When every subscriber cancels (polling restarted), share disconnects upstream without completing;
                // clear it here too, or later requests would keep reusing the dead publisher.
                receiveCancel: { [weak self] in
                    self?.inFlight = nil
                }
            )
            .share()
            .eraseToAnyPublisher()
        inFlight = publisher
        return publisher
    }

    private func fetchRates(attempt: Int) -> AnyPublisher<[String: Double], Error> {
        guard attempt < providers.count else {
            return Fail(error: URLError(.cannotLoadFromNetwork)).eraseToAnyPublisher()
        }
        let provider = providers[attempt]

        guard now() >= rateLimitedUntil[attempt] ?? .distantPast, let url = URL(string: provider.urlString) else {
            return fetchRates(attempt: attempt + 1)
        }
        let request = URLRequest.liveData(url)

        return client.dataPublisher(for: request)
            .mapError { $0 as Error }
            .receive(on: DispatchQueue.main)
            .tryMap { [weak self] data, response -> [String: Double] in
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if http.statusCode == 429, let self {
                    // Don't ask a source that is limiting this IP again until it is over; the next source answers.
                    let pause = PriceService.retryAfter(http) ?? Self.rateLimitBackoff
                    self.rateLimitedUntil[attempt] = self.now().addingTimeInterval(pause)
                }
                guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
                let rates = try provider.parse(data)
                guard !rates.isEmpty else { throw URLError(.cannotParseResponse) }
                return rates
            }
            .catch { [weak self] _ -> AnyPublisher<[String: Double], Error> in
                guard let self else {
                    return Fail(error: URLError(.cancelled)).eraseToAnyPublisher()
                }
                return self.fetchRates(attempt: attempt + 1)
            }
            .eraseToAnyPublisher()
    }
}

// MARK: - Shared cache

/// The last rate table, shared by the app and the widget extension through the App Group container. A nil directory
/// (no App Group, e.g. an unsigned build; tests) keeps the cache in memory only.
struct ExchangeRateCacheStore: Sendable {
    static let fileName = "exchange-rates.json"

    struct Entry: Codable, Equatable {
        var rates: [String: Double]
        var fetchedAt: Date
    }

    let directory: URL?

    static var appGroup: ExchangeRateCacheStore {
        let id = Bundle.main.object(forInfoDictionaryKey: WidgetSnapshotStore.appGroupInfoKey) as? String
        return ExchangeRateCacheStore(directory: id.flatMap {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)
        })
    }

    private var fileURL: URL? { directory?.appendingPathComponent(Self.fileName) }

    /// nil when missing or unreadable; the rates are then fetched.
    func load() -> Entry? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(Entry.self, from: data)
    }

    /// Best effort: a failed write only means the next process fetches again.
    func save(_ entry: Entry) {
        guard let url = fileURL, let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Self.encoder.encode(entry).write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

// MARK: - Providers

/// One FX source, parsed into "currency code (uppercase) → units per 1 USD".
protocol ExchangeRateProvider: Sendable {
    var urlString: String { get }
    func parse(_ data: Data) throws -> [String: Double]
}

/// open.er-api.com: {"result":"success","rates":{"CNY":7.24,...}}
struct ERAPIRateProvider: ExchangeRateProvider {
    let urlString = Constants.API.erApiRatesURL

    func parse(_ data: Data) throws -> [String: Double] {
        struct Response: Decodable {
            let result: String
            let rates: [String: Double]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.result == "success" else { throw URLError(.badServerResponse) }
        return response.rates
    }
}

/// fawazahmed0/currency-api (hosted on jsDelivr and pages.dev): {"date":"...","usd":{"cny":7.24,...}}
struct CurrencyAPIRateProvider: ExchangeRateProvider {
    let urlString: String

    func parse(_ data: Data) throws -> [String: Double] {
        struct Response: Decodable {
            let usd: [String: Double]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return Dictionary(uniqueKeysWithValues: response.usd.map { ($0.key.uppercased(), $0.value) })
    }
}
