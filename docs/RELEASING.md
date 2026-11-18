# Releasing

Coinscal is distributed as a Developer ID-signed, notarized zip and DMG from `dl.coinscal.app` and GitHub Releases, and updates itself with Sparkle. Only the output of `make mac-release-notarized` is distributed.

## Prerequisites

| Item | Setup |
|---|---|
| Signing | `DEVELOPMENT_TEAM` in `local.mk` and the Team's "Developer ID Application" certificate in the keychain (`DEVELOPER_ID` selects one if there are several) |
| Notarization | In `local.mk`: `NOTARY_PROFILE` (created once with `xcrun notarytool store-credentials`), or `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` with the `.p8` key outside the repository |
| Update signing key | `make mac-update-keys BACKUP=<file outside the repository>`, once |
| Sparkle tools | `make sparkle-tools` downloads `generate_keys` and `sign_update` 2.10.0 into `Build/Sparkle/`, checked against a pinned SHA-256 |
| Upload | Wrangler signed in with R2 access (`make site-login`) and the GitHub CLI signed in (`gh auth login`) |
| Hosting | Cloudflare R2 bucket `coinscal-dl`, served only through the custom domain `dl.coinscal.app` |

Release commands need a logged-in GUI session (the DMG layout is written through Finder) and no mounted volume named "Coinscal".

## Steps

1. **Version.** In `Apple/project.yml`, raise `CURRENT_PROJECT_VERSION` for every distributed build and `MARKETING_VERSION` for a new version. They are defined nowhere else.
2. **Catalog.** Run `make catalog` to refresh the coin catalog, then `make test`.
3. **Notes.** Write the release notes in `docs/release-notes/<version>/`: `en.md`, `zh-Hans.md`, and `zh-Hant.md`, one `- item` per line, with the same items in every language. `make test-mac` checks every version. Add the release to `CHANGELOG.md`.
4. **Build.** `make mac-release-notarized` produces `Build/macOS/Dist/Coinscal-<version>.zip` and `.dmg`.
5. **Publish.** `make mac-publish DRY_RUN=1` checks and renders without uploading; then `make mac-publish CONFIRM=<version>`.

## Build and Notarization

`scripts/release/release.sh`:

- Builds the Release configuration with manual Developer ID signing, Hardened Runtime, and secure timestamps; no provisioning profile is needed.
- Re-signs Sparkle's nested code with the Developer ID, innermost first and without `--deep`: `Installer.xpc`, `Downloader.xpc` (entitlements preserved), `Autoupdate`, `Updater.app`, `Sparkle.framework`, then the app.
- Verifies the app, the widget, and Sparkle's components: Developer ID of this Team, Hardened Runtime, timestamp, no `get-task-allow`.
- Notarizes and staples the app, builds the zip and DMG from the stapled app, notarizes and staples the DMG, and checks both with `spctl`. On failure it prints the notarization log.

`make mac-release` stops before notarization. Its output is blocked by Gatekeeper on other Macs and is only for local testing.

The DMG (`scripts/dmg/make-dmg.sh`) has a rendered background (`render-background.swift`, 660×420pt), a volume icon (`render-volume-icon.swift`), and a Finder layout with the app at (180, 250) and Applications at (480, 170); the size and coordinates appear in both scripts and must change together. The layout script must not call Finder's `update`, which removes the custom volume icon.

## Publishing

`make mac-publish CONFIRM=<version>` (`scripts/release/publish.py`):

1. Checks that the notarized zip and DMG exist and are stapled, the build number is higher than the live appcast's, and the release notes are complete.
2. Signs the zip with Sparkle's EdDSA key from the login Keychain and renders `appcast.xml` and the notes pages into `Build/macOS/Publish/<version>/`. `DRY_RUN=1` stops here.
3. Uploads the archives, `Coinscal.dmg`, the notes, and finally the feeds (`appcast.<lang>.xml`, then `appcast.xml`), so a feed never points to a missing file.
4. Creates the GitHub Release `v<version>` with the zip and DMG.

| Object on `dl.coinscal.app` | Content | Cache |
|---|---|---|
| `appcast.<lang>.xml` | Feed for one in-app language, with only that language's release notes; read by current builds | 5 minutes |
| `appcast.xml` | Feed with release notes in every language; read by 1.0 and 1.0.1 | 5 minutes |
| `Coinscal-<version>.zip` | Notarized app; what Sparkle downloads | Immutable |
| `Coinscal-<version>.dmg` | Notarized DMG | Immutable |
| `Coinscal.dmg` | Copy of the latest DMG, linked from the website | 5 minutes |
| `notes/<version>.<lang>.html` | Release notes per language | Immutable |

The appcast item carries `sparkle:version` (the build number), `sparkle:shortVersionString`, `sparkle:minimumSystemVersion` 14.0, the zip with its EdDSA signature and length, and the release notes link: one per language in `appcast.xml`, only its own in `appcast.<lang>.xml`.

## Keys and Secrets

- The EdDSA private key lives in the login Keychain (account `com.gicek.coinscal`) and in an offline backup; `update-keys.sh` refuses to write the backup inside the repository. Only the public key (`SUPublicEDKey`) is committed. Losing the key strands installed copies on their version. To restore it on another Mac: `Build/Sparkle/2.10.0/dist/bin/generate_keys --account com.gicek.coinscal -f <backup>`.
- Cloudflare credentials stay in Wrangler's user configuration or `CLOUDFLARE_API_TOKEN`; Apple credentials stay in `local.mk` or the keychain. None of them go into the repository.
