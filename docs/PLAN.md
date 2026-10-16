# Coinscal Work Plan

> Purpose: a working document for day-to-day execution that records the near-term batches and tech debt. It is not a scope commitment and can change as work proceeds. Verification status lives in [VALIDATION](VALIDATION.md).

## Current Batch: In-App Updates (Design)

- [ ] Write `docs/UPDATES.md`: update feed format, where release files live on Cloudflare storage, signature and integrity checks, user flow, and what the website and the release scripts publish
- [ ] Register it under "Features Under Consideration" in [ROADMAP](ROADMAP.md) and get approval before implementation

## Next Batch: Remote Coin Catalog Updates

External dependencies: a public repository and the Actions secret `COINGECKO_API_KEY` (see [COIN_CATALOG](COIN_CATALOG.md)).

- [ ] GitHub Actions generates the catalog daily and publishes it to the `catalog` branch after validation passes
- [ ] The client fetches from jsDelivr every 24 hours, caches in the sandbox, and keeps the current catalog if validation fails
- [ ] Add jsDelivr requests to the privacy notes

## Tech Debt Register (numbers are stable IDs, not an order)

| # | Debt | Risk | Batch |
|---|---|---|---|
| 1 | `MenuBarViewModel` sets `button.layer?.backgroundColor` before `wantsLayer = true` (the logo half of this item was fixed on 2026-10-15) | The first time "Show Background" is turned on, the background color only appears on the next refresh | Next batch |
| 2 | The network layer is still Combine | Inconsistent with the guidelines (async/await); cancellation semantics are hard to reason about | ROADMAP Engineering |
| 3 | `PriceFormatter` creates a new `NumberFormatter` on every call | Extra overhead while scrolling lists | Next batch |
| 4 | `NSApp.activate(ignoringOtherApps:)` is deprecated in macOS 14 | A future SDK may remove it | Next batch |
| 5 | Logos of coins not yet added (browsing the add panel) rely only on the system URL cache | Offline, the panel shows symbol placeholders for them | Remote coin catalog updates |
| 6 | The website's price feed (`Site/js/prices.js`) re-implements the app's source order and parsing in JavaScript | When the app's data sources change, the website can silently diverge | Revisit if a source changes |
