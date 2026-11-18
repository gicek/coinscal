# Data Sources

Coinscal calls public, key-free APIs directly from the Mac. All limits below are per IP address and were checked against each provider's documentation on Oct 16, 2026; "observed" marks behavior seen in live requests but not documented.

## Prices

`PriceService` tries the sources in order and starts the next round from the source that last answered:

| # | Source | Request |
|---|---|---|
| 1 | Binance `api.binance.com/api/v3/ticker/24hr?symbols=[…]` | Only the watchlist pairs; `priceChangePercent` uses the rolling window's `openPrice` |
| 2 | Binance mirror `data-api.binance.vision` | Same as Binance |
| 3 | OKX `/api/v5/market/tickers?instType=SPOT` | All spot pairs, filtered locally; change computed from `open24h` |
| 4 | Bybit `/v5/market/tickers?category=spot` | All spot pairs, filtered locally; `price24hPcnt` is a ratio relative to `prevPrice24h` |

- Only USDT pairs are used. A source that returns any watchlist coin becomes the primary source for the round.
- **Fill-in**: coins the primary source lacks are requested from sources on other exchanges. A mirror can be tried after a request failure and is skipped once its exchange has given a definitive listing answer or is rate-limited. A failed fill-in request keeps the primary result.
- **Missing pairs**: Binance fails a whole batch with HTTP 400 (-1121) if one pair doesn't exist; the service then requests the full list on the same host and filters it. Once an exchange's answer shows it doesn't list a coin, that coin is left out of its requests for 30 minutes (`PriceService.unavailableTTL`), so one unlisted coin doesn't make every Binance round a full-list request.
- **Halted pairs**: Binance still returns halted pairs with their last price; tickers whose `closeTime` is more than an hour old are dropped.
- **Rate limits**: HTTP 429, 418, or 403, and OKX code 50011 (also sent as HTTP 200), pause that exchange, mirror included, until its `Retry-After`; without one, for 1 minute, or 10 minutes after a 403 (Bybit's documented wait). Continuing after a Binance 429 leads to an IP ban.
- Each request times out after 5 seconds without data and bypasses the URL cache.

### Fixed-day opening prices

The regular tickers supply current prices and rolling 24-hour statistics. With a fixed midnight selected, the app computes the change as `(last − open) / open × 100`, using the opening price on the exchange that supplied that coin's latest quote.

| Exchange | Opening price |
|---|---|
| Binance and mirror | `/api/v3/ticker/tradingDay` with `timeZone=0` or `8`, `type=MINI`, and batches of up to 100 symbols. The returned `openTime` must match the selected boundary. |
| OKX | `sodUtc0` or `sodUtc8` in the regular ticker response. |
| Bybit | `/v5/market/kline` for the first 1-hour spot candle of the selected day, using the candle's exact start and open. Up to 8 coin requests are started in a polling round. |

The app caches opens in memory by exchange, symbol, and day start. Opening requests run after quote failover and fill-in, and wait at most 3 seconds or the time remaining in the widget's request budget. Missing opens are retried after a minute, subject to the exchange's existing rate-limit pause. The app publishes prices even if the opening requests fail. A fixed-day change is absent until a valid open is available.

## Exchange Rates

`ExchangeRateService` fetches a USD-based table from open.er-api.com, then the jsDelivr copy of currency-api, then its Cloudflare Pages copy. The table is cached for one hour in memory and in the App Group container (`exchange-rates.json`), shared by the app and the widget extension. USD needs no request. A source that answers HTTP 429 is skipped for its `Retry-After`, or 20 minutes. If every source fails, the cached table is used even when expired. A table must contain a valid rate for the requested currency. Partial tables preserve rates and their original cache ages for currencies they omit. Concurrent callers for the same currency share one request.

ExchangeRate-API's terms ask apps that show its rates to link "Rates By Exchange Rate API" to `https://www.exchangerate-api.com`. The About pane and the website footer carry that link in every language.

## Rate Limits

| Source | Documented limit | Cost per Coinscal request | When exceeded |
|---|---|---|---|
| Binance REST | 6000 weight/min, 300,000 requests/5 min | 1–20 pairs: weight 2; 21–100: 40; more, or the full list: 80 | HTTP 429 with `Retry-After`; repeated violations: HTTP 418 bans from 2 minutes to 3 days |
| Binance trading-day ticker | Shares the Binance REST limit | Weight 4 per pair, capped at 200 per request; opens cached for the trading day | Same as Binance REST |
| Binance mirror | Not documented | As Binance | Observed: shares Binance's weight budget |
| OKX tickers | 20 requests/2 s | 1 request | Code 50011 as HTTP 429 or 200 |
| Bybit tickers | 600 requests/5 s for all `api.bybit.com` traffic | 1 request | HTTP 403; lifts after at least 10 minutes |
| open.er-api.com | "Request once every hour"; data refreshes daily | 1 request | HTTP 429 for 20 minutes |
| currency-api (jsDelivr, Cloudflare Pages) | No limits published | 1 request | Not documented |
| Binance WebSocket (website only) | 300 connections/5 min; 5 messages/s per connection | 1 connection, about 10 streams per visitor | Connection closed; repeated offenders may be banned |

Usage stays far inside these limits:

| Case | Per user | Share of the limit | Users per IP before the limit |
|---|---|---|---|
| Up to 20 coins on Binance | 6 requests, weight 12 per minute | 0.2% | about 500 |
| 21–100 coins on Binance | Weight 240 per minute | 4% | about 25 |
| OKX as primary or fill-in | Up to 6 requests per minute | 1% of 600/min | about 100 |
| Bybit as primary | 6 requests per minute | under 0.1% | over 1000 |
| Exchange rates | 1 request per hour for the app and widgets together | Within guidance | — |

Users behind a VPN or proxy share its exit IP, so part of a budget may already be used by others. If a limit is reached, the paused exchange is skipped and the others carry the prices.

## Request Volume

- **App**: one round every 10 seconds, never overlapping the previous one; normally a single Binance request.
- **Widgets**: use the app's snapshot while it is fresh; otherwise one price request per timeline reload (about every 15 minutes or longer, set by the system).
- **Website demo**: one WebSocket per visitor; REST rounds at most every 10 seconds while the stream is quiet or a coin has no price, querying OKX and Bybit per coin.
- **Logos**: one download per watchlist coin without a bundled logo, from CoinGecko's image CDN.
- **Updates**: one appcast request a day to `dl.coinscal.app`.

## Coin Catalog

The catalog (`Apple/Mac/Resources/coins.json`, schema version 1) is bundled with the app. Clients never call CoinGecko: its key-free API has a low shared limit, and the catalog changes slowly. A release carries catalog updates.

The CoinGecko id is a coin's identity. A rename keeps the id and changes the symbol, so watchlists keep working. A project that moves to a new coin gets a new id; `scripts/catalog/migrations.json` maps the old id to the new one by hand.

`make catalog` (`scripts/catalog/generate_catalog.py generate --previous`) regenerates it:

1. Take the CoinGecko top 1000 by market cap. `COINGECKO_API_KEY` (a Demo key) raises the rate limit.
2. Keep coins with a USDT spot pair currently trading on Binance, OKX, or Bybit: halted Binance pairs are dropped, symbols must be ASCII, an exchange price more than 20% from CoinGecko's is treated as a different coin, and each symbol appears once. These coins are `listed` (searchable).
3. Keep every id of the previous catalog as an unlisted entry: still tradable → `active`; mapped to a tradable successor → `migrated`; otherwise `delisted`. A migration target is kept only when an old id that maps to it is kept.
4. Validate, then write.

Entry fields: `id`, `symbol`, `name`, `rank`, `logoURL`, `status` (`active`, `delisted`, `migrated`), `listed`, `migratedTo`.

Validation runs in Python (`generate_catalog.py validate`, part of `make test-mac`) and in Swift (`CoinCatalog.validate`), with the same rules: schema version, id and symbol character sets, name length, 200–1000 listed coins, tradable bitcoin and ethereum, no duplicate tradable symbols, logo hosts on the allowlist, listed coins tradable, migration targets present and tradable.

The current snapshot has 447 listed coins. 79 logos are bundled (`coin-<id>` assets); other logos are downloaded on demand ([Architecture](ARCHITECTURE.md#coin-catalog-client)).

## Checking the Sources

`make mac-check-sources` queries every source over the real network: coverage of the catalog per source, both fixed-day modes for BTC and ETH, price agreement (more than 20% apart for the same symbol is an error, 2–20% a warning), failover with Binance unreachable, and exchange rate agreement (more than 1% apart is an error). It is manual and runs separately from `make test`.

## References

- Binance REST and WebSocket limits: <https://developers.binance.com/docs/binance-spot-api-docs/rest-api>, <https://developers.binance.com/docs/binance-spot-api-docs/web-socket-streams>
- Binance market data endpoints: <https://github.com/binance/binance-spot-api-docs/blob/master/faqs/market_data_only.md>
- OKX: <https://www.okx.com/docs-v5/en/>
- Bybit: <https://bybit-exchange.github.io/docs/v5/rate-limit>
- ExchangeRate-API open access: <https://www.exchangerate-api.com/docs/free>
- currency-api: <https://github.com/fawazahmed0/exchange-api>
- jsDelivr: <https://www.jsdelivr.com/terms/terms-of-use>
- Cloudflare Pages limits: <https://developers.cloudflare.com/pages/platform/limits/>
