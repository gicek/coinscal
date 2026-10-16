import Combine
import Foundation
import Testing
@testable import Coinscal

@MainActor
@Suite struct PriceServiceTests {
    private let binanceBTC = json(#"[{"symbol":"BTCUSDT","lastPrice":"100","priceChangePercent":"1","closeTime":\#(Int(Date().timeIntervalSince1970 * 1000))}]"#)
    private let okxBTC = json(#"{"code":"0","data":[{"instId":"BTC-USDT","last":"101","open24h":"100"}]}"#)
    private let okxOKB = json(#"{"code":"0","data":[{"instId":"OKB-USDT","last":"120","open24h":"100"}]}"#)
    private let okxNothingWanted = json(#"{"code":"0","data":[{"instId":"ETH-USDT","last":"2000","open24h":"2000"}]}"#)
    private let bybitNothingWanted = json(#"{"retCode":0,"result":{"list":[{"symbol":"ETHUSDT","lastPrice":"2000","price24hPcnt":"0"}]}}"#)

    private func isBinance(_ url: URL) -> Bool { url.host == "api.binance.com" }
    private func isBinanceVision(_ url: URL) -> Bool { url.host == "data-api.binance.vision" }
    private func isOKX(_ url: URL) -> Bool { url.host == "www.okx.com" }
    private func isBybit(_ url: URL) -> Bool { url.host == "api.bybit.com" }

    @Test func appliesExchangeRate() async throws {
        let client = StubHTTPClient()
        client.on(isBinance, reply: .status(200, binanceBTC))
        let service = PriceService(client: client, exchangeRateService: FixedExchangeRateService(rate: 7))

        let snapshot = try await firstValue(service.fetchQuotes(symbols: ["btc"], currency: .cny))
        #expect(snapshot.prices["BTC"] == 700)
        #expect(snapshot.changes24h["BTC"] == 1)
        #expect(snapshot.usdToTargetRate == 7)
    }

    @Test func failsOverAndRemembersWorkingProvider() async throws {
        let client = StubHTTPClient()
        client.on(isBinance, reply: .failure(.timedOut))
        client.on(isBinanceVision, reply: .status(503))
        client.on(isOKX, reply: .status(200, okxBTC))
        let service = PriceService(client: client, exchangeRateService: FixedExchangeRateService())

        let first = try await firstValue(service.fetchQuotes(symbols: ["BTC"], currency: .usd))
        #expect(first.prices["BTC"] == 101)
        #expect(client.requestedURLs.map(\.host) == ["api.binance.com", "data-api.binance.vision", "www.okx.com"])

        _ = try await firstValue(service.fetchQuotes(symbols: ["BTC"], currency: .usd))
        #expect(client.requestedURLs.last?.host == "www.okx.com")
        #expect(client.requestedURLs.count == 4, "the next poll starts at the source that worked")
    }

    /// Regression: one pair Binance does not list makes the whole batch fail with 400;
    /// the full list is used instead and the other coins keep their prices.
    @Test func binanceRejectedBatchFallsBackToFullList() async throws {
        let client = StubHTTPClient()
        client.on({ self.isBinance($0) && $0.hasQuery }, reply: .status(400, json(#"{"code":-1121,"msg":"Invalid symbol."}"#)))
        client.on({ self.isBinance($0) && !$0.hasQuery }, reply: .status(200, binanceBTC))
        let service = PriceService(client: client, exchangeRateService: FixedExchangeRateService())

        let snapshot = try await firstValue(service.fetchQuotes(symbols: ["BTC", "OKB"], currency: .usd))
        #expect(snapshot.prices["BTC"] == 100)
        #expect(snapshot.prices["OKB"] == nil)
        #expect(client.requestedURLs.prefix(2).map(\.hasQuery) == [true, false])
    }

    /// Coins the primary exchange does not list are priced by other exchanges;
    /// the Binance mirror is skipped because it lists the same pairs.
    @Test func fillsMissingSymbolsFromOtherExchanges() async throws {
        let client = StubHTTPClient()
        client.on(isBinance, reply: .status(200, binanceBTC))
        client.on(isOKX, reply: .status(200, okxOKB))
        let service = PriceService(client: client, exchangeRateService: FixedExchangeRateService())

        let snapshot = try await firstValue(service.fetchQuotes(symbols: ["BTC", "OKB"], currency: .usd))
        #expect(snapshot.prices == ["BTC": 100, "OKB": 120])
        #expect(abs((snapshot.changes24h["OKB"] ?? 0) - 20) < 1e-9)
        #expect(!client.requestedURLs.contains { self.isBinanceVision($0) })
        #expect(!client.requestedURLs.contains { self.isBybit($0) }, "nothing left to fill after OKX")
    }

    /// A symbol no exchange lists is not requested again on every poll, only after the TTL.
    @Test func remembersSymbolsAnExchangeDoesNotList() async throws {
        let client = StubHTTPClient()
        client.on(isBinance, reply: .status(200, binanceBTC))
        client.on(isOKX, reply: .status(200, okxNothingWanted))
        client.on(isBybit, reply: .status(200, bybitNothingWanted))
        var now = Date(timeIntervalSince1970: 1_000_000)
        let service = PriceService(client: client, exchangeRateService: FixedExchangeRateService(), now: { now })

        _ = try await firstValue(service.fetchQuotes(symbols: ["BTC", "NOPE"], currency: .usd))
        #expect(client.requestedURLs.map(\.host) == ["api.binance.com", "www.okx.com", "api.bybit.com"])

        _ = try await firstValue(service.fetchQuotes(symbols: ["BTC", "NOPE"], currency: .usd))
        #expect(client.requestedURLs.count == 4, "within the TTL only the primary source is asked")

        now = now.addingTimeInterval(PriceService.unavailableTTL + 1)
        _ = try await firstValue(service.fetchQuotes(symbols: ["BTC", "NOPE"], currency: .usd))
        #expect(client.requestedURLs.count == 7, "after the TTL the other exchanges are asked again")
    }

    /// Regression: a coin Binance doesn't list made every poll a rejected batch plus the full list (weight 82 instead
    /// of 2, docs/DATA_SOURCE_LIMITS.md). Once the full list shows it is missing, it stays out of the batch.
    @Test func coinMissingOnBinanceLeavesTheBatch() async throws {
        let client = StubHTTPClient()
        client.on({ self.isBinance($0) && $0.hasQuery }, reply: .status(400, json(#"{"code":-1121,"msg":"Invalid symbol."}"#)))
        client.on({ self.isBinance($0) && $0.query?.contains("BTCUSDT") == true && $0.query?.contains("OKB") == false },
                  reply: .status(200, binanceBTC))
        client.on({ self.isBinance($0) && !$0.hasQuery }, reply: .status(200, binanceBTC))
        client.on(isOKX, reply: .status(200, okxOKB))
        var now = Date(timeIntervalSince1970: 1_000_000)
        let service = PriceService(client: client, exchangeRateService: FixedExchangeRateService(), now: { now })

        _ = try await firstValue(service.fetchQuotes(symbols: ["BTC", "OKB"], currency: .usd))
        let firstRound = client.requestedURLs.count
        #expect(client.requestedURLs.map { self.isBinance($0) && !$0.hasQuery } == [false, true, false], "batch, full list, OKX")

        let second = try await firstValue(service.fetchQuotes(symbols: ["BTC", "OKB"], currency: .usd))
        #expect(second.prices == ["BTC": 100, "OKB": 120])
        let secondRound = client.requestedURLs.dropFirst(firstRound)
        #expect(secondRound.count == 2, "the BTC batch and the OKX fill-in")
        #expect(secondRound.first.map { self.isBinance($0) && $0.query?.contains("OKB") == false } == true,
                "the batch asks for BTC only")
        #expect(!secondRound.contains { self.isBinance($0) && !$0.hasQuery }, "no full list")

        now = now.addingTimeInterval(PriceService.unavailableTTL + 1)
        let before = client.requestedURLs.count
        _ = try await firstValue(service.fetchQuotes(symbols: ["BTC", "OKB"], currency: .usd))
        #expect(client.requestedURLs[before].query?.contains("OKB") == true, "after the TTL the batch includes it again")
    }

    /// Continuing after Binance's 429 gets the IP banned: the exchange (mirror included) is skipped until Retry-After.
    @Test func rateLimitedExchangeIsSkippedUntilRetryAfter() async throws {
        let client = StubHTTPClient()
        client.on(isBinance, reply: .status(429, headers: ["Retry-After": "120"]))
        client.on(isBinanceVision, reply: .status(200, binanceBTC))
        client.on(isOKX, reply: .status(200, okxBTC))
        var now = Date(timeIntervalSince1970: 1_000_000)
        let service = PriceService(client: client, exchangeRateService: FixedExchangeRateService(), now: { now })

        let first = try await firstValue(service.fetchQuotes(symbols: ["BTC"], currency: .usd))
        #expect(first.prices["BTC"] == 101)
        #expect(client.requestedURLs.map(\.host) == ["api.binance.com", "www.okx.com"], "the mirror shares the budget")

        // Make every other source fail so later rounds reach Binance's turn.
        client.on(isOKX, reply: .status(500))
        client.on(isBybit, reply: .status(500))
        now = now.addingTimeInterval(60)
        _ = try? await firstValue(service.fetchQuotes(symbols: ["BTC"], currency: .usd))
        #expect(!client.requestedURLs.dropFirst(2).contains { self.isBinance($0) || self.isBinanceVision($0) },
                "still inside Retry-After")

        now = now.addingTimeInterval(61)
        _ = try? await firstValue(service.fetchQuotes(symbols: ["BTC"], currency: .usd))
        #expect(client.requestedURLs.contains { self.isBinance($0) } && client.requestedURLs.filter { self.isBinance($0) }.count == 2,
                "asked again once Retry-After has passed")
    }

    @Test func forbiddenAndOKXCode50011BackOff() async throws {
        let client = StubHTTPClient()
        client.on(isBinance, reply: .failure(.timedOut))
        client.on(isBinanceVision, reply: .failure(.timedOut))
        client.on(isOKX, reply: .status(200, json(#"{"code":"50011","msg":"Rate limit reached.","data":[]}"#)))
        client.on(isBybit, reply: .status(403))
        var now = Date(timeIntervalSince1970: 1_000_000)
        let service = PriceService(client: client, exchangeRateService: FixedExchangeRateService(), now: { now })

        _ = try? await firstValue(service.fetchQuotes(symbols: ["BTC"], currency: .usd))
        now = now.addingTimeInterval(PriceService.rateLimitBackoff - 1)
        _ = try? await firstValue(service.fetchQuotes(symbols: ["BTC"], currency: .usd))
        #expect(client.requestedURLs.filter { self.isOKX($0) }.count == 1, "OKX 50011 pauses OKX")
        #expect(client.requestedURLs.filter { self.isBybit($0) }.count == 1, "Bybit 403 pauses Bybit")

        now = now.addingTimeInterval(2)
        _ = try? await firstValue(service.fetchQuotes(symbols: ["BTC"], currency: .usd))
        #expect(client.requestedURLs.filter { self.isOKX($0) }.count == 2, "OKX after its default pause")
        #expect(client.requestedURLs.filter { self.isBybit($0) }.count == 1, "Bybit waits 10 minutes")

        now = now.addingTimeInterval(PriceService.forbiddenBackoff)
        _ = try? await firstValue(service.fetchQuotes(symbols: ["BTC"], currency: .usd))
        #expect(client.requestedURLs.filter { self.isBybit($0) }.count == 2)
    }

    /// A failing fill-in source keeps the primary prices and is retried on the next poll.
    @Test func fillFailureKeepsPrimaryPricesAndIsNotRemembered() async throws {
        let client = StubHTTPClient()
        client.on(isBinance, reply: .status(200, binanceBTC))
        client.on(isOKX, reply: .status(500))
        client.on(isBybit, reply: .failure(.timedOut))
        let service = PriceService(client: client, exchangeRateService: FixedExchangeRateService())

        let snapshot = try await firstValue(service.fetchQuotes(symbols: ["BTC", "OKB"], currency: .usd))
        #expect(snapshot.prices == ["BTC": 100])

        _ = try await firstValue(service.fetchQuotes(symbols: ["BTC", "OKB"], currency: .usd))
        #expect(client.requestedURLs.filter { self.isOKX($0) }.count == 2)
    }

    /// Regression: USDT has no USDT/USDT pair; it is priced at 1 USD without a request.
    @Test func quoteAssetIsPricedAtOneDollar() async throws {
        let client = StubHTTPClient()
        let service = PriceService(client: client, exchangeRateService: FixedExchangeRateService(rate: 7.2))

        let snapshot = try await firstValue(service.fetchQuotes(symbols: ["USDT"], currency: .cny))
        #expect(snapshot.prices["USDT"] == 7.2)
        #expect(client.requestedURLs.isEmpty)
    }

    @Test func allProvidersFailingFails() async {
        let client = StubHTTPClient()
        let service = PriceService(client: client, exchangeRateService: FixedExchangeRateService())
        await #expect(throws: (any Error).self) {
            _ = try await firstValue(service.fetchQuotes(symbols: ["BTC"], currency: .usd))
        }
        #expect(client.requestedURLs.count == PriceService.defaultProviders.count)
    }
}

@MainActor
@Suite struct ExchangeRateServiceTests {
    private let erApiCNY = json(#"{"result":"success","rates":{"CNY":7.2,"USD":1}}"#)

    private func isErApi(_ url: URL) -> Bool { url.host == "open.er-api.com" }
    private func isJsDelivr(_ url: URL) -> Bool { url.host == "cdn.jsdelivr.net" }

    @Test func usdNeedsNoRequest() async throws {
        let client = StubHTTPClient()
        let rate = try await firstValue(ExchangeRateService(client: client).fetchUSDExchangeRate(to: .usd))
        #expect(rate == 1)
        #expect(client.requestedURLs.isEmpty)
    }

    @Test func failsOverToSecondSourceAndCaches() async throws {
        let client = StubHTTPClient()
        client.on(isErApi, reply: .status(500))
        client.on(isJsDelivr, reply: .status(200, json(#"{"date":"2026-10-15","usd":{"cny":7.1}}"#)))
        let service = ExchangeRateService(client: client)

        #expect(try await firstValue(service.fetchUSDExchangeRate(to: .cny)) == 7.1)
        #expect(try await firstValue(service.fetchUSDExchangeRate(to: .cny)) == 7.1)
        #expect(client.requestedURLs.count == 2, "second request within the TTL uses the cache")
    }

    @Test func reusesStaleRateWhenAllSourcesFail() async throws {
        let client = StubHTTPClient()
        client.on(isErApi, reply: .status(200, erApiCNY))
        var now = Date(timeIntervalSince1970: 0)
        let service = ExchangeRateService(client: client, now: { now })
        #expect(try await firstValue(service.fetchUSDExchangeRate(to: .cny)) == 7.2)

        client.on({ _ in true }, reply: .failure(.notConnectedToInternet))
        now = now.addingTimeInterval(Constants.API.exchangeRateCacheTTL + 1)
        #expect(try await firstValue(service.fetchUSDExchangeRate(to: .cny)) == 7.2)
    }

    /// ExchangeRate-API blocks an IP for 20 minutes after a 429; it is skipped meanwhile and the next source answers.
    @Test func rateLimitedSourceIsSkipped() async throws {
        let client = StubHTTPClient()
        client.on(isErApi, reply: .status(429))
        client.on({ !self.isErApi($0) }, reply: .failure(.timedOut))
        var now = Date(timeIntervalSince1970: 0)
        let service = ExchangeRateService(client: client, now: { now })
        _ = try? await firstValue(service.fetchUSDExchangeRate(to: .cny))

        now = now.addingTimeInterval(60)
        client.on(isJsDelivr, reply: .status(200, json(#"{"date":"2026-10-15","usd":{"cny":7.1}}"#)))
        #expect(try await firstValue(service.fetchUSDExchangeRate(to: .cny)) == 7.1)
        #expect(client.requestedURLs.filter { self.isErApi($0) }.count == 1, "paused for 20 minutes")

        now = now.addingTimeInterval(ExchangeRateService.rateLimitBackoff + Constants.API.exchangeRateCacheTTL)
        _ = try await firstValue(service.fetchUSDExchangeRate(to: .cny))
        #expect(client.requestedURLs.filter { self.isErApi($0) }.count == 2, "asked again after the pause")
    }

    /// The table is shared through the App Group file: another process within the TTL makes no request.
    @Test func storedRatesAreSharedAcrossInstances() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ExchangeRateCacheStore(directory: directory)
        var now = Date(timeIntervalSince1970: 1_000_000)

        let app = StubHTTPClient()
        app.on(isErApi, reply: .status(200, erApiCNY))
        let appService = ExchangeRateService(client: app, cacheStore: store, now: { now })
        #expect(try await firstValue(appService.fetchUSDExchangeRate(to: .cny)) == 7.2)
        #expect(store.load()?.rates["CNY"] == 7.2)

        let widget = StubHTTPClient()
        widget.on(isErApi, reply: .status(200, json(#"{"result":"success","rates":{"CNY":7.3,"USD":1}}"#)))
        let widgetService = ExchangeRateService(client: widget, cacheStore: store, now: { now })
        now = now.addingTimeInterval(Constants.API.exchangeRateCacheTTL - 10)
        #expect(try await firstValue(widgetService.fetchUSDExchangeRate(to: .cny)) == 7.2)
        #expect(widget.requestedURLs.isEmpty, "within the TTL the stored table is used")

        now = now.addingTimeInterval(20)
        #expect(try await firstValue(widgetService.fetchUSDExchangeRate(to: .cny)) == 7.3)
        #expect(store.load()?.rates["CNY"] == 7.3, "the fresh table is stored for the other process")
    }

    /// Regression: after the request in flight is cancelled (polling restarted), the next request must go out and succeed.
    @Test func cancelledRequestDoesNotBlockNextOne() async throws {
        let client = StubHTTPClient()
        client.on(isErApi, reply: .pending)
        let service = ExchangeRateService(client: client)
        let pending = service.fetchUSDExchangeRate(to: .cny).sink(receiveCompletion: { _ in }, receiveValue: { _ in })
        pending.cancel()

        client.on(isErApi, reply: .status(200, erApiCNY))
        #expect(try await firstValue(service.fetchUSDExchangeRate(to: .cny)) == 7.2)
        #expect(client.requestedURLs.count == 2)
    }
}
