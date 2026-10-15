#!/usr/bin/env python3
"""Generate and validate the coin catalog coins.json (plan: docs/COIN_CATALOG.md).

    generate  CoinGecko top 250 by market cap ∩ USDT spot pairs on Binance/OKX/Bybit → first 100 tradable (listed);
                        every id from the previous catalog is kept (migrated / delisted / tradable outside the top 100) so existing watchlists keep working.
    validate  same rules as the client; CI must pass it before publishing.

Standard library only. Optional COINGECKO_API_KEY (Demo key) raises the rate limit.
"""
import argparse
import datetime
import json
import os
import re
import statistics
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

SCHEMA_VERSION = 1
TARGET_LISTED = 100
MIN_LISTED = 50
MAX_LISTED = 150
# Exchange price vs CoinGecko price beyond this ratio means a different coin with the same symbol; skipped
MAX_PRICE_DEVIATION = 0.20
# Binance still returns halted pairs with their last price; a 24h window that ended longer ago is halted (same as the app)
BINANCE_STALE_SECONDS = 3600
QUOTE_SYMBOL = "USDT"
LOGO_HOSTS = {"coin-images.coingecko.com", "assets.coingecko.com"}
ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]{0,79}$")
SYMBOL_PATTERN = re.compile(r"^[A-Z0-9]{1,15}$")
STATUSES = {"active", "delisted", "migrated"}
COINGECKO = "https://api.coingecko.com/api/v3"


def fetch_json(url, headers=None, attempts=4):
    """GET JSON, retrying 429 and network errors with backoff."""
    for attempt in range(attempts):
        request = urllib.request.Request(url, headers={
            "User-Agent": "coinscal-catalog/1",
            "Accept": "application/json",
            **(headers or {}),
        })
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code == 429 and attempt < attempts - 1:
                time.sleep(30 * (attempt + 1))
                continue
            raise
        except urllib.error.URLError:
            if attempt < attempts - 1:
                time.sleep(5)
                continue
            raise
    raise RuntimeError("unreachable")


def coingecko_headers():
    key = os.environ.get("COINGECKO_API_KEY", "").strip()
    return {"x-cg-demo-api-key": key} if key else {}


def coingecko_markets(**params):
    query = urllib.parse.urlencode({"vs_currency": "usd", **params})
    return fetch_json(f"{COINGECKO}/coins/markets?{query}", coingecko_headers())


def exchange_prices():
    """USDT spot pairs currently tradable on the three exchanges: symbol → [prices...]."""
    prices = {}

    def add(symbol, price):
        try:
            value = float(price)
        except (TypeError, ValueError):
            return
        if value > 0:
            prices.setdefault(symbol, []).append(value)

    fresh_after = (time.time() - BINANCE_STALE_SECONDS) * 1000
    for item in fetch_json("https://api.binance.com/api/v3/ticker/24hr"):
        if item["symbol"].endswith("USDT") and item["closeTime"] >= fresh_after:
            add(item["symbol"][:-4], item["lastPrice"])
    for item in fetch_json("https://www.okx.com/api/v5/market/tickers?instType=SPOT")["data"]:
        if item["instId"].endswith("-USDT"):
            add(item["instId"][:-5], item["last"])
    for item in fetch_json("https://api.bybit.com/v5/market/tickers?category=spot")["result"]["list"]:
        if item["symbol"].endswith("USDT"):
            add(item["symbol"][:-4], item["lastPrice"])
    return prices


def tradable(market, prices):
    """Whether the coin trades under the same symbol and its price agrees with CoinGecko (no symbol collisions)."""
    symbol = market["symbol"].upper()
    if not SYMBOL_PATTERN.match(symbol):
        return False  # non-ASCII symbols (exchanges also list meme coins with Chinese names) cannot be priced by symbol
    if symbol == QUOTE_SYMBOL:
        return True
    if symbol not in prices or not market.get("current_price"):
        return False
    deviation = abs(statistics.median(prices[symbol]) - market["current_price"]) / market["current_price"]
    return deviation <= MAX_PRICE_DEVIATION


def logo_url(url):
    if not url:
        return None
    return url if urllib.parse.urlparse(url).hostname in LOGO_HOSTS else None


def entry(market, status, listed, migrated_to=None):
    coin = {
        "id": market["id"],
        "symbol": market["symbol"].upper(),
        "name": market["name"],
        "rank": market.get("market_cap_rank"),
        "logoURL": logo_url(market.get("image") or market.get("logoURL")),
        "status": status,
        "listed": listed,
    }
    if migrated_to:
        coin["migratedTo"] = migrated_to
    return coin


def load_previous(path):
    """Reads the previous catalog; also accepts the legacy top100coins.json array."""
    if not path or not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as file:
        data = json.load(file)
    coins = data["coins"] if isinstance(data, dict) else data
    return {coin["id"]: coin for coin in coins}


def generate(previous_path, migrations_path):
    with open(migrations_path, encoding="utf-8") as file:
        migrations = {old: value["to"] for old, value in json.load(file)["migrations"].items()}
    previous = load_previous(previous_path)
    prices = exchange_prices()
    markets = [m for m in coingecko_markets(order="market_cap_desc", per_page=250, page=1) if m.get("market_cap_rank")]
    markets.sort(key=lambda m: m["market_cap_rank"])

    catalog = {}
    for market in markets:
        if sum(1 for c in catalog.values() if c["listed"]) >= TARGET_LISTED:
            break
        symbol = market["symbol"].upper()
        if market["id"] in migrations or not tradable(market, prices):
            continue
        # One coin per symbol (prices are looked up by symbol, duplicates would mix them up)
        if any(c["symbol"] == symbol for c in catalog.values()):
            continue
        catalog[market["id"]] = entry(market, "active", True)

    # Ids from the previous catalog that are no longer in the top 100, plus migration targets: fetch current metadata by id
    needed = (set(previous) | set(migrations.values()) | set(migrations)) - set(catalog)
    current = {}
    needed_list = sorted(needed)
    for start in range(0, len(needed_list), 100):
        chunk = needed_list[start:start + 100]
        for market in coingecko_markets(ids=",".join(chunk), per_page=250):
            current[market["id"]] = market

    listed_symbols = {c["symbol"] for c in catalog.values()}
    # Decide migration targets first: if the target is not tradable, replacing would not give a price either, so the old coin counts as delisted
    def target_active(target):
        if target in catalog:
            return catalog[target]["status"] == "active"
        return target in current and tradable(current[target], prices) and current[target]["symbol"].upper() not in listed_symbols

    for coin_id in sorted(set(migrations.values()) - set(catalog)):
        if coin_id in current and target_active(coin_id):
            catalog[coin_id] = entry(current[coin_id], "active", False)
            listed_symbols.add(catalog[coin_id]["symbol"])

    for coin_id in needed_list:
        if coin_id in catalog:
            continue
        if coin_id not in previous and coin_id not in migrations.values():
            continue  # an old id from the migration table that was never in the catalog does not need to be kept
        market = current.get(coin_id) or previous.get(coin_id)
        if market is None:
            continue
        if coin_id in migrations and target_active(migrations[coin_id]):
            catalog[coin_id] = entry(market, "migrated", False, migrations[coin_id])
        elif coin_id in migrations:
            catalog[coin_id] = entry(market, "delisted", False)
        elif coin_id in current and tradable(current[coin_id], prices) and market["symbol"].upper() not in listed_symbols:
            catalog[coin_id] = entry(market, "active", False)
        else:
            catalog[coin_id] = entry(market, "delisted", False)

    coins = sorted(catalog.values(), key=lambda c: (not c["listed"], c["rank"] or 10**9, c["id"]))
    return {
        "schemaVersion": SCHEMA_VERSION,
        "generatedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "coins": coins,
    }


def validate(catalog):
    """Same rules as the client CoinCatalog; returns the problems found, empty when valid."""
    problems = []
    if catalog.get("schemaVersion") != SCHEMA_VERSION:
        return [f"schemaVersion must be {SCHEMA_VERSION}"]
    coins = catalog.get("coins")
    if not isinstance(coins, list):
        return ["coins must be an array"]
    ids = [c.get("id") for c in coins]
    if len(ids) != len(set(ids)):
        problems.append("duplicate id")
    by_id = {c.get("id"): c for c in coins}
    listed = [c for c in coins if c.get("listed")]
    if not MIN_LISTED <= len(listed) <= MAX_LISTED:
        problems.append(f"listed count {len(listed)} not in {MIN_LISTED}–{MAX_LISTED}")
    for required in ("bitcoin", "ethereum"):
        coin = by_id.get(required)
        if not coin or not coin.get("listed") or coin.get("status") != "active":
            problems.append(f"missing tradable {required}")
    active_symbols = [c["symbol"] for c in coins if c.get("status") == "active" and isinstance(c.get("symbol"), str)]
    duplicated = {s for s in active_symbols if active_symbols.count(s) > 1}
    if duplicated:
        problems.append(f"duplicate tradable symbols: {sorted(duplicated)}")
    for coin in coins:
        cid = coin.get("id", "?")
        if not isinstance(coin.get("id"), str) or not ID_PATTERN.match(coin["id"]):
            problems.append(f"{cid}: invalid id")
        if not isinstance(coin.get("symbol"), str) or not SYMBOL_PATTERN.match(coin["symbol"]):
            problems.append(f"{cid}: invalid symbol")
        if not isinstance(coin.get("name"), str) or not 0 < len(coin["name"]) <= 60:
            problems.append(f"{cid}: invalid name")
        if coin.get("status") not in STATUSES:
            problems.append(f"{cid}: invalid status")
        if coin.get("rank") is not None and not (isinstance(coin["rank"], int) and coin["rank"] > 0):
            problems.append(f"{cid}: invalid rank")
        logo = coin.get("logoURL")
        if logo is not None and urllib.parse.urlparse(logo).hostname not in LOGO_HOSTS:
            problems.append(f"{cid}: logo host not allowed")
        if coin.get("listed") and coin.get("status") != "active":
            problems.append(f"{cid}: a listed coin must be active")
        target = coin.get("migratedTo")
        if coin.get("status") == "migrated":
            if not target or target not in by_id:
                problems.append(f"{cid}: migratedTo must point to a coin in the catalog")
            elif by_id[target].get("status") != "active":
                problems.append(f"{cid}: migration target {target} is not tradable")
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    gen = sub.add_parser("generate")
    gen.add_argument("--previous", help="previous catalog (every id in it is kept)")
    gen.add_argument("--migrations", required=True)
    gen.add_argument("--out", required=True)
    val = sub.add_parser("validate")
    val.add_argument("path")
    args = parser.parse_args()

    if args.command == "validate":
        with open(args.path, encoding="utf-8") as file:
            problems = validate(json.load(file))
    else:
        catalog = generate(args.previous, args.migrations)
        problems = validate(catalog)
        if not problems:
            with open(args.out, "w", encoding="utf-8") as file:
                json.dump(catalog, file, ensure_ascii=False, indent=2)
                file.write("\n")
            listed = sum(1 for c in catalog["coins"] if c["listed"])
            counts = {s: sum(1 for c in catalog["coins"] if c["status"] == s) for s in sorted(STATUSES)}
            print(f"wrote {args.out}: {len(catalog['coins'])} coins, listed {listed}, status {counts}")
    for problem in problems:
        print(f"✗ {problem}", file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
