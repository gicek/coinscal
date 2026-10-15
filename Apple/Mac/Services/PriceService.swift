import Foundation
import Combine

/// Quote for one coin, priced in USD/USDT.
struct TickerQuote: Equatable {
    let priceUsd: Double
    let change24hPercent: Double?
}

/// Result of one poll; prices are already converted to the display currency with `usdToTargetRate`.
struct PriceSnapshot {
    let prices: [String: Double]
    let changes24h: [String: Double]
    let usdToTargetRate: Double
}

/// Implementations must deliver on the main thread (`CoinListViewModel` is `@MainActor`).
protocol PriceServicing {
    func fetchQuotes(symbols: [String], currency: BaseCurrency) -> AnyPublisher<PriceSnapshot, Error>
}

/// Price service over several public sources.
///
/// - Failover: sources are tried in order; the last one that worked becomes the next starting point.
/// - Fill-in: symbols the primary source does not list are requested from sources on other exchanges.
///   A symbol a source has confirmed it does not list is skipped there for `unavailableTTL`, so a coin
///   listed nowhere costs no extra requests on every poll. Request failures are transient and not remembered.
///
/// Price and 24h change come from the same request. State is only touched on the main thread.
final class PriceService: PriceServicing {
    /// The quote asset has no USDT/USDT pair; it is priced at 1 USD without a request.
    static let quoteAssetSymbol = "USDT"
    /// How long "this exchange does not list this symbol" is remembered.
    static let unavailableTTL: TimeInterval = 30 * 60

    private let client: HTTPClient
    private let exchangeRateService: ExchangeRateServicing
    private let providers: [TickerProvider]
    private let now: () -> Date
    /// Index of the source that last succeeded as primary.
    private var preferredProviderIndex = 0
    /// "listing/SYMBOL" → when the listing was seen without that symbol.
    private var unavailableSince: [String: Date] = [:]

    init(
        client: HTTPClient = URLSession.shared,
        exchangeRateService: ExchangeRateServicing,
        providers: [TickerProvider] = PriceService.defaultProviders,
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.exchangeRateService = exchangeRateService
        self.providers = providers
        self.now = now
    }

    static let defaultProviders: [TickerProvider] = [
        BinanceTickerProvider(baseURL: Constants.API.binanceBaseURL),
        BinanceTickerProvider(baseURL: Constants.API.binanceVisionBaseURL),
        OKXTickerProvider(),
        BybitTickerProvider(),
    ]

    func fetchQuotes(symbols: [String], currency: BaseCurrency) -> AnyPublisher<PriceSnapshot, Error> {
        let normalized = Array(Set(symbols.map { $0.uppercased() })).sorted()
        guard !normalized.isEmpty else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }
        let includesQuoteAsset = normalized.contains(Self.quoteAssetSymbol)
        let tradable = normalized.filter { $0 != Self.quoteAssetSymbol }

        // Start from the last working source so an unreachable one is not retried first every time.
        let start = preferredProviderIndex
        let order = (0..<providers.count).map { (start + $0) % providers.count }

        let tickers: AnyPublisher<[String: TickerQuote], Error> = tradable.isEmpty
            ? Just([:]).setFailureType(to: Error.self).eraseToAnyPublisher()
            : fetchTickers(symbols: tradable, order: order, attempt: 0)
                .flatMap { [weak self] primary -> AnyPublisher<[String: TickerQuote], Error> in
                    guard let self else { return Just(primary.quotes).setFailureType(to: Error.self).eraseToAnyPublisher() }
                    return self.fillMissing(primary.quotes, symbols: tradable, primaryIndex: primary.index)
                }
                .eraseToAnyPublisher()

        return tickers
            .combineLatest(exchangeRateService.fetchUSDExchangeRate(to: currency))
            .map { quotes, rate in
                var quotes = quotes
                if includesQuoteAsset {
                    quotes[Self.quoteAssetSymbol] = TickerQuote(priceUsd: 1, change24hPercent: 0)
                }
                var prices: [String: Double] = [:]
                var changes: [String: Double] = [:]
                for (symbol, quote) in quotes {
                    prices[symbol] = quote.priceUsd * rate
                    if let change = quote.change24hPercent {
                        changes[symbol] = change
                    }
                }
                return PriceSnapshot(prices: prices, changes24h: changes, usdToTargetRate: rate)
            }
            .eraseToAnyPublisher()
    }

    // MARK: - Failover

    private func fetchTickers(
        symbols: [String],
        order: [Int],
        attempt: Int
    ) -> AnyPublisher<(index: Int, quotes: [String: TickerQuote]), Error> {
        guard attempt < order.count else {
            return Fail(error: URLError(.cannotLoadFromNetwork)).eraseToAnyPublisher()
        }
        let index = order[attempt]
        let provider = providers[index]

        guard let request = provider.makeRequest(symbols: symbols) else {
            return fetchTickers(symbols: symbols, order: order, attempt: attempt + 1)
        }

        return Self.load(request, provider: provider, symbols: symbols, client: client)
            .tryMap { quotes -> (index: Int, quotes: [String: TickerQuote]) in
                // A source that matched nothing counts as failed; try the next one.
                guard !quotes.isEmpty else { throw URLError(.zeroByteResource) }
                return (index, quotes)
            }
            .receive(on: DispatchQueue.main)
            .handleEvents(receiveOutput: { [weak self] _ in
                self?.preferredProviderIndex = index
            })
            .catch { [weak self] _ -> AnyPublisher<(index: Int, quotes: [String: TickerQuote]), Error> in
                guard let self else {
                    return Fail(error: URLError(.cancelled)).eraseToAnyPublisher()
                }
                return self.fetchTickers(symbols: symbols, order: order, attempt: attempt + 1)
            }
            .eraseToAnyPublisher()
    }

    // MARK: - Fill-in from other exchanges

    private func fillMissing(
        _ quotes: [String: TickerQuote],
        symbols: [String],
        primaryIndex: Int
    ) -> AnyPublisher<[String: TickerQuote], Error> {
        // One source per exchange, skipping the primary's exchange (a mirror lists the same pairs).
        var seenListings: Set<String> = [providers[primaryIndex].listing]
        let candidates = providers.indices.filter { seenListings.insert(providers[$0].listing).inserted }
        return fill(quotes, missing: symbols.filter { quotes[$0] == nil }, candidates: candidates[...])
    }

    private func fill(
        _ quotes: [String: TickerQuote],
        missing: [String],
        candidates: ArraySlice<Int>
    ) -> AnyPublisher<[String: TickerQuote], Error> {
        guard !missing.isEmpty, let index = candidates.first else {
            return Just(quotes).setFailureType(to: Error.self).eraseToAnyPublisher()
        }
        let provider = providers[index]
        let rest = candidates.dropFirst()
        let wanted = missing.filter { !isKnownUnavailable($0, on: provider.listing) }
        guard !wanted.isEmpty, let request = provider.makeRequest(symbols: wanted) else {
            return fill(quotes, missing: missing, candidates: rest)
        }

        return Self.load(request, provider: provider, symbols: wanted, client: client)
            .receive(on: DispatchQueue.main)
            .map { [weak self] found -> [String: TickerQuote] in
                for symbol in wanted where found[symbol] == nil {
                    self?.markUnavailable(symbol, on: provider.listing)
                }
                return quotes.merging(found) { primary, _ in primary }
            }
            // Fill-in never fails the poll: keep what the primary source returned.
            .catch { _ in Just(quotes).setFailureType(to: Error.self) }
            .flatMap { [weak self] merged -> AnyPublisher<[String: TickerQuote], Error> in
                guard let self else { return Just(merged).setFailureType(to: Error.self).eraseToAnyPublisher() }
                return self.fill(merged, missing: missing.filter { merged[$0] == nil }, candidates: rest)
            }
            .eraseToAnyPublisher()
    }

    private func unavailableKey(_ symbol: String, _ listing: String) -> String { "\(listing)/\(symbol)" }

    private func isKnownUnavailable(_ symbol: String, on listing: String) -> Bool {
        guard let since = unavailableSince[unavailableKey(symbol, listing)] else { return false }
        return now().timeIntervalSince(since) < Self.unavailableTTL
    }

    private func markUnavailable(_ symbol: String, on listing: String) {
        unavailableSince[unavailableKey(symbol, listing)] = now()
    }

    // MARK: - Loading

    /// Loads and parses one request. A rejected batch (HTTP 400, e.g. Binance when any pair in the
    /// list does not exist) is retried with the source's full ticker list, filtered locally.
    private static func load(
        _ request: URLRequest,
        provider: TickerProvider,
        symbols: [String],
        client: HTTPClient
    ) -> AnyPublisher<[String: TickerQuote], Error> {
        loadOnce(request, provider: provider, symbols: symbols, client: client)
            .catch { error -> AnyPublisher<[String: TickerQuote], Error> in
                guard case TickerProviderError.requestRejected = error,
                      let fallback = provider.makeFallbackRequest() else {
                    return Fail(error: error).eraseToAnyPublisher()
                }
                return loadOnce(fallback, provider: provider, symbols: symbols, client: client)
            }
            .eraseToAnyPublisher()
    }

    private static func loadOnce(
        _ request: URLRequest,
        provider: TickerProvider,
        symbols: [String],
        client: HTTPClient
    ) -> AnyPublisher<[String: TickerQuote], Error> {
        client.dataPublisher(for: request)
            .mapError { $0 as Error }
            .tryMap { data, response -> [String: TickerQuote] in
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                switch http.statusCode {
                case 200..<300: break
                case 400: throw TickerProviderError.requestRejected
                default: throw URLError(.badServerResponse)
                }
                return try provider.parse(data, symbols: symbols)
            }
            .eraseToAnyPublisher()
    }
}

// MARK: - Providers

enum TickerProviderError: Error {
    /// The source rejected the request parameters (HTTP 400).
    case requestRejected
}

/// One price source: builds the request and parses it into symbol → quote (USD/USDT),
/// returning only symbols in `symbols`.
protocol TickerProvider: Sendable {
    /// Exchange whose pairs this source lists; mirrors of one exchange share it.
    var listing: String { get }
    func makeRequest(symbols: [String]) -> URLRequest?
    /// Full-list request used when a batch request is rejected; nil when there is none.
    func makeFallbackRequest() -> URLRequest?
    func parse(_ data: Data, symbols: [String]) throws -> [String: TickerQuote]
}

extension TickerProvider {
    func makeFallbackRequest() -> URLRequest? { nil }
}

private func makeGETRequest(_ urlString: String) -> URLRequest? {
    guard let url = URL(string: urlString) else { return nil }
    return URLRequest(url: url, timeoutInterval: Constants.API.requestTimeout)
}

/// Binance /ticker/24hr: last price and 24h change in one request. The main host and the
/// data-api.binance.vision mirror share the protocol and the listing.
struct BinanceTickerProvider: TickerProvider {
    /// Halted pairs (delisted, status `BREAK`) still return their last price with `closeTime` frozen at
    /// the halt (e.g. MATIC, FTM, LRC, RNDR). A window that ended longer ago than this is treated as
    /// halted and dropped.
    static let staleTickerThreshold: TimeInterval = 3600

    let baseURL: String
    var now: @Sendable () -> Date = { Date() }
    var listing: String { "binance" }

    func makeRequest(symbols: [String]) -> URLRequest? {
        let pairs = symbols.map { "\"\($0)USDT\"" }.joined(separator: ",")
        var components = URLComponents(string: "\(baseURL)/ticker/24hr")
        components?.queryItems = [URLQueryItem(name: "symbols", value: "[\(pairs)]")]
        guard let url = components?.url else { return nil }
        return URLRequest(url: url, timeoutInterval: Constants.API.requestTimeout)
    }

    /// The whole batch fails with 400 (-1121) when any pair does not exist; fall back to the full 24hr list.
    func makeFallbackRequest() -> URLRequest? {
        makeGETRequest("\(baseURL)/ticker/24hr")
    }

    func parse(_ data: Data, symbols: [String]) throws -> [String: TickerQuote] {
        struct Item: Decodable {
            let symbol: String
            let lastPrice: String
            let priceChangePercent: String
            /// End of the 24h statistics window, in milliseconds.
            let closeTime: Double
        }
        let items = try JSONDecoder().decode([Item].self, from: data)
        let wanted = Set(symbols)
        let freshAfter = (now().timeIntervalSince1970 - Self.staleTickerThreshold) * 1000
        var result: [String: TickerQuote] = [:]
        for item in items where item.symbol.hasSuffix("USDT") && item.closeTime >= freshAfter {
            let symbol = String(item.symbol.dropLast(4))
            guard wanted.contains(symbol), let price = Double(item.lastPrice) else { continue }
            result[symbol] = TickerQuote(priceUsd: price, change24hPercent: Double(item.priceChangePercent))
        }
        return result
    }
}

/// OKX /market/tickers?instType=SPOT: all spot pairs, filtered locally by SYMBOL-USDT;
/// the 24h change is computed from `open24h`.
struct OKXTickerProvider: TickerProvider {
    var listing: String { "okx" }

    func makeRequest(symbols: [String]) -> URLRequest? {
        makeGETRequest(Constants.API.okxTickersURL)
    }

    func parse(_ data: Data, symbols: [String]) throws -> [String: TickerQuote] {
        struct Response: Decodable {
            struct Item: Decodable {
                let instId: String
                let last: String
                let open24h: String
            }
            let code: String
            let data: [Item]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.code == "0" else { throw URLError(.badServerResponse) }

        let wanted = Set(symbols)
        var result: [String: TickerQuote] = [:]
        for item in response.data where item.instId.hasSuffix("-USDT") {
            let symbol = String(item.instId.dropLast(5))
            guard wanted.contains(symbol), let price = Double(item.last) else { continue }
            let change: Double? = Double(item.open24h).flatMap { open in
                open > 0 ? (price - open) / open * 100 : nil
            }
            result[symbol] = TickerQuote(priceUsd: price, change24hPercent: change)
        }
        return result
    }
}

/// Bybit /v5/market/tickers?category=spot: all spot pairs, filtered locally;
/// `price24hPcnt` is a fraction, not a percentage.
struct BybitTickerProvider: TickerProvider {
    var listing: String { "bybit" }

    func makeRequest(symbols: [String]) -> URLRequest? {
        makeGETRequest(Constants.API.bybitTickersURL)
    }

    func parse(_ data: Data, symbols: [String]) throws -> [String: TickerQuote] {
        struct Response: Decodable {
            struct Item: Decodable {
                let symbol: String
                let lastPrice: String
                let price24hPcnt: String
            }
            struct Result: Decodable {
                let list: [Item]
            }
            let retCode: Int
            let result: Result
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.retCode == 0 else { throw URLError(.badServerResponse) }

        let wanted = Set(symbols)
        var result: [String: TickerQuote] = [:]
        for item in response.result.list where item.symbol.hasSuffix("USDT") {
            let symbol = String(item.symbol.dropLast(4))
            guard wanted.contains(symbol), let price = Double(item.lastPrice) else { continue }
            result[symbol] = TickerQuote(priceUsd: price, change24hPercent: Double(item.price24hPcnt).map { $0 * 100 })
        }
        return result
    }
}
