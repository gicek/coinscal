# Coinscal Project Definition

> This document defines the product and the scope of the first milestone. For implementation and verification status, see [Implementation and Verification Status](VALIDATION.md). For execution order, see the [Roadmap](ROADMAP.md). Items marked "to be confirmed" need confirmation from the product owner.

## Product Name

**Coinscal** - Real-time crypto price monitor

Coinscal fills one gap: glancing at prices any time without opening an exchange app or website. It lives in the macOS menu bar, shows the current price and 24h change of the coins in your watchlist, and sends a system notification when a price hits your target. It does not handle trading, portfolio management, or market analysis.

## Problem

People who follow crypto prices usually keep an exchange website or phone app open and refresh it over and over, which interrupts their work. Exchange app alerts depend on an account and a phone. Coinscal puts prices in the menu bar and delivers alerts through system notifications, with no account or API key. (To be confirmed)

## Target Users

Individuals who work on a Mac, hold or follow a few major coins, and want to learn about price changes passively. (To be confirmed)

**Not typical users or scenarios**: traders who need millisecond-level prices or order book depth; investors who need portfolio profit and loss tracking; users who follow small coins outside the catalog.

## Product Principles

- **Works with zero configuration**: On first launch you get BTC / ETH prices and a default 2% change alert. No sign-up or key required.
- **No data collection**: No server, no account, no analytics. Settings stay on your Mac.
- **Data sources degrade gracefully**: When any single public data source is unavailable, the app switches automatically and the UI keeps working.
- **Lightweight and always running**: No Dock icon. The popover opens and closes instantly.

## First Milestone

### Platform

macOS 14 or later, Apple silicon (arm64).

### Scope

- The menu bar shows the current price of one selected coin. It can be colored by 24h change and have a background color. It can also show only the app icon.
- Left-click popover: current price and 24h change for the watchlist, with a bottom bar to open Settings, manage the watchlist, or quit. Right-click menu: menu bar coin, Settings, About, Quit.
- Watchlist management: search the coin catalog (about 100 tradable coins, see [COIN_CATALOG](COIN_CATALOG.md)) or add from recommended coins; delete; drag to reorder. When a project migrates to a successor coin, the watchlist switches to the successor automatically.
- Price alerts: each coin has its own "above / below a price" or "change of N% from a reference price" condition, and sends a system notification when triggered. There is a global switch.
- Quote currencies: USD, CNY, KRW, HKD, JPY, TWD, SGD, MYR, AUD, CAD, EUR, GBP.
- Color schemes: "Green Up, Red Down" / "Red Up, Green Down" / "Custom".
- Desktop and Notification Center widgets: "Coin Price" (small) and "Watchlist" (medium, large). In "Edit Widget" you can choose coins, quote currency, sort order, and color by change. When the app is not running, the widget fetches prices itself (design in [WIDGET](WIDGET.md), added 2026-10-15).
- Desktop ticker: a click-through price panel pinned to the desktop (between the wallpaper and the desktop icons). It updates every 10 seconds along with the app, has the same sizes and content as the widget, has adjustable background opacity, and can be dragged to any display (see [DESKTOP_OVERLAY](DESKTOP_OVERLAY.md), added 2026-10-15).
- Open at login (off by default). UI languages: English, Simplified Chinese, and Traditional Chinese. Follows the system or switches instantly in the app.

### Out of Scope for the First Milestone

- Accounts, cloud sync, self-hosted servers.
- Trading, placing orders, holdings, and profit and loss tracking.
- Candlestick charts, historical charts, order book depth.
- Data sources that require an API key.
- Custom coins outside the catalog (searching arbitrary remote coins, manually entering trading pairs).

Update this document and the roadmap before adding any of these.

## Success Criteria

- When any price data source is unreachable, the remaining data sources provide a price within the next polling cycle.
- A listed coin in the catalog shows a price as long as at least one price source has it.
- Price alerts fire only when the condition is actually met. Switching the quote currency produces no false alerts.
- The user's watchlist and alert settings survive app upgrades.
- All UI text has translations in all three UI languages.

## Confirmed Product Decisions

| Decision | Choice |
|---|---|
| Product name | Coinscal |
| Platform | macOS menu bar app (`LSUIElement`) |
| Bundle ID | `com.gicek.coinscal` |
| Minimum OS | macOS 14: the app uses macOS 14 SwiftUI APIs (two-parameter `onChange`, `withAnimation` completion, `.windowBackground`). Under the "development start year − 4" rule it should be macOS 13 (whether to lower it is to be confirmed) |
| Distribution | Direct zip or DMG (DMG added 2026-10-15: opening it shows a guide to drag the app into Applications, with the background and drag illustration designed in brand colors); Developer ID code signing + Apple notarization (added 2026-10-15: `make mac-release` only signs; `make mac-release-notarized` also notarizes and staples the ticket. Use only the latter for public distribution) |
| License | MIT; the repository is planned to be public |
| Server | None. Prices and exchange rates come directly from public, keyless APIs. The coin catalog is generated as a static file by a scheduled repository job and served through jsDelivr (see [COIN_CATALOG](COIN_CATALOG.md)) |
| Data sources | Prices: Binance → Binance mirror → OKX → Bybit; coins missing from the primary source are filled in from other exchanges. Exchange rates: open.er-api → jsDelivr currency-api → pages.dev currency-api |
| Default alert | Newly added coins default to "Change 2%"; notifications are on by default |
| Open at login | Off by default; the user turns it on in Settings |
| Projects migrated to a successor coin | The watchlist switches to the successor automatically with no migration prompt (changed 2026-10-15: previously the app showed a prompt and the user replaced the coin with one click. The user decided the UI should use the successor's name directly, with no explanation of the old-to-new migration) |

## Adjustable Product Parameters

| Parameter | Current value | Location |
|---|---|---|
| Polling interval | 10 seconds | `Constants.Defaults.pollingInterval` |
| Timeout per data source | 5 seconds | `Constants.API.requestTimeout` |
| Exchange rate cache | 1 hour | `Constants.API.exchangeRateCacheTTL` |
| "Exchange doesn't have this coin" cache | 30 minutes | `PriceService.unavailableTTL` |
| Change alert range | 0.5 % – 200 % | `AlertEvaluator.clampAlertThreshold` |
| Visible popover rows | 4 – 8 rows | `Constants.Popover` |
| Listed coins in catalog | 100 | `scripts/catalog/generate_catalog.py` `TARGET_LISTED` |
