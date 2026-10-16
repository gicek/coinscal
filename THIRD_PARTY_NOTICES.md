# Third-Party Notices

This file records every third-party dependency in Coinscal. When a dependency changes, update its locked version, license, source, purpose, and removal plan.

No third-party code dependencies yet: the app uses only Apple system frameworks.

## External data and assets (not code dependencies)

At runtime the app calls these public APIs directly. It embeds none of their code, and use is subject to each service's terms: the Binance, OKX, and Bybit public market data APIs; open.er-api.com (ExchangeRate-API); fawazahmed0/currency-api (hosted on jsDelivr and pages.dev).

The coin catalog (names, ranks, remote logo URLs) is generated from CoinGecko data. The app's "About" page credits CoinGecko as its free data terms require.

Coin logos in `Apple/Mac/Resources/Assets.xcassets/coin-*`, and the logos the app downloads from CoinGecko's image CDN for watchlist coins, are trademarks of their respective projects and are used only to identify the matching coin.

The website includes the logos of the 10 recommended coins (`Site/img/coins/`, from CoinGecko's image CDN, resized to 64 px) for the same purpose.

The X icon on the "About" page (`Assets.xcassets/brand-x.imageset`) is a trademark of X Corp. and is used only to link to this project's X account.

## Website services

The website's live demo calls the same public price and exchange rate APIs from the visitor's browser. Cloudflare hosts the site (Workers Static Assets) and counts visits with Cloudflare Web Analytics, which Cloudflare injects into pages on `coinscal.app`.

## Build and deploy tools (not shipped)

| Tool | Version | License | Use | Removal |
|---|---|---|---|---|
| Wrangler (Cloudflare) | 4.137.0, pinned in the `Makefile` and run through `npx` | MIT OR Apache-2.0 | Deploys `Site/` to Cloudflare Workers Static Assets (`make site-deploy`) | Deploy through the Cloudflare dashboard or another static host; nothing in `Site/` depends on it |
