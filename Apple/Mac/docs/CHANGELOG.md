# Coinscal Mac Changelog

Features added, changed, fixed, and removed, newest first. Third-level headings start with Added / Changed / Fixed / Removed; fixes describe the symptom, root cause, fix, and tests.

## 2026-10-16

### Changed: Recommended coins
Settings → Watchlist → "Recommended" lists BTC, ETH, BNB, SOL, ZEC, HYPE, BCH, LTC, UNI, AAVE (was BTC, ETH, BNB, SOL, XRP, ADA, DOGE, AVAX, DOT, POL), in `recommendedCoins.json` and the `Constants.Defaults.recommendedCoinSymbols` fallback. All ten are listed and active in the catalog and trade on Binance and OKX. HYPE's logo is now bundled (`coin-hyperliquid`, 50 px from CoinGecko's image CDN; 79 bundled logos), so the recommendations show no placeholder offline. The default watchlist (BTC, ETH) is unchanged.

- Tests: `make test` passes.

### Added: Text size for the desktop panel
Settings → General → "Desktop" has "Text Size" (Normal / Large, Normal by default). Large adds 2pt to every text in the panel (names, prices, changes, the title, and the time) and leaves the coin icons and the logo at their size. To fit, rows grow from 38pt to 42pt, the change column from 74pt to 87pt, and the panel from 364pt to 400pt wide.

- New strings: `desktop.textSize`, `desktop.textSize.normal`, `desktop.textSize.large`.
- Tests: settings default and tolerant decoding, the Large size, and the rendered-height check at both text sizes. On a real Mac with 7 coins, Large measured 400×351 with nothing truncated.

### Changed: One desktop panel layout that fits the watchlist
The desktop panel no longer has a "Size" setting (Small / Medium / Large, Medium by default). It always uses the large widget's list, shows the first 16 watchlist coins instead of 4 or 8, and its height fits the coins it shows (88pt for one coin, 673pt for 16; 170pt before the first prices). Adding or removing coins grows or shrinks the panel downward from its top edge.

- Settings: the saved position is now the top-left corner (`desktopOverlayTopLeft`). A bottom-left position saved by an earlier version is converted once with the size it was saved with, so the top edge stays put; `desktopOverlaySize` is no longer stored.
- Removed strings: `desktop.size`, `desktop.size.small`, `desktop.size.medium`, `desktop.size.large`.
- Tests: `DesktopOverlayTests` covers the height for 0, 1, 8, and 20 coins, the 16-coin limit, the migration of old positions, and top-edge anchoring; one test renders `WidgetListView` and checks that the computed height matches it for 1, 5, and 16 coins. On a real Mac, a large panel saved by the old version reopened 364×361 with 8 coins and its top edge in place.

### Changed: No ellipsis on buttons and menu items
"Settings", "Check for Updates" (right-click menu and the About pane), and "Adjust Position" (Settings → General) no longer end with "…", in all three languages. The search field placeholder keeps its ellipsis.

### Fixed: Gear icon in front of "Settings" on first launch
- Symptom: on the first launch after a fresh install, the right-click menu showed a gear icon in front of "Settings" on macOS 26; later launches showed none.
- Root cause: `NSMenuEnableActionImages = false` was written in `applicationDidFinishLaunching`, after AppKit had already read it. Only the next launch picked up the saved value.
- Fix: `CoinscalApp.init` writes it before any menu exists.
- Tests: on a real Mac with the key deleted, the old build showed the gear on the first launch and the new build showed no icon on any item.

### Fixed: Green changes hard to read on the transparent desktop panel
- Symptom: with the desktop panel's background below 20%, the green 24h changes looked dark and blurry over light wallpapers, while white text stayed sharp.
- Root cause: legibility depends on luminance contrast, and the default green #2CBD84 is about 1.3:1 against a light blue-gray wallpaper (red #F6465D about 1.9:1). The dark shadow makes white text readable because white is far brighter than the shadow; green is about as bright as the shadow, so the shadow only blurs it. Lifting the color 30% toward white with a same-hue shadow made it worse (about 1.0:1).
- Fix: over the wallpaper, changes and the stale time are white with the same shadow as the prices; only the leading ▲ / ▼ or ⚠︎ keeps its color (`SignalText` in `WidgetViews.swift`). Widgets and opaque panels are unchanged.
- Tests: `make test-mac` passes; checked on a real desktop over a light wallpaper (dark wallpaper pending in VALIDATION).

### Added: In-app updates
Coinscal checks `https://dl.coinscal.app/appcast.xml` once a day with Sparkle 2.10.0 (design in docs/UPDATES.md) and installs a new version only after the user agrees. A scheduled check that finds an update doesn't open a window unless Coinscal is in front; the popover title bar shows an "Update Available" capsule instead. "Check for Updates…" is in the right-click menu and the About pane, which also has "Automatically Check for Updates" (on by default) and now lists Sparkle under open source components. Archives must carry a valid EdDSA signature (public key in `Info.plist`) and the same Team ID.

- Sandbox: Sparkle's installer XPC service with the `-spks` / `-spki` mach-lookup exceptions; the Downloader service stays off.
- `release.sh` signs Sparkle's XPC services and helpers with the Developer ID before notarization, and its checks cover them. New commands: `make mac-update-keys` (signing key), `make mac-publish` (appcast, R2 upload, GitHub Release), `make sparkle-tools`.
- The release zip grows from about 1.3 MB to 2.3 MB.
- Tests: 5 in `UpdateControllerTests` with `FakeUpdaterBackend`; a Developer ID-signed `make mac-release` build passes the extended signing checks.

### Changed: No scroll bars in the popover list and the watchlist settings list
The menu bar popover's coin list and the added-coins list in Settings → Watchlist no longer show a vertical scroll bar (`.scrollIndicators(.never)`, which also holds with "Show scroll bars: Always"). Both still scroll with a trackpad or mouse wheel, and drag reordering still auto-scrolls. Checked on a real Mac via Accessibility: the watchlist list's scroll area no longer has a scroll bar.

### Fixed: Settings window ignored its default size on first open
- Symptom: with no saved window frame, the Settings window opened at 600×472 instead of the default 786×500. On this Mac the change had looked fine only because an 800×500 frame saved before the default changed was always restored.
- Root cause: assigning `contentViewController` resizes the window to the SwiftUI view's fitting size (its 600pt minimum width), which discards the `contentRect` the window was created with.
- Fix: `openSettingsWindow` applies the default size with `setContentSize` after attaching the hosting controller and before `setFrameAutosaveName`, so a saved frame still wins.
- Tests: on a real Mac, a first open (saved frame masked via the argument domain) measured 786×500 twice in a row, and a saved 800×500 frame was still restored.

## 2026-10-15

### Changed: Searchable coins expanded to the top 1000 by market cap; logos downloaded on demand
The catalog now takes the CoinGecko top 1000 by market cap (was 250) and lists every coin that trades as a USDT spot pair on Binance, OKX, or Bybit (was the first 100): 451 searchable coins, down to rank 957, with a 119KB `coins.json`. The bundled snapshot was rebuilt from scratch (no released version has stored watchlists yet), so it no longer carries delisted or migrated entries, and the 18 bundled logos of coins that left it were removed (78 remain, about 640KB). The generator now keeps a migration target only when an old id pointing to it is kept. Listed-count validation is now 200–1000 in both `generate_catalog.py` and `CoinCatalog`. No new logos are bundled; when a coin without one enters the watchlist, `CoinLogoStore` downloads its logo once into the App Group container (`CoinLogoCache`), so the app, the widget, and the desktop ticker show it offline too, and deletes it when the coin is removed. Downloads go through `HTTPClient`, allowlisted HTTPS hosts only, at most 512KB, and must decode as an image. Tests: `CoinLogoStoreTests` (6).

### Added: Developer ID code signing and notarization
Release is split into two commands: `make mac-release` signs with a Developer ID Application certificate (manual signing, no embedded provisioning profile, secure timestamp) and produces a zip and a DMG without notarization; `make mac-release-notarized` builds on that by first notarizing the app and stapling the ticket (so the app inside the zip passes offline too), then packaging the zip and DMG, signing and notarizing the DMG, stapling it, and finally verifying with `spctl`. Hardened Runtime is enabled for all configurations in `project.yml`. Before packaging, `scripts/release/release.sh` checks the code signing identity, Team, Hardened Runtime, timestamp, and `get-task-allow` of both the app and the widget; missing notarization credentials (`NOTARY_PROFILE` or an App Store Connect API key) fail before the build, and a rejected submission prints the notarization log. The former `make mac-dmg` is folded into these two commands. Verified: the signed Release app and widget run normally; both the app and the DMG pass notarization and are stapled, `spctl` reports Notarized Developer ID, and Gatekeeper allows them after a simulated download quarantine.

### Changed: Adding watchlist coins moved to a "+" panel in the title bar
Previously the top of the content area held an "Add Coin" heading and a search field; while typing, the recommendations row was replaced by search results, taking up a lot of space above the list. Now a "+" button sits at the far right of the title bar and opens an add panel below it (`WatchlistAddCoinPanel`). The panel is an in-window card rather than an NSPopover: a popover centers on its arrow and only shifts at screen edges, so with "+" at the far right of the window half of it would hang outside the window. The panel's search field is focused on open; with no input it lists all listed coins, with a checkmark on those already added. Clicking a coin adds it and keeps the panel open for adding more; Return adds the first result not yet added; closing clears the search. The content area now holds only the recommendations row and the added list. New strings "No matching coins" and "Clear Search" (all three languages). The "+" lives at the `SettingsWindow` level and is present in all three panes (hidden in "General" and "About"): when attached to the watchlist pane's own `.toolbar`, switching to the other two panes made SwiftUI remove the whole window toolbar, so the title bar fell back to a narrow centered title and the sidebar shifted down. Esc is handled by a local key monitor (the search field's field editor swallows Esc, so `onExitCommand` never receives it) and is passed through during input method composition. Checked on a real Mac: title bar, title, and sidebar positions match across all three panes, with no leftover button base at the top right of "General" and "About"; the button sits at the far right of the title bar, the panel appears below it with its right edge 8pt from the window, and clicking outside or pressing Esc closes it. Tests: `WatchlistViewModelTests` adds coverage for the add panel list (all listed coins with no input, instant filtering while typing). The old search results debounce pipeline and `searchResults` were removed along with the old search area.

### Added: DMG installer
`make mac-dmg` produces `Build/macOS/Dist/Coinscal-<version>.dmg`. It opens a 660×420 window with the app at the lower left and Applications at the upper right. The background is a Bitcoin 2019–2025 monthly chart (approximate data, hardcoded in the script): a logarithmic price axis on the right with ticks at 3,000 / 20,000 / 60,000 / 120,000 / 300,000 / 500,000 / 800,000 / 1,000,000, horizontal grid lines on the ticks and vertical lines per year, and the last close marked with a brand-color price tag; the areas around the icons, file names, and illustration fade out. The drag illustration in the middle is a rising candlestick run (gradient rounded bodies, including one pullback), with a smooth trend line sweeping over the wicks and ending in an arrow pointing at Applications, over a fading area fill; its scale and texture set it apart from the fine monthly chart in the background. The background is rendered with Core Graphics by `scripts/dmg/render-background.swift` (1x / 2x), and the Finder layout is written with AppleScript. The mounted volume icon is the system removable disk icon with the center arrow erased and the logo mark laid over it (`scripts/dmg/render-volume-icon.swift`). With "show hidden files" on, hidden items are moved outside the window, and `.fseventsd` is deleted before compression; Finder may still occasionally scroll sideways and reveal `.background` and `.VolumeIcon.icns`, which is accepted. The layout script does not call Finder's `update`: on macOS 26 it deletes `.VolumeIcon.icns` and clears the volume's custom icon flag. Checked on a real Mac by opening the DMG and comparing screenshots of icon placement and background alignment; `hdiutil verify` and the code signing check of the bundled app pass.

### Added: Desktop ticker
Settings → General adds "Desktop" (off by default): a click-through price panel pinned to the desktop, between the wallpaper and the desktop icons, shown on every Space, excluded from Mission Control and window switching, with a frosted background that lets the wallpaper show through. Content and style reuse the widget views (small shows the menu bar coin; medium / large show the first 4 / 8 watchlist coins), updated with the app every 10 seconds, without WidgetKit refresh budget limits. Turning on "Show on Desktop" goes straight into position adjustment (the panel floats to the top and can be dragged; switching sizes during adjustment does not exit it); switching Small / Medium / Large always anchors on the panel's top-left corner, and clicking "Done" saves the position and restores click-through; "Adjust Position…" in Settings re-enters adjustment at any time. The panel can be dragged to any display and its position is saved in global coordinates; when a display is unplugged the panel moves to the nearest display and returns when it is reconnected. Background opacity is adjustable (0–100%); below 20% the text switches to Finder-style white file name text with a light shadow (icons and background excluded), readable on both light and dark wallpapers. The first time it is turned on it defaults to Medium. Verified on a real Mac: window level, default position, click-through, position adjustment, and persistence across relaunch (docs/DESKTOP_OVERLAY.md). Tests: 14 in `DesktopOverlayTests`.

### Added: Desktop and Notification Center widgets
New Widget Extension `CoinscalWidget` (design in docs/WIDGET.md): "Coin Price" small (follows the menu bar coin by default) and "Watchlist" medium / large (4 / 8 rows). "Edit Widget" offers the coin, the coin source (watchlist / manual), sort order (watchlist order / 24h change high to low / low to high), quote currency (follows the app by default), and coloring by price change. On each update the app writes an App Group snapshot and requests a throttled reload (every 5 minutes, or on a price move > 1%, or when a visible setting changes); when the snapshot is stale the widget fetches prices itself, and offline it uses the old snapshot marked as stale. Price changes are shown with color, an arrow, and a sign together, so they stay distinguishable in monochrome mode. Clicking a widget opens the menu bar popover (`coinscal://popover`; on a cold launch it opens after setup). Because the app is not activated in this case, a `.transient` popover would not close on a desktop click, so while the popover is shown a global mouse monitor closes it on clicks outside the app. The color hex extension moved to `Utilities/Color+Hex.swift` so it can be shared. Tests: 13 in `WidgetTests`.

### Changed: Old coins are replaced by their successors automatically; migration notice removed
When a project moves to a new coin (for example MATIC → POL), the old coin in the watchlist is replaced with the new one at launch or when the catalog updates, and the UI shows the new coin's name and price directly. The "Migrated to X" note, the "Replace" button, and their three strings are removed. Replacement follows the previous rules (Change / Off alerts are kept, Above / Below are reset to the default, if the new coin is already in the watchlist only the old one is removed, and the menu bar coin follows along). The logic moved to `CoinCatalog.settingsWithSuccessors` and runs in `CoinListViewModel` before the list is built. Tests: 4 for the replacement rules (rewritten from the old replace tests), 1 for list building.

### Changed: Settings window uses a unified title bar whose title follows the pane
Previously the title bar was transparent, the title hidden, and there was no toolbar: the three panes started at different heights, and the "General" form showed through the title area when scrolled up. Now the detail area's title is bridged to the window title via `sceneBridgingOptions` and shows the current pane (General / Watchlist / About); the window has an empty toolbar with `.unified`, so the title bar height is the same in all three panes (66pt on macOS 26) and content scrolls under the title bar. Language switching no longer sets the window title by hand (SwiftUI refreshes it). The 24pt padding of the "About" pane moved inside the scroll view: it used to be outside, so the scroll area started 24pt below the title bar and content scrolled up was clipped there, leaving a blank strip. Measured on a real Mac with Accessibility: title bar height and title position match across all three panes.

### Changed: Settings window default width 786
The Settings window first opens at 786×500 (previously the maximum size, 800×500); the resizable range is unchanged, and the autosaved window size is used afterward.

### Fixed: Menu bar goes blank after switching to "Icon"
- Symptom: while showing the price, switching to "Icon" removed the price but the logo did not appear, leaving only an empty slot in the menu bar. Whether it reproduced depended on how many times the price had refreshed before the switch, so it often happened on the first switch after each launch.
- Root cause: the logo was set only when `button.image == nil`. After setting `image = nil` in price mode, `NSStatusBarButton` returned a 1×1 placeholder image instead of nil every other time, so when switching to the icon the guard wrongly concluded "already has an image" and skipped it, while the title was cleared and the width shrank to 28pt.
- Fix: the logo is loaded once; when showing the logo, the check is by object identity (`MenuBarViewModel.applyLogo`) and the logo is set if it is not in place; the price path no longer sets the logo as a side effect.
- Tests: 2 new in `MenuBarViewModelTests` (button holding a placeholder image / no image both switch to the logo); on a real Mac with Accessibility, 8 consecutive price ↔ icon switches, and all 25 snapshots in icon state showed the 18pt logo.

### Added: Menu bar can show only the app icon
Settings → General adds "Show: Price / Icon" (segmented control, Price by default). With "Icon", the menu bar shows only the monochrome logo, and Coin, Color by Price Change, Color Scheme, and background color are disabled. The former "Display" section is renamed "Menu Bar", and the redundant "Menu Bar" prefix is dropped inside it ("Menu Bar Coin" → "Coin"); the quote currency applies to both the popover and alerts, so it moved to a new "Prices" section. The new field `menuBarContent` falls back to Price when missing or unrecognized. The display decision is extracted as `MenuBarViewModel.priceCoin`. Tests: 1 for settings encoding/decoding, 4 for the display decision.

### Changed: App icon, About pane logo, and menu bar icon redrawn from the new vector mark
The master mark was re-vectorized (`design/coinscal-logo-*.svg`): the rings are exact concentric circles, the ₿ is rebuilt geometrically, and the bull's head is strictly symmetric with smooth edges.

- App icon: follows Apple's older template with an 824 px white plate, 185 px corner radius, and a slight bottom shadow (the old plate was 924 px, a size larger than other system icons); the mark keeps the same proportion of the plate height; all sizes exported with `sips`.
- About pane `app-logo`: now 80 / 160 / 240 px, matching the 80pt display size (the old @2x was only 128 px and was upscaled).
- Menu bar icon (`design/coinscal-menubar.svg`): 1x / 2x completed. At 16pt the old image had gaps under 0.5px between parts and blurred into a blob; the small-size version thickens the ring, shrinks the ₿ slightly, widens the gaps between parts to ≥1px (@2x), and fills in the tips of the thin wedge gaps. The mark is 17pt tall on an 18pt canvas; code unchanged.

### Changed: About pane contact info is now email and X
The "About" pane contact info changed from a single X link to two rows, email and X (`AboutContactLinks`), with addresses centralized in `Constants.Contact`; the X icon is the template vector image `brand-x`, with the trademark notice in THIRD_PARTY_NOTICES.

### Added: Coinscal 1.0
The first release of the macOS menu bar crypto price app.

- The menu bar shows the current price of the selected coin, optionally colored by 24h change and with a background color; left-click opens a popover with the watchlist, and the right-click menu switches the menu bar coin.
- Watchlist management: search the catalog of about 100 tradable coins or add from recommendations, and drag to reorder; migrated coins (for example MATIC → POL) can be replaced in one click, and delisted coins are marked "No market data".
- Price alerts: above / below a price (alerts once when the threshold is crossed) or a change of N% from a reference price, delivered as system notifications; switching the quote currency does not cause false alerts.
- Prices come from Binance, a Binance mirror, OKX, and Bybit with failover in order, and coins missing from the primary source are filled in from other exchanges; exchange rates come from three public sources and are cached.
- 12 quote currencies; three color schemes; English, Simplified Chinese, and Traditional Chinese, with instant in-app switching; Open at Login (off by default).
- Tests: 56 unit tests; live data source check with `make mac-check-sources`.
