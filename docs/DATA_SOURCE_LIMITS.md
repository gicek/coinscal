# Data Source Limits

> Rate limits of the public price and exchange rate sources, and whether normal use stays within them. Checked against each provider's official documentation on Oct 16, 2026; "observed" marks behavior seen with live requests that the documentation doesn't state. For the request flow, see "Data Sources" in [TECHNICAL](TECHNICAL.md).

## Conclusion

A single user is far inside every limit. With up to 20 coins, Coinscal uses about 0.2% of Binance's per-IP budget, and no source is called more often than its guidance allows. The tightest case is many users behind one public IP (an office or school network) with large watchlists; it still leaves headroom, see "Headroom" below. A source that signals a rate limit is left alone until the limit is over.

## Limits by Source

All limits are per IP address; no source needs an API key.

| Source | Documented limit | Cost of Coinscal's request | Over the limit |
|---|---|---|---|
| Binance `api.binance.com/api/v3/ticker/24hr` | 6000 request weight per minute, 300,000 raw requests per 5 minutes | `symbols=` with 1–20 pairs: weight 2; 21–100 pairs: 40 (at most 100 pairs per request); no parameter (all pairs): 80 | HTTP 429 with `Retry-After`; continuing after 429 gets an automatic ban, HTTP 418, from 2 minutes up to 3 days for repeat offenders |
| Binance mirror `data-api.binance.vision` | Not documented separately | Same as above | Not documented. Observed: shares the 6000 weight budget with `api.binance.com` (the `x-mbx-used-weight-1m` counter rises across both hosts) |
| OKX `/api/v5/market/tickers?instType=SPOT` | 20 requests per 2 seconds | 1 request, all spot pairs | Error code 50011, returned either as HTTP 429 or as HTTP 200 with `"code":"50011"`; ban duration not documented |
| Bybit `/v5/market/tickers?category=spot` | 600 requests per 5 seconds, across all `api.bybit.com` traffic | 1 request, all spot pairs | HTTP 403 "access too frequent"; wait at least 10 minutes, then the ban lifts automatically |
| ExchangeRate-API `open.er-api.com/v6/latest/USD` | No number; "request once every hour and never get rate limited", data refreshes once every 24 hours | 1 request, all currencies | HTTP 429 for 20 minutes |
| currency-api on jsDelivr | jsDelivr: "no limits on bandwidth or number of requests" within its terms; the project: "No Rate limits" | 1 request | Not documented |
| currency-api on Cloudflare Pages `latest.currency-api.pages.dev` | Not documented (Cloudflare Pages publishes no request limit for static files) | 1 request | Not documented |
| Binance WebSocket `data-stream.binance.vision` (website demo only) | 300 connection attempts per 5 minutes; 5 incoming messages per second per connection (pings, pongs, subscribe messages); 1024 streams per connection | 1 connection per visitor, about 10 streams | Over the message limit the connection is closed; IPs disconnected repeatedly "may be banned" |

Other documented behavior worth knowing:

- Binance reports the weight used so far in the `X-MBX-USED-WEIGHT-1M` response header. OKX and Bybit public endpoints return no usage headers (observed).
- OKX serves market data from several independent caches, so a later response can be slightly older than an earlier one.
- jsDelivr caches `@latest` versions for up to 7 days at the edge (observed: `s-maxage=43200`, so up to about 12 hours); daily rates make this acceptable.
- ExchangeRate-API's terms ask apps that show its rates to link "Rates By Exchange Rate API" to `https://www.exchangerate-api.com`. The About pane (under "Data Sources") and the website footer carry that link, in English in every language.

## What Coinscal Sends

- **App**: one price round every 10 seconds (`Constants.Defaults.pollingInterval`), never overlapping the previous round. A round normally makes one Binance batch request for the watchlist. Coins Binance doesn't have are filled in from OKX, then Bybit, with one full-list request each.
- **Coins an exchange doesn't list**: once an exchange's answer shows it doesn't list a coin, that coin isn't asked for there for 30 minutes (`PriceService.unavailableTTL`), in the primary batch as well as in fill-in. A Binance batch with a missing pair fails with HTTP 400 and falls back to the full list (weight 80); that happens once, then the batch leaves the coin out and costs weight 2 again, with one more full-list round every 30 minutes.
- **Rate limits**: HTTP 429 or 418, HTTP 403, and OKX code 50011 (also when sent as HTTP 200) mark the exchange as rate-limited. It is skipped, mirror included, until its `Retry-After` has passed; without one, for 1 minute (`PriceService.rateLimitBackoff`), or 10 minutes after a 403 (`PriceService.forbiddenBackoff`, Bybit's documented wait). The round moves on to the next exchange. An exchange rate source that answers HTTP 429 is skipped for its `Retry-After`, or 20 minutes (`ExchangeRateService.rateLimitBackoff`, ExchangeRate-API's block).
- **Exchange rates**: requested only for non-USD currencies, at most once per hour (`Constants.API.exchangeRateCacheTTL`). The table is kept in memory and in the App Group container (`exchange-rates.json`), so a relaunch, the widget extension, and the app all reuse a table younger than an hour instead of fetching their own.
- **Widgets**: use the app's snapshot while it is fresh (15 minutes). Otherwise each timeline reload (about every 15 minutes or longer, set by the system) makes one price request; exchange rates come from the shared table while it is younger than an hour.
- **Website demo**: one WebSocket connection per visitor; while it is quiet for 15 seconds, one REST round every 10 seconds in the app's order. Exchange rates at most once per hour per page.

## Headroom

| Case | Usage per user | Share of the limit | Users sharing one IP before the limit |
|---|---|---|---|
| Up to 20 coins on Binance | 6 requests/min, weight 12/min | 0.2% of Binance's 6000/min | about 500 |
| 21–100 coins on Binance | weight 240/min | 4% | about 25 |
| Some watchlist coins only on OKX or Bybit | Binance as above, plus up to 6 OKX or Bybit requests/min, and a Binance full list (weight 80) every 30 minutes | 1% of OKX's 600/min | about 100 for OKX |
| Binance unreachable, OKX primary | 6 requests/min | 1% of OKX's 600/min | about 100 |
| Bybit primary | 6 requests/min | under 0.1% of Bybit's 7200/min | over 1000 |
| Exchange rates | 1 request/hour for the app and widgets together | Within ExchangeRate-API's hourly guidance | — |

A single user can't reach any limit. Users of a VPN or proxy share its exit IP with everyone else on it, so part of the budget may already be in use (observed through one proxy: about 1,500 of Binance's 6000 weight per minute before Coinscal's requests). If an office's users do reach a limit, each exchange pauses as it asks and the remaining exchanges carry the prices.

## Sources

- Binance REST limits and `ticker/24hr` weights: <https://developers.binance.com/docs/binance-spot-api-docs/rest-api> (also `rest-api.md` in <https://github.com/binance/binance-spot-api-docs>); live `GET /api/v3/exchangeInfo` `rateLimits`.
- Binance market data endpoints: <https://github.com/binance/binance-spot-api-docs/blob/master/faqs/market_data_only.md>
- Binance WebSocket limits: <https://developers.binance.com/docs/binance-spot-api-docs/web-socket-streams>
- OKX rate limits, tickers, and error codes: <https://www.okx.com/docs-v5/en/>
- Bybit rate limits: <https://bybit-exchange.github.io/docs/v5/rate-limit>
- ExchangeRate-API open access: <https://www.exchangerate-api.com/docs/free>
- currency-api: <https://github.com/fawazahmed0/exchange-api>
- jsDelivr terms and caching: <https://www.jsdelivr.com/terms/terms-of-use>, <https://github.com/jsdelivr/jsdelivr>
- Cloudflare Pages limits: <https://developers.cloudflare.com/pages/platform/limits/>
