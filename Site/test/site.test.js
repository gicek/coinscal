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
import { language, setLanguage } from "../js/i18n.js";
import { PriceFeed } from "../js/prices.js";
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
    assert.equal(formatPrice(0.00000012345), "1.23e-7");
    assert.equal(formatShort(67234.56), "67,235");
    assert.equal(formatShort(100.5), "100");
    assert.equal(formatShort(0.000012345), "1.23e-5");
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
    const appColors = readFileSync(new URL("../../Apple/Mac/App/Constants.swift", import.meta.url), "utf8");
    const up = appColors.match(/upColorHex = "(#[A-F0-9]{6})"/)[1];
    const down = appColors.match(/downColorHex = "(#[A-F0-9]{6})"/)[1];
    assert.equal(priceColor(s, 1), up);
    assert.equal(priceColor(s, -1), down);
    assert.equal(priceColor({ ...s, scheme: "redUpGreenDown" }, 1), down);
    assert.equal(priceColor({ ...s, colorEnabled: false }, 1), null);
    assert.equal(priceColor(s, null), null);
    assert.equal(menubarCoin(s).symbol, "BTC");
    assert.equal(menubarCoin({ ...s, menubarCoin: "solana" }).symbol, "BTC");
    assert.equal(menubarCoin({ ...s, menubarContent: "icon" }), null);
    assert.equal(menubarCoin({ ...s, coins: [] }), null);
});

function replaceGlobal(t, name, value) {
    const descriptor = Object.getOwnPropertyDescriptor(globalThis, name);
    Object.defineProperty(globalThis, name, { configurable: true, value });
    t.after(() => {
        if (descriptor) Object.defineProperty(globalThis, name, descriptor);
        else delete globalThis[name];
    });
}

test("REST fills coins without a recent stream tick and cannot overwrite a newer tick", async (t) => {
    t.mock.method(Date, "now", () => 100_000);
    replaceGlobal(t, "document", { hidden: false });
    replaceGlobal(t, "navigator", { onLine: true });
    let socket;
    replaceGlobal(t, "WebSocket", class {
        constructor() { socket = this; }
        close() {}
    });
    const sendBTC = (price) => socket.onmessage({ data: JSON.stringify({ data: { s: "BTCUSDT", c: price } }) });

    const feed = new PriceFeed();
    feed.symbols = ["BTC", "HYPE"];
    feed.openStream();

    let complete;
    const waiting = new Promise((resolve) => { complete = resolve; });
    t.mock.method(globalThis, "fetch", () => waiting);
    const firstPoll = feed.tick();
    sendBTC(75);
    complete({ ok: true, json: async () => [{ symbol: "BTCUSDT", lastPrice: 70 }, { symbol: "HYPEUSDT", lastPrice: 44 }] });
    await firstPoll;
    assert.equal(feed.quote("BTC").price, 75);
    assert.equal(feed.quote("HYPE").price, 44);

    t.mock.method(Date, "now", () => 112_000);
    sendBTC(76);
    const requests = [];
    t.mock.method(globalThis, "fetch", async (url) => {
        requests.push(url);
        return { ok: true, json: async () => [{ symbol: "HYPEUSDT", lastPrice: 45 }] };
    });
    await feed.tick();
    assert.equal(requests.length, 1);
    assert.match(decodeURIComponent(requests[0]), /symbols=\["HYPEUSDT"\]/);
    assert.equal(feed.quote("HYPE").price, 45);
    assert.equal(feed.isStale("HYPE", 142_000), true);
});

test("the first failed price round ends the loading state", async (t) => {
    t.mock.method(globalThis, "fetch", async () => { throw new Error("offline"); });
    replaceGlobal(t, "navigator", { onLine: true });
    let status;
    const feed = new PriceFeed({ onStatus: (update) => { status = update; } });
    feed.symbols = ["BTC"];
    feed.reportStatus();
    assert.equal(status.loading, true);
    await feed.poll(feed.symbols);
    assert.equal(status.loading, false);
    assert.equal(status.unavailable, true);
});

test("a late language response cannot replace the user's latest choice", async (t) => {
    replaceGlobal(t, "document", {
        documentElement: { dataset: {}, classList: { remove() {} } },
        querySelectorAll: () => [],
    });
    const pending = new Map();
    t.mock.method(globalThis, "fetch", (url) => new Promise((resolve) => pending.set(url, resolve)));
    const first = setLanguage("zh-Hans", { remember: false });
    const second = setLanguage("zh-Hant", { remember: false });
    pending.get("/messages/zh-Hant.json")({ ok: true, json: async () => ({}) });
    await second;
    pending.get("/messages/zh-Hans.json")({ ok: true, json: async () => ({}) });
    await first;
    assert.equal(language(), "zh-Hant");
});
