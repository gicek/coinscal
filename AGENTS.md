# Coinscal Repository Development Rules

This file applies to the whole repository and follows the shared project development guide (`project-guide`). Where it conflicts with the guide, this file wins, and the difference is recorded in "Deviations from the Standard".

## Project Profile

| Dimension | Value |
|---|---|
| Client platform | macOS (menu bar app) |
| Shared core | None |
| Website | Static site in `Site/` (plain HTML, CSS, and JavaScript, no build step), served at `coinscal.app` and `coinscal.gicek.com` by Cloudflare Workers Static Assets (`make site-deploy`); see [WEBSITE](docs/WEBSITE.md) |
| Backend | None (the client calls public price / exchange rate APIs directly) |
| Admin console | None |
| Distribution | Direct Mac download as zip and DMG, signed with Developer ID (`make mac-release`); notarized with the ticket stapled before public distribution (`make mac-release-notarized`) |
| UI languages | `en`, `zh-Hans`, `zh-Hant` (source language `en`), switchable instantly in the app and on the website |
| Minimum OS | macOS 14 (the 4-year rule would give macOS 13; see "Confirmed Product Decisions" in PROJECT for why) |
| License | MIT (`LICENSE`). The repo will be public: don't commit keys, internal addresses, or personal config |
| Guide version | project-guide 1.1 |

## Product Name

- Product name: `Coinscal`
- Tagline: Real-time crypto price monitor
- Don't introduce former product names in code, docs, targets, bundle IDs, logs, or UI strings.

## Where Status and History Live

Documents are either current-state or historical. Keep each kind in its own place.

| Kind | Documents | Rule |
|---|---|---|
| Current state | `README.md`, `AGENTS.md`, `docs/PROJECT.md`, `docs/DESIGN.md`, `docs/TECHNICAL.md`, `docs/DEVELOPMENT.md`, `docs/LOCALIZATION.md`, topic docs (`docs/<TOPIC>.md`), `THIRD_PARTY_NOTICES.md` | Describe the project as it is now. When something changes, rewrite the text; don't append "previously…" or "changed on…" narratives. Product decisions keep their approval date, and a changed default notes its date and old value in one parenthetical. |
| History | `Apple/Mac/docs/CHANGELOG.md`, `Site/docs/CHANGELOG.md` | What changed and when, newest first. Fixes record symptom, root cause, fix, and tests. Entries aren't rewritten later. |
| Status | `docs/VALIDATION.md` | What is verified and what is pending, with dates, newest first. |
| Plans | `docs/ROADMAP.md`, `docs/PLAN.md` | What comes next. ROADMAP is the commitment; PLAN is a working draft and the tech debt register. |

`README.md` covers only the introduction, shipped features, requirements, quick start, and links to docs. `docs/PROJECT.md` defines product scope; don't describe roadmap plans as shipped features.

## Document Precedence

Before changing scope or architecture, read in this order:

1. `docs/PROJECT.md` defines the product and the first milestone.
2. `docs/DESIGN.md` defines user flows, interaction rules, and UI states.
3. `docs/TECHNICAL.md` defines data contracts, data sources, the concurrency model, and the test strategy.
4. `docs/ROADMAP.md` defines development order and items under consideration.

When documents conflict, the higher one wins; fix the lower one in the same change. `docs/PLAN.md` is the day-to-day work plan and tech debt log. It isn't a scope commitment and can change freely. When an item enters development and changes scope, interaction, or data contracts, still update the baseline docs above.

**Changelogs**: `Apple/Mac/docs/CHANGELOG.md` (app) and `Site/docs/CHANGELOG.md` (website) record additions, changes, fixes, and removals in reverse date order. Add an entry to the affected component's changelog when a change is merged.

## First Milestone Scope

The first milestone (1.x) is a standalone menu bar price tool: the current price of one coin in the menu bar, the watchlist in a popover, per-coin price alerts, quote currency conversion, and a three-language UI. `docs/PROJECT.md` defines the scope.

**Explicitly out of scope**: accounts and cloud sync, a custom backend, trading and order placement, holdings and P&L tracking, candlestick and historical charts, data sources that need an API key, and custom coins outside the coin catalog. Update `docs/PROJECT.md` and `docs/ROADMAP.md` before adding any of these.

## Fixed Project Names

- Xcode project: `Apple/Coinscal.xcodeproj`, generated from `Apple/project.yml`
- macOS target and scheme: `CoinscalMac` (source in `Apple/Mac`; test target `CoinscalMacTests`, source in `Apple/Mac/Tests`)
- Widget extension target: `CoinscalWidget` (source in `Apple/MacWidget`; source shared with the main app is in `Apple/Mac/Shared`, and other shared files are listed one by one in `project.yml`), bundle ID `com.gicek.coinscal.widget`, App Group `$(TeamIdentifierPrefix)com.gicek.coinscal`.
- Website: `Site/` (messages in `Site/messages/`, tests in `Site/test/`, changelog in `Site/docs/CHANGELOG.md`).
- Bundle ID: `com.gicek.coinscal` (tests `com.gicek.coinscal.tests`). The UserDefaults domain follows the bundle ID; changing the ID loses all user settings.
- The product name is `Coinscal` everywhere (app bundle name, display name, process name, Swift module name).

If the official bundle ID needs a different organization prefix, change all targets and all docs together, and provide a settings migration.

## Build Output

- Use the root `Makefile` for building, testing, running, and releasing. `make help` lists all commands.
- All build caches and products go in the root `Build/macOS/`. Don't add `.build`, `DerivedData`, `build`, or `dist` in source directories. The website has no build step and is deployed from `Site/` as is.
- `Build/` is a disposable derived directory and isn't committed to Git. Clean it with `make clean`.
- Put machine-private config in `local.mk` (not committed; template in `local.mk.example`).
- `Apple/project.yml` is the source of the Xcode project. After changing targets, build settings, or source paths, run `make project`. Don't edit `project.pbxproj` by hand. Adding or removing source files doesn't require a `project.yml` change (files are included by directory), but rerun `make project`.

## Architecture Rules

- UI state and view models are `@MainActor`. The price and exchange rate services are currently Combine publishers that deliver results on the main thread (the `PriceServicing` contract). New code uses async/await; the migration plan is in ROADMAP.
- Inject networking, settings storage, and system notifications through protocols: `HTTPClient`, `SettingsStore`, `PriceAlertNotifying`. Don't use `URLSession.shared`, `UserDefaults.standard`, or `UNUserNotificationCenter` directly in business types.
- Polling must not cancel and resend while the previous request is still in flight. (When a data source times out, the next poll would interrupt failover, and it would never reach the later data sources.)
- An alert's reference price and the current price must be in the same quote currency. On a currency change, discard in-flight results and reset the reference price.
- `AppSettings` decoding must tolerate errors field by field, and new fields need defaults. Keep `addedCoins` as the JSON key for `watchlistCoins`.
- Log with `Logger` (subsystem `com.gicek.coinscal`), not `print`. Don't log user settings.
- **Text fields inside List rows are a trap** (`WatchlistView`): the underlying `NSTableView` intercepts first-responder clicks on in-row controls, and SwiftUI `FocusState` is unreliable inside rows. So the threshold input wraps an AppKit `NSTextField` that doesn't take part in hit testing while not editing; an outer tap gesture calls `makeFirstResponder` directly (`FullHitTextField` / `AlertFieldProxy`). The representable must implement `sizeThatFits` to fill the width. Don't "simplify" it back to a SwiftUI `TextField`.
- **Watchlist drag reordering is gesture-driven** (`WatchlistReorderSupport.swift`): insertion slot = floating row center ÷ fixed row height of 44pt; on release, the order is committed once after the settle animation. Don't switch back to per-row hit testing with NSDraggingSession / DropDelegate; it jitters back and forth while rows animate out of the way.
- **Settings window toolbar items live at the `SettingsWindow` level and exist on every pane** (hidden on panes that don't need them). Don't move them into a single pane's `.toolbar` or use `if` to leave an item empty: on a pane with no toolbar items SwiftUI removes the whole window toolbar, and the title bar and sidebar shift (see TECHNICAL).
- **Website**: no framework, build step, or npm dependencies. Outbound links live only in `Site/js/config.js` (pages use `data-link`). Every visible string has a key in all three `Site/messages/*.json` files. Changing the inline script in a page's `<head>` changes its CSP hash: update `Site/_headers` in the same change (`make test-site` fails otherwise). A new API the demo calls must be added to the CSP `connect-src`.
- Settings window panes don't set an explicit background color, so the system window material shows through. (On macOS 26 an opaque `windowBackgroundColor` layer doesn't match the material.)

## Security

- Don't commit keys, signing material, or API tokens. Logs must not contain keys, tokens, or user content.
- The sandbox requests only `network.client`. All data sources must use HTTPS; no ATS exceptions.
- Pin versions when adding a dependency or tool, and update `THIRD_PARTY_NOTICES.md` in the same change. Don't copy, link, or derive from GPL code. There are no third-party code dependencies; the only third-party tool is Wrangler, pinned in the `Makefile`.
- Cloudflare credentials stay in Wrangler's user config (`make site-login`) or the environment, never in the repository.

## Tests and Definition of Done

- Add tests for feature changes at the lowest effective layer (Swift Testing for the app, `node:test` in `Site/test/` for the website). Items that need a real Mac or manual verification go under pending verification in `docs/VALIDATION.md`.
- Write user-visible strings in the source language only and add them to `Apple/Mac/Resources/Localizable.xcstrings`, filling in all three languages in the same change. A localization guard failure in `make test-mac` is a defect; don't skip it. Use `Text(verbatim:)` for literals that don't need localization.
- **Tests never touch the real UserDefaults, notification center, login items, or network**: inject `InMemorySettingsStore`, `SpyNotifier`, `StubHTTPClient`, `FakePriceService` (`Apple/Mac/Tests/TestSupport.swift`). When the app launches as the test host, `AppDelegate` does no setup.
- `make test` is the full test entry point. Judge success by the `** TEST SUCCEEDED **` result line, not by the exit code after a pipe.
- When product decisions, user-visible interactions, milestone scope, dependencies, data sources, or file paths change, update the matching docs.
- For string-only changes with no logic change, run `make test-mac` (includes the localization guards) and update the docs. For the website, run `make test-site`.

## AI Collaboration

- Don't commit unless explicitly asked. One change per commit; format `<type>(<scope>): <summary>`, imperative mood (e.g. `fix(alerts): reset reference price on currency change`).
- For proposals that change product scope, data sources, or architecture, first write `docs/<TOPIC>.md` and register it under "Features Under Consideration" in ROADMAP. Implement only after approval.
- Record decisions, removals, and default changes with an absolute date and a reason.
- When confidence is low or something is ambiguous, list the options and let the user choose. Don't implement based on a guess.

## Deviations from the Standard

- **Semantic localization keys** (e.g. `menu.change`) instead of English source strings as keys: to support instant in-app language switching, all strings go through `loc(_:)`, which picks the `.lproj` sub-bundle for the language. String Catalog entries are marked `extractionState: manual`, and `SWIFT_EMIT_LOC_STRINGS = NO`.
- **Single-platform docs not merged**: DESIGN and PLAN stay separate rather than being merged into PROJECT / ROADMAP.
- **CI doesn't run app tests**: the app target depends on the local Xcode 26 SDK, which hosted runners may not have. `make test` runs locally; CI runs the localization guards, the website checks, and the artifact hygiene check (see the comments in `.github/workflows/tests.yml`).
