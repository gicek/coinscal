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
- **Market cap rank must be intersected with exchanges**: the top 100 by market cap includes coins that don't trade on Binance / OKX / Bybit (stablecoins, RWA, exchange tokens). Taking the top N directly would produce many entries without prices.
- **Clients don't call CoinGecko directly**: the keyless API has a very low rate limit, so users behind the same egress IP would crowd each other out, and if the API starts requiring a key, the key can't ship in the client. So the catalog is generated centrally on the repository side, and clients only read a static file.

## Generation Rules

`generate_catalog.py generate` (`make catalog`):

1. Take the CoinGecko top 250 by market cap.
2. Intersect with USDT spot pairs currently tradable on all three exchanges: drop Binance halted pairs; symbols must be ASCII; an exchange price deviating > 20% from the CoinGecko price counts as a different coin with the same name and is dropped; only one entry per symbol.
3. Take the top 100 by market cap as `listed`.
4. Keep every id from the previous catalog as a non-`listed` entry: still tradable → `active`; in the migration table with a tradable target → `migrated`; everything else → `delisted`.
5. The result is checked with `validate` first and written only if it passes.

The optional environment variable `COINGECKO_API_KEY` (a CoinGecko Demo Key) raises the rate limit.

## Client

- `CoinCatalog` is the only source of coin metadata, injected into `CoinListViewModel`, `WatchlistViewModel`, and the right-click menu.
- Search and recommendations use only `listed`; the watchlist looks up any entry by id.
- `active` coins are included in price fetches; `delisted` coins show "No market data"; `migrated` coins are not shown: old ids in the watchlist are automatically replaced with the successor that `migratedTo` points to (`CoinCatalog.settingsWithSuccessors`; for the rules, see "Projects Migrated to a Successor Coin" in [DESIGN](DESIGN.md)).
- Logo: uses the local image when a bundled `coin-<id>` asset exists, otherwise the remote URL from the catalog (host allowlist).
- Validation rules exist in both Python and Swift and must match (see [TECHNICAL](TECHNICAL.md)).

## Remote Updates (Not Implemented)

- A scheduled repository job (GitHub Actions, daily) runs the generation script. After validation and checks of the same kind as `make mac-check-sources` pass, it publishes to a separate `catalog` branch.
- The client fetches from jsDelivr every 24 hours (with ETag). Load order is sandbox cache → bundled snapshot. If the remote file fails validation, the whole file is discarded and the current catalog stays in use. The cache is written atomically.
- Risk control: the catalog contains only metadata; prices still come from exchanges. The client validates structure and ranges and enforces the logo host allowlist.

External conditions (to be done by the repository owner): make the repository public; configure `COINGECKO_API_KEY` as an Actions secret.

## Acceptance Checklist

- First launch offline: uses the bundled snapshot, and the UI is complete.
- Remote catalog corrupt or missing `bitcoin`: discarded; the current catalog stays in use.
- Watchlist contains `render-token`: shows RENDER with a price.
- Watchlist contains `matic-network`: after launch it automatically shows as POL with a price, with no migration prompt; change alerts are kept, and above / below alerts reset to the default.
- `make mac-check-sources`: PASS, and every listed coin has a price.
