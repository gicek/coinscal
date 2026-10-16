# Coinscal Work Plan

> Purpose: a working document for day-to-day execution that records the near-term batch, tech debt, and optimization ideas. It is not a scope commitment and can change as work proceeds.

## Current Batch: Remote Coin Catalog Updates

External dependencies: a public repository and the Actions secret `COINGECKO_API_KEY` (see [COIN_CATALOG](COIN_CATALOG.md)).

- [ ] GitHub Actions generates the catalog daily and publishes it to the `catalog` branch after validation passes
- [ ] The client fetches from jsDelivr every 24 hours, caches in the sandbox, and keeps the current catalog if validation fails
- [ ] Add jsDelivr requests to the privacy notes

## Wrap-Up After Verification

- [ ] Actual layout of the Settings window in all three languages (longer English labels: `Color by Price Change`, `Green Up, Red Down`)

## Tech Debt Register (numbers are stable IDs, not an order)

| # | Debt | Risk | Batch |
|---|---|---|---|
| 1 | `MenuBarViewModel` sets the logo and then clears it on every refresh; `button.layer` gets its background color before `wantsLayer = true` | The first time "Show Background" is turned on, the background color only appears on the next refresh; unnecessary redraws | Next batch |
| 2 | The network layer is still Combine | Inconsistent with the guidelines (async/await); cancellation semantics are hard to reason about | ROADMAP Engineering |
| 3 | `PriceFormatter` creates a new `NumberFormatter` on every call | Extra overhead while scrolling lists | Next batch |
| 4 | `NSApp.activate(ignoringOtherApps:)` is deprecated in macOS 14 | A future SDK may remove it | Next batch |
| 5 | Logos of coins not yet added (browsing the add panel) rely only on the system URL cache | Offline, the panel shows symbol placeholders for them (watchlist coins are cached since 2026-10-15) | Remote coin catalog updates |
