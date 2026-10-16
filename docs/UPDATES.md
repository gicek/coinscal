# In-App Updates

> Status: approved and implemented 2026-10-16; 1.0 published with the updater. The first update between two published builds is pending verification (see [VALIDATION](VALIDATION.md)). Decisions: Sparkle 2 as the update engine; update files on Cloudflare R2 at `dl.coinscal.app`; automatic daily checks that ask before installing; release notes in all three UI languages.

## Goal

Users of the direct download get new versions without visiting the website: Coinscal checks for updates once a day, shows the release notes, and installs and relaunches after the user agrees. Every update is verified twice: Sparkle's EdDSA signature on the archive and Apple code signing with the same Team ID.

Not in scope: beta or other update channels; delta updates (the zip is about 1.3 MB); updates for builds that aren't notarized.

## Options Considered

| Option | Result |
|---|---|
| **Sparkle 2** (chosen) | The standard updater for directly distributed Mac apps (MIT). Signed archives, standard update UI, sandbox support through its installer XPC service, download, replace, and relaunch handled. Cost: the first third-party code dependency, about 3 MB added to the app. |
| Custom "check only" | Reads a version file and opens the download page; the user installs the DMG by hand. No dependency, but no real in-app installation: a sandboxed app can't safely replace its own bundle. |

| Hosting | Result |
|---|---|
| **R2 bucket + custom domain** (chosen) | Cloudflare R2 holds the appcast and the archives; free tier (10 GB storage, no egress fees). Served at `https://dl.coinscal.app/`. GitHub Releases gets the same zip and DMG. |
| Appcast on the website, archives on GitHub Releases | No R2, but GitHub downloads can be slow or blocked in some regions. |

## Design

### Feed and files

R2 bucket `coinscal-dl`, public only through the custom domain `dl.coinscal.app` (set up 2026-10-16, minimum TLS 1.2). The domain serves file downloads and nothing else: the `r2.dev` public URL stays disabled, there is no directory listing, and only the objects below are published:

| Object | Content | Cache |
|---|---|---|
| `appcast.xml` | Sparkle feed with the latest release only | `max-age=300` |
| `Coinscal-<version>.zip` | Notarized, stapled app; what Sparkle downloads | immutable |
| `Coinscal-<version>.dmg` | Notarized DMG for manual installs | immutable |
| `Coinscal.dmg` | Copy of the latest DMG; the website's download button points here | `max-age=300` |
| `notes/<version>.<lang>.html` | Release notes, one file per UI language, rendered from `Site/releases/<version>.json` | immutable |

Appcast item fields: `sparkle:version` = `CURRENT_PROJECT_VERSION` (must increase with every release), `sparkle:shortVersionString` = `MARKETING_VERSION`, `sparkle:minimumSystemVersion` = `14.0`, the zip enclosure with `sparkle:edSignature` and `length`, and one `sparkle:releaseNotesLink xml:lang="…"` per language (`en`, `zh-Hans`, `zh-Hant`).

### App

- Sparkle 2.10.0 through Swift Package Manager, pinned in `Apple/project.yml`, linked into `CoinscalMac` only (not the widget extension).
- `Info.plist`: `SUFeedURL` = `https://dl.coinscal.app/appcast.xml`; `SUPublicEDKey`; `SUEnableInstallerLauncherService` = YES; `SUEnableAutomaticChecks` = YES (no "check automatically?" prompt); `SUScheduledCheckInterval` = 86400; automatic installation stays off, so every update asks first. No system profile is sent.
- Entitlements: `com.apple.security.temporary-exception.mach-lookup.global-name` with `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` and `$(PRODUCT_BUNDLE_IDENTIFIER)-spki`. The Downloader XPC service stays off because the app already has `network.client`.
- `UpdateController` (`Services/UpdateService.swift`) holds the state the UI shows and talks to an `UpdaterBackend` protocol: `SparkleUpdaterBackend` wraps `SPUStandardUpdaterController` in the app, and tests use `FakeUpdaterBackend`. In the unit-test host no backend is attached, so no updater starts and every update action is disabled.
- Coinscal has no Dock icon, so a scheduled check that finds an update doesn't pop a window over the user's work ("gentle reminders"): the popover header shows an "Update Available" capsule, and clicking it opens Sparkle's update window. A check the user starts shows the window at once.

### User interface

- Right-click menu: "Check for Updates…" (between About and Quit).
- Settings → About: version, "Check for Updates…" button, "Automatically Check for Updates" toggle (Sparkle stores this preference itself; it isn't part of `AppSettings`).
- Popover header: an "Update Available" capsule when a scheduled check found one.
- New strings in `Localizable.xcstrings` in all three languages. Sparkle's own windows use its bundled translations, which follow the system language, not Coinscal's in-app language setting.

### Release flow

`make mac-publish CONFIRM=<version>` runs after `make mac-release-notarized`:

1. Checks that the notarized zip and DMG for `<version>` exist in `Build/macOS/Dist/`, the build number is higher than the one in the live appcast, and release notes exist in all three languages.
2. Signs the zip with Sparkle's `sign_update` (EdDSA private key from the login Keychain) and writes `appcast.xml` and the release notes pages into `Build/macOS/Publish/<version>/`. `make mac-publish DRY_RUN=1` stops here.
3. Uploads the zip, DMG, `Coinscal.dmg`, release notes, and finally `appcast.xml` to R2, so the feed never points at a file that isn't there yet.
4. Creates the GitHub Release `v<version>` with the zip and DMG.

`scripts/release/release.sh` also signs Sparkle's nested code with the Developer ID before notarization, innermost first and without `--deep`: `Installer.xpc`, `Downloader.xpc`, `Autoupdate`, `Updater.app`, then `Sparkle.framework`, then the app. Its existing checks extend to these components.

Sparkle's command-line tools (`sign_update`, `generate_keys`) come from the pinned Sparkle release archive, downloaded into `Build/Sparkle/` and checked against its SHA-256 (`make sparkle-tools`).

Release notes are written per release in `Site/releases/<version>.json`, with the same keys in `en`, `zh-Hans`, and `zh-Hant`; publishing fails if a language is missing.

### Keys and secrets

- The EdDSA key pair is created once by the maintainer with `make mac-update-keys BACKUP=<file>` (Keychain account `com.gicek.coinscal`). The private key lives in the login Keychain, and the exported backup goes offline; the script refuses to write it inside the repository. Losing the key means existing installs can't verify new updates. Only the public key is committed (`SUPublicEDKey`).
- R2 uploads use Wrangler (`make site-login`) or an R2 API token in the environment. No credentials in the repository.

## Changes by Area

| Area | Change |
|---|---|
| App | Sparkle package, `UpdateController` and `SparkleUpdaterBackend`, menu item, About pane controls, popover header capsule, Info.plist keys, entitlements, strings |
| Release | `release.sh` signs Sparkle components; new `scripts/release/publish.py` and `make mac-publish` |
| Website | Download button points to `https://dl.coinscal.app/Coinscal.dmg`; privacy page mentions the daily update check |
| Docs | PROJECT (decision, privacy principle wording), DESIGN (menu, About pane, popover header), TECHNICAL (update flow, data source table), DEVELOPMENT (keys, R2, publish), THIRD_PARTY_NOTICES (Sparkle 2.10.0, MIT), README privacy, VALIDATION |

## Risks

1. **The update path can't be tested end to end until two versions with the updater exist**: no version has been published yet, so the first public release already includes Sparkle and is installed by hand; publishing the next build is the first real in-app update.
2. **Signing nested Sparkle code** is the most common cause of notarization and sandbox failures; the release script's checks must cover every component.
3. **Losing the EdDSA private key** strands existing users on their current version until they reinstall by hand.

## Acceptance Checklist

- Unit tests (`UpdateControllerTests`): actions are disabled without a backend; checks are forwarded only when the backend can check; the automatic-check preference reaches the backend; the reminder shows until handled.
- `make mac-release-notarized` passes with Sparkle embedded; `codesign` and `spctl` checks cover the XPC service and helpers.
- With version N installed from the DMG and N+1 published: a manual check offers N+1 with release notes in the system language; installing replaces the app, relaunches it, and settings, watchlist, widgets, and login item survive.
- A scheduled check shows "Update Available" in the popover without opening a window.
- An archive with a bad EdDSA signature or a different Team ID is rejected.
- Offline, or with `dl.coinscal.app` unreachable, a check fails quietly and the app keeps working.
- The website's download button serves the latest DMG.

