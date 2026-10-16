# Coinscal Implementation and Verification Status

> The single record of what is verified and what is still pending. Entries are newest first; each says what changed, what was verified, and what remains to be tested. For features, see the [README](../README.md); for scope, see the [Project Definition](PROJECT.md); for change history, see the changelogs.

## Automated Checks (last run 2026-10-16)

- `make test`: PASS.
  - App: localization guards scan 42 files with 0 issues; the bundled coin catalog passes Python validation; 97 unit tests in 13 suites pass (`** TEST SUCCEEDED **`). Coverage: alert evaluation, price formatting, settings encoding/decoding and fault tolerance, menu bar price / icon logic, widget coin selection / freshness / sorting / reload throttling / string keys, desktop ticker position and level, data source parsing, failover and cross-exchange fill-in, exchange rate caching and fallback, polling and currency switching, catalog validation, successor replacement, on-demand logo download and cache cleanup.
  - Website: localization guards scan 7 scripts with 0 issues; 7 offline checks pass (formatting matches `PriceFormatter`, every page key exists, the CSP hash matches each inline script, every demo coin has a logo, demo settings fall back field by field, price colors and the menu bar coin follow the app's rules).
- `make mac-check-sources` (real network, manual): PASS. All four price sources and three exchange rate sources respond. All 450 catalog symbols get a price (USDT is priced locally); 374 symbols quoted by two or more sources agree within 2%, except two warnings within the 20% limit (ZIL 14.9%, AI 5.6%; illiquid pairs). With the Binance hosts unreachable, round 1 fails over in 10.3 s and round 2 starts from the working source in 0.1 s. All three exchange rate sources cover the 12 currencies, and failover from the first source works.

## Records

### 2026-10-16: Website

Static site in `Site/`, deployed to `coinscal.app` and `coinscal.gicek.com` ([WEBSITE](WEBSITE.md)).

- Verified (Chrome via Playwright, local preview and production): live prices over the Binance WebSocket and the Wi-Fi state; with the WebSocket blocked, REST polls every 10 seconds (requests at 0.3 s, 10.3 s, 21.3 s, 32.3 s) and prices stay live; the panel shows and hides from the Coinscal item and the power button; currency, background, and watchlist changes reach the panel and the menu bar item; the language menu works by mouse and keyboard and switches all three languages in place; light and dark; 390 pt wide with no horizontal scroll. On both domains: HTTPS, the CSP and other headers in effect, unknown paths and files in `.assetsignore` return 404, no console errors, and Cloudflare Web Analytics loads under the CSP on `coinscal.app`.
- Pending: Safari on macOS and iOS (glass panel `backdrop-filter`, `light-dark()` colors, select menus, language menu); Lighthouse ≥ 90 in performance, accessibility, best practices, and SEO; download buttons, once the repository and its first release are public.

### 2026-10-16: Settings window default size; no scroll bars in lists

- Verified on a real Mac: with no saved frame, the Settings window opens at 786×500 (twice in a row), and a saved 800×500 frame is still restored; the watchlist list's scroll area has no scroll bar (Accessibility).
- Pending: none.

### 2026-10-15: Developer ID code signing and notarization

- Verified: `make mac-release-notarized` got Accepted for both the app and DMG; ticket stapling validates; `spctl` assesses both as `Notarized Developer ID`; the app extracted from the zip with a download quarantine attribute passes Gatekeeper; the app and the widget are Developer ID signed, with Hardened Runtime, a timestamp, no `get-task-allow`, and the App Group expanded to the Team prefix; the signed Release app runs, shows prices, and the widget extension launches. Without notarization, `spctl` reports `Unnotarized Developer ID` (expected).
- Pending: download the zip and DMG through a browser on another Mac; first launch isn't blocked by Gatekeeper, and the widget can be added.

### 2026-10-15: DMG installer

- Verified (macOS 26, Retina): layout aligns with the background; the volume icon in the Finder title bar and sidebar shows a disk with the logo; `hdiutil verify` and the code signing check of the bundled app pass.
- Pending: open the DMG on another Mac (macOS 14 / 15, including a non-Retina display): the background is sharp, the icons sit at both ends of the illustration, the volume icon shows the logo, and file names are readable in dark mode.
- Known limitation (accepted 2026-10-15): with "show hidden files" on, Finder occasionally scrolls sideways and reveals `.background` and `.VolumeIcon.icns` (2 of 5 times in testing). Both files are required; users who don't show hidden files are unaffected.

### 2026-10-15: Coin catalog top 1000 and on-demand logos

- Verified: five coins without a bundled logo (HYPE, CKB, CVC, NVDAx, MOVR) added from search each got a valid `CoinLogos/<id>.img` (PNG or JPEG, 1–28KB) in the App Group container, and bundled coins weren't downloaded; removing CVC and MOVR deleted their files and kept the others; the catalog has 451 listed coins (119KB); generating with `--previous` keeps old ids and migrations (EOS → Vaulta, FTM → Sonic).
- Pending: a downloaded logo stays after going offline and relaunching; the watchlist widget and the desktop ticker show it on their next refresh.

### 2026-10-15: Desktop ticker

- Verified (measurements in [DESKTOP_OVERLAY](DESKTOP_OVERLAY.md)): level between the wallpaper and the icons; top-right by default; click-through; turning it on enters adjustment; switching size during adjustment stays in adjustment; switching size when placed keeps the top-left corner fixed; adjusting saves the position and restores click-through; the position persists after relaunch without entering adjustment; dragging to an external display persists after relaunch; the opacity slider writes to settings.
- Pending: how the frosted glass blends with real wallpapers; light / dark readability at each opacity, especially below 20% on light wallpapers; desktop icons under the panel can still be selected and dragged; unplugging the panel's display moves it to the nearest display, and it returns when reconnected; position after sleep and wake; full-screen apps and switching Spaces; unaffected by "Click wallpaper to reveal desktop".

### 2026-10-15: Desktop and Notification Center widgets

- Verified: the extension is registered by the system; the app writes snapshots; `coinscal://popover` opens the popover both while the app runs and from a cold launch.
- Pending: both widgets in all three sizes can be added on the desktop and in Notification Center; change is distinguishable in light, dark, and monochrome (app window in front); edit option defaults and changes take effect; updates within about 15 minutes while the app runs, and fetches prices itself after the app quits; clicking a widget opens the popover even when the app isn't running, and clicking the desktop or another app closes it.

### 2026-10-15: Settings window and icons

- Verified: on macOS 26 (Accessibility), the title bar height and title position match in all three panes, the title follows the pane and the language, and "General" scrolls under the title bar.
- Pending:
  1. Title bar on macOS 14 / 15: same checks as above.
  2. Settings "Menu Bar" section and "Show" switch: section and row names are correct in all three languages; Price ↔ Icon takes effect immediately; in Icon mode the related options are grayed out while the quote currency stays editable; the segmented control isn't truncated in any language, and the title refreshes after switching languages.
  3. Layout of the whole Settings window in all three languages (longest English labels: "Color by Price Change", "Green Up, Red Down").
  4. Redrawn icons: the menu bar logo (shown with no price, for example when launched offline) is sharp and correctly sized on light and dark menu bars and on Retina and non-Retina displays; the app icon matches the size of other icons in Finder, Launchpad, and notifications; the About pane logo is sharp.

### 2026-10-15: Coinscal 1.0 baseline

Debug build on macOS 26; the preferences domain was backed up before testing and restored afterward.

- Verified on a real Mac:
  1. Menu bar price, left-click popover, right-click menu, and the three Settings panes.
  2. Upgrade compatibility: existing settings (language, watchlist and order, alert conditions, display options, open at login) read back unchanged.
  3. Instant switching among the three languages, including the Settings window title and the color scheme radio group.
  4. USDT in the watchlist shows 1.00; with a coin not listed on Binance, other coins still update.
  5. Switching the quote currency doesn't trigger alerts; prices convert with exchange rates.
  6. System notifications arrive with correct text (they don't appear when the app's notifications are off in System Settings, which is system behavior).
  7. "Open at Login" drives the system login item (on → enabled, off → disabled).
  8. Delisted coins show "No market data"; a renamed coin (RENDER) shows live prices.
- Pending:
  1. With MATIC in the watchlist and a catalog that marks it `migrated` (the bundled snapshot has no migrated entries; this applies to a future catalog update), it shows as POL with a price after launch (unit-tested).
  2. The "No market data" text for delisted coins in the popover.
  3. A first launch with no saved settings doesn't register a login item (unit-tested).
  4. Above / Below alerts fire only when the price crosses the threshold (unit-tested).

## Focused Verification

The checklist for remote coin catalog updates (not implemented) is in "Acceptance Checklist" in [COIN_CATALOG](COIN_CATALOG.md).
