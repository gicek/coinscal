# Development

Run every command from the repository root. Repository rules are in [AGENTS.md](../AGENTS.md).

## Toolchain

| Tool | Version | Notes |
|---|---|---|
| Xcode | 27 (macOS 27 SDK) | Required: the app uses macOS 27 APIs behind availability checks |
| XcodeGen | 2.46.0 | `brew install xcodegen` or the pinned release archive |
| Python | 3.9+ | Localization guards, catalog tools, website preview |
| Node.js | 20+ for website checks; 22+ for Wrangler | The Makefile picks the newest nvm-installed Node 22+ for Wrangler |

If `xcode-select` points to the Command Line Tools, set `export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer` in `local.mk`. Release tooling is listed in [Releasing](RELEASING.md).

## Commands

```bash
make project        # generate Apple/Coinscal.xcodeproj from Apple/project.yml
make mac            # build Build/macOS/Debug/Coinscal.app (CONFIGURATION=Release for a release build)
make mac-run        # build, verify the signature, and launch
make test           # make test-mac + make test-site + make test-release
make test-mac       # localization guards, catalog and release notes validation, unit tests
make test-site      # website localization guards and offline checks
make test-release   # offline release script checks
make site-run       # website preview at http://localhost:8787/
make mac-check-sources  # manual check of every data source over the network
make catalog        # regenerate the coin catalog online
make clean          # delete Build/
make help           # everything else
```

Builds run with `-quiet`; pass `XCODEBUILD_FLAGS=` for full output. Judge test runs by the `** TEST SUCCEEDED **` line, not by an exit code after a pipe.

To work in Xcode, run `make project` and open `Apple/Coinscal.xcodeproj` with the `CoinscalMac` scheme. Run `make project` again after adding or removing files or changing `project.yml`; never edit `project.pbxproj` by hand.

## Local Configuration

Copy `local.mk.example` to `local.mk` (ignored by Git) for machine-specific settings. Without `DEVELOPMENT_TEAM`, builds are signed ad hoc: the App Group is unavailable, so widgets fetch their own prices and nothing is shared, and permissions such as notifications reset with every build. With a Team, builds use a real certificate.

## Debug Builds

Debug builds are a separate app, "Coinscal Debug", with their own bundle IDs, App Group, settings, and URL scheme ([Architecture](ARCHITECTURE.md#build-configurations)). They run next to an installed Coinscal, and the widget gallery lists both. The first launch uses default settings. Debug builds check for updates only on request, since they can't install a release build. Two debug builds still exclude each other.

`make test-mac` unregisters its test host app from Launch Services afterwards, so the system offers only the widget of `Build/macOS/Debug`.

## Output

| Content | Path |
|---|---|
| Apps | `Build/macOS/<Configuration>/Coinscal.app` |
| DerivedData | `Build/macOS/DerivedData/` |
| Tests | `Build/macOS/Tests/` |
| Release archives | `Build/macOS/Dist/` |
| Rendered appcast and notes | `Build/macOS/Publish/<version>/` |
| Sparkle tools | `Build/Sparkle/<version>/` |

Nothing is built inside source directories, and `Build/` is never committed.

## Testing

- Unit tests use Swift Testing and run with the debug app as host; `AppDelegate` skips all setup when `XCTestConfigurationFilePath` is set.
- Tests inject test doubles instead of system services ([Architecture](ARCHITECTURE.md#testing)).
- The `com.apple.linkd.autoShortcut` connection errors in test logs come from the sandboxed host and can be ignored.
- CI runs repository hygiene, localization, release script, and website checks on Linux. The `xcode-27` ARM64 job runs `make test-mac` and checks the generated Xcode project. Run `make test` locally before merging.

## Website

`Site/` is served as is, with no build step. Preview with `make site-run` rather than opening files: pages load `/messages/*.json` with root-relative paths, and the preview applies the CSP from `Site/_headers`. Deployment is described in [Website](WEBSITE.md).
