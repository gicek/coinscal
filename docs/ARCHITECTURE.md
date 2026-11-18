# Architecture

## Overview

- **Swift 6 with SwiftUI on AppKit.** AppKit owns the status item, the menu bar panel, the Settings window, and the desktop ticker window; their content is SwiftUI.
- **No backend.** Prices and exchange rates come straight from public, key-free APIs with failover ([Data Sources](DATA_SOURCES.md)).
- **One dependency.** Sparkle for in-app updates; everything else is Apple frameworks.
- **Combine data flow.** Services return Combine publishers that deliver on the main thread. A move to async/await is a roadmap candidate.
- **Generated project.** `Apple/project.yml` (XcodeGen) generates `Apple/Coinscal.xcodeproj`.

| Item | Value |
|---|---|
| Toolchain | Xcode 27 (macOS 27 SDK), Swift 6 language mode, complete strict concurrency, warnings as errors |
| Deployment target | macOS 14.0, arm64 |
| Tests | Swift Testing |
| Dependency | Sparkle 2.10.0 (Swift Package, app target only) |

## Structure

```
CoinscalApp (@main) → AppDelegate (wiring; does nothing when it is the unit-test host)
  ├─ SettingsViewModel ── SettingsStore
  ├─ CoinListViewModel ── PriceServicing (PriceService ── HTTPClient, ExchangeRateServicing)
  │                    └─ PriceAlertNotifying (NotificationService)
  ├─ MenuBarViewModel → NSStatusItem
  ├─ MenuBarPanelController → NSPanel hosting CoinPopoverView
  ├─ DesktopOverlayController → desktop-level window hosting the shared widget views
  ├─ WidgetSnapshotWriter → App Group snapshot, WidgetCenter
  └─ UpdateController ── UpdaterBackend (SparkleUpdaterBackend)

CoinscalWidget (extension) → WidgetDataLoader → App Group snapshot, or its own PriceService
```

| Path | Contents |
|---|---|
| `Apple/Mac/App` | Entry point, `AppDelegate`, `Constants` |
| `Apple/Mac/Models` | `AppSettings`, `WatchlistCoin`, `Coin`, enums |
| `Apple/Mac/Services` | Prices, exchange rates, HTTP, coin catalog and logos, settings storage, notifications, login item, updates, widget snapshot writer |
| `Apple/Mac/ViewModels` | `CoinListViewModel`, `SettingsViewModel`, `MenuBarViewModel`, `WatchlistViewModel` |
| `Apple/Mac/Views` | `MenuBar/` (panel), `Settings/`, `DesktopOverlay/`, `Components/` |
| `Apple/Mac/Utilities` | `AlertEvaluator`, `PriceFormatter`, `LocalizationManager` |
| `Apple/Mac/Shared` | Code shared with the widget extension: snapshot model and store, widget rules, widget views, logo cache |
| `Apple/Mac/Resources` | Assets, `Localizable.xcstrings`, `coins.json` (catalog), `recommendedCoins.json` |
| `Apple/MacWidget` | Widget extension: widgets, timeline providers, App Intents configuration |
| `Apple/Mac/Tests` | Unit tests and test doubles (`TestSupport.swift`) |

## Concurrency and Lifecycle

- View models, `AppDelegate`, `NotificationService`, `LaunchAtLoginService`, and `LocalizationManager` are `@MainActor`. Services deliver on the main thread (`receive(on: DispatchQueue.main)`), as the `PriceServicing` contract requires.
- Polling: a timer calls `refresh()` every `pollingInterval`. A tick is skipped while the previous round is still running, so a slow source never interrupts failover. Settings changes that affect prices (display currency, alerts switch, interval, language; debounced 0.5 s) and watchlist changes cancel the round in flight and fetch immediately.
- A result that arrives after the display currency changed is discarded.
- Single instance: at launch the app quits if another process with its bundle ID is running.

## Settings

- `AppSettings` is stored as JSON under `appSettings` in the app's `UserDefaults`, only through `SettingsStore`.
- Decoding tolerates errors per field: a missing or invalid field falls back to its default, and a corrupt watchlist entry drops only that entry. New fields need a default and a test in `AppSettingsCodingTests`. The JSON key for `watchlistCoins` stays `addedCoins`.
- `WatchlistCoin.notificationThreshold` is a USD price for `above` / `below`, a percentage for `change`, and 0 for `notSet`.

## Prices and Alerts

- Every source quotes in USDT, treated as USD. `PriceSnapshot.prices` is already converted to the display currency with `usdToTargetRate`. USDT itself is 1 USD with 0% change, without a request. Changes are percentages (`2.5` means +2.5%).
- Request flow, failover, fill-in, and rate-limit handling: [Data Sources](DATA_SOURCES.md).
- `AlertEvaluator`:
  - `change`: fires when `|price − reference| / reference × 100 ≥ threshold`, then the reference becomes the price.
  - `above` / `below`: the threshold is converted to the display currency; fires only when a reference exists on the other side of the threshold. Without a reference it only records one (`updateReferencePriceAfterNoTrigger` describes how it follows the price).
  - References are valid within one display currency; `CoinListViewModel` clears them when the currency changes.

## Coin Catalog Client

- `CoinCatalog` loads `coins.json` and is the only source of coin metadata. Search and recommendations use `listed` coins; the watchlist resolves any id. Only `active` coins are priced; `delisted` coins show "No market data"; `migrated` ids are replaced by their successor (`CoinCatalog.settingsWithSuccessors`).
- `CoinCatalog.validate` mirrors the Python validator ([Data Sources](DATA_SOURCES.md#coin-catalog)); change both together.
- Logos resolve in this order: bundled `coin-<id>` asset → App Group cache (`CoinLogoCache`, `CoinLogos/<id>.img`) → remote URL → symbol placeholder. The widget and the desktop ticker can't load remote images while rendering and skip that step.
- `CoinLogoStore` (app only) downloads the logo of each watchlist coin without a bundled asset, at launch and whenever the watchlist changes, and deletes logos of removed coins. Downloads go through the injected `HTTPClient` (the shared session, with a 15 s timeout): HTTPS on the allowlisted hosts, HTTP 200, at most 512 KB, must decode as an image. Without an App Group (unsigned builds) nothing is cached.

## Menu Bar

- `MenuBarViewModel` renders the status item. A colored price or one with a background is a single non-template image (`MenuBarTitleImage`: button height, 13pt padding, 4pt corners), which macOS fades evenly on an inactive display; an attributed title over a layer background renders blurred there. The default style stays a plain title tinted by the system.
- The logo's presence is checked by identity (`button.image !== menuBarLogo`): after `image = nil`, `NSStatusBarButton` may report a 1×1 placeholder image.
- The right-click menu is built on every open (so it follows the language) and hides item images: `NSMenuEnableActionImages` is set to false in `CoinscalApp.init`, before AppKit reads it, and on macOS 27 every item also sets `preferredImageVisibility = .hidden`.

### Panel

`MenuBarPanelController` shows `CoinPopoverView` in an app-managed `NSPanel` rather than an `NSPopover`. On macOS 27, pressing the status item takes key status from a popover and reaches global mouse monitors on mouse-down; a transient popover closes there, and the status item action on mouse-up reopened it.

- `MenuBarPanel` is borderless and non-activating, can become key, sits at `.popUpMenu` level, doesn't hide on deactivation, and shows and hides without animation.
- `toggle()` decides from the panel's own visibility. Dismissal monitors exist only while it is shown: a global mouse-down monitor (other apps), a local one (other Coinscal windows), Esc (`cancelOperation`), and resigning key. Presses inside the status item window are ignored by all of them; that click's toggle closes the panel.
- The content is a `MenuBarPanelHostingView` whose `acceptsFirstMouse` is true, because the app is often not active while the panel is shown (macOS 14+ may refuse `NSApp.activate`, and widget clicks never activate it). It sits in an `NSVisualEffectView` with the `.popover` material, masked to 16pt corners; a SwiftUI material in a transparent window is too thin.
- `MenuBarPanelLayout.frame` centers the panel 6pt below the status item, at least 8pt from the left and right edges of the visible frame and never above it.

## Settings Window

- The default size is applied with `setContentSize` after `contentViewController` is set (the hosting controller resizes the window to its fitting size) and before `setFrameAutosaveName` restores a saved frame. `windowWillResize` clamps the size, since the hosting controller overrides `maxSize`.
- `sceneBridgingOptions = [.title, .toolbars]` turns the pane's `navigationTitle` into the window title. The window starts with an empty `.unified` `NSToolbar`. Toolbar items live at the `SettingsWindow` level and exist on every pane, hidden where unused (the Watchlist "+" is transparent, disabled, and hidden from accessibility elsewhere): a pane without toolbar items makes SwiftUI remove the whole toolbar, and the title bar and sidebar shift.
- Panes set no background color, so the window material shows through.
- In watchlist rows, the threshold field is an AppKit `NSTextField` wrapper (`FullHitTextField`, `AlertFieldProxy`) that ignores hit testing until edited, because the underlying `NSTableView` intercepts clicks on in-row controls and `FocusState` is unreliable there.
- Drag reordering is gesture-driven (`WatchlistReorderSupport.swift`): the insertion slot is the floating row's center divided by the fixed 44pt row height, and the order is committed once after the drop animation. Per-row drop targets jitter while rows move aside.

## Desktop Ticker

- `DesktopOverlayController` uses a borderless, transparent, shadowless window that ignores mouse events, joins all Spaces, is stationary, and is ignored by window cycling. It can become key only while being positioned.
- Level: one above the desktop wallpaper level (`CGWindowLevelForKey(.desktopWindow) + 1`), below the desktop icons; `.floating` while being positioned.
- Content: `DesktopOverlayLayout.content` builds `WidgetEntryContent` from `CoinListViewModel` and reuses the shared widget list view on an `NSVisualEffectView` (`.behindWindow`, always active).
- Size: `DesktopOverlayLayout.windowSize` uses the list's row height (`WidgetListView.rowHeight`); a test checks it against the rendered view. Width 364pt, or 400pt with large text; large text sets the `widgetTextBoost` environment value to 2, which the shared views add to font sizes, row height, and the change column.
- Position: `desktopOverlayTopLeft` stores the top-left corner in global coordinates (nil means the main display's top right). `DesktopOverlayLayout.frame` places it on the display it overlaps most, or the nearest one, clamped to that display's visible frame, without rewriting the saved value; it is recomputed on screen changes and wake. Older settings stored the bottom-left corner and are converted on decode.
- Below 20% opacity (`DesktopOverlayLayout.textNeedsHalo`) the content uses a dark appearance and the `widgetTextHalo` environment value, which adds two soft dark shadows to text. While being positioned the background is at least 60% opaque, because fully transparent pixels of a borderless window receive no clicks.
- Turning the ticker on enters positioning only when the setting changes from off to on (`startsAdjusting`), not at launch.

## Widgets

- `CoinscalWidget` is embedded in `Coinscal.app/Contents/PlugIns`. It has no framework: `project.yml` lists every app source file it compiles (shared code, models, catalog, price and exchange rate services, formatting, localization) plus the asset catalog, strings, and `coins.json`. Add new dependencies of the extension to that list.
- The app and the extension share an App Group (`$(TeamIdentifierPrefix)$(COINSCAL_APP_ID)`, read at runtime from `CoinscalAppGroup` in Info.plist). It needs a signing Team; without one, snapshot and shared-rate I/O are no-ops and the widget fetches its own prices.
- **App side** (`WidgetSnapshotWriter`, independent of the menu bar and the ticker): on every price or settings change (debounced 1 s) it builds `widget-snapshot.json`. It always saves the first snapshot after launch; after that, it saves while a widget is placed, or when a setting the widgets show changes (`plan(previous:next:widgetsInstalled:)`). It asks WidgetKit to reload only for such a setting change while a widget is placed; periodic and price-driven reloads would exhaust each widget's daily reload budget. Placed widgets are queried with `WidgetCenter.getCurrentConfigurations` at most every 5 minutes (an error counts as placed); when a widget appears, the latest snapshot is saved.
- **Extension side** (`WidgetDataLoader`): uses the snapshot when it is younger than 15 minutes, in the right currency, and covers the coins; otherwise fetches with its own `PriceService` (failover state lives as long as the process), cut off after 15 s, falling back to the old snapshot shown as stale. Each timeline has one entry and asks for the next reload 15 minutes later.
- The gallery preview (`context.isPreview`) uses the user's coins with real prices (fresh snapshot, or one request cut off after 5 s) and falls back to sample data; the placeholder always uses sample data.
- Configuration uses `AppIntentConfiguration`; coin options come from the bundled catalog's listed coins. Strings follow the app language stored in the snapshot (`LocalizationManager.string(for:language:)`); the system renders the edit panel and gallery chrome in the system language.
- Clicking a widget opens `<scheme>://popover` (`coinscal`, or `coinscal-debug` for debug builds, read from `CoinscalURLScheme`). On a cold launch the URL arrives before the panel exists; it opens after setup, retrying for up to 2 s until the status item is on screen.

## Updates

- `UpdateController` holds the update state shown in the UI and talks to an `UpdaterBackend`: `SparkleUpdaterBackend` wraps `SPUStandardUpdaterController`; tests use `FakeUpdaterBackend`, and the unit-test host attaches none.
- The feed follows the in-app language: the updater delegate (`feedURLString(for:)`) turns `SUFeedURL` into `appcast.<code>.xml` (`UpdateFeed`, read before every check), a feed whose only release notes link is in that language. Sparkle would otherwise choose among localized links by the system language. `appcast.xml` keeps all three for older builds.
- Info.plist: `SUFeedURL` `https://dl.coinscal.app/appcast.xml`, `SUPublicEDKey`, `SUEnableAutomaticChecks`, `SUScheduledCheckInterval` 86400, `SUEnableInstallerLauncherService`. Automatic installation is off and no system profile is sent.
- Sparkle verifies each archive's EdDSA signature and requires the same Team ID. The sandbox allows Sparkle's installer through the mach-lookup exceptions `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` / `-spki`; the downloader service stays off because the app has `network.client`.
- Gentle reminders: a scheduled check shows Sparkle's window only when Coinscal is frontmost; otherwise `updateAvailable` drives the panel header until Sparkle reports that the user saw it or the session ended.
- Publishing and signing: [Releasing](RELEASING.md).

## Localization

- `Localizable.xcstrings` uses semantic keys (`extractionState: manual`, `SWIFT_EMIT_LOC_STRINGS = NO`). `LocalizationManager` loads the `<lang>.lproj` bundle of the selected language, and `loc(_:)` is the only way to read a string, which makes language changes instant. Rules and terminology: [Localization](LOCALIZATION.md).

## Platform Notes

- `LSUIElement`: no Dock icon. The app activates itself before showing the panel or Settings, but must work when macOS refuses.
- The sandbox grants only `network.client` (plus the App Group and Sparkle's mach-lookup exceptions). Every source uses HTTPS; there are no ATS exceptions.
- Price and exchange rate requests use `URLSession.liveData` (no URL cache) with `reloadIgnoringLocalCacheData`.
- Launch at login uses `SMAppService.mainApp`.
- Logging uses `Logger` with subsystem `com.gicek.coinscal` and categories `Settings`, `Notifications`, `LaunchAtLogin`, `CoinCatalog`, `CoinLogos`, and `Widget`. Only error descriptions are logged, never settings or the watchlist.

## Build Configurations

| | Release | Debug |
|---|---|---|
| App name | Coinscal | Coinscal Debug |
| Bundle ID | `com.gicek.coinscal` | `com.gicek.coinscal.debug` |
| Widget | `com.gicek.coinscal.widget` | `com.gicek.coinscal.debug.widget` |
| App Group | `<Team>.com.gicek.coinscal` | `<Team>.com.gicek.coinscal.debug` |
| URL scheme | `coinscal` | `coinscal-debug` |

The values come from `COINSCAL_APP_ID`, `COINSCAL_DISPLAY_NAME`, and `COINSCAL_URL_SCHEME`, set per configuration in `project.yml`. The tests use `com.gicek.coinscal.tests` with the debug app as host.

## Testing

- Unit tests never touch the real `UserDefaults`, notification center, login items, updater, or network. They inject `InMemorySettingsStore`, `SpyNotifier`, `StubHTTPClient`, `FakePriceService`, and `FakeUpdaterBackend`, and wait for main-thread delivery with `drainMainQueue()` instead of sleeping.

| Area | Tests |
|---|---|
| Alerts, formatting, settings coding | `AlertEvaluatorTests`, `PriceFormatterTests`, `AppSettingsCodingTests` |
| Price and exchange rate services | `PriceServiceTests`, `TickerProviderTests`: parsing, failover, the Binance batch fallback, halted pairs, fill-in, unavailable and rate-limit memory, rate caching and fallback |
| Polling and alerts state | `CoinListViewModelTests`: no interrupted rounds, stale results discarded, no false alerts on currency change, crossings only |
| Catalog, logos, watchlist | `CoinCatalogTests`, `CoinLogoStoreTests`, `WatchlistViewModelTests` |
| Menu bar and panel | `MenuBarViewModelTests`, `MenuBarPanelLayoutTests` |
| Widgets | `WidgetTests`: coin choice, freshness, sorting, staleness, snapshot I/O, when to save and reload, string keys |
| Desktop ticker | `DesktopOverlayTests`: settings, size, position, displays, level |
| Updates | `UpdateControllerTests` |

- `make mac-check-sources` checks every source against the real network (manual, not part of `make test`).
- The website has its own offline checks in `Site/test/` ([Website](WEBSITE.md)).
- Behavior that needs a real Mac is tracked in [Validation](VALIDATION.md).
