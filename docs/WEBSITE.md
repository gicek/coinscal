# Website

`Site/` is the product page at `https://coinscal.app/`, also served at `https://coinscal.gicek.com/` with `coinscal.app` as the canonical URL. It explains the app, runs a live demo of the menu bar panel, and links to the latest DMG at `https://dl.coinscal.app/Coinscal.dmg`.

## Stack

- Plain HTML, CSS, and JavaScript modules: no framework, build step, or npm dependencies.
- Hosted on Cloudflare Workers Static Assets without Worker code (`Site/wrangler.jsonc`). `Site/.assetsignore` keeps tooling and tests from being served.
- Pages: `/` (landing), `/privacy`, `404.html`.

| Path | Contents |
|---|---|
| `index.html`, `privacy.html`, `404.html` | Pages; English text with `data-i18n` keys |
| `css/site.css` | Styles, including light and dark appearances |
| `js/main.js`, `js/panel.js` | Menu bar, panel, and demo settings |
| `js/prices.js`, `js/format.js`, `js/coins.js` | Price feed, formatting, demo coins |
| `js/i18n.js`, `messages/*.json` | Localization |
| `js/config.js` | Every outbound link |
| `_headers` | CSP and security headers |
| `test/` | Offline checks (`make test-site`) |

## Hero

A Mac menu bar with the Coinscal panel hanging from it.

- **Menu bar**: the Coinscal item (rendered with the app's rules from the demo settings; click to toggle the panel), a language menu, a Wi-Fi icon that shows whether live prices are flowing, an appearance switch that can return to following the system, and a clock.
- **Panel**: a copy of the app's panel at the same point sizes, opening with Bitcoin and Ethereum. The gear opens demo settings (display currency, menu bar coin, Price / Icon, coloring, background, color scheme); "Manage Watchlist" adds or removes the app's ten recommended coins; the power button hides the panel. A changed price glows briefly. Settings are saved in local storage (`coinscal.demo`) and read back field by field.
- The menu bar background is on by default on the website, unlike the app, so the price stands out; "Custom" colors are app-only.

Below the hero: four feature cards, a privacy section, the download section, and a footer with GitHub, Releases, Issues, Privacy, and the ExchangeRate-API credit.

## Live Data

The demo calls the app's public APIs from the browser:

- Prices: a Binance WebSocket (`data-stream.binance.vision`, `<symbol>usdt@ticker`). While it has been quiet for 15 seconds, or a coin has no price, REST rounds run at most every 10 seconds in the app's order (Binance, Binance mirror, OKX, Bybit), filling missing coins from the next source. OKX and Bybit are asked one coin at a time. Requests time out after 5 seconds, and rounds never overlap. New coins, coming back online, and returning to the tab start a round at once.
- Exchange rates: open.er-api.com, then jsDelivr currency-api, cached for an hour.
- Formatting matches `PriceFormatter`, which `make test-site` checks.

`js/prices.js` follows the app's source order but is simpler: no full-list fallback and no rate-limit pauses. When the app's sources change, update it, the CSP `connect-src` in `_headers`, and this document together.

## Localization

`messages/<lang>.json` holds the same three languages as the app, with `en` as the source. Pages carry English text plus `data-i18n` keys, so they read correctly before scripts run. The language comes from local storage, then the browser's languages (`zh-TW`, `zh-HK`, `zh-MO`, and `zh-Hant` map to Traditional Chinese, other Chinese tags to Simplified Chinese). Visitors whose browser prefers Chinese get the page hidden for up to 1.2 seconds until messages load. There are no per-language URLs.

## Security and Privacy

- `_headers` sets the CSP (site scripts, the hash of the one inline script, `connect-src` limited to the price and exchange rate APIs, Cloudflare Web Analytics), `nosniff`, `Referrer-Policy`, `Permissions-Policy`, and `Cross-Origin-Opener-Policy`. Changing the inline script changes its hash; `make test-site` fails until `_headers` matches.
- No cookies or ads. The only third-party script is Cloudflare Web Analytics, injected on the `coinscal.app` zone; it is cookieless and disclosed on the privacy page. Local storage holds only the language, appearance, and demo settings.
- Outbound links live only in `js/config.js`; pages reference them with `data-link`.

## Deployment

- `make site-deploy CONFIRM=yes` runs `make test-site`, then `wrangler deploy` from `Site/`. Sign in once with `make site-login` (`make site-whoami` shows the account), or set `CLOUDFLARE_API_TOKEN` with Workers Scripts, Workers Routes, and DNS permissions.
- Both custom domains are declared in `wrangler.jsonc`; their zones must belong to the signed-in account, and a hostname with existing DNS records must be cleared before binding.
- `og.jpg` (1200×630) is a screenshot of the hero; retake it when the hero changes.
