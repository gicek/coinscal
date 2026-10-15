import Foundation
import Testing
@testable import Coinscal

@Suite struct TickerProviderTests {
    /// Fixed "now" = 2026-10-15 03:00 UTC; closeTime is in milliseconds.
    private let now = Date(timeIntervalSince1970: 1_792_033_200)
    private var nowMs: Int { Int(now.timeIntervalSince1970 * 1000) }

    private func binance() -> BinanceTickerProvider {
        BinanceTickerProvider(baseURL: "https://example.com", now: { [now] in now })
    }

    @Test func binanceParsesOnlyWantedUsdtPairs() throws {
        let data = json("""
        [{"symbol":"BTCUSDT","lastPrice":"65000.5","priceChangePercent":"-1.25","closeTime":\(nowMs)},
         {"symbol":"ETHBTC","lastPrice":"0.05","priceChangePercent":"0.1","closeTime":\(nowMs)},
         {"symbol":"XRPUSDT","lastPrice":"0.5","priceChangePercent":"3","closeTime":\(nowMs)}]
        """)
        let quotes = try binance().parse(data, symbols: ["BTC"])
        #expect(quotes == ["BTC": TickerQuote(priceUsd: 65000.5, change24hPercent: -1.25)])
    }

    /// Regression: Binance still returns the last price of halted (BREAK) pairs; they must be dropped or stale prices show.
    @Test func binanceDropsHaltedPairs() throws {
        let nineDaysAgo = nowMs - 9 * 86_400_000
        let justUnderAnHour = nowMs - 3_500_000
        let data = json("""
        [{"symbol":"BTCUSDT","lastPrice":"65000","priceChangePercent":"1","closeTime":\(justUnderAnHour)},
         {"symbol":"LRCUSDT","lastPrice":"0.01879","priceChangePercent":"0","closeTime":\(nineDaysAgo)}]
        """)
        let quotes = try binance().parse(data, symbols: ["BTC", "LRC"])
        #expect(quotes.keys.sorted() == ["BTC"])
    }

    @Test func binanceBatchRequestAndFullListFallback() throws {
        let provider = BinanceTickerProvider(baseURL: "https://example.com/api/v3")
        let batch = try #require(provider.makeRequest(symbols: ["BTC", "ETH"])?.url)
        let symbols = URLComponents(url: batch, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
        #expect(symbols == #"["BTCUSDT","ETHUSDT"]"#)
        let fallback = try #require(provider.makeFallbackRequest()?.url)
        #expect(fallback.absoluteString == "https://example.com/api/v3/ticker/24hr")
    }

    @Test func okxComputesChangeFromOpen() throws {
        let data = json("""
        {"code":"0","data":[
          {"instId":"BTC-USDT","last":"110","open24h":"100"},
          {"instId":"ETH-USDT","last":"10","open24h":"0"},
          {"instId":"BTC-USDC","last":"1","open24h":"1"}]}
        """)
        let quotes = try OKXTickerProvider().parse(data, symbols: ["BTC", "ETH"])
        #expect(quotes["BTC"]?.priceUsd == 110)
        #expect(abs((quotes["BTC"]?.change24hPercent ?? 0) - 10) < 1e-9)
        #expect(quotes["ETH"]?.change24hPercent == nil, "no change when open24h is 0")
    }

    @Test func okxErrorCodeThrows() {
        #expect(throws: (any Error).self) {
            try OKXTickerProvider().parse(json(#"{"code":"50011","data":[]}"#), symbols: ["BTC"])
        }
    }

    @Test func bybitPercentIsAFraction() throws {
        let data = json("""
        {"retCode":0,"result":{"list":[{"symbol":"SOLUSDT","lastPrice":"150","price24hPcnt":"0.0125"}]}}
        """)
        let quotes = try BybitTickerProvider().parse(data, symbols: ["SOL"])
        #expect(quotes["SOL"]?.priceUsd == 150)
        #expect(abs((quotes["SOL"]?.change24hPercent ?? 0) - 1.25) < 1e-9)
    }
}
