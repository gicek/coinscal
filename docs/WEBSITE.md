# Website

> Status: approved and deployed 2026-10-16; Safari and Lighthouse pending verification (see [VALIDATION](VALIDATION.md)). Source in `Site/`; for commands, see "Website" in [DEVELOPMENT](DEVELOPMENT.md).

## Goal

A product page for Coinscal: what it does, a live demo, and a download link to the latest notarized DMG (`https://dl.coinscal.app/Coinscal.dmg`, see [UPDATES](UPDATES.md)). The hero is a Mac menu bar with the Coinscal panel hanging from it (layout modeled on [swiftvm.app](https://swiftvm.app/), with Coinscal's own wallpaper, colors, and copy).

## Domains and Hosting

| Item | Value |
|---|---|
| Canonical domain | `https://coinscal.app/` (canonical, Open Graph, sitemap) |
| Second domain | `https://coinscal.gicek.com/` serves the same site; search engines follow the canonical link |
| Hosting | Cloudflare Workers Static Assets, no Worker code (`Site/wrangler.jsonc`) |
| Form | Plain HTML, CSS, and JavaScript modules; no framework, no build step, no npm dependencies |
| Pages | `/` (landing page), `/privacy`, `404.html` |

## Hero: the Menu Bar

Right side of the menu bar, left to right:

| Item | Behavior |
|---|---|
| Coinscal | Shows what the app's menu bar button would show for the demo settings: `<symbol> <price>` with the app's coloring and background rules, or the monochrome logo ("Icon", no price yet, empty watchlist). Click to show or hide the panel; when hidden, a pulsing ring marks the item. |
| Language | An input-menu glyph (`EN`, or the first character of the Chinese language's name); click for a menu listing the three languages, each written in its own script (checkmark on the current one; arrow keys and Esc work). Switches the whole page in place and remembers the choice. |
| Wi-Fi | Connected icon while prices are live (a price arrived within the last 30 seconds and the browser is online); crossed-out icon otherwise. |
| Appearance | Sun or moon; switches the page between light and dark. Choosing what the system already shows clears the override, so the page follows the system again. |
| Clock | The visitor's real date and time, formatted for the page language (date hidden on narrow screens). |

The left side holds the site name and links: Features, Download, GitHub (hidden on narrow screens).

## Hero: the Panel

The panel copies the app's popover (`CoinPopoverView`) in the app's points: 320 wide, 38-point header with "Coinscal" and a loading spinner, 52-point rows (logo, name, symbol, price without currency symbol, 24h change), at least 4 and at most 8 rows tall, and the 52-point footer (gear, "Manage Watchlist", power). Open by default with Bitcoin and Ethereum, drawn 1.16× on screens 1200 pt and wider. Below it, a note says the panel is a demo only and the app has the full features.

Web-only behavior:

- **Gear**: replaces the list with demo settings: Display Currency (the app's 12), Menu Bar Coin, Show (Price / Icon), Color by Price Change, Show Background (on by default on the website, unlike the app, so the menu bar price stands out), Color Scheme (Green Up, Red Down / Red Up, Green Down; "Custom" is app-only). A back button returns to the list.
- **Manage Watchlist**: lists the app's 10 recommended coins with add and remove buttons, and notes that the app offers more coins. Removing every coin shows the app's empty state with "Add Coins".
- **Power**: hides the panel, like clicking the Coinscal item.
- Demo settings are saved in the browser's local storage (`coinscal.demo`), read back field by field so a bad value falls back to its default.
- A changed price glows briefly so the demo reads as live. The app doesn't do this.

## Layout

- Wide screens: copy on the left, the panel hanging from the Coinscal item on the right.
- Narrower than 960 pt: the copy moves below the panel by the panel's height (and back up when it's hidden).
- The panel moves left if it would cross the right gutter. No horizontal scrolling at 375 pt.
- Wallpaper: a dawn sky over a price chart's ridges in the light appearance, the same chart under a night sky in the dark one, both in brand colors.

Sections below the hero:

- Features: one row of four cards (menu bar price, desktop widgets, pinned to the desktop, price alerts) and a small centered line saying there is more.
- Privacy: one statement that data is fetched on the Mac and nothing is collected, with four short points: no account, no data collection, private by design, open source.
- Download: system requirement, "Free and open source", and the download buttons.
- Footer links: GitHub, Releases, Issues, Privacy.

## Data

The demo calls the same public, keyless APIs as the app, straight from the browser (all allow cross-origin requests):

- Prices: a Binance WebSocket stream (`data-stream.binance.vision`, `<symbol>usdt@ticker`) keeps prices current. While it's quiet for 15 seconds, REST polls every 10 seconds in the app's order, Binance → Binance mirror → OKX → Bybit, filling coins a source lacks from the next one. A request is never started while one is in flight. Each request times out after 5 seconds.
- Exchange rates: open.er-api.com, then jsDelivr currency-api; cached for an hour.
- Prices are in USDT, treated as USD, then converted to the display currency. Formatting matches `PriceFormatter` (`,` grouping and `.` decimals in every language).

## Localization

Strings live in `Site/messages/<lang>.json` (`en` is the source) with the same three languages as the app. HTML carries the English text plus `data-i18n` keys, so the page reads fine before scripts run; JavaScript uses `t("key")`. A visitor whose browser prefers Chinese gets the page hidden for up to 1.2 seconds until the messages load, instead of a flash of English. The language is detected from local storage, then the browser's languages (`zh-TW`, `zh-HK`, and `zh-Hant` map to Traditional Chinese). There are no per-language URLs, so there are no `hreflang` links.

## Security and Privacy

- `Site/_headers` sets the CSP (scripts from the site plus the hash of the one inline theme and language script; `connect-src` lists only the price and exchange rate APIs; Cloudflare Web Analytics is allowed in both), `nosniff`, `Referrer-Policy`, `Permissions-Policy`, and `Cross-Origin-Opener-Policy`.
- No cookies or ads. The only third-party script is Cloudflare Web Analytics, which Cloudflare injects on the `coinscal.app` zone (`static.cloudflareinsights.com`, reporting to `cloudflareinsights.com`); it is cookieless, and the privacy page says so (decided 2026-10-16). Local storage holds only the language, appearance, and demo settings.
- Links are in `Site/js/config.js` only; pages reference them with `data-link`. An empty link disables its button.

## Acceptance Checklist

- [x] `make test-site`: localization guards, formatting matches the app, every page key exists, the CSP hash matches each inline script, every demo coin has a logo, settings fall back field by field.
- [x] Headless Chrome: live prices and the Wi-Fi state; REST fallback when the WebSocket fails; panel open and closed; settings (currency, background) and watchlist changes reach the panel and the menu bar item; language menu by mouse and keyboard; light and dark; 390 pt wide with no horizontal scroll; no console errors under the CSP.
- [ ] Safari on macOS and iOS: glass panel (`backdrop-filter`), `light-dark()` colors, select menus, and the language menu.
- [ ] Lighthouse ≥ 90 in performance, accessibility, best practices, and SEO.
- [x] Deployed: both custom domains serve the site over HTTPS with the headers in effect; files listed in `.assetsignore` return 404; live prices load on both domains; Cloudflare Web Analytics loads under the CSP.
- [x] The download buttons serve the latest DMG from `dl.coinscal.app`.
