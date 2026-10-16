// Live prices for the demo, from the same public, keyless sources as the app, in the same order:
// Binance → Binance mirror → OKX → Bybit (Constants.API). A Binance WebSocket stream keeps prices current
// between REST refreshes; while it is quiet, REST polls every 10 seconds. Coins a source lacks are filled in
// from the next one. Prices are in USDT, treated as USD.

const TIMEOUT_MS = 5000;
const POLL_MS = 10000;
const STREAM_QUIET_MS = 15000;
const ONLINE_WINDOW_MS = 30000;

const BINANCE = "https://api.binance.com/api/v3";
const BINANCE_MIRROR = "https://data-api.binance.vision/api/v3";
const BINANCE_STREAM = "wss://data-stream.binance.vision/stream";
const OKX = "https://www.okx.com/api/v5/market/ticker";
const BYBIT = "https://api.bybit.com/v5/market/tickers";

async function getJSON(url) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
    try {
        const response = await fetch(url, { signal: controller.signal, cache: "no-store" });
        if (!response.ok) throw new Error(`${response.status}`);
        return await response.json();
    } finally {
        clearTimeout(timer);
    }
}

const number = (value) => {
    const n = Number(value);
    return Number.isFinite(n) ? n : null;
};

function binanceSource(base) {
    return async (symbols) => {
        const pairs = JSON.stringify(symbols.map((s) => `${s}USDT`));
        const rows = await getJSON(`${base}/ticker/24hr?symbols=${encodeURIComponent(pairs)}`);
        const out = new Map();
        for (const row of rows) {
            const price = number(row.lastPrice);
            if (price > 0) out.set(row.symbol.replace(/USDT$/, ""), { price, change: number(row.priceChangePercent) });
        }
        return out;
    };
}

// OKX and Bybit are asked one pair at a time: their all-pairs lists are large and they are only fallbacks.
async function eachSymbol(symbols, fetchOne) {
    const out = new Map();
    const results = await Promise.allSettled(symbols.map(fetchOne));
    results.forEach((result, i) => {
        if (result.status === "fulfilled" && result.value) out.set(symbols[i], result.value);
    });
    if (!out.size) throw new Error("no prices");
    return out;
}

async function okx(symbols) {
    return eachSymbol(symbols, async (symbol) => {
        const row = (await getJSON(`${OKX}?instId=${symbol}-USDT`)).data?.[0];
        const price = number(row?.last);
        const open = number(row?.open24h);
        if (!(price > 0)) return null;
        return { price, change: open > 0 ? ((price - open) / open) * 100 : null };
    });
}

async function bybit(symbols) {
    return eachSymbol(symbols, async (symbol) => {
        const row = (await getJSON(`${BYBIT}?category=spot&symbol=${symbol}USDT`)).result?.list?.[0];
        const price = number(row?.lastPrice);
        const change = number(row?.price24hPcnt);
        if (!(price > 0)) return null;
        return { price, change: change == null ? null : change * 100 };
    });
}

// In the app's order: Binance → Binance mirror → OKX → Bybit.
const SOURCES = [binanceSource(BINANCE), binanceSource(BINANCE_MIRROR), okx, bybit];

export class PriceFeed {
    constructor({ onUpdate = () => {}, onStatus = () => {} } = {}) {
        this.onUpdate = onUpdate;
        this.onStatus = onStatus;
        this.symbols = [];
        this.quotes = new Map();
        this.lastSuccess = 0;
        this.lastStreamMessage = 0;
        this.lastPoll = 0;
        this.inFlight = false;
        this.socket = null;
        this.reconnectDelay = 2000;
        this.reconnectTimer = null;
    }

    start() {
        setInterval(() => this.tick(), 1000);
        window.addEventListener("online", () => this.tick(true));
        window.addEventListener("offline", () => this.reportStatus());
        document.addEventListener("visibilitychange", () => {
            if (!document.hidden) this.tick(true);
        });
    }

    setSymbols(symbols) {
        const next = [...new Set(symbols)];
        if (next.join() === this.symbols.join()) return;
        this.symbols = next;
        // Coins are often added a few in a row: reconnect once they settle, not on every click.
        clearTimeout(this.reconnectTimer);
        this.reconnectTimer = setTimeout(() => this.openStream(), this.socket ? 600 : 0);
        this.tick(true);
    }

    quote(symbol) {
        return this.quotes.get(symbol) ?? null;
    }

    /** Polls over REST when the stream has gone quiet. Never starts a request while one is in flight. */
    tick(force = false) {
        this.reportStatus();
        if (!this.symbols.length || this.inFlight || document.hidden) return;
        const now = Date.now();
        const streamHealthy = now - this.lastStreamMessage < STREAM_QUIET_MS;
        const missing = this.symbols.some((s) => !this.quotes.has(s));
        if (!force && !missing && (streamHealthy || now - this.lastPoll < POLL_MS)) return;
        this.poll();
    }

    async poll() {
        this.inFlight = true;
        this.lastPoll = Date.now();
        const wanted = [...this.symbols];
        let remaining = wanted;
        for (const source of SOURCES) {
            if (!remaining.length) break;
            try {
                const result = await source(remaining);
                for (const [symbol, quote] of result) this.quotes.set(symbol, quote);
                remaining = remaining.filter((s) => !result.has(s));
            } catch {
                // Try the next source in the same refresh.
            }
        }
        this.inFlight = false;
        if (remaining.length < wanted.length) {
            this.lastSuccess = Date.now();
            this.onUpdate();
        }
        this.reportStatus();
    }

    openStream() {
        clearTimeout(this.reconnectTimer);
        if (this.socket) {
            this.socket.onclose = null;
            this.socket.close();
            this.socket = null;
        }
        if (!this.symbols.length || typeof WebSocket === "undefined") return;
        const streams = this.symbols.map((s) => `${s.toLowerCase()}usdt@ticker`).join("/");
        const socket = new WebSocket(`${BINANCE_STREAM}?streams=${streams}`);
        this.socket = socket;
        socket.onmessage = (event) => {
            let data;
            try {
                data = JSON.parse(event.data).data;
            } catch {
                return;
            }
            const price = number(data?.c);
            if (!(price > 0) || typeof data.s !== "string") return;
            this.quotes.set(data.s.replace(/USDT$/, ""), { price, change: number(data.P) });
            this.lastStreamMessage = this.lastSuccess = Date.now();
            this.reconnectDelay = 2000;
            this.onUpdate();
            this.reportStatus();
        };
        socket.onclose = () => {
            this.socket = null;
            this.reconnectTimer = setTimeout(() => this.openStream(), this.reconnectDelay);
            this.reconnectDelay = Math.min(this.reconnectDelay * 2, 60000);
        };
    }

    reportStatus() {
        const online = navigator.onLine !== false && Date.now() - this.lastSuccess < ONLINE_WINDOW_MS;
        this.onStatus({ online, loading: !this.lastSuccess && !!this.symbols.length });
    }
}

// Exchange rates from USD, from the app's first two FX sources; cached for an hour.
const RATE_SOURCES = [
    async () => (await getJSON("https://open.er-api.com/v6/latest/USD")).rates,
    async () => {
        const usd = (await getJSON("https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json")).usd;
        return Object.fromEntries(Object.entries(usd).map(([code, rate]) => [code.toUpperCase(), rate]));
    },
];
const RATE_TTL_MS = 3600 * 1000;

export class ExchangeRates {
    constructor(onUpdate = () => {}) {
        this.onUpdate = onUpdate;
        this.rates = { USD: 1 };
        this.fetchedAt = 0;
        this.inFlight = null;
    }

    rate(currency) {
        if (currency === "USD") return 1;
        if (Date.now() - this.fetchedAt > RATE_TTL_MS) this.refresh();
        const rate = this.rates[currency];
        return rate > 0 ? rate : null;
    }

    refresh() {
        if (this.inFlight) return this.inFlight;
        this.inFlight = (async () => {
            for (const source of RATE_SOURCES) {
                try {
                    const rates = await source();
                    if (rates && rates.CNY > 0) {
                        this.rates = { ...rates, USD: 1 };
                        this.fetchedAt = Date.now();
                        this.onUpdate();
                        return;
                    }
                } catch {}
            }
            // Retry in a minute instead of on every render.
            this.fetchedAt = Date.now() - RATE_TTL_MS + 60000;
        })().finally(() => {
            this.inFlight = null;
        });
        return this.inFlight;
    }
}
