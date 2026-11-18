# Coinscal

Coinscal is a macOS menu bar app for crypto prices. It shows the price of a chosen coin in the menu bar, your watchlist in a panel, desktop and Notification Center widgets, and notifies you when a price reaches your target. It has no backend, no account, and collects no data.

Website: [coinscal.app](https://coinscal.app/) · Download: [latest release](https://github.com/gicek/coinscal/releases/latest)

## Features

- **Menu bar price**: the selected coin's price, optionally colored by price change and set on a colored background, or just the app icon.
- **Watchlist panel**: click the menu bar item for the price and change of every coin in your watchlist. Choose a rolling 24-hour window or a day starting at midnight in UTC+0 or UTC+8.
- **Watchlist**: search about 450 coins (the top 1000 by market cap that trade against USDT on Binance, OKX, or Bybit), add recommended coins, and drag to reorder. Coins the catalog marks as migrated to a successor are replaced automatically.
- **Price alerts**: per coin, above or below a price, or a percentage move; delivered as system notifications.
- **Widgets**: "Coin Price" and "Watchlist" for the desktop and Notification Center. They refresh on their own, even when the app isn't running.
- **Desktop ticker**: a click-through price list pinned to the desktop, updated with the app every 10 seconds.
- **12 display currencies**: USD, CNY, KRW, HKD, JPY, TWD, SGD, MYR, AUD, CAD, EUR, GBP.
- **Reliable data**: public, key-free APIs with automatic failover between sources.
- **In-app updates**: a daily check, release notes, and signed updates installed only after you agree.
- **Languages**: English, Simplified Chinese, and Traditional Chinese, switchable without a restart.

## Requirements

macOS 14 or later on Apple silicon.

## Privacy

- Coinscal talks only to the public price and exchange rate APIs listed in [Data Sources](docs/DATA_SOURCES.md), and once a day to `dl.coinscal.app` to check for updates.
- No account, analytics, or telemetry. Settings stay on your Mac.
- Notification permission is used only for price alerts.

## Building from Source

Requires Xcode 27 and XcodeGen (`brew install xcodegen`).

```bash
make mac-run    # generate the Xcode project, build, and launch "Coinscal Debug"
make test       # localization guards, unit tests, and website checks
make help       # all commands
```

Debug builds are a separate app, "Coinscal Debug", so they run next to an installed copy. See the [Development Guide](docs/DEVELOPMENT.md).

## Documentation

| Document | Contents |
|---|---|
| [Product](docs/PRODUCT.md) | Scope, behavior of every surface, and product rules |
| [Architecture](docs/ARCHITECTURE.md) | Code structure, data flow, contracts, and platform notes |
| [Data Sources](docs/DATA_SOURCES.md) | Price and exchange rate sources, rate limits, and the coin catalog |
| [Development](docs/DEVELOPMENT.md) | Toolchain, commands, configuration, and testing |
| [Releasing](docs/RELEASING.md) | Signing, notarization, publishing, and in-app updates |
| [Localization](docs/LOCALIZATION.md) | Languages, string rules, and terminology |
| [Website](docs/WEBSITE.md) | The `coinscal.app` site and its live demo |
| [Roadmap](docs/ROADMAP.md) | Status, candidates, and known issues |
| [Validation](docs/VALIDATION.md) | Automated checks and pending manual verification |
| [Changelog](CHANGELOG.md) | Changes by release |

Contributions are welcome; see [CONTRIBUTING](CONTRIBUTING.md). Report security issues as described in [SECURITY](SECURITY.md).

## License

[MIT](LICENSE). Third-party components, data, and assets are listed in [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md).
