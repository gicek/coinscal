# Coinscal

A lightweight macOS menu bar app for crypto prices. It keeps your watchlist prices and 24h change in the menu bar and sends a system notification when a price hits your target. No backend, no account, no data collection.

## Features

- **Menu bar prices**: Shows the current price of the selected coin, colored by direction (green up / red down, red up / green down, or custom), with an optional background tint. Can also show only the app icon.
- **Watchlist popover**: Left-click to see the price and 24h change of every coin in your watchlist. Right-click to quickly switch the menu bar coin.
- **Watchlist management**: Search about 450 tradable coins (the top 1000 by market cap that trade on Binance, OKX, or Bybit) or add from recommended coins, and drag the handle to reorder. When a project migrates to a successor coin (e.g. MATIC → POL), the app switches to the new coin automatically.
- **Desktop and Notification Center widgets**: Price and 24h change for a single coin or your watchlist. You can edit the coin, quote currency, sort order, and colors. Widgets update on their own even when the app isn't running.
- **Desktop ticker**: Pins prices to the desktop like a sticky note. Mouse clicks pass straight through, it blends into the wallpaper, and it updates with the app every 10 seconds.
- **Price alerts**: Set above, below, or percent-change alerts per coin. A triggered alert sends a system notification.
- **Multiple quote currencies**: USD, CNY, KRW, HKD, JPY, TWD, SGD, MYR, AUD, CAD, EUR, GBP, with automatic exchange rate conversion.
- **Multi-source failover**: Switches automatically when any price or exchange rate data source is unavailable. No API key needed.
- **Launch at login** and **multiple languages**: English / Simplified Chinese / Traditional Chinese, switchable instantly while running.

## Requirements

| Item | Requirement |
|---|---|
| System | macOS 14 or later, Apple silicon |
| Development | Xcode 26.5, XcodeGen (`brew install xcodegen`) |

## Quick Start

```bash
make mac-run                # Generate the project, build, and launch
make test                   # Localization guards + unit tests
make mac-release            # Release: Developer ID-signed zip and DMG in Build/macOS/Dist/
make mac-release-notarized  # Release and notarize: sign, notarize, and staple the ticket
make help                   # All commands
```

After launch, the BTC price appears in the menu bar. Left-click to open the watchlist popover, then use "Manage Watchlist" in the bottom bar to add coins and set alerts.

## Data Sources

The app calls public, key-free APIs directly and fails over in order:

| Type | Source |
|---|---|
| Prices | Binance → Binance mirror (data-api.binance.vision) → OKX → Bybit |
| Exchange rates | open.er-api.com → jsDelivr currency-api → currency-api.pages.dev (cached for 1 hour) |
| Coin catalog | Built-in snapshot, generated from CoinGecko market cap ranks and the spot listings of the three exchanges (`make catalog`) |

Only coins quoted in USDT with a spot pair on the exchanges above are supported.

## Privacy

- No servers, no sign-up, no data collected or uploaded.
- Network requests go only to the public APIs above (the sandbox grants only `network.client`).
- Settings stay on your Mac.
- The app requests notification permission only for price alerts.

## Development

```
Apple/
├── project.yml          # XcodeGen source → Coinscal.xcodeproj
└── Mac/                 # App source (App / Models / Services / ViewModels / Views / Utilities / Resources)
    ├── Tests/           # Unit tests (Swift Testing)
    └── docs/CHANGELOG.md
docs/                    # Project docs
scripts/                 # Localization guard, DMG, release, coin catalog
Build/                   # All build output (not committed)
```

## Documentation

- [Development rules](AGENTS.md)
- [Project definition](docs/PROJECT.md) · [Interaction design](docs/DESIGN.md) · [Technical architecture](docs/TECHNICAL.md) · [Roadmap](docs/ROADMAP.md)
- [Work plan](docs/PLAN.md) · [Implementation and verification status](docs/VALIDATION.md) · [Development guide](docs/DEVELOPMENT.md) · [Localization](docs/LOCALIZATION.md)
- [Changelog](Apple/Mac/docs/CHANGELOG.md) · [Third-party notices](THIRD_PARTY_NOTICES.md)

## License

[MIT](LICENSE). Third-party data and assets are listed in [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md).
