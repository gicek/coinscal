# Coinscal Website Changelog

Features added, changed, fixed, and removed, newest first. Third-level headings start with Added / Changed / Fixed / Removed; fixes describe the symptom, root cause, fix, and tests.

## 2026-10-16

### Added: ExchangeRate-API attribution link
The footer links "Rates By Exchange Rate API" to `https://www.exchangerate-api.com` (`LINKS.exchangeRateApi`), since the demo converts prices with ExchangeRate-API's rates and its terms require the link on such pages. The text is the same in all three languages.

### Changed: Demo coins follow the new recommended coins
The demo's coin picker offers the app's new recommended coins: BTC, ETH, BNB, SOL, ZEC, HYPE, BCH, LTC, UNI, AAVE. Logos for ZEC, HYPE, BCH, LTC, UNI, and AAVE were added to `Site/img/coins/` (64 px from CoinGecko's image CDN) and those of XRP, ADA, DOGE, AVAX, DOT, and POL removed. A coin saved in the demo settings that is no longer offered is dropped when the settings load.

- Tests: a new `make test-site` check compares the demo coins with `recommendedCoins.json`, their ids and names with the catalog, and the logo files with the coin list.

### Changed: Downloads from dl.coinscal.app; release notes files
The download buttons point to the latest DMG at `https://dl.coinscal.app/Coinscal.dmg`. The privacy page says the app checks `dl.coinscal.app` for updates once a day and sends only its name and version. Release notes for in-app updates live in `Site/releases/<version>.json` (all three languages; not served by the site); `make test-site` checks that every language has the same items. Deployed with the 1.0 release.

### Added: Product website with a live menu bar demo
A static site in `Site/`, deployed to `coinscal.app` and `coinscal.gicek.com` on Cloudflare Workers Static Assets. The hero is a Mac menu bar (Coinscal, language, Wi-Fi, appearance, clock) with a reproduction of the app's popover hanging from the Coinscal item, showing live prices from the app's data sources: a Binance WebSocket stream, with 10-second REST polling in the app's source order when the stream fails. The panel's gear and "Manage Watchlist" open web-only demo settings and a coin picker; the menu bar price shows its background by default. Below the hero: four feature cards, a privacy section (no account, no data collection, private by design, open source), and the download section. English, Simplified Chinese, and Traditional Chinese, switchable in place; light and dark. Also a privacy page and a 404 page. Visits are counted with cookieless Cloudflare Web Analytics, which the CSP allows and the privacy page discloses.

- Plain HTML, CSS, and JavaScript modules: no framework, build step, or npm dependencies. Deployed with `make site-deploy CONFIRM=yes`; Wrangler runs on the newest nvm-installed Node 22+.
- Design and data rules: [WEBSITE](../../docs/WEBSITE.md).
- Tests: `Site/test/site.test.js` (7), run by `make test-site` with the localization guards.
