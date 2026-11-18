# Changelog

Notable changes to the Coinscal app, newest first. Versions follow `MARKETING_VERSION` in `Apple/project.yml`.

## Unreleased

### Added

- "Automatically Install Updates" in Settings → About, off by default.

### Changed

- The "Update Available" reminder stays after a relaunch until you open the update window or install the update.

### Development

- Debug builds check for updates only on request.

## 1.1.0 — 2026-11-18

### Fixed

- Clicking the menu bar item now closes the panel on macOS 27; before, the panel disappeared and reopened.
- Widgets keep updating through the day. The app used to request a widget reload every 5 minutes, which used up the system's daily budget and stopped widgets, often by the evening.
- The menu bar price stays sharp on a display that isn't active.
- The right-click menu shows no icon next to "Settings" on macOS 27.
- A widget's own price request gives up after 15 seconds and shows the last prices instead of failing the refresh.

### Changed

- Release notes for updates follow the in-app language instead of the system language.
- The widget gallery previews your own coins with live prices instead of sample data.
- The app writes widget data only while a widget is placed.
- The right-click menu no longer has "About Coinscal"; it remains in Settings.
- The panel is drawn by Coinscal instead of a system popover, with the same size, material, and placement.
- The coin catalog is refreshed: 447 searchable coins.

### Development

- Debug builds are a separate app, "Coinscal Debug", that runs next to an installed copy.
- Builds and tests require Xcode 27.

## 1.0.1 — 2026-10-16

### Changed

- Desktop ticker: one layout whose height fits up to 16 coins, a "Large" text size, and white text with a soft shadow below 20% background opacity, so changes stay readable on light wallpapers.
- Watchlist: click an added coin in the add panel to remove it. Recommended coins are BTC, ETH, BNB, SOL, ZEC, HYPE, BCH, LTC, UNI, and AAVE.
- Fewer requests to price sources: coins an exchange doesn't list are left out of its requests for 30 minutes, rate-limited sources are paused until their limit passes, and the app and widgets share one exchange rate table.
- Price and exchange rate responses are no longer stored in the URL cache.
- Buttons and menu items no longer end with an ellipsis.
- The About pane credits ExchangeRate-API, as its terms require.

### Fixed

- No icon next to "Settings" in the right-click menu on the first launch.

## 1.0 — 2026-10-16

First public release.

- Menu bar price of a chosen coin, colored by 24h change, with an optional background, or the app icon only.
- Watchlist panel with prices and 24h change; watchlist of about 450 coins with search, recommendations, drag reordering, and automatic replacement of migrated coins.
- Price alerts per coin: above, below, or a percentage change.
- "Coin Price" and "Watchlist" widgets for the desktop and Notification Center.
- Desktop ticker: a click-through price list pinned to the desktop.
- 12 display currencies; English, Simplified Chinese, and Traditional Chinese.
- Price failover across Binance, OKX, and Bybit, and exchange rate failover across three sources.
- In-app updates with Sparkle.
- Developer ID-signed, notarized zip and DMG.
