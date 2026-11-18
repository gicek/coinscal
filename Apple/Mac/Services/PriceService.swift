import Foundation
import Combine

/// Quote for one coin, priced in USD/USDT.
struct TickerQuote: Equatable {
    let priceUsd: Double
    let change24hPercent: Double?
    var openUTC0: Double? = nil
    var openUTC8: Double? = nil
    var quotedAt: Date? = nil
}

/// Result of one poll; prices are already converted to the display currency with `usdToTargetRate`.
struct PriceSnapshot {
    let prices: [String: Double]
    let pricesUSD: [String: Double]
    let priceChanges: [String: Double]
    let usdToTargetRate: Double
    var changeDayStart: Date? = nil
}

/// Implementations must deliver on the main thread (`CoinListViewModel` is `@MainActor`).
protocol PriceServicing {
    func fetchQuotes(symbols: [String], currency: BaseCurrency, changeBasis: PriceChangeBasis) -> AnyPublisher<PriceSnapshot, Error>
}

extension PriceServicing {
    func fetchQuotes(symbols: [String], currency: BaseCurrency) -> AnyPublisher<PriceSnapshot, Error> {
        fetchQuotes(symbols: symbols, currency: currency, changeBasis: .rolling24h)
    }
}

/// Price service over several public sources.
///
/// - Failover: sources are tried in order; the last one that worked becomes the next starting point.
/// - Fill-in: symbols the primary source does not list are requested from sources on other exchanges.
///   A symbol a source has confirmed it does not list is skipped there for `unavailableTTL`, also in the primary
///   batch: one coin Binance lacks would otherwise make every Binance batch fail with HTTP 400 and fall back to the
///   full list (weight 80 instead of 2, docs/DATA_SOURCES.md). Request failures are transient and not remembered.
/// - Rate limits: an exchange that answers with a rate limit is skipped until its `Retry-After` (or a default) passes,
///   mirrors included, since they share the per-IP budget. Continuing after Binance's 429 gets the IP banned.
///
/// Fixed-day changes use the open on the same exchange as the last price. State is only touched on the main thread.
final class PriceService: PriceServicing {
    /// The quote asset has no USDT/USDT pair; it is priced at 1 USD without a request.
    static let quoteAssetSymbol = "USDT"
    /// How long "this exchange does not list this symbol" is remembered.
    static let unavailableTTL: TimeInterval = 30 * 60
    /// Pause after a rate limit without `Retry-After` (Binance 429, OKX 50011).
    static let rateLimitBackoff: TimeInterval = 60
    /// Pause after HTTP 403: Bybit asks to wait at least 10 minutes, Binance uses 403 for its firewall.
    static let forbiddenBackoff: TimeInterval = 10 * 60
    private static let openingTimeout: TimeInterval = 3

    private let client: HTTPClient
    private let exchangeRateService: ExchangeRateServicing
    private let providers: [TickerProvider]
    private let now: () -> Date
    /// Index of the source that last succeeded as primary.
    private var preferredProviderIndex = 0
    /// "listing/SYMBOL" → when the listing was seen without that symbol.
    private var unavailableSince: [String: Date] = [:]
    /// Listing → when its rate limit is expected to be over.
    private var rateLimitedUntil: [String: Date] = [:]
    private struct SourcedTicker {
        let quote: TickerQuote
        let providerIndex: Int
    }
    private struct OpeningKey: Hashable {
        let listing: String
        let symbol: String
        let dayStart: Date
    }
    private enum Opening {
        case price(Double)
        case retryAfter(Date)
    }
    private var openings: [OpeningKey: Opening] = [:]

    init(
        client: HTTPClient = URLSession.liveData,
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

    func fetchQuotes(
        symbols: [String], currency: BaseCurrency, changeBasis: PriceChangeBasis
    ) -> AnyPublisher<PriceSnapshot, Error> {
        fetchQuotes(symbols: symbols, currency: currency, changeBasis: changeBasis, deadline: nil)
    }

    /// A widget deadline limits optional enrichment so it can still receive the prices before timing out.
    func fetchQuotes(
        symbols: [String], currency: BaseCurrency, changeBasis: PriceChangeBasis, deadline: Date?
    ) -> AnyPublisher<PriceSnapshot, Error> {
        let normalized = Array(Set(symbols.map { $0.uppercased() })).sorted()
        guard !normalized.isEmpty else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }
        let includesQuoteAsset = normalized.contains(Self.quoteAssetSymbol)
        let tradable = normalized.filter { $0 != Self.quoteAssetSymbol }

        // Start from the last working source so an unreachable one is not retried first every time.
        let start = preferredProviderIndex
        let order = (0..<providers.count).map { (start + $0) % providers.count }

        let tickers: AnyPublisher<[String: SourcedTicker], Error> = tradable.isEmpty
            ? Just([:]).setFailureType(to: Error.self).eraseToAnyPublisher()
            : fetchTickers(symbols: tradable, order: order, attempt: 0)
                .flatMap { [weak self] primary -> AnyPublisher<[String: SourcedTicker], Error> in
                    let sourced = primary.quotes.mapValues { SourcedTicker(quote: $0, providerIndex: primary.index) }
                    guard let self else { return Just(sourced).setFailureType(to: Error.self).eraseToAnyPublisher() }
                    let alreadyTried = Set(order.prefix { $0 != primary.index })
                    return self.fillMissing(sourced, symbols: tradable, primaryIndex: primary.index, alreadyTried: alreadyTried)
                }
                .eraseToAnyPublisher()

        return tickers
            .flatMap { [self] quotes -> AnyPublisher<(pricesUSD: [String: Double], changes: [String: Double], start: Date?), Error> in
                let date = now()
                let start = changeBasis.dayStart(at: date)
                let changes: AnyPublisher<[String: Double], Never>
                if let start {
                    // Leave time for the widget's main-queue delivery after optional requests finish.
                    let remaining = deadline.map { $0.timeIntervalSince(date) - 0.1 } ?? Self.openingTimeout
                    changes = dayChanges(
                        for: quotes, basis: changeBasis, start: start, at: date, timeout: min(Self.openingTimeout, remaining)
                    )
                } else {
                    changes = Just(quotes.compactMapValues { $0.quote.change24hPercent }).eraseToAnyPublisher()
                }
                return changes.map { changes in
                    var prices = quotes.mapValues { $0.quote.priceUsd }
                    var changes = changes
                    if includesQuoteAsset {
                        prices[Self.quoteAssetSymbol] = 1
                        changes[Self.quoteAssetSymbol] = 0
                    }
                    return (prices, changes, start)
                }
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
            }
            .combineLatest(exchangeRateService.fetchUSDExchangeRate(to: currency))
            .map { quotes, rate in
                PriceSnapshot(
                    prices: quotes.pricesUSD.mapValues { $0 * rate }, pricesUSD: quotes.pricesUSD,
                    priceChanges: quotes.changes, usdToTargetRate: rate, changeDayStart: quotes.start
                )
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
        // Coins this exchange is known not to list stay out of the batch; fill-in looks for them elsewhere.
        let wanted = symbols.filter { !isKnownUnavailable($0, on: provider.listing) }

        guard !isRateLimited(provider.listing), !wanted.isEmpty,
              let request = provider.makeRequest(symbols: wanted) else {
            return fetchTickers(symbols: symbols, order: order, attempt: attempt + 1)
        }

        return Self.load(request, provider: provider, symbols: wanted, client: client)
            .receive(on: DispatchQueue.main)
            .tryMap { [weak self] quotes -> (index: Int, quotes: [String: TickerQuote]) in
                // The source answered, so what it left out is not listed there.
                self?.markMissing(wanted, in: quotes, on: provider.listing)
                // A source that matched nothing counts as failed; try the next one.
                guard !quotes.isEmpty else { throw URLError(.zeroByteResource) }
                return (index, quotes)
            }
            .handleEvents(receiveOutput: { [weak self] _ in
                self?.preferredProviderIndex = index
            })
            .catch { [weak self] error -> AnyPublisher<(index: Int, quotes: [String: TickerQuote]), Error> in
                guard let self else {
                    return Fail(error: URLError(.cancelled)).eraseToAnyPublisher()
                }
                self.noteRateLimit(error, on: provider.listing)
                return self.fetchTickers(symbols: symbols, order: order, attempt: attempt + 1)
            }
            .eraseToAnyPublisher()
    }

    // MARK: - Fill-in from other exchanges

    private func fillMissing(
        _ quotes: [String: SourcedTicker],
        symbols: [String],
        primaryIndex: Int,
        alreadyTried: Set<Int>
    ) -> AnyPublisher<[String: SourcedTicker], Error> {
        // The primary's listing already answered. Elsewhere, a mirror can still help after a transport failure.
        let candidates = providers.indices.filter {
            !alreadyTried.contains($0) && providers[$0].listing != providers[primaryIndex].listing
        }
        return fill(quotes, missing: symbols.filter { quotes[$0] == nil }, candidates: candidates[...])
    }

    private func fill(
        _ quotes: [String: SourcedTicker],
        missing: [String],
        candidates: ArraySlice<Int>
    ) -> AnyPublisher<[String: SourcedTicker], Error> {
        guard !missing.isEmpty, let index = candidates.first else {
            return Just(quotes).setFailureType(to: Error.self).eraseToAnyPublisher()
        }
        let provider = providers[index]
        let rest = candidates.dropFirst()
        let wanted = missing.filter { !isKnownUnavailable($0, on: provider.listing) }
        guard !isRateLimited(provider.listing), !wanted.isEmpty, let request = provider.makeRequest(symbols: wanted) else {
            return fill(quotes, missing: missing, candidates: rest)
        }

        return Self.load(request, provider: provider, symbols: wanted, client: client)
            .receive(on: DispatchQueue.main)
            .map { [weak self] found -> [String: SourcedTicker] in
                self?.markMissing(wanted, in: found, on: provider.listing)
                return quotes.merging(found.mapValues { SourcedTicker(quote: $0, providerIndex: index) }) { primary, _ in primary }
            }
            // Fill-in never fails the poll: keep what the primary source returned.
            .catch { [weak self] error -> Just<[String: SourcedTicker]> in
                self?.noteRateLimit(error, on: provider.listing)
                return Just(quotes)
            }
            .setFailureType(to: Error.self)
            .flatMap { [weak self] merged -> AnyPublisher<[String: SourcedTicker], Error> in
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

    private func markMissing(_ wanted: [String], in found: [String: TickerQuote], on listing: String) {
        for symbol in wanted where found[symbol] == nil {
            unavailableSince[unavailableKey(symbol, listing)] = now()
        }
    }

    private func isRateLimited(_ listing: String) -> Bool {
        guard let until = rateLimitedUntil[listing] else { return false }
        return now() < until
    }

    private func noteRateLimit(_ error: Error, on listing: String) {
        guard case TickerProviderError.rateLimited(let retryAfter) = error else { return }
        rateLimitedUntil[listing] = now().addingTimeInterval(retryAfter ?? Self.rateLimitBackoff)
    }

    // MARK: - Fixed-day changes

    private func dayChanges(
        for quotes: [String: SourcedTicker], basis: PriceChangeBasis, start: Date, at date: Date, timeout: TimeInterval
    ) -> AnyPublisher<[String: Double], Never> {
        // Keep both available day windows, so switching back to a basis doesn't repeat successful requests.
        let activeDays = Set([PriceChangeBasis.utc0.dayStart(at: date), PriceChangeBasis.utc8.dayStart(at: date)].compactMap { $0 })
        openings = openings.filter { activeDays.contains($0.key.dayStart) }
        let usable = quotes.filter { $0.value.quote.quotedAt.map { $0 >= start } ?? true }
        var needed: [Int: [String]] = [:]
        for (symbol, ticker) in usable {
            let provider = providers[ticker.providerIndex]
            let key = OpeningKey(listing: provider.listing, symbol: symbol, dayStart: start)
            if let open = basis == .utc0 ? ticker.quote.openUTC0 : ticker.quote.openUTC8, open.isFinite, open > 0 {
                openings[key] = .price(open)
            }
            switch openings[key] {
            case .price: continue
            case .retryAfter(let until) where date < until: continue
            default: needed[ticker.providerIndex, default: []].append(symbol)
            }
        }

        let requests = needed.flatMap { index, symbols -> [AnyPublisher<Void, Never>] in
            let provider = providers[index]
            guard timeout > 0, !isRateLimited(provider.listing) else { return [] }
            return provider.openingRequests(symbols: symbols.sorted(), basis: basis, start: start)
                .map { loadOpenings($0, provider: provider, start: start, at: date, timeout: timeout) }
        }
        return Publishers.MergeMany(requests)
            .collect()
            .map { [self] _ in
                usable.reduce(into: [String: Double]()) { changes, item in
                    let (symbol, ticker) = item
                    let key = OpeningKey(listing: providers[ticker.providerIndex].listing, symbol: symbol, dayStart: start)
                    guard case .price(let open) = openings[key] else { return }
                    let change = (ticker.quote.priceUsd - open) / open * 100
                    if change.isFinite { changes[symbol] = change }
                }
            }
            .eraseToAnyPublisher()
    }

    private func loadOpenings(
        _ request: OpeningRequest, provider: TickerProvider, start: Date, at date: Date, timeout: TimeInterval
    ) -> AnyPublisher<Void, Never> {
        let keys = request.symbols.map { OpeningKey(listing: provider.listing, symbol: $0, dayStart: start) }
        // Reserve requests before subscribing, including across concurrent widget timelines.
        for key in keys { openings[key] = .retryAfter(date.addingTimeInterval(Self.rateLimitBackoff)) }
        return client.dataPublisher(for: request.urlRequest)
            .mapError { $0 as Error }
            .tryMap { data, response in
                try Self.checkResponse(response)
                return try provider.parseOpenings(data, symbols: request.symbols, start: start)
            }
            .receive(on: DispatchQueue.main)
            .timeout(.seconds(timeout), scheduler: DispatchQueue.main, customError: { URLError(.timedOut) })
            .map { [self] prices in
                for key in keys {
                    if let open = prices[key.symbol], open.isFinite, open > 0 { openings[key] = .price(open) }
                }
            }
            .catch { [self] error -> Just<Void> in
                noteRateLimit(error, on: provider.listing)
                return Just(())
            }
            .eraseToAnyPublisher()
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

    /// `Retry-After` in seconds (the form Binance sends); nil when missing or an HTTP date.
    static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init).flatMap { $0 > 0 ? $0 : nil }
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
                try checkResponse(response)
                return try provider.parse(data, symbols: symbols)
            }
            .eraseToAnyPublisher()
    }

    private static func checkResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        switch http.statusCode {
        case 200..<300: break
        case 400: throw TickerProviderError.requestRejected
        case 418, 429: throw TickerProviderError.rateLimited(retryAfter: retryAfter(http))
        case 403: throw TickerProviderError.rateLimited(retryAfter: retryAfter(http) ?? forbiddenBackoff)
        default: throw URLError(.badServerResponse)
        }
    }
}

// MARK: - Providers

enum TickerProviderError: Error {
    /// The source rejected the request parameters (HTTP 400).
    case requestRejected
    /// The source is limiting this IP (HTTP 429 / 418 / 403, or OKX code 50011); `retryAfter` is its `Retry-After`.
    case rateLimited(retryAfter: TimeInterval?)
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
    func openingRequests(symbols: [String], basis: PriceChangeBasis, start: Date) -> [OpeningRequest]
    func parseOpenings(_ data: Data, symbols: [String], start: Date) throws -> [String: Double]
}

extension TickerProvider {
    func makeFallbackRequest() -> URLRequest? { nil }
    // OKX includes both opens in its regular ticker.
    func openingRequests(symbols: [String], basis: PriceChangeBasis, start: Date) -> [OpeningRequest] { [] }
    func parseOpenings(_ data: Data, symbols: [String], start: Date) throws -> [String: Double] { [:] }
}

struct OpeningRequest {
    let urlRequest: URLRequest
    let symbols: [String]
}

private func makeGETRequest(_ urlString: String) -> URLRequest? {
    guard let url = URL(string: urlString) else { return nil }
    return .liveData(url)
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
        return .liveData(url)
    }

    /// The whole batch fails with 400 (-1121) when any pair does not exist; fall back to the full 24hr list.
    func makeFallbackRequest() -> URLRequest? {
        makeGETRequest("\(baseURL)/ticker/24hr")
    }

    func openingRequests(symbols: [String], basis: PriceChangeBasis, start: Date) -> [OpeningRequest] {
        guard let offset = basis.utcOffset else { return [] }
        // tradingDay requires symbol(s) and accepts at most 100 per request.
        return stride(from: 0, to: symbols.count, by: 100).compactMap { index in
            let batch = Array(symbols[index..<min(index + 100, symbols.count)])
            let pairs = batch.map { "\"\($0)USDT\"" }.joined(separator: ",")
            var components = URLComponents(string: "\(baseURL)/ticker/tradingDay")
            components?.queryItems = [
                URLQueryItem(name: "symbols", value: "[\(pairs)]"),
                URLQueryItem(name: "timeZone", value: String(offset)),
                URLQueryItem(name: "type", value: "MINI")
            ]
            guard let url = components?.url else { return nil }
            return OpeningRequest(urlRequest: .liveData(url), symbols: batch)
        }
    }

    func parseOpenings(_ data: Data, symbols: [String], start: Date) throws -> [String: Double] {
        struct Item: Decodable {
            let symbol: String
            let openPrice: String
            let openTime: Double
        }
        let items = try JSONDecoder().decode([Item].self, from: data)
        let wanted = Set(symbols)
        let openTime = start.timeIntervalSince1970 * 1000
        var result: [String: Double] = [:]
        for item in items where item.openTime == openTime && item.symbol.hasSuffix("USDT") {
            let symbol = String(item.symbol.dropLast(4))
            if wanted.contains(symbol) { result[symbol] = Double(item.openPrice) }
        }
        return result
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
            guard wanted.contains(symbol), let price = Double(item.lastPrice), price.isFinite, price > 0 else { continue }
            result[symbol] = TickerQuote(
                priceUsd: price, change24hPercent: Double(item.priceChangePercent).flatMap { $0.isFinite ? $0 : nil },
                quotedAt: Date(timeIntervalSince1970: item.closeTime / 1000)
            )
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
                let sodUtc0: String?
                let sodUtc8: String?
                let ts: String?
            }
            let code: String
            let data: [Item]
        }
        struct Status: Decodable { let code: String }
        // OKX can report its rate limit as HTTP 200 with code 50011, with or without a `data` field.
        if (try? JSONDecoder().decode(Status.self, from: data))?.code == "50011" {
            throw TickerProviderError.rateLimited(retryAfter: nil)
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.code == "0" else { throw URLError(.badServerResponse) }

        let wanted = Set(symbols)
        var result: [String: TickerQuote] = [:]
        for item in response.data where item.instId.hasSuffix("-USDT") {
            let symbol = String(item.instId.dropLast(5))
            guard wanted.contains(symbol), let price = Double(item.last), price.isFinite, price > 0 else { continue }
            let change: Double? = Double(item.open24h).flatMap { open in
                guard open.isFinite, open > 0 else { return nil }
                let percent = (price - open) / open * 100
                return percent.isFinite ? percent : nil
            }
            result[symbol] = TickerQuote(
                priceUsd: price, change24hPercent: change,
                openUTC0: item.sodUtc0.flatMap(Double.init), openUTC8: item.sodUtc8.flatMap(Double.init),
                quotedAt: item.ts.flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) }
            )
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

    func openingRequests(symbols: [String], basis: PriceChangeBasis, start: Date) -> [OpeningRequest] {
        let startMs = Int64(start.timeIntervalSince1970 * 1000)
        // Bybit only accepts one pair per candle request. Spread large lists across polling rounds.
        return symbols.prefix(8).compactMap { symbol in
            let url = "\(Constants.API.bybitKlineURL)?category=spot&symbol=\(symbol)USDT&interval=60"
                + "&start=\(startMs)&end=\(startMs + 3_599_999)&limit=1"
            guard let request = makeGETRequest(url) else { return nil }
            return OpeningRequest(urlRequest: request, symbols: [symbol])
        }
    }

    func parseOpenings(_ data: Data, symbols: [String], start: Date) throws -> [String: Double] {
        struct Response: Decodable {
            struct Result: Decodable { let symbol: String; let list: [[String]] }
            let retCode: Int
            let result: Result?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        if response.retCode == 10006 { throw TickerProviderError.rateLimited(retryAfter: nil) }
        guard response.retCode == 0, let result = response.result else { throw URLError(.badServerResponse) }
        let startMs = String(Int64(start.timeIntervalSince1970 * 1000))
        guard let symbol = symbols.first, result.symbol == "\(symbol)USDT",
              let candle = result.list.first(where: { $0.count >= 2 && $0[0] == startMs }),
              let open = Double(candle[1]) else { return [:] }
        return [symbol: open]
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
            let time: Double?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.retCode == 0 else { throw URLError(.badServerResponse) }

        let wanted = Set(symbols)
        var result: [String: TickerQuote] = [:]
        for item in response.result.list where item.symbol.hasSuffix("USDT") {
            let symbol = String(item.symbol.dropLast(4))
            guard wanted.contains(symbol), let price = Double(item.lastPrice), price.isFinite, price > 0 else { continue }
            let change = Double(item.price24hPcnt).flatMap { ratio -> Double? in
                let percent = ratio * 100
                return percent.isFinite ? percent : nil
            }
            result[symbol] = TickerQuote(
                priceUsd: price, change24hPercent: change,
                quotedAt: response.time.map { Date(timeIntervalSince1970: $0 / 1000) }
            )
        }
        return result
    }
}
