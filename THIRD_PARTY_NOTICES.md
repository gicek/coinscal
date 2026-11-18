# Third-Party Notices

## Code

| Component | Version | License | Use |
|---|---|---|---|
| [Sparkle](https://github.com/sparkle-project/Sparkle) | 2.10.0 (Swift Package pinned in `Apple/project.yml`, `Package.resolved` committed) | MIT | In-app updates |

Everything else in the app uses Apple system frameworks. The About pane lists Sparkle under open source components.

## Tools (not shipped)

| Tool | Version | License | Use |
|---|---|---|---|
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | 2.46.0, enforced by the Makefile and checksum-verified in CI | MIT | Generates the Xcode project |
| Wrangler (Cloudflare) | 4.137.0, pinned in the `Makefile`, run through `npx` | MIT OR Apache-2.0 | Website deployment and release uploads |
| Sparkle command-line tools | 2.10.0 release archive, SHA-256 pinned in the `Makefile` | MIT | Update signing key and archive signatures |

## Data and Services

- The app and the website demo call the public market data APIs of Binance, OKX, and Bybit, open.er-api.com (ExchangeRate-API), and fawazahmed0/currency-api (served by jsDelivr and Cloudflare Pages), subject to each provider's terms. No code from them is included. ExchangeRate-API is credited with the link its terms require.
- The coin catalog (names, ranks, logo URLs) is generated from CoinGecko data, credited in the About pane.
- The website is hosted on Cloudflare, which also provides its cookieless Web Analytics.

## Trademarks

- Coin logos bundled in `Apple/Mac/Resources/Assets.xcassets/coin-*` and `Site/img/coins/`, and those downloaded from CoinGecko's image CDN, are trademarks of their projects and are used only to identify the coins.
- The X logo in the About pane (`brand-x.imageset`) is a trademark of X Corp. and links to the project's X account.
