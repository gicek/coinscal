# Product

Coinscal lets you check crypto prices at a glance without opening an exchange app or website. It lives in the macOS menu bar, shows the current price and price change of your watchlist, and notifies you when a price reaches your target. It doesn't trade, track holdings, or analyze markets.

## Principles

- **Works without setup**: the first launch shows BTC and ETH with a 2% change alert. No sign-up or API key.
- **Private**: no server, account, or analytics. Settings stay on the Mac.
- **Resilient**: if a data source fails, the next one takes over and the UI keeps working.
- **Light**: no Dock icon; the panel opens and closes instantly.

## Scope

Version 1.x is a standalone menu bar price tool for macOS 14 or later on Apple silicon, in English, Simplified Chinese, and Traditional Chinese.

Out of scope: accounts and sync, a Coinscal server, trading, holdings and profit tracking, charts and order books, data sources that need an API key, and coins outside the catalog. Adding any of these needs a scope decision recorded in this document first.

## Menu Bar Item

- "Show" is "Price" (default) or "Icon". With "Icon" the item always shows the monochrome logo.
- With a price: `<symbol> <price>` by default, for example `BTC 65,000`. Turning off "Show Coin Symbol" displays only the number. The menu bar omits the currency symbol. Decimals depend on magnitude, without trailing zeros: none from 100, up to two from 1 to 100, up to four below 1. A positive price that would round to zero uses compact scientific notation.
- Without a price (starting up or empty watchlist), the item shows the monochrome logo. If a refresh fails, it keeps the last available price.
- "Color by Price Change" uses the selected price change basis to color the price. With "Show Badge" on, the colored badge uses white text on the same price color used for plain text. With price coloring off, the badge uses the menu bar text color for its background and inverts the text.
- Left click toggles the panel. Right click opens the menu.

## Panel

320pt wide: a header, the watchlist, and a footer with Settings, "Manage Watchlist", and Quit. The list is sized for 4 to 8 rows and scrolls beyond that, without a visible scroll bar. Each row shows the logo, name, symbol, price in the display currency, and price change. Quotes older than 30 minutes show a warning icon and their last retrieval time in the change column. The header shows the selected day boundary in a fixed-day mode. An empty watchlist shows an empty state with "Add Coins", which opens Settings → Watchlist.

Opening the panel leaves the frontmost app active, as the system's menu bar extras do. The panel closes on a second click on the menu bar item, a click anywhere else, Esc, switching to another app, and when Settings opens. When a scheduled update check has found a new version, the header shows "Update Available"; clicking it opens the update window.

## Right-Click Menu

"Menu Bar Coin" (a submenu of the watchlist, current coin checked), "Settings", "Check for Updates" (disabled while a check runs), "Quit Coinscal" (⌘Q). Menu items show no icons.

## Settings

A window with four panes, General, Display, Watchlist, and About, under a shared title bar that shows the pane name. Default size 786×500, resizable from 600×420 to 800×500; the last size is remembered. Every change applies and saves immediately. The app menu's "Settings" item (⌘,) opens the same window. All panes except Watchlist are grouped forms.

- **General**
  - "Open at Login" (off by default) and "Language" (Follow System, English, Simplified Chinese, Traditional Chinese).
  - Prices: "Display Currency" and "Price Change Basis". The basis selector offers "Rolling 24 Hours" (default), "Midnight (UTC+0)", and "Midnight (UTC+8)" in that order. The menu bar color, panel, desktop ticker, and widgets follow this setting.
  - Updates: "Automatically Check for Updates" (on by default), "Automatically Install Updates" (off by default; available while automatic checks are on), and the version with "Check for Updates".
- **Display**
  - Menu Bar: "Show" (Price / Icon), "Coin", "Show Coin Symbol", "Color by Price Change", the "Color Scheme" menu (Green Up, Red Down / Red Up, Green Down / Custom) with "Up Color" and "Down Color" rows for Custom, and "Show Badge". Icon mode disables the price controls. The color scheme and custom colors are available when price coloring is on. Disabled controls retain their selections.
  - Desktop: "Show on Desktop", "Text Size" (Normal / Large), "Background Opacity", and "Position" with "Adjust"; grayed out while the ticker is off.
- **Watchlist**
  - "+" at the right of the title bar opens an add panel with a search field (focused) over the listed coins, matching symbol or name. With no input it lists every listed coin. Clicking a coin toggles it in the watchlist (added coins show a checkmark that turns into a remove sign on hover); the panel stays open. Return adds the first result not yet added. Esc, a click outside, "+" again, or switching panes closes it and clears the search.
  - "Recommended": BTC, ETH, BNB, SOL, ZEC, HYPE, BCH, LTC, UNI, AAVE; click to add or remove.
  - The watchlist header holds "Price Alerts", the master switch for alerts. While it is on and macOS has notifications for Coinscal turned off, a notice under the header offers "Open System Settings".
  - The watchlist: drag handle to reorder (also with arrow keys when focused or VoiceOver actions), the alert condition and value, and delete. The delete button appears on hover; the row's context menu and a VoiceOver action also delete. Coins without a market show "No market data". An empty watchlist shows "Add Coins", which opens the add panel.
- **About**: version (selectable), contact, data sources with the "Rates By Exchange Rate API" credit, and open source components.

## Widgets

| Widget | Sizes | Content |
|---|---|---|
| Coin Price | Small | One coin: logo, symbol, name, price, price change, update time |
| Watchlist | Medium (4 rows), Large (8 rows) | Logo, symbol and name, price, and price change per row; title and update time |

- The price change uses color, ▲ / ▼, and a sign, so it stays readable when macOS shows desktop widgets in monochrome.
- The update time shows the oldest displayed quote. It turns orange with ⚠︎ when a quote is older than 30 minutes. The Watchlist widget also marks the affected rows. Before any price is available the widget says "Open Coinscal to get prices". Coins without a market show "No market data".
- Edit Widget:
  - Coin Price: Coin ("Follow Menu Bar Coin" by default, or any listed coin), Display Currency ("Follow App" by default), Color by Price Change (on).
  - Watchlist: Source ("Watchlist" by default, or "Choose Manually" with up to 4 or 8 coins), Sort By (watchlist order, or the selected price change high to low or low to high), Display Currency, Color by Price Change.
- Language and the color scheme follow the app.
- The widget gallery previews the user's own coins with live prices, falling back to sample prices when offline.
- Widgets refresh about every 15 to 30 minutes, as the system's budget allows, and fetch prices themselves when the app isn't running. Clicking a widget opens the panel, launching the app first if needed.

## Desktop Ticker

A price list pinned to the desktop, between the wallpaper and the desktop icons, on every Space. Mouse clicks pass through it, and it doesn't appear in window switching. Unlike a widget it updates with the app every 10 seconds, and it disappears when the app quits.

- One layout, the large widget's list: up to the first 16 watchlist coins, limited further by the available screen height. Stale quotes are marked in their rows. The list grows downward from its top edge. "Large" text adds 2pt to all text.
- "Background Opacity" (0–100%, 100% by default) affects only the frosted background. Below 20%, text turns white with a faint shadow, like desktop icon labels, so it stays readable on any wallpaper; only ▲ / ▼ and ⚠︎ keep their colors.
- By default it sits at the top right of the main display. Turning on "Show on Desktop", or "Adjust Position", brings it to the front with a dashed border and "Drag to move / Done"; it can be dragged to any display. "Done" (or Return) saves the position and restores click-through. If its display is disconnected, it moves to the nearest display until that one returns.

## Price Change

- Rolling 24 hours uses each source's rolling statistics. Fixed-day change compares the latest quote with the same exchange's opening price since the chosen midnight. UTC+8 midnight occurs at 16:00 UTC.
- When today's opening price is unavailable, the current price remains visible and the change shows `—`. Every price alert uses its own reference price regardless of the display basis.

## Price Alerts

- An alert fires only while "Price Alerts" is on and the coin's condition isn't "Off". New coins default to "Change 2%".
- **Change**: fires when the price moves at least N% (0.5–200%) from the reference price, then the reference resets to the current price. The reference is the first price received or the price at the last alert, not the 24h open.
- **Above / Below**: fires once when the price crosses the threshold; staying past it doesn't repeat. Thresholds are entered in the display currency and stored and evaluated in USD. The amount field waits for an exchange rate for the selected currency. Switching a coin to Above or Below proposes the current price ±2%.
- Without a reference (first price after launch, after changing the display currency) the app records one and doesn't fire, since it can't know whether a crossing happened. Changing the display currency resets every reference. Editing a coin’s alert resets that coin’s reference.

## Updates

- Coinscal checks for updates once a day. A scheduled check opens no window unless Coinscal is in front; it shows "Update Available" in the panel header instead, also after a relaunch, until the user opens the update window or the update is installed.
- "Check for Updates" opens the update window at once, with release notes and "Install Update", or a note that Coinscal is up to date. A failed scheduled check stays silent; a manual one shows the error.
- Nothing installs without the user's consent: either "Install Update" in the update window, or "Automatically Install Updates" turned on (in Settings or the update window), which installs found updates when Coinscal quits. Installing replaces the app and relaunches it, keeping settings, watchlist, widgets, and the login item.
- Release notes follow the in-app language. The update window itself comes from Sparkle and follows the system language.

## Coin Availability

- If a source fails or doesn't answer within 5 seconds, the next one is used, and the source that answered becomes the first choice for the next round. If every source fails, the last prices stay on screen. If every exchange rate source fails, the last rates are used.
- A coin missing from one exchange is priced from another. A coin no source trades shows `--`.
- A watchlist coin that is missing from the catalog is dropped.
- When the catalog marks a coin as migrated to a tradable successor, the watchlist replaces it in place at launch, without a prompt. Change and Off alerts are kept; Above and Below reset to "Change 2%" because the old threshold doesn't apply. If the successor is already in the watchlist, the old coin is removed; the menu bar coin follows the replacement.

## Interaction and Copy Rules

- Changes to the display currency, price change basis, or language schedule a price refresh after 0.5 seconds. Language changes apply immediately, including open windows.
- Drag reordering respects "Reduce motion".
- Button and menu item labels never end with an ellipsis.
- Prices and percentages use `.` for decimals and `,` for grouping in every language and region.
- Each language option is written in its own language.
- The website reproduces the menu bar item and the panel ([Website](WEBSITE.md)); changes to their look or rules update the site in the same change.

## Parameters

| Parameter | Value | Defined in |
|---|---|---|
| Polling interval | 10 s | `Constants.Defaults.pollingInterval` |
| Request timeout per source | 5 s | `Constants.API.requestTimeout` |
| Exchange rate cache | 1 h | `Constants.API.exchangeRateCacheTTL` |
| Change alert range | 0.5–200% | `AlertEvaluator.clampAlertThreshold` |
| Default alert | Change 2% | `Constants.Defaults.defaultNotificationThreshold` |
| Panel rows | 4–8 | `Constants.Popover` |
| Desktop ticker coins | up to 16 | `DesktopOverlayLayout.rowLimit` |
| Widget stale after | 30 min | `WidgetContent.staleAfter` |
