# Desktop and Notification Center Widgets

> Status: approved and implemented on 2026-10-15, with data Option B (the widget fetches prices itself when the app isn't running). For implementation constraints, see "Widget Snapshot and Reload" in [TECHNICAL](TECHNICAL.md); for appearance pending verification on a real Mac, see [VALIDATION](VALIDATION.md). The UI mockup is a local temporary file, `/tmp/coinscal-widget/widget-mockup.html` (not committed; generated during review).

## Goal

See watchlist prices on the desktop or in Notification Center without opening the menu bar. View only: no trading and no trend lines (the PROJECT first milestone excludes candlestick and historical charts). The only data is the current price and 24h change.

## Widget Kinds

One Widget Extension provides two widgets. Both can be placed on the desktop (macOS 14+) and in Notification Center.

| Widget | Sizes | Content |
|---|---|---|
| **Coin Price** | Small | One coin: logo, symbol, name, large current price, 24h change (arrow + percentage), update time at the bottom |
| **Watchlist** | Medium, large | List: 4 rows in medium, 8 rows in large. Each row lays out logo, symbol and name, current price, and 24h change (fixed width, right-aligned) on one line; title and update time at the top |

No medium single-coin widget (only two data points, not enough to fill it) and no extra-large size.

### Visual Rules

- The background uses the system `containerBackground` (light / dark automatically); no brand color blocks.
- Prices use monospaced digits, formatted the same as the menu bar (`PriceFormatter`, with the quote currency symbol).
- Change: colored by the color scheme, and **also** shown with ▲ / ▼ and a plus or minus sign. On macOS 14, desktop widgets turn monochrome (vibrant) when an app window is in front, so color alone would lose information.
- Coin logos are desaturated by the system in monochrome mode (`widgetAccentedRenderingMode(.desaturated)`, macOS 15+).
- States:
  - No data (just added, app never run): logo placeholder + "Open Coinscal to get prices".
  - Stale data (older than 30 minutes): prices show as usual; the update time switches to the secondary color with ⚠︎.
  - Delisted coin: the change position shows "No market data", matching the popover.
- Clicking: the whole widget opens the menu bar popover (`coinscal://popover`). Clicking any row in the large list also opens the popover (no single-coin detail page).

## Edit Widget (Configurable Options)

Each existing app setting was reviewed, with these conclusions.

| App setting | In widget configuration? | Handling |
|---|---|---|
| Menu bar coin | ✅ As the default for "Coin Price" | Option "Follow Menu Bar Coin" (default) or a specific coin |
| Watchlist and order | ✅ | "Watchlist" takes the first N in watchlist order by default |
| Quote currency | ✅ | "Follow App" (default) or one of 12 currencies |
| Color by price change + color scheme | ✅ Toggle only | "Color by Price Change" on (default, using the app's color scheme) / off; custom colors are not set again in the widget |
| Interface language | ❌ | Follows the app's language setting |
| Menu bar background color, show price / icon | ❌ | Applies only to the menu bar |
| Price alerts | ❌ | Alerts use system notifications; the widget doesn't duplicate them |

Final configuration options:

**Coin Price (small)**
1. Coin: Follow Menu Bar Coin (default) / pick one from the listed coins in the catalog (searchable).
2. Display Currency: Follow App (default) / USD, CNY…
3. Color by Price Change: on (default) / off.

**Watchlist (medium, large)**
1. Source: Watchlist (default) / Choose Manually.
2. Coins: appears when the source is "Choose Manually"; up to 4 for medium and 8 for large.
3. Sort By: Watchlist Order (default) / 24h Change, High to Low / 24h Change, Low to High.
4. Display Currency, Color by Price Change: same as above.

## Data and Reload

WidgetKit can't refresh every 10 seconds like the menu bar: the system gives each widget a reload budget (on the order of dozens per day), so it shows "near real-time" data. That's why every widget shows its update time.

- On every polling round, the app writes a snapshot to the App Group shared container: coins, prices, 24h change, status, quote currency, color settings, language, and write time. The settings themselves stay in the original `UserDefaults` domain and are not migrated.
- The app requests a widget reload (`WidgetCenter.reloadAllTimelines()`) at most once every 5 minutes, or earlier when a price moved more than 1% since the last push. The system may coalesce further.
- Widget timeline: reads the snapshot to produce one entry; the next reload is scheduled 15 minutes later.
- When the app isn't running (snapshot not updated for more than 15 minutes), the widget fetches prices over the network itself (chosen on 2026-10-15): the price service, coin catalog, and exchange rate code are compiled into the extension, and the extension requests `network.client`. Fetched results are used only for that timeline and are not written back to the snapshot. If fetching fails, it uses the old snapshot and shows the stale state.

## Project Setup

- New target `CoinscalWidget` (Widget Extension, source in `Apple/MacWidget/`), generated by `project.yml` and embedded in `Coinscal.app`; Bundle ID `com.gicek.coinscal.widget`.
- Shared code doesn't use a framework: source files such as `PriceFormatter`, the snapshot model, and coin metadata are compiled into both targets (`project.yml` lists them by file).
- Coin logos (about 800KB) go into an asset catalog shared by both targets.
- App Group: `$(TeamIdentifierPrefix)com.gicek.coinscal` (on macOS, prefixed with the Team ID; no provisioning profile needed). Both targets' entitlements include this group; the extension also needs the sandbox and `network.client`.
- Configuration uses `AppIntentConfiguration` (macOS 14+). Coin options are an `AppEntity`, with the option list taken from the catalog in the snapshot.
- Strings go into `Localizable.xcstrings` (semantic keys `widget.*`), with all three languages added at once. The localization guard is extended to scan `Apple/MacWidget`.
- Tests: snapshot encoding/decoding and fault tolerance, sorting / taking the first N, staleness checks, configuration defaults (Swift Testing, without touching the real App Group).

## Risks and Prerequisites

1. **Code signing (prerequisite)**: the App Group requires real Team signing. This Mac already has a development certificate, but `local.mk` doesn't set `DEVELOPMENT_TEAM`; without it the project only compiles and the widget can't read data. CI doesn't sign and only verifies compilation.
2. **Reload frequency**: the system budget determines the actual reload interval, so minute-level updates can't be guaranteed. The UI communicates this through the update time.
3. **Monochrome mode**: on macOS 14, desktop widgets lose color when out of focus, so change must include an arrow and a plus or minus sign (already required in the visual rules).
4. **Language**: widgets are rendered by a system process and can only read the language setting from the snapshot. After switching language in the app, the change takes effect at the next reload.

## Acceptance Checklist

- Both widgets can be added on the desktop and in Notification Center; all three sizes lay out correctly; change is distinguishable in light, dark, and monochrome modes.
- Configuration defaults are correct; with "Follow Menu Bar Coin", changing the coin in the app is reflected at the next reload.
- While the app runs, the update time is no older than about 15 minutes; after quitting the app, the widget fetches prices itself and shows the stale state when offline.
- Strings are complete in all three languages, and the localization guard passes.
- Clicking a widget opens the menu bar popover.

## Development Steps (After Approval)

1. Configure code signing and the App Group, and get an empty extension to appear in the widget gallery (verify the signing prerequisite first).
2. Snapshot writing and reload throttling (app side) + unit tests.
3. "Coin Price" small UI and configuration.
4. "Watchlist" medium / large UI and configuration.
5. Documentation sync (PROJECT, DESIGN, TECHNICAL, ROADMAP, VALIDATION, CHANGELOG).
