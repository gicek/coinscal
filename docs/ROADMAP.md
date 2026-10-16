# Coinscal Roadmap

> This document organizes development order by acceptance criteria, not by dates. For current implementation status, see [Implementation and Verification Status](VALIDATION.md). For near-term work, see the [Work Plan](PLAN.md).

## Current Commitment

The first milestone (1.x) delivers a standalone menu bar price tool: current price in the menu bar, watchlist popover, per-coin price alerts, multiple quote currencies, and a UI in three languages. See the [Project Definition](PROJECT.md) for scope. Other ideas go in the under-consideration list and are not scheduled.

| Phase | Status | Deliverables |
|---|---|---|
| 1.0 features | Implemented | Every item in PROJECT "Scope" |
| Engineering foundation | Implemented | XcodeGen project, Makefile entry points, `Build/` output directory, unit tests, localization guards, CI, docs |
| Reliability | In progress | Failover, cross-exchange price fill-in, no false alerts when switching currency, tolerant settings decoding, coin catalog (implemented); remote catalog updates (not started, see [COIN_CATALOG](COIN_CATALOG.md)) |
| Desktop and Notification Center widgets | Implemented | "Coin Price" and "Watchlist" widgets with edit options; they fetch prices themselves when the app isn't running ([WIDGET](WIDGET.md)); appearance on a real Mac pending verification |
| Desktop ticker | Implemented | Click-through desktop price panel, refreshed every 10 seconds with the app, can be dragged to any display ([DESKTOP_OVERLAY](DESKTOP_OVERLAY.md)); multiple panels not done |
| Website | Deployed | Static site with a live menu bar demo in three languages at `coinscal.app` ([WEBSITE](WEBSITE.md)); Safari and Lighthouse pending verification |
| Release pipeline | In progress | Developer ID code signing and notarization (`mac-release` / `mac-release-notarized`, implemented; first launch on another Mac pending verification); upload via `mac-publish` (not started) |

## Engineering Foundation

Done when: `make mac` builds successfully from a clean repository; the result line of `make test` is `** TEST SUCCEEDED **`; the CI hygiene and localization guard jobs pass; the source tree contains no build outputs.

## Reliability

Done when: if any price data source is unreachable or rejects requests, a price arrives within the next polling cycle; a listed coin in the catalog has a price as long as one price source trades it; switching the quote currency produces no alerts; settings survive upgrades; catalog renames and migrations reach users without a new release. Each item has unit tests; real network behavior is verified with `make mac-check-sources` and VALIDATION.

## Website

Done when: `coinscal.app` serves the current `Site/` with the headers in effect; the main flows work in Chrome and in Safari on macOS and iOS; Lighthouse scores ≥ 90 in all four categories; the download buttons lead to the latest notarized release.

## Release Pipeline

Done when: `make mac-release-notarized` produces a zip and DMG that are Developer ID signed, notarized, and have the ticket stapled, and first launch on another Mac isn't blocked by Gatekeeper; `make mac-publish` requires entering the version number to confirm.

## Features Under Consideration

### Data

- Whether the catalog should exclude stablecoins (listed coins currently include USDC, USDS, USDE, and others).

### Distribution

- In-app updates: the app checks for and installs new versions, with update files on Cloudflare's free storage. Next after the website (2026-10-16); needs a design doc and approval before implementation.

### Engineering

- Migrate the network layer from Combine to async/await (`actor` services + `Task` polling loop).

## Rules for Changing the Roadmap

New features entering the first milestone must update `PROJECT.md`, `DESIGN.md`, `TECHNICAL.md`, and this document together. Adding an idea to the under-consideration list is not a commitment. Changes to platform, distribution, data source strategy, or privacy boundaries require reconfirming the product decisions.
