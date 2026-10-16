# Coin Catalog

> Feature design: how the coin catalog used by the watchlist, search, and recommendations is generated, validated, and updated. For the data contract, see "Coin Catalog" in [Technical Architecture](TECHNICAL.md); for implementation status, see [Implementation and Verification Status](VALIDATION.md).

## Status

| Part | Status |
|---|---|
| Generation script `scripts/catalog/generate_catalog.py`, `make catalog` | Implemented |
| Bundled snapshot `Apple/Mac/Resources/coins.json` and client `CoinCatalog` | Implemented |
| Delisted status, automatic replacement of old coins with successors | Implemented |
| Runtime remote updates (scheduled generation + jsDelivr distribution) | Not started; waiting on external conditions (see the end of this document) |

## Goals and Non-Goals

- Goals: renamed symbols, coins newly entering the top ranks, and old-to-successor coin mappings reach users. A usable catalog is always available offline, on first launch, and when the remote fetch fails.
- Non-goals: letting users enter arbitrary trading pairs; any server-side capability unrelated to the catalog (accounts, sync, push).

## Design Rationale

- **CoinGecko id is the identity**: the watchlist stores ids (`WatchlistCoin.coinId`). When a coin is renamed, its id stays the same and its symbol changes (for example, `render-token` went from RNDR to RENDER, and `iota` from MIOTA to IOTA). Refreshing the symbol by id restores quotes, and users don't need to change their watchlist.
- **Old-to-successor mappings need manual maintenance**: a project that moves to a new coin gets a new id (for example, `matic-network`→`polygon-ecosystem-token`). The old id still exists but no longer trades, so this can't be detected automatically. `scripts/catalog/migrations.json` maintains these mappings; in the catalog the old id is marked `migrated` and points to the new id through `migratedTo`.
- **Market cap rank must be intersected with exchanges**: the top ranks by market cap include coins that don't trade on Binance / OKX / Bybit (stablecoins, RWA, exchange tokens). Taking the top N directly would produce many entries without prices.
- **Clients don't call CoinGecko directly**: the keyless API has a very low rate limit, so users behind the same egress IP would crowd each other out, and if the API starts requiring a key, the key can't ship in the client. So the catalog is generated centrally on the repository side, and clients only read a static file.

## Generation Rules

`generate_catalog.py generate` (`make catalog`):

1. Take the CoinGecko top 1000 by market cap (four pages of 250).
2. Intersect with USDT spot pairs currently tradable on any of the three exchanges: drop Binance halted pairs; symbols must be ASCII; an exchange price deviating > 20% from the CoinGecko price counts as a different coin with the same name and is dropped; only one entry per symbol.
3. Every remaining coin is `listed` (searchable).
4. Keep every id from the previous catalog (`--previous`, which `make catalog` always passes) as a non-`listed` entry: still tradable → `active`; in the migration table with a tradable target → `migrated`; everything else → `delisted`. A migration target is kept only when an old id that moves to it is kept.
5. The result is checked with `validate` first and written only if it passes.

The optional environment variable `COINGECKO_API_KEY` (a CoinGecko Demo Key) raises the rate limit.

The bundled snapshot has 451 coins, all listed and `active`, down to market cap rank 957 (about 120KB). It was generated without `--previous` before the first release, so it carries no `delisted` or `migrated` entries yet. Always regenerate with `make catalog`, which passes `--previous`, so that ids in existing watchlists are kept.

## Client

- `CoinCatalog` is the only source of coin metadata, injected into `CoinListViewModel`, `WatchlistViewModel`, and the right-click menu.
- Search and recommendations use only `listed`; the watchlist looks up any entry by id.
- `active` coins are included in price fetches; `delisted` coins show "No market data"; `migrated` coins are not shown: old ids in the watchlist are automatically replaced with the successor that `migratedTo` points to (`CoinCatalog.settingsWithSuccessors`; for the rules, see "Projects Migrated to a Successor Coin" in [DESIGN](DESIGN.md)).
- Logo: see "Logos" below.
- Validation rules exist in both Python and Swift and must match (see [TECHNICAL](TECHNICAL.md)).

## Logos

Only 78 logos ship in the app (`coin-<id>` assets, about 640KB, mostly the top coins); bundling all of them would grow the app for coins most users never add. The rest are fetched on demand:

- When a coin enters the watchlist (and at every launch for coins already in it), `CoinLogoStore` downloads its `logoURL` once through the injected `HTTPClient` and stores it in the App Group container (`CoinLogos/<id>.img`, `CoinLogoCache`). Only HTTPS URLs on the logo host allowlist are fetched; the response must be HTTP 200, at most 512KB, and decode as an image. A failed download is retried at the next launch or watchlist change.
- When a coin leaves the watchlist, its cached logo is deleted. Coins with a bundled asset are never downloaded.
- Lookup order everywhere: bundled asset → cached file → remote URL (`AsyncImage`, e.g. while browsing the add panel) → symbol placeholder. The widget and the desktop ticker can't load remote images while rendering, so they use bundled → cached → placeholder.
- Without an App Group (unsigned builds) there is no cache and nothing is downloaded; views fall back to the remote URL.

## Remote Updates (Not Implemented)

- A scheduled repository job (GitHub Actions, daily) runs the generation script. After validation and checks of the same kind as `make mac-check-sources` pass, it publishes to a separate `catalog` branch.
- The client fetches from jsDelivr every 24 hours (with ETag). Load order is sandbox cache → bundled snapshot. If the remote file fails validation, the whole file is discarded and the current catalog stays in use. The cache is written atomically.
- Risk control: the catalog contains only metadata; prices still come from exchanges. The client validates structure and ranges and enforces the logo host allowlist.

External conditions (to be done by the repository owner): make the repository public; configure `COINGECKO_API_KEY` as an Actions secret.

## Acceptance Checklist

- First launch offline: uses the bundled snapshot, and the UI is complete.
- Remote catalog corrupt or missing `bitcoin`: discarded; the current catalog stays in use.
- Watchlist contains `render-token`: shows RENDER with a price.
- Watchlist contains `matic-network` (with a catalog that still has it as `migrated`, e.g. from a remote update): after launch it automatically shows as POL with a price, with no migration prompt; change alerts are kept, and above / below alerts reset to the default.
- `make mac-check-sources`: PASS, and every listed coin has a price.
