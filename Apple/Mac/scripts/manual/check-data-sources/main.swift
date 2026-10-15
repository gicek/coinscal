// Manual live-network check of every price and FX source (not part of `make test`).
// Run with `make mac-check-sources`. Exit code 1 when a source is down or data looks wrong.
import Combine
import Foundation

let warnPriceDeviation = 2.0  // % between sources: thin venue, worth a look
let maxPriceDeviation = 20.0  // % between sources: stale ticker or symbol collision
let maxRateDeviation = 1.0    // % between FX sources for the same currency
let coreSymbols = ["BTC", "ETH"]
var problems: [String] = []
var warnings: [String] = []

struct FixedRate: ExchangeRateServicing {
    func fetchUSDExchangeRate(to currency: BaseCurrency) -> AnyPublisher<Double, Error> {
        Just(1).setFailureType(to: Error.self).eraseToAnyPublisher()
    }
}

func wait<T>(_ publisher: AnyPublisher<T, Error>, timeout: TimeInterval = 40) -> (Result<T, Error>, TimeInterval) {
    let start = Date()
    var result: Result<T, Error>?
    let token = publisher.sink(receiveCompletion: {
        if case .failure(let e) = $0 { result = .failure(e) }
    }, receiveValue: { result = .success($0) })
    while result == nil, Date().timeIntervalSince(start) < timeout {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    token.cancel()
    return (result ?? .failure(URLError(.timedOut)), Date().timeIntervalSince(start))
}

func pct(_ a: Double, _ b: Double) -> Double { abs(a - b) / b * 100 }
func median(_ v: [Double]) -> Double { let s = v.sorted(); return s[s.count / 2] }
func secs(_ t: TimeInterval) -> String { String(format: "%.1fs", t) }

struct CatalogFile: Decodable {
    struct Entry: Decodable { let symbol: String; let status: String; let listed: Bool }
    let coins: [Entry]
}
let catalogPath = CommandLine.arguments.dropFirst().first ?? "Apple/Mac/Resources/coins.json"
let catalog = try! JSONDecoder().decode(CatalogFile.self, from: Data(contentsOf: URL(fileURLWithPath: catalogPath)))
// Only listed coins are checked (delisted / migrated catalog entries have no market by definition).
let symbols = Array(Set(catalog.coins.filter { $0.listed && $0.status == "active" }.map { $0.symbol.uppercased() })).sorted()
let tradable = symbols.filter { $0 != PriceService.quoteAssetSymbol }

// MARK: - 1. Each price source on its own, full catalog
print("== Price sources: \(tradable.count) catalog symbols (USDT is priced locally) ==")
let priceSources: [(String, TickerProvider)] = [
    ("Binance", BinanceTickerProvider(baseURL: Constants.API.binanceBaseURL)),
    ("Binance Vision", BinanceTickerProvider(baseURL: Constants.API.binanceVisionBaseURL)),
    ("OKX", OKXTickerProvider()),
    ("Bybit", BybitTickerProvider()),
]
var quotesBySource: [String: [String: Double]] = [:]
var changesBySource: [String: Int] = [:]
for (name, provider) in priceSources {
    let service = PriceService(exchangeRateService: FixedRate(), providers: [provider])
    let (result, elapsed) = wait(service.fetchQuotes(symbols: tradable, currency: .usd))
    switch result {
    case .success(let snapshot):
        let prices = snapshot.prices.filter { $0.key != PriceService.quoteAssetSymbol }
        quotesBySource[name] = prices
        changesBySource[name] = snapshot.changes24h.count
        let missing = tradable.filter { prices[$0] == nil }
        print("\(name): OK \(secs(elapsed))  coverage \(prices.count)/\(tradable.count)  24h change \(snapshot.changes24h.count)")
        print("  missing: \(missing.joined(separator: " "))")
        for core in coreSymbols where prices[core] == nil { problems.append("\(name) has no \(core)") }
    case .failure(let error):
        print("\(name): FAILED \(secs(elapsed)) \(error)")
        problems.append("\(name) failed: \(error)")
    }
}

// MARK: - 2. Cross-source price consistency
print("\n== Price consistency (symbols quoted by 2+ sources) ==")
var compared = 0
var outliers: [(String, Double, String)] = []
for symbol in tradable {
    let quotes = quotesBySource.compactMap { name, prices in prices[symbol].map { (name, $0) } }
    guard quotes.count >= 2 else { continue }
    compared += 1
    let mid = median(quotes.map(\.1))
    let worst = quotes.max { pct($0.1, mid) < pct($1.1, mid) }!
    let dev = pct(worst.1, mid)
    if dev > warnPriceDeviation { outliers.append((symbol, dev, quotes.map { "\($0.0)=\($0.1)" }.sorted().joined(separator: ", "))) }
}
let anywhere = Set(quotesBySource.values.flatMap(\.keys))
print("compared \(compared) symbols; priced by at least one source: \(anywhere.count)/\(tradable.count)")
print("nowhere: \(tradable.filter { !anywhere.contains($0) }.joined(separator: " "))")
for (symbol, dev, detail) in outliers.sorted(by: { $0.1 > $1.1 }) {
    print(String(format: "  %@ deviates %.1f%%: %@", symbol, dev, detail))
    let message = String(format: "%@ price differs %.1f%% between sources", symbol, dev)
    if dev > maxPriceDeviation { problems.append(message) } else { warnings.append(message) }
}
if outliers.isEmpty { print("all within \(warnPriceDeviation)%") }

// MARK: - 3. Failover: both Binance hosts unreachable
print("\n== Failover (Binance hosts unreachable) ==")
let failover = PriceService(exchangeRateService: FixedRate(), providers: [
    BinanceTickerProvider(baseURL: "https://10.255.255.1/api/v3"),
    BinanceTickerProvider(baseURL: "https://10.255.255.2/api/v3"),
    OKXTickerProvider(),
    BybitTickerProvider(),
])
for round in 1...2 {
    let (result, elapsed) = wait(failover.fetchQuotes(symbols: ["BTC", "ETH"], currency: .usd))
    let ok = (try? result.get())?.prices["BTC"] != nil
    print("round \(round): \(ok ? "OK" : "FAILED") \(secs(elapsed))")
    if !ok { problems.append("failover round \(round) failed") }
}

// MARK: - 4. Each FX source on its own, every supported currency
print("\n== FX sources: \(BaseCurrency.allCases.count) currencies ==")
let fxSources: [(String, ExchangeRateProvider)] = [
    ("open.er-api", ERAPIRateProvider()),
    ("jsDelivr currency-api", CurrencyAPIRateProvider(urlString: Constants.API.jsDelivrRatesURL)),
    ("pages.dev currency-api", CurrencyAPIRateProvider(urlString: Constants.API.currencyApiPagesRatesURL)),
]
var ratesBySource: [String: [BaseCurrency: Double]] = [:]
for (name, provider) in fxSources {
    let service = ExchangeRateService(providers: [provider])
    var rates: [BaseCurrency: Double] = [:]
    var elapsedTotal: TimeInterval = 0
    for currency in BaseCurrency.allCases {
        let (result, elapsed) = wait(service.fetchUSDExchangeRate(to: currency))
        elapsedTotal += elapsed
        if let rate = try? result.get() { rates[currency] = rate }
    }
    ratesBySource[name] = rates
    let missing = BaseCurrency.allCases.filter { rates[$0] == nil }.map(\.rawValue)
    print("\(name): \(rates.count)/\(BaseCurrency.allCases.count) currencies \(secs(elapsedTotal))\(missing.isEmpty ? "" : "  missing: \(missing.joined(separator: " "))")")
    if !missing.isEmpty { problems.append("\(name) missing \(missing.joined(separator: " "))") }
}
print(String(format: "%-5@ %@", "", fxSources.map { $0.0 }.map { $0.padding(toLength: 24, withPad: " ", startingAt: 0) }.joined()))
for currency in BaseCurrency.allCases {
    let values = fxSources.map { ratesBySource[$0.0]?[currency] }
    let row = values.map { ($0.map { String(format: "%.4f", $0) } ?? "-").padding(toLength: 24, withPad: " ", startingAt: 0) }.joined()
    print(String(format: "%-5@ %@", currency.rawValue, row))
    let present = values.compactMap { $0 }
    if present.count >= 2 {
        let mid = median(present)
        let dev = present.map { pct($0, mid) }.max()!
        if dev > maxRateDeviation { problems.append(String(format: "%@ rate differs %.2f%% between FX sources", currency.rawValue, dev)) }
    }
}

// MARK: - 5. FX failover: first source unreachable
print("\n== FX failover (first source unreachable) ==")
let fxFailover = ExchangeRateService(providers: [
    CurrencyAPIRateProvider(urlString: "https://10.255.255.1/usd.min.json"),
    ERAPIRateProvider(),
])
let (fxResult, fxElapsed) = wait(fxFailover.fetchUSDExchangeRate(to: .cny))
if let rate = try? fxResult.get() { print("CNY \(rate) after \(secs(fxElapsed))") } else {
    print("FAILED \(secs(fxElapsed))"); problems.append("FX failover failed")
}

// MARK: - 6. Default production chain
print("\n== Default chain (production order) ==")
let production = PriceService(exchangeRateService: ExchangeRateService())
// Primary source plus fill-in from other exchanges must price every listed coin.
let (fullResult, fullElapsed) = wait(production.fetchQuotes(symbols: tradable, currency: .usd))
if let full = try? fullResult.get() {
    let unpriced = tradable.filter { full.prices[$0] == nil }
    print("all listed coins: \(tradable.count - unpriced.count)/\(tradable.count) priced \(secs(fullElapsed))\(unpriced.isEmpty ? "" : "  unpriced: \(unpriced.joined(separator: " "))")")
    if !unpriced.isEmpty { problems.append("default chain leaves \(unpriced.count) listed coins unpriced") }
} else {
    print("all listed coins: FAILED"); problems.append("default chain failed for the full catalog")
}
for currency in [BaseCurrency.usd, .cny, .eur] {
    let (result, elapsed) = wait(production.fetchQuotes(symbols: ["BTC", "ETH", "USDT"], currency: currency))
    if let s = try? result.get() {
        print(String(format: "%@: BTC %.2f  ETH %.2f  USDT %.4f  rate %.4f  %@", currency.rawValue, s.prices["BTC"] ?? -1, s.prices["ETH"] ?? -1, s.prices["USDT"] ?? -1, s.usdToTargetRate, secs(elapsed)))
    } else {
        print("\(currency.rawValue): FAILED"); problems.append("default chain failed for \(currency.rawValue)")
    }
}

print("\n== Result ==")
warnings.forEach { print("WARN: \($0)") }
if problems.isEmpty {
    print("PASS: all sources reachable and consistent")
} else {
    problems.forEach { print("ISSUE: \($0)") }
    print("FAIL: \(problems.count) issue(s)")
    exit(1)
}
