// Offline checks for the website: formatting matches the app, every key the pages use exists, the CSP still
// allows the inline scripts, and the demo's settings tolerate bad saved values. Run with `npm run check`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { formatPercent, formatPrice, formatShort } from "../js/format.js";
import { LINKS, SITE_URL } from "../js/config.js";
import { DEFAULT_SETTINGS, loadSettings, menubarCoin, priceColor } from "../js/panel.js";
import { COINS } from "../js/coins.js";

const site = fileURLToPath(new URL("..", import.meta.url));
const read = (path) => readFileSync(`${site}/${path}`, "utf8");
const pages = readdirSync(site).filter((f) => f.endsWith(".html"));
const messages = JSON.parse(read("messages/en.json"));
const lookup = (key) => key.split(".").reduce((node, part) => node?.[part], messages);

test("prices format like the app's PriceFormatter", () => {
    assert.equal(formatPrice(67234.56), "67,235");
    assert.equal(formatPrice(3456.7), "3,457");
    assert.equal(formatPrice(42.1), "42.10");
    assert.equal(formatPrice(0.5), "0.5000");
    assert.equal(formatPrice(0.12345678), "0.123457");
    assert.equal(formatShort(67234.56), "67,235");
    assert.equal(formatShort(42.1), "42.1");
    assert.equal(formatShort(0.5), "0.5");
    assert.equal(formatPercent(1.234), "+1.23%");
    assert.equal(formatPercent(0), "+0.00%");
    assert.equal(formatPercent(-2.5), "-2.50%");
});

test("every message key used in the pages exists", () => {
    for (const page of pages) {
        const html = read(page);
        for (const [, key] of html.matchAll(/data-(?:i18n|i18n-aria|i18n-title|i18n-content|title-key)="([^"]+)"/g)) {
            assert.equal(typeof lookup(key), "string", `${page}: ${key}`);
        }
    }
});

test("the CSP allows each page's inline script", () => {
    const csp = read("_headers");
    for (const page of pages) {
        for (const [, script] of read(page).matchAll(/<script>([\s\S]*?)<\/script>/g)) {
            const hash = createHash("sha256").update(script).digest("base64");
            assert.ok(csp.includes(`'sha256-${hash}'`), `${page}: inline script hash ${hash} is missing from _headers`);
        }
    }
});

test("outbound links are HTTPS", () => {
    assert.match(SITE_URL, /^https:\/\//);
    for (const [key, url] of Object.entries(LINKS)) {
        if (url) assert.match(url, /^https:\/\//, key);
    }
});

test("every demo coin has a logo", () => {
    const logos = new Set(readdirSync(`${site}/img/coins`));
    for (const coin of COINS) assert.ok(logos.has(`${coin.id}.png`), coin.id);
});

test("demo coins are the app's recommended coins, with catalog ids and names", () => {
    const app = `${site}/../Apple/Mac/Resources`;
    const recommended = JSON.parse(readFileSync(`${app}/recommendedCoins.json`, "utf8"));
    assert.deepEqual(COINS.map((c) => c.symbol), recommended);
    const catalog = JSON.parse(readFileSync(`${app}/coins.json`, "utf8")).coins.filter((c) => c.listed);
    for (const coin of COINS) {
        const entry = catalog.find((c) => c.symbol === coin.symbol);
        assert.deepEqual([coin.id, coin.name], [entry?.id, entry?.name], coin.symbol);
    }
    const logos = readdirSync(`${site}/img/coins`).map((f) => f.replace(/\.png$/, "")).sort();
    assert.deepEqual(logos, COINS.map((c) => c.id).sort(), "no logos left over from earlier lists");
});

test("release notes cover every language with the same items", () => {
    const dir = `${site}/releases`;
    const files = readdirSync(dir, { withFileTypes: true }).filter((e) => e.isFile() && e.name.endsWith(".json"));
    for (const { name } of files) {
        const data = JSON.parse(read(`releases/${name}`));
        assert.equal(`${data.version}.json`, name, `${name}: version doesn't match the file name`);
        const counts = ["en", "zh-Hans", "zh-Hant"].map((lang) => {
            const items = data.notes?.[lang];
            assert.ok(Array.isArray(items) && items.length && items.every((i) => typeof i === "string" && i.trim()), `${name}: ${lang}`);
            return items.length;
        });
        assert.equal(new Set(counts).size, 1, `${name}: languages have different item counts`);
    }
});

test("demo settings fall back field by field", () => {
    const store = new Map();
    globalThis.localStorage = { getItem: (k) => store.get(k) ?? null, setItem: (k, v) => store.set(k, v) };
    try {
        assert.deepEqual(loadSettings(), DEFAULT_SETTINGS);
        store.set("coinscal.demo", JSON.stringify({ coins: ["solana", "nope", "solana"], currency: "XYZ", colorEnabled: false, scheme: 3 }));
        const s = loadSettings();
        assert.deepEqual(s.coins, ["solana"]);
        assert.equal(s.currency, "USD");
        assert.equal(s.colorEnabled, false);
        assert.equal(s.scheme, "greenUpRedDown");
        store.set("coinscal.demo", "{not json");
        assert.deepEqual(loadSettings(), DEFAULT_SETTINGS);
    } finally {
        delete globalThis.localStorage;
    }
});

test("price colors and the menu bar coin follow the app's rules", () => {
    const s = { ...DEFAULT_SETTINGS };
    assert.equal(priceColor(s, 1), "#2CBD84");
    assert.equal(priceColor(s, -1), "#F6465D");
    assert.equal(priceColor({ ...s, scheme: "redUpGreenDown" }, 1), "#F6465D");
    assert.equal(priceColor({ ...s, colorEnabled: false }, 1), null);
    assert.equal(priceColor(s, null), null);
    assert.equal(menubarCoin(s).symbol, "BTC");
    assert.equal(menubarCoin({ ...s, menubarCoin: "solana" }).symbol, "BTC");
    assert.equal(menubarCoin({ ...s, menubarContent: "icon" }), null);
    assert.equal(menubarCoin({ ...s, coins: [] }), null);
});
