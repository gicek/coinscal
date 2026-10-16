# Coinscal Development Guide

Run all commands below from the repository root. For repository rules, see the [Development Rules](../AGENTS.md). For verification coverage, see [Implementation and Verification Status](VALIDATION.md).

## Toolchain

| Tool | Version | Install |
|---|---|---|
| Xcode | 26.5 (Swift 6 language mode) | App Store |
| XcodeGen | 2.45 | `brew install xcodegen` |
| Python | 3.9+ (localization guards, website preview) | Bundled with the system |
| Node.js | 20+ for website checks (CI uses 24); 22+ for Wrangler, which the Makefile picks from nvm automatically | `nvm install 24` |
| Wrangler | 4.137.0 (website deploys, run through `npx`; not installed in the repo) | Downloaded on first use by `make site-login` or `make site-deploy` |

CI (`.github/workflows/tests.yml`) runs only the repository hygiene checks, the localization guards, and the website checks. App unit tests depend on a local Xcode and run through `make test` locally. Run it before merging.

## Common Commands

Matches `make help`:

```bash
make help                   # All commands
make project                # Generate Apple/Coinscal.xcodeproj from Apple/project.yml
make mac                    # Build Build/macOS/Debug/Coinscal.app (CONFIGURATION=Release builds the release version)
make mac-run                # Build, verify code signing, and launch
make mac-release            # Release: Developer ID-signed zip and DMG in Build/macOS/Dist/ (not notarized; needs a GUI session)
make mac-release-notarized  # Release and notarize: same as above, then notarize the app and DMG, staple the tickets, and run Gatekeeper checks
make test                   # Full test suite (make test-mac + make test-site)
make test-site              # Website: localization guards + offline checks (Node 20+)
make site-run               # Website: local preview at http://localhost:8787/ with Site/_headers applied (SITE_PORT= to change)
make site-login             # Website: sign in to Cloudflare for deploys (opens a browser)
make site-whoami            # Website: show the signed-in Cloudflare account
make site-deploy CONFIRM=yes  # Website: test, then deploy Site/ to Cloudflare
make mac-check-sources      # Manual: check all price and exchange rate data sources over the real network; exits with code 1 on failure
make catalog                # Regenerate the built-in coin catalog online (run before a release; set COINGECKO_API_KEY for a higher rate limit)
make clean                  # Delete Build/ and fallback outputs in the source tree
```

Builds use `-quiet` by default; for full output, run `make mac XCODEBUILD_FLAGS=`. Judge test results by the `** TEST SUCCEEDED **` result line.

To develop in Xcode: run `make project` first, then open `Apple/Coinscal.xcodeproj` with the `CoinscalMac` scheme. Run `make project` again after adding or removing source files.

## Output Paths

| Content | Path |
|---|---|
| Debug / Release app | `Build/macOS/<Configuration>/Coinscal.app` |
| DerivedData | `Build/macOS/DerivedData/` |
| Tests | `Build/macOS/Tests/` |
| Distribution packages | `Build/macOS/Dist/` |

## Local Configuration

Copy `local.mk.example` to `local.mk` (not committed). With `DEVELOPMENT_TEAM` empty, builds use local ad-hoc signing. Once set, builds are signed with a real certificate, so TCC state such as notification authorization persists across builds. The App Group that the widget and app use to share data is also available only with a Team set (with it empty, the widget can only fetch prices itself).

## Version Numbers

Change `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` only in `Apple/project.yml`. Increment the build number for every distributed build.

## Release

1. Packaging: both `make mac-release` (sign only) and `make mac-release-notarized` (sign and notarize) produce `Build/macOS/Dist/Coinscal-<version>.zip` and `.dmg`. The flow is in `scripts/release/release.sh`.
   `scripts/dmg/make-dmg.sh` generates the DMG: `scripts/dmg/render-background.swift` renders the background on the fly (660×420pt, 1x / 2x combined into a TIFF, not committed), and the Finder layout is written to the volume's `.DS_Store` via AppleScript. The window size and icon coordinates (app 180,250; Applications 480,170) are written separately in both scripts; change them together. `scripts/dmg/render-volume-icon.swift` generates the volume icon by overlaying the main part of the logo on the system removable disk icon. Don't call Finder's `update` in the layout script: on macOS 26 it deletes `.VolumeIcon.icns` and clears the volume's custom icon flag.
2. Code signing and notarization:
   - Code signing: Release builds are signed manually with a `Developer ID Application` certificate (`CODE_SIGN_STYLE=Manual`, no embedded provisioning profile) with a secure `--timestamp`. Hardened Runtime is enabled for all configurations in `project.yml`. The App Group uses the Team prefix (`<TeamID>.com.gicek.coinscal`); Developer ID doesn't need a provisioning profile. Prerequisites: `DEVELOPMENT_TEAM` set in `local.mk`, and that Team's Developer ID Application certificate in the keychain (if there are several, give the full name in `DEVELOPER_ID`).
   - The script first verifies the app and the embedded widget: Developer ID, this Team, Hardened Runtime, timestamp, no `get-task-allow`. It fails if any check fails.
   - Notarization (only `mac-release-notarized`): it first zips the app, submits it to `notarytool`, and staples the ticket to the app, so the app inside the zip passes even offline. It then builds the zip and DMG from the stapled app, signs the DMG, submits it for notarization, and staples the DMG. Finally `spctl` verifies the app as `Notarized Developer ID` and checks that the DMG passes. On failure it prints the notarization log and exits with an error.
   - Put one of two notarization credentials in `local.mk`: `NOTARY_PROFILE` (first run `xcrun notarytool store-credentials <name> --apple-id <Apple ID> --team-id <Team ID>` once and enter an app-specific password), or `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_PATH` (keep the .p8 outside the repository). Missing credentials fail before the build starts.
   - Output from `make mac-release` is blocked by Gatekeeper on first launch on other Macs; use it only locally or for internal testing. Use only `make mac-release-notarized` for public distribution.
3. Upload: attach the zip and DMG to a GitHub Release (no upload command yet). Update `Apple/Mac/docs/CHANGELOG.md` before releasing.

## Website

- `Site/` is served as-is: there is no build step and nothing goes to `Build/`. `Site/.assetsignore` keeps `wrangler.jsonc`, `package.json`, `test/`, and `docs/` from being served.
- Preview with `make site-run`, not by opening the files: pages load `/messages/*.json` and use root-relative paths, and the preview applies the CSP from `Site/_headers` so a blocked request shows up locally.
- Deploying publishes the site, so `make site-deploy` requires `CONFIRM=yes`. It runs `make test-site` first, then `wrangler deploy` from `Site/`. Sign in once with `make site-login` (`make site-whoami` shows the account), or set `CLOUDFLARE_API_TOKEN` (Workers Scripts edit, plus Workers Routes and DNS for the custom domains) in the environment. Never commit the token.
- Custom domains `coinscal.app` and `coinscal.gicek.com` are declared in `Site/wrangler.jsonc` (`custom_domain: true`); both zones must be in the account Wrangler is signed in to. Binding a custom domain fails if the hostname already has DNS records; delete them first. Cloudflare Web Analytics is enabled on the `coinscal.app` zone and injects its script there; the CSP in `Site/_headers` allows it. Wrangler keeps local state in `Site/.wrangler/` (ignored, removed by `make clean`).
- The Open Graph image `Site/og.jpg` (1200×630) is a screenshot of the hero; retake it when the hero changes.

## Common Pitfalls

- Run both release commands in a logged-in GUI session (for the DMG layout). The first run triggers an automation permission prompt to allow controlling Finder. If a volume named Coinscal is already mounted, the script refuses to continue; eject it first.
- A Coinscal instance already running on this Mac has the same Bundle ID as a new build, so the instance launched later exits immediately (single-instance protection). Quit the release version before debugging.
- Unit tests run with the app as the host. When `AppDelegate` detects `XCTestConfigurationFilePath`, it does no setup. The many `com.apple.linkd.autoShortcut` connection errors in the test log are system noise from the sandboxed test host and can be ignored.
