# Coinscal Interaction Design

> This document defines user flows, UI states, and copy rules. For product scope, see the [Project Definition](PROJECT.md). For implementation status, see [Implementation and Verification Status](VALIDATION.md).

## Information Architecture

### Menu Bar Button

- The "Menu Bar → Show" setting is either "Price" (default) or "Icon". With "Icon", the button always shows only the monochrome logo. The rules below apply only to "Price".
- With a price: `<symbol> <price>` (for example `BTC 65,000`). The price has no currency symbol. Decimal places depend on magnitude (≥100: none; 1–100: two; <1: up to four).
- Without a price (starting up, all data sources failed, empty watchlist): only the monochrome logo.
- "Color by Price Change" on: the text is colored by the selected coin's 24h change. "Show Background" on: rounded background color with inverted text.

### Popover (Left Click)

320pt wide: title bar + watchlist + bottom bar (Settings, Manage Watchlist, Quit). The list reserves at least 4 rows and shows at most 8; beyond that it scrolls, without a visible scroll bar. Each row: logo, name, symbol, current price (in the quote currency), 24h change. With an empty watchlist it shows an empty state and "Add Coins", which opens the "Watchlist" pane in Settings.

### Right-Click Menu

Switch the menu bar coin (submenu, current item checked), Settings, About, Quit (⌘Q).

### Settings Window

Three sidebar panes: General, Watchlist, About. The top of the content area is a shared title bar showing the current pane's name; all three panes have the same height. Content scrolls up under the title bar. The window defaults to 786×500, can be resized between 600×420 and 800×500, and remembers its last size.

- **General**: Launch ("Open at Login"); Menu Bar ("Show": Price / Icon segmented control, "Coin", "Color by Price Change" + "Color Scheme", "Show Background"); Desktop ("Show on Desktop", "Size" Small / Medium / Large (Medium by default), "Background Opacity", "Adjust Position…"; the rest are grayed out when off); Prices ("Display Currency", which applies to the menu bar, popover, and alerts, so it is not in the Menu Bar section); Notifications ("Price Alerts" master switch); Language. When "Show" is "Icon", the other Menu Bar options are grayed out (kept in place, not hidden).
- **Watchlist**: A "+" button at the far right of the title bar opens an add panel below the button (an in-window card whose right edge stays inside the window, not a system popover). At the top is a search field (focused on open) that searches the roughly 450 tradable coins currently listed in the coin catalog by symbol or name. With no input it lists all listed coins. Added rows show a checkmark; clicking a row that isn't added adds it. The panel stays open for adding several coins in a row. Return adds the first result that isn't added. Esc (except during input method composition), clicking outside the panel, clicking "+" again, or switching panes closes it and clears the search. With no matches it shows "No matching coins". The content area contains only "Recommended" (click to toggle add / remove; coins that aren't listed are skipped) and the added list (drag handle to reorder, alert condition + value, delete; it scrolls without a visible scroll bar). In the added list, delisted coins show "No market data" under the symbol; popover rows show the same text in place of the change.
- **About**: Version, contact, data sources.

### Desktop and Notification Center Widgets

Two kinds: "Coin Price" (small, follows the menu bar coin by default) and "Watchlist" (medium with 4 rows, large with 8 rows). See [WIDGET](WIDGET.md) for layout, states, and edit options. Key points:

- Change is shown with color, ▲ / ▼, and a plus or minus sign together. Each widget shows its update time, with ⚠︎ when older than 30 minutes.
- Edit options follow the app by default (menu bar coin, watchlist, quote currency, color scheme). Changing them affects only that widget. Language follows the app.
- Clicking opens the menu bar popover. If the app isn't running, it launches first and then shows the popover.

### Desktop Ticker

A click-through price panel pinned to the desktop (between the wallpaper and the desktop icons). Its content and style match the widget. It updates every 10 seconds along with the app and has adjustable background opacity (below 20%, text switches to white with a light shadow, like Finder file names; the icon and background get no shadow). By default it sits in the top-right corner of the main display and can be dragged to any display. Turning on "Show on Desktop" goes straight into position adjustment: the panel floats to the top layer and shows a dashed border with "Drag to move / Done". Changing the size during adjustment doesn't exit it. Clicking "Done" saves the position and restores click-through. "Adjust Position…" in Settings re-enters adjustment at any time. See [DESKTOP_OVERLAY](DESKTOP_OVERLAY.md).

### Website Demo

The website's hero reproduces the menu bar button and the popover with live prices; see [WEBSITE](WEBSITE.md). When the look or rules of either change here, update the website in the same change.

## Core Flows

### Price Alerts

- Preconditions: the notification master switch is on, and the coin's alert condition is not "Off".
- Change: alerts when the current price moves ≥ N% up or down from the reference price; after alerting, the reference price resets to the current price. The reference price is the first price received or the price at the last alert, not the 24h open.
- Above / Below: alerts once when the price crosses from one side of the threshold to the other. Staying on the other side doesn't repeat the alert. Thresholds are stored in USD and displayed and entered in the current quote currency.
- With no reference price (first price after launch, after switching the quote currency), the app only records the reference price and doesn't alert, because it can't tell whether a crossing happened. If the price is already on the other side of the threshold at launch, the alert waits until it comes back to this side and crosses again.
- Switching the quote currency: all reference prices reset, no alert.
- When switching to Above / Below, the threshold defaults to the current price ±2%.

### Data Source Failure

When the current data source fails or times out (5 seconds), the app switches to the next one in order; the source that succeeds becomes the starting point for the next round. If all fail, the previous round's prices are kept and the menu bar doesn't clear. If all exchange rate sources fail, the expired cache is used.

### Projects Migrated to a Successor Coin

- When the catalog points an old coin id to a successor (for example MATIC → POL) and the successor is tradable, the old coin in the watchlist is replaced with the successor at launch or after a catalog update. The UI shows only the successor's name and price, with no migration prompt.
- It is replaced in place. Change / Off alerts keep their settings; Above / Below alerts revert to the default "Change 2%" (the threshold was in the old coin's price and isn't comparable). If the successor is already in the watchlist, the old coin is just removed. If the menu bar shows the old coin, it switches to the successor.

## General Interaction Rules

- Settings take effect and are saved immediately; there is no "Apply" button. After the quote currency or language changes, prices are refetched within 0.5 seconds.
- Language switches take effect immediately without restarting. An open Settings window (including titles and radio groups) switches along with it.
- Launch at login is off by default; the first launch doesn't register a login item.
- Respect "Reduce motion": no make-way animation while dragging to reorder.

## Copy Rules

- The source language is English; translations go in the String Catalog. For terminology, see [Localization](LOCALIZATION.md).
- Prices and percentages use `.` as the decimal point and `,` as the thousands separator, regardless of the system region.
- Each language option is written in its own language (English, Simplified Chinese, and Traditional Chinese each appear in their own script).
