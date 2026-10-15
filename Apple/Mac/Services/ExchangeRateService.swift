import Foundation
import Combine

protocol ExchangeRateServicing {
    func fetchUSDExchangeRate(to currency: BaseCurrency) -> AnyPublisher<Double, Error>
}

/// USD → fiat rates: public sources tried in order, the whole table cached in memory (TTL in Constants).
/// USDT is treated as USD; USD returns 1.0 without a request.
final class ExchangeRateService: ExchangeRateServicing {
    private let client: HTTPClient
    private let providers: [ExchangeRateProvider]
    /// Cache and request coalescing are main-thread only (polling and callbacks run on the main thread).
    private var cachedRates: [String: Double] = [:]
    private var cacheTimestamp: Date?
    /// Concurrent subscribers share the request in flight.
    private var inFlight: AnyPublisher<[String: Double], Error>?

    private let now: () -> Date

    init(
        client: HTTPClient = URLSession.shared,
        providers: [ExchangeRateProvider] = ExchangeRateService.defaultProviders,
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.providers = providers
        self.now = now
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

        if let timestamp = cacheTimestamp,
           now().timeIntervalSince(timestamp) < Constants.API.exchangeRateCacheTTL,
           let rate = cachedRates[currency.rawValue] {
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
                    self?.cachedRates = rates
                    self?.cacheTimestamp = self?.now()
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

        guard let url = URL(string: provider.urlString) else {
            return fetchRates(attempt: attempt + 1)
        }
        let request = URLRequest(url: url, timeoutInterval: Constants.API.requestTimeout)

        return client.dataPublisher(for: request)
            .mapError { $0 as Error }
            .tryMap { data, response -> [String: Double] in
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
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
