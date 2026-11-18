# Roadmap

## Status

Version 1.x, as defined in [Product](PRODUCT.md), is implemented and released: menu bar price, panel, watchlist, alerts, display currencies, widgets, the desktop ticker, in-app updates, and the website. 1.1.0 is the latest release. Open verification items are tracked in [Validation](VALIDATION.md).

## Candidates

Not scheduled. A candidate that changes scope, data sources, or architecture gets a written proposal and approval before work starts.

| Candidate | Notes |
|---|---|
| async/await networking | Replace the Combine services with actor-based services and a `Task` polling loop. |
| Remote catalog updates | A scheduled job publishes a validated catalog that the app fetches daily, so renames and migrations arrive between releases. Releases already carry catalog updates through in-app updates, so this is worth doing only if the catalog changes faster than releases. |
| Stablecoins in the catalog | Decide whether to exclude coins such as USDC and USDE from search. |

## Known Issues

| Issue | Impact |
|---|---|
| `NSApp.activate(ignoringOtherApps:)` is deprecated since macOS 14 | A future SDK may remove it; move to cooperative activation. |
| `PriceFormatter` creates a `NumberFormatter` on every call | Extra work while lists scroll. |
| Logos of coins not in the watchlist rely on the URL cache | Offline, the add panel shows symbol placeholders for them. |
| The website re-implements the app's price sources in JavaScript | A source change in the app can leave the website behind unless both are updated. |
| With "show hidden files" on, Finder sometimes scrolls the DMG window and reveals `.background` and `.VolumeIcon.icns` | Cosmetic; both files are required. |
