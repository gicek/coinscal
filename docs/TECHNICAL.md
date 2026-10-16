# Coinscal Technical Architecture

> This document defines technology choices, data contracts, data sources, and the test strategy. This is a single-platform project, so macOS implementation details also live here. For implementation status, see [Implementation and Verification Status](VALIDATION.md). For build operations, see [Development Guide](DEVELOPMENT.md).

## Technology Choices

- **Swift 6 + SwiftUI, with AppKit hosting the menu bar**: AppKit drives `NSStatusItem`, `NSPopover`, and the Settings `NSWindow`; their content is SwiftUI. The menu bar title needs an `NSAttributedString` for coloring.
- **One third-party dependency**: Sparkle for in-app updates, the standard updater for directly distributed Mac apps. Everything else uses system frameworks (Foundation, Combine, SwiftUI, AppKit, UserNotifications, ServiceManagement, OSLog).
- **No backend**: prices and exchange rates come directly from public APIs that need no key, with multi-source failover.
- **Combine drives the data flow**: this is the current state. New code uses async/await; see ROADMAP for the migration.
- **XcodeGen**: `Apple/project.yml` generates the project.

## Tech Stack

| Item | Version |
|---|---|
| Xcode | 26.5 (Swift 6 language mode, complete strict concurrency, warnings as errors) |
| Deployment target | macOS 14.0, arm64 |
| XcodeGen | 2.45 |
| Testing | Swift Testing |
| Third-party dependencies | Sparkle 2.10.0 (Swift Package, app target only) |
| Website | Static HTML, CSS, and JavaScript modules in `Site/`; Node 20+ `node:test` for offline checks; Wrangler 4.137.0 for deploys |

## System Structure

```
CoinscalApp (@main) ──▶ AppDelegate (wiring; skipped when running as test host)
   ├─ SettingsViewModel ── SettingsStore (UserDefaultsSettingsStore)
   ├─ CoinListViewModel ── PriceServicing (PriceService ── HTTPClient + ExchangeRateServicing)
   │                    └─ PriceAlertNotifying (NotificationService)
   ├─ MenuBarViewModel ──▶ NSStatusItem
   ├─ WidgetSnapshotWriter ──▶ App Group snapshot + WidgetCenter reload
   ├─ DesktopOverlayController ──▶ click-through window at desktop level (reuses widget views)
   └─ UpdateController ── UpdaterBackend (SparkleUpdaterBackend ──▶ Sparkle, dl.coinscal.app)
Views: MenuBar/ (popover), Settings/ (Settings window), Components/

CoinscalWidget (Widget Extension) ── WidgetDataLoader ── snapshot, or fetches prices with its own PriceService
```

| Directory | Contents |
|---|---|
| `Apple/Mac/App` | Entry point, `AppDelegate`, `Constants` |
| `Apple/Mac/Models` | `AppSettings`, `WatchlistCoin`, `Coin`, enums |
| `Apple/Mac/Services` | Prices, exchange rates, HTTP, settings storage, notifications, login item, updates |
| `Apple/Mac/ViewModels` | `CoinListViewModel`, `SettingsViewModel`, `MenuBarViewModel`, `WatchlistViewModel` |
| `Apple/Mac/Views` | SwiftUI views |
| `Apple/Mac/Utilities` | `AlertEvaluator`, `PriceFormatter`, `LocalizationManager` |
| `Apple/Mac/Shared` | Shared by the main app and the widget extension: snapshot model and I/O, widget rules, widget views |
| `Apple/MacWidget` | Widget Extension: configuration (App Intents), timeline, widget definitions |
| `Apple/Mac/Resources` | `Assets.xcassets`, `Localizable.xcstrings`, `coins.json` (coin catalog snapshot), `recommendedCoins.json` |
| `Apple/Mac/Tests` | Unit tests and test doubles |

## Data Contracts

### Desktop Ticker Window

- `DesktopOverlayController` (`Views/DesktopOverlay/`): a borderless, transparent, shadowless `NSWindow` with `ignoresMouseEvents` and `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`. It can become key only while adjusting position.
- Level: `CGWindowLevelForKey(.desktopWindow) + 1`, between the wallpaper and desktop icons (not at the wallpaper level, so the wallpaper doesn't cover it after switching Spaces). Temporarily `.floating` while adjusting position.
- Content: `DesktopOverlayLayout.content` builds `WidgetEntryContent` from `CoinListViewModel.coins` and settings, reusing `Shared/WidgetViews`. The background is an `NSVisualEffectView` with `.behindWindow` (state fixed to active).
- Position: `AppSettings.desktopOverlayOrigin` is in global coordinates (nil means the top-right corner of the main display). `DesktopOverlayLayout.frame` picks the display that overlaps it most, or the nearest one if none overlaps, then clamps to that display's `visibleFrame`. The fallback doesn't overwrite the saved value. It repositions on `didChangeScreenParameters` and on wake.
- Background opacity `desktopOverlayBackgroundOpacity` (0…1, clamped on decode) applies only to the blur layer. While adjusting position it is at least 0.6, because fully transparent pixels in a borderless window don't receive clicks. Below 0.2 (`DesktopOverlayLayout.textNeedsHalo`), the content switches to a dark appearance, and the `widgetTextHalo` environment value makes the shared widget views add two light shadow layers (`TextHalo`) to every piece of text (text only). Secondary text uses 85% white (`SecondaryText`; the system `.secondary` is too faint against pure white), and primary text is pure white (`WallpaperLegibility`). Icons and background stay the same, and wallpaper colors are not read. System widgets don't set this value.
- The "Adjust Position…" button in settings hands off to `AppDelegate` through `Notification.Name.coinscalAdjustDesktopOverlay`.
- Adjust on open: `DesktopOverlayLayout.startsAdjusting` is true only when an already applied setting changes from off to on (the first application at launch doesn't count). Changing size (while adjusting or already placed) uses `resized`, anchored at the top-left corner and clamped to the current display. When already placed, the new bottom-left corner is written back to `desktopOverlayOrigin` (asynchronously, to avoid reentrancy inside the settings publish callback).

### Widget Snapshot and Reload

- Target `CoinscalWidget` (`com.gicek.coinscal.widget`) is embedded in `Coinscal.app/Contents/PlugIns`. No framework: `project.yml` lists each app source file compiled into the extension (`Shared/`, models, coin catalog, price and exchange rate services, formatting, localization), plus Assets, the String Catalog, and `coins.json`. When you add a source file the extension depends on, add it to the list.
- App Group `$(TeamIdentifierPrefix)com.gicek.coinscal` (Team prefix, no provisioning profile needed). Both targets' entitlements and Info.plist (`CoinscalAppGroup`, read at runtime) use this value. It requires `DEVELOPMENT_TEAM` in `local.mk`; in unsigned builds, reading and writing the snapshot is a no-op.
- App side, `WidgetSnapshotWriter`: writes `widget-snapshot.json` on every coin or settings change (debounced 1 second). It requests `reloadAllTimelines` when ≥ 5 minutes have passed since the last request, any price moved > 1%, or a widget-visible setting changed.
- Extension side: uses the snapshot directly when it is less than 15 minutes old, has the same currency, and covers the needed coins. Otherwise it fetches prices with its own `PriceService` (keeping failover state while the process lives); on failure it uses the old snapshot and shows it as stale. The next timeline reload is scheduled 15 minutes later.
- Strings follow the app language stored in the snapshot (`LocalizationManager.string(for:language:)`). The system renders text in the edit panel and the widget gallery in the system language. `WidgetTests.widgetKeysAreTranslated` scans the extension and `Shared/` sources for `widget.*` keys and ensures all three languages are present (the localization guard only checks `Text("…")`).
- Clicking a widget opens `coinscal://popover`. On a cold launch the URL arrives before the popover is wired up, so the popover opens after wiring; it retries for 2 seconds until the status item is on screen. A popover opened this way belongs to an app that was not activated (macOS 14 cooperative activation), so `.transient` won't close it when you click the desktop. While the popover is shown, a global mouse monitor is installed (mouse events need no Accessibility permission); a click outside the app closes the popover, and the monitor is removed on close.

### Settings Persistence

- The whole `AppSettings` is stored as JSON under the `appSettings` key in `UserDefaults.standard`, read and written only through `SettingsStore`.
- The JSON key for `watchlistCoins` is `addedCoins` (kept for compatibility with older versions; don't change it).
- Decoding is fault-tolerant per field: a missing field or unknown enum value falls back to that field's default only; a single corrupt entry in `addedCoins` drops only that entry. New fields must have a default and be covered in `AppSettingsCodingTests`.
- The meaning of `WatchlistCoin.notificationThreshold` depends on `alertKind`: for `above` / `below` it is a **USD** price; for `change` it is a percentage; `notSet` stores 0.

### Coin Catalog (`coins.json`, schemaVersion 1)

- Generation: `scripts/catalog/generate_catalog.py` (`make catalog`). CoinGecko top 1000 by market cap ∩ USDT spot pairs on any of the three exchanges (Binance halted pairs filtered out, symbols must be ASCII, exchange price within 20% of CoinGecko) → all of them become `listed`. `make catalog` passes `--previous`, so every id in the previous catalog is kept (a migration target only when an old id pointing to it is kept); see [COIN_CATALOG](COIN_CATALOG.md). `scripts/catalog/migrations.json` maintains migration relationships by hand; if the target isn't tradable, the coin is treated as delisted.
- Entry fields: `id` (CoinGecko id, the watchlist identity), `symbol`, `name`, `rank`, `logoURL`, `status` (`active` / `delisted` / `migrated`), `listed`, `migratedTo`.
- Validation rules exist in both Python (`generate_catalog.py validate`, run offline by `make test-mac`) and Swift (`CoinCatalog.validate`). **If you change one, change the other**: schema version, id / symbol character sets, name length, 200–1000 listed, must include tradable bitcoin and ethereum, no duplicate tradable symbols (prices are queried by symbol), logo host allowlist, listed coins must be tradable, migration target exists and is tradable.
- Client: `CoinCatalog` is the only metadata source. Search and recommendations use only `listed`; the watchlist looks up any entry by id. Only `active` coins are included in price fetches.
- Logos: bundled `coin-<id>` asset → logo cached in the App Group container (`CoinLogoCache`, `<container>/CoinLogos/<id>.img`) → remote URL → symbol placeholder. `CoinLogoStore` (app only, `@MainActor`) downloads the logo of every watchlist coin without a bundled asset once, on launch and whenever the watchlist changes (driven from `AppDelegate`), and deletes logos of coins that left the watchlist; views get it through the `coinLogoStore` environment value. Downloads go through `HTTPClient`, HTTPS on the allowlisted hosts only, ≤ 512KB, must decode as an image. Rules and rationale: "Logos" in [COIN_CATALOG](COIN_CATALOG.md).
- Runtime remote updates (Option B, fetching the `catalog` branch via jsDelivr) are not implemented yet; see [COIN_CATALOG](COIN_CATALOG.md).

### Prices

- All data source quotes are in USDT and treated as USD. `PriceSnapshot.prices` is already multiplied by `usdToTargetRate` to convert to the quote currency.
- `USDT` itself is fixed at 1 USD with 0 24h change; no data source is queried.
- 24h change is expressed as a percentage (`2.5` means +2.5 %).

### Alert Evaluation (`AlertEvaluator`)

- `change`: `|current price − reference price| / reference price × 100 ≥ threshold`. After firing, reference price = current price.
- `above` / `below`: the threshold is converted to the quote currency before comparing. Fires only when a reference price exists and is on the other side of the threshold (crossings only). When the reference price is empty, it only establishes the reference price. For how the reference price follows when nothing fires, see `updateReferencePriceAfterNoTrigger`.
- A reference price is valid only within one quote currency: `CoinListViewModel` clears all reference prices as soon as it detects a quote currency change.

## Data Sources

### Prices (`PriceService`)

Failover in order; the last successful source is the starting point for the next round:

| # | Source | Request | Notes |
|---|---|---|---|
| 1 | Binance `api.binance.com/api/v3/ticker/24hr?symbols=[…]` | Requests only watchlist pairs | If any pair doesn't exist, the whole batch fails with HTTP 400 (-1121); falls back to the full parameterless list on the same host and filters locally. Halted pairs (`BREAK`) still return the price at halt time; entries whose `closeTime` is older than 1 hour are dropped |
| 2 | `data-api.binance.vision` (same protocol) | Same as above | |
| 3 | OKX `/api/v5/market/tickers?instType=SPOT` | Full list, filtered locally by `SYMBOL-USDT` | Change is computed from `open24h` |
| 4 | Bybit `/v5/market/tickers?category=spot` | Full list, filtered locally | `price24hPcnt` is a decimal ratio |

A source counts as successful (the primary source) if it returns any watchlist coin. Coins missing from the primary source are backfilled from sources on **other exchanges** (mirrors of the same exchange are skipped). When an exchange confirms it doesn't have a symbol, that is remembered for 30 minutes (`PriceService.unavailableTTL`) and the symbol isn't requested there in the meantime. A failed backfill request is treated as temporary: it isn't remembered and doesn't affect the primary result. Coins that none of the four sources have show `--`.

Check per-source coverage, cross-source price differences, and failover against the real network with `make mac-check-sources` (a manual test, not part of `make test`). A cross-source price difference > 20% for the same coin counts as a data error (stale quote, or a different coin with the same name); 2–20% only warns (exchanges with poor liquidity). A cross-source exchange rate difference > 1% counts as an error.

### Exchange Rates (`ExchangeRateService`)

open.er-api.com → jsDelivr currency-api → currency-api.pages.dev. The whole table is cached in memory for 1 hour. USD is not requested. If all sources fail, the stale cache is used. Concurrent requests share one in-flight request; it is cleared when all subscribers cancel it, so later requests don't reuse a disconnected publisher.

### Updates (`UpdateService`)

- Feed `https://dl.coinscal.app/appcast.xml`, set in `Info.plist` (`SUFeedURL`) with `SUPublicEDKey`, `SUEnableAutomaticChecks` = YES, and `SUScheduledCheckInterval` = 86400. Automatic installation is off. No system profile is sent.
- Sparkle verifies each archive's EdDSA signature against `SUPublicEDKey` and requires the new app to be signed by the same Team ID.
- Sandbox: `SUEnableInstallerLauncherService` = YES and the mach-lookup exceptions `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` / `-spki` let Sparkle's installer XPC service replace the app. The Downloader XPC service is off because the app has `network.client`.
- `SparkleUpdaterBackend` implements gentle reminders: a scheduled check shows Sparkle's window only when Coinscal is in focus; otherwise `UpdateController.updateAvailable` drives the popover capsule until Sparkle reports user attention or the session ends. Sparkle calls its user driver delegate on the main thread, so the conformance is `@preconcurrency`.
- Release signing: Xcode leaves Sparkle's XPC services and helpers ad-hoc signed; `release.sh` re-signs `Installer.xpc`, `Downloader.xpc` (entitlements preserved), `Autoupdate`, `Updater.app`, the framework, and then the app with the Developer ID, never with `--deep`. Feed and file layout: [UPDATES](UPDATES.md).

## Concurrency and Lifecycle

- ViewModels, `AppDelegate`, `NotificationService`, `LaunchAtLoginService`, and `LocalizationManager` are `@MainActor`.
- Service-layer callbacks are delivered on the main thread (`receive(on: DispatchQueue.main)`); `PriceServicing` implementations must follow this.
- Polling: a `Timer` fires `refresh()` every `pollingInterval` seconds. If the previous round hasn't finished (worst case 4 sources × 5-second timeout), that tick is skipped. On settings changes (quote currency, notification toggle, interval, language; debounced 0.5 seconds) or watchlist additions and removals, `startPolling()` cancels the in-flight request and refetches immediately.
- If the quote currency has changed when an in-flight request returns, the result is discarded.
- Single instance: at launch, if another instance with the same Bundle ID is found, the app quits.

## Localization Implementation

- `Localizable.xcstrings` uses semantic keys (`extractionState: manual`); the build output is a `.lproj/Localizable.strings` per language.
- `LocalizationManager` loads the `<lang>.lproj` sub-bundle for the selected language, and `loc(_:)` is the only entry point for strings. Language changes take effect immediately (views redraw when `settings` changes; the context menu is rebuilt each time it opens).
- For contracts and terminology, see [Localization](LOCALIZATION.md).

## macOS Platform Notes

- `LSUIElement = YES`: no Dock icon. Call `NSApp.activate` before showing the popover or the Settings window, otherwise click events are routed incorrectly.
- The popover's anchor arrow is hidden through the private KVC key `shouldHideAnchor`.
- `NSMenuEnableActionImages = false`: prevents macOS 26 from automatically adding icons to menu items.
- The Settings window size is clamped as a fallback in `windowWillResize`: `NSHostingController` layout overrides `maxSize` at runtime.
- Setting the window's `contentViewController` resizes it to the SwiftUI view's fitting size (the 600pt minimum width), discarding the initial `contentRect`. `openSettingsWindow` therefore calls `setContentSize` with the default size afterward, before `setFrameAutosaveName` restores any saved frame.
- Settings window title bar: `NSHostingController.sceneBridgingOptions = [.title, .toolbars]` makes the detail area's `navigationTitle` the window title. The window must first get an empty `NSToolbar` (without SwiftUI toolbar items, bridging doesn't create one and you get a plain 32pt title bar), with the `.unified` style (measured 66pt tall on macOS 26). The sidebar toggle is removed with `.toolbar(removing: .sidebarToggle)`. Toolbar items can only live on the detail layer of `SettingsWindow`, present in every pane: once bridging takes over the window toolbar, switching to a pane without toolbar items (items attached to a single pane, or items with empty content) removes the whole toolbar, the title bar falls back to a narrow centered title, and the sidebar shifts down. That's why the Watchlist "+" is always present; in other panes it is transparent, disabled, and hidden from accessibility, and on macOS 26 `sharedBackgroundVisibility(.hidden)` also removes its glass base.
- Whether the menu bar logo is in place is checked by object identity (`button.image !== menuBarLogo`), not by `button.image == nil`: after `image = nil`, `NSStatusBarButton` sometimes returns a 1×1 placeholder image (observed on macOS 26), so a nil check would miss setting the logo.
- The sandbox has only `network.client`. All data sources are HTTPS, with no ATS exceptions.
- The login item uses `SMAppService.mainApp`.

## Logging and Diagnostics

`Logger(subsystem: "com.gicek.coinscal")`, categories: `Settings`, `Notifications`, `LaunchAtLogin`, `CoinCatalog`, `CoinLogos`, `Widget`. Log only error descriptions; don't log settings content or the watchlist.

## Test Strategy

- Pure logic: `AlertEvaluator`, `PriceFormatter`, `AppSettings` encoding and decoding, parsing for each data source.
- Services: `PriceService` / `ExchangeRateService` get a `StubHTTPClient` injected (the data source list can be injected too), covering failover, the Binance whole-batch 400 fallback and halt filtering, cross-exchange backfill and the "exchange doesn't have it" cache, USDT, exchange rate caching and stale fallback, and in-flight cancellation.
- Desktop ticker: `DesktopOverlayTests` covers settings fault tolerance, sizes, default position and clamping to the screen, multi-display selection and fallback, adjust on open, the resize anchor, content selection, and window level.
- Widget: `WidgetTests` covers coin selection, currency, snapshot freshness, sorting, staleness, snapshot I/O (temporary directory), reload throttling, and string keys.
- Catalog: `CoinCatalogTests` validates the bundled snapshot and each rejection case; `CoinCatalogTests` also covers automatically replacing old coins with their successors, and `WatchlistViewModelTests` covers the scope of search and of the browse list in the add panel.
- State machine: `CoinListViewModel` gets `FakePriceService` and `SpyNotifier` injected, covering polling not interrupting in-flight requests, discarding old results and avoiding false alerts on currency change, and above / below alerting only on crossings.
- Settings storage: `UserDefaultsSettingsStore` gets `InMemoryDataStorage` injected, so tests leave no preference files on disk.
- Updates: `UpdateControllerTests` uses `FakeUpdaterBackend`; no Sparkle updater runs in the test host.
- Real network: `Apple/Mac/scripts/manual/check-data-sources.sh` (`make mac-check-sources`).
- Website: `Site/test/site.test.js` (`make test-site`) checks formatting parity with `PriceFormatter`, message keys, the CSP hashes, demo coin logos, and demo settings fallback. The website's price feed mirrors the app's source order but is a separate JavaScript implementation; when the app's sources change, update `Site/js/prices.js`, the CSP in `Site/_headers`, and [WEBSITE](WEBSITE.md) together.
- Wait for main-thread delivery with `drainMainQueue()`; tests don't `sleep`.
- Needs manual verification: menu bar appearance, drag-to-reorder feel, system notification delivery, login item, real data source reachability, installing an update end to end (see VALIDATION).

## Open Source and Dependencies

The only third-party code dependency is Sparkle; Wrangler and Sparkle's command-line tools are pinned build tools. See [THIRD_PARTY_NOTICES](../THIRD_PARTY_NOTICES.md). 78 coin logos are bundled assets; the rest are downloaded from CoinGecko's image CDN when a coin is added to the watchlist. Data comes from the public APIs in the table above.
