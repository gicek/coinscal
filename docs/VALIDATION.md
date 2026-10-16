# Coinscal Implementation and Verification Status

This document records verification coverage for implemented capabilities and items pending verification. For a user-facing feature overview, see the [README](../README.md). For product scope, see the [Project Definition](PROJECT.md).

## Current Status (2026-10-15)

### Automated Verification

- `make test`: localization guards report 0 issues, the built-in coin catalog Python validation passes, and all 97 unit tests in 13 suites pass (`** TEST SUCCEEDED **`). Coverage: alert evaluation, price formatting, settings encoding/decoding and fault tolerance, menu bar price / icon display logic, widget coin selection / freshness / sorting / refresh throttling / copy keys, desktop ticker position and level, data source parsing, failover and cross-exchange price fill-in, exchange rate caching and fallback, polling and currency switching, coin catalog validation, automatic replacement of old coins with successors, on-demand logo download and cache cleanup.
- `make mac-check-sources` (real network, run manually): PASS. All four price sources and three exchange rate sources are available; all 99 tradable listed coins in the catalog get prices through the production path; cross-source price spread ≤ 2% (illiquid pairs only warn); when Binance is unreachable, round 1 switches to OKX in about 10 s and the next round starts directly from OKX; all three exchange rate sources cover the 12 currencies with < 1% difference.

### Verification on a Real Mac (Debug build, macOS 26; preferences domain backed up before testing and restored afterward)

Verified:

1. Menu bar price, left-click popover, right-click menu, and the three Settings panes.
2. Upgrade compatibility: existing settings (language, watchlist and order, alert conditions, display options, open at login) read back unchanged.
3. Instant switching among the three languages; the Settings window title and color scheme radio group update along with it.
4. Watchlist with USDT: shows 1.00; with a coin not listed on Binance, other coins still update normally.
5. Switching the quote currency doesn't trigger alerts; prices convert using exchange rates.
6. System notifications are delivered with correct text (they don't appear when notifications for this app are turned off in System Settings, which is system behavior).
7. The "Open at Login" switch drives the system login item (on → enabled, off → disabled).
8. Catalog status display: delisted coins show "No market data"; a renamed coin (RENDER) shows live prices.

Pending verification:

1. Actual layout of the Settings window in all three languages (longer English labels).
2. With MATIC in the watchlist and a catalog that marks it `migrated` (the bundled snapshot no longer has migrated entries since the Oct 15, 2026 rebuild; this applies to future catalog updates), it shows as POL with a price after launch (the logic has unit tests).
3. The explanatory text for delisted coins in the popover.
4. First launch (no saved settings) doesn't register a login item (unit tests cover the default value).
5. Above / Below alerts fire only when crossing the threshold (covered by unit tests).
6. Settings "Menu Bar" section and "Show" switch (2026-10-15): section and row names are correct in all three languages; Price ↔ Icon takes effect immediately; in Icon mode the related options are grayed out while the quote currency can still be changed; segmented control text isn't truncated in any of the three languages, and the title refreshes after switching languages.
7. Settings window title bar (2026-10-15): on macOS 14 / 15, the title bar height is the same in all three panes, the title follows pane and language changes, and "General" scrolls up under the title bar (measured with accessibility on macOS 26).
8. Redrawn icons (2026-10-15): sharpness and size of the menu bar logo when there is no price (launch while offline) on light / dark menu bars and on Retina and non-Retina displays; the app icon matches the size of other system icons in Finder, Launchpad, and notifications; the About pane logo is sharp.
9. Desktop and Notification Center widgets (2026-10-15): both widgets in all three sizes can be added on the desktop and in Notification Center; change is distinguishable in light / dark and monochrome (app window in front); edit option defaults and changes take effect; updates within about 15 minutes while the app runs, and fetches prices itself after the app quits; clicking a widget opens the popover (including when the app isn't running), and clicking the desktop or another app closes it. Tested: the extension is registered by the system, the app writes snapshots, and the popover opens via `coinscal://popover` both while running and from a cold launch.
10. Desktop ticker (2026-10-15): how the frosted glass blends with the wallpaper; light / dark readability at each background opacity (below 20%, how the light text and text shadow look on real wallpapers, especially names and times on light wallpapers); desktop icons under the panel can still be selected and dragged; after unplugging the panel's display it moves temporarily to the nearest display and returns when reconnected; position is correct after sleep and wake; behavior with full-screen apps and when switching desktop Spaces; unaffected when "Click wallpaper to reveal desktop" is on. Tested: level between the wallpaper and icons; dragging to an external display persists after relaunch; the background opacity slider writes to settings; top-right by default; click-through; turning it on enters adjustment; switching size during adjustment stays in adjustment; switching size when placed keeps the top-left corner fixed; adjusting position saves and restores click-through; position persists after relaunch without entering adjustment (see "Measurements" in [DESKTOP_OVERLAY](DESKTOP_OVERLAY.md)).
11. DMG installer (2026-10-15): when opened on another Mac (including non-Retina external displays, macOS 14 / 15), the background is sharp, the icons land on both ends of the illustration, and the volume icon shows the logo; file names are readable in dark mode. Tested (macOS 26 Retina): layout aligns with the background; the volume icon in the Finder title bar and sidebar shows a disk with the logo overlaid; image verification and in-package code signing checks pass. Known limitation (accepted 2026-10-15): with "show hidden files" on, `.background` and `.VolumeIcon.icns` are moved outside the window to the right, but Finder occasionally scrolls horizontally on its own and reveals them (2 of 5 times in testing). Both files are required for the background and volume icon; users who don't show hidden files are unaffected.
12. Developer ID code signing and notarization (2026-10-15): download the zip and DMG through a browser (with the quarantine attribute) to another Mac; first launch isn't blocked by Gatekeeper and the widget can be added. Tested: `make mac-release-notarized` got Accepted for both the app and DMG notarizations, ticket stapling validation passed, and `spctl` assesses both as `Notarized Developer ID`; the app extracted from the zip with the download quarantine attribute added passes Gatekeeper; both the app and the widget are Developer ID signed, with Hardened Runtime, a timestamp, and no `get-task-allow`, and the App Group expands to the Team prefix; the signed Release app runs normally, shows prices in the menu bar, and the widget extension launches; without notarization `spctl` assesses it as `Unnotarized Developer ID` (expected).
13. Coin catalog top 1000 and on-demand logos (2026-10-15): the logo stays after going offline and relaunching; the watchlist widget and desktop ticker show it on their next refresh. Tested: on a real Mac, five coins without a bundled logo (HYPE, CKB, CVC, NVDAx, MOVR) were added from search, and each got a valid `CoinLogos/<id>.img` (PNG or JPEG, 1–28KB) in the App Group container while bundled coins weren't downloaded; removing CVC and MOVR from the watchlist deleted their files and kept the others; the rebuilt catalog has 451 listed coins (119KB); generating with the previous catalog still keeps old ids and migrations (EOS → Vaulta, FTM → Sonic); unit tests cover the download rules.

## Focused Verification

The verification checklist for remote coin catalog updates is in "Acceptance Checklist" in [COIN_CATALOG](COIN_CATALOG.md) (feature not implemented).
