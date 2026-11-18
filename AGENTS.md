# Repository Rules

Rules for everyone changing this repository, human or agent. Product scope is in [docs/PRODUCT.md](docs/PRODUCT.md), the code structure in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Project

| Item | Value |
|---|---|
| Product | Coinscal, a macOS menu bar app for crypto prices |
| App | `Apple/`: target and scheme `CoinscalMac` (`Apple/Mac`), widget extension `CoinscalWidget` (`Apple/MacWidget`, shared code in `Apple/Mac/Shared`), tests `CoinscalMacTests` (`Apple/Mac/Tests`) |
| Website | `Site/`: static HTML, CSS, and JavaScript on Cloudflare ([docs/WEBSITE.md](docs/WEBSITE.md)) |
| Backend | None; the app calls public, key-free APIs |
| Platform | macOS 14+, Apple silicon; built with Xcode 27 |
| Languages | `en` (source), `zh-Hans`, `zh-Hant` |
| Distribution | Developer ID-signed, notarized zip and DMG with Sparkle updates ([docs/RELEASING.md](docs/RELEASING.md)) |
| License | MIT; the repository is public |

## Names and Identifiers

- The product name is `Coinscal` everywhere: bundle name, process, Swift module.
- Release bundle ID `com.gicek.coinscal`, widget `com.gicek.coinscal.widget`, App Group `$(TeamIdentifierPrefix)com.gicek.coinscal`, URL scheme `coinscal`. Debug builds use the `.debug` variants and the scheme `coinscal-debug`, named "Coinscal Debug".
- These values come only from `COINSCAL_APP_ID`, `COINSCAL_DISPLAY_NAME`, and `COINSCAL_URL_SCHEME` in `Apple/project.yml`. Never hardcode them in code, entitlements, or Info.plist.
- User settings live in the `UserDefaults` domain of the bundle ID; changing the release ID requires a settings migration.

## Build

- Use the root `Makefile` (`make help`). All build output goes to `Build/`, which is never committed; nothing is built in source directories.
- `Apple/project.yml` is the source of the Xcode project. Run `make project` after changing it or adding files; never edit `project.pbxproj` by hand. Files are included by directory, except that the widget extension lists the app files it compiles.
- Machine-specific settings go in `local.mk` (template `local.mk.example`).

## Architecture Rules

- View models and UI state are `@MainActor`. Services return Combine publishers that deliver on the main thread (`PriceServicing`); keep new services consistent with that until the async/await migration.
- Inject networking, settings, notifications, and the updater through `HTTPClient`, `SettingsStore`, `PriceAlertNotifying`, and `UpdaterBackend`. Business types never use `URLSession.shared`, `UserDefaults.standard`, or `UNUserNotificationCenter` directly.
- A polling round is never cancelled by the next timer tick; otherwise a slow source keeps failover from reaching the later sources.
- Alert reference prices are valid in one display currency; a currency change discards results in flight and resets the references.
- `AppSettings` decodes field by field with defaults for new fields; the JSON key of `watchlistCoins` stays `addedCoins`.
- Log with `Logger` (subsystem `com.gicek.coinscal`), never `print`, and never log settings or the watchlist.
- The widget snapshot writer reloads widgets only when a widget-visible setting changes; periodic or price-driven reloads exhaust the WidgetKit budget.
- Keep these implementations; each replaces a simpler version that failed ([docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)):
  - The menu bar panel is an `NSPanel`, not an `NSPopover`; its dismissal ignores presses in the status item window, and its hosting view accepts the first mouse.
  - A colored menu bar price is drawn as one image, not an attributed title over a layer background.
  - Watchlist row text fields wrap `NSTextField` (`FullHitTextField`, `AlertFieldProxy`), not a SwiftUI `TextField`.
  - Watchlist reordering is gesture-driven (`WatchlistReorderSupport.swift`), not per-row drop targets.
  - Settings toolbar items live on `SettingsWindow` and exist on every pane, hidden where unused.
- Website: no framework, build step, or npm dependencies; outbound links only in `Site/js/config.js`; every visible string keyed in all three `Site/messages/*.json`; a changed inline script needs its new hash in `Site/_headers`; a new API needs a CSP `connect-src` entry.

## Security

- Never commit keys, tokens, certificates, or local configuration. Logs contain no secrets or user content.
- The app sandbox grants only `network.client` (plus the App Group and Sparkle's installer exceptions). All endpoints use HTTPS, with no ATS exceptions.
- Dependencies and tools are pinned; a change updates [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) in the same commit. No GPL-derived code. The only code dependency is Sparkle.
- The update signing key stays in the maintainer's Keychain and offline backup; only `SUPublicEDKey` is committed.

## Tests and Done

- Add tests at the lowest effective level: Swift Testing for the app, `node:test` in `Site/test/` for the website. Tests never touch the real `UserDefaults`, notification center, login items, updater, or network; use the doubles in `Apple/Mac/Tests/TestSupport.swift`.
- Write user-visible strings in English and add all three languages to the catalog in the same change ([docs/LOCALIZATION.md](docs/LOCALIZATION.md)). A localization guard failure is a defect.
- `make test` must end with `** TEST SUCCEEDED **` and pass the website checks.
- Manual checks that a change needs go into [docs/VALIDATION.md](docs/VALIDATION.md).

## Documents

| Document | Role |
|---|---|
| `README.md` | Introduction, features, install, build, documentation index |
| `docs/PRODUCT.md` | Scope and behavior; the reference for what the app does |
| `docs/ARCHITECTURE.md` | Code structure, contracts, and implementation constraints |
| `docs/DATA_SOURCES.md`, `docs/LOCALIZATION.md`, `docs/WEBSITE.md` | Topic references |
| `docs/DEVELOPMENT.md`, `docs/RELEASING.md` | How to build, test, and release |
| `docs/ROADMAP.md` | Status, candidates, and known issues |
| `docs/VALIDATION.md` | Verification status |
| `CHANGELOG.md` | User-visible changes by release |
| `docs/release-notes/<version>/` | Release notes shown in the update window, one Markdown file per language |

- Documents describe the current state. When behavior changes, rewrite the affected text instead of appending history; history belongs in `CHANGELOG.md` and Git.
- A change that affects behavior, scope, data sources, dependencies, or paths updates the matching documents in the same change. If documents disagree, `PRODUCT.md` wins over `ARCHITECTURE.md`, which wins over the topic documents; fix the other one.
- A change to scope, data sources, or architecture is proposed and approved before implementation, and recorded in `PRODUCT.md` or `ROADMAP.md`.

## Commits

- Commit only when asked. One change per commit, as `<type>(<scope>): <summary>` in the imperative.
- When requirements are unclear, present the options instead of guessing.
