// The demo panel, made after Apple/Mac/Views/MenuBar/CoinPopoverView.swift in the app's points: 320 wide, a
// 38-point header, 52-point rows (at least 4 and at most 8 rows tall), and a 52-point footer. The gear and
// "Manage Watchlist" open small web-only versions of the app's settings inside the panel.
import { COINS, CURRENCIES, UP_COLOR, DOWN_COLOR, coinById } from "./coins.js";
import { formatPercent, formatPrice } from "./format.js";
import { t } from "./i18n.js";

const ROW_HEIGHT = 52;
const MIN_ROWS = 4;
const MAX_ROWS = 8;
const STORAGE_KEY = "coinscal.demo";

export const DEFAULT_SETTINGS = {
    coins: ["bitcoin", "ethereum"],
    currency: "USD",
    menubarCoin: "bitcoin",
    menubarContent: "price",
    colorEnabled: true,
    background: true,
    scheme: "greenUpRedDown",
};

export function loadSettings() {
    let saved = {};
    try {
        saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}") || {};
    } catch {}
    const s = { ...DEFAULT_SETTINGS };
    // Field by field, like AppSettings decoding: a bad field falls back to its default.
    if (Array.isArray(saved.coins)) s.coins = [...new Set(saved.coins.filter((id) => coinById(id)))];
    if (CURRENCIES.some(([code]) => code === saved.currency)) s.currency = saved.currency;
    if (coinById(saved.menubarCoin)) s.menubarCoin = saved.menubarCoin;
    if (["price", "icon"].includes(saved.menubarContent)) s.menubarContent = saved.menubarContent;
    if (typeof saved.colorEnabled === "boolean") s.colorEnabled = saved.colorEnabled;
    if (typeof saved.background === "boolean") s.background = saved.background;
    if (["greenUpRedDown", "redUpGreenDown"].includes(saved.scheme)) s.scheme = saved.scheme;
    return s;
}

function saveSettings(settings) {
    try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
    } catch {}
}

/** SettingsViewModel.priceColor: null means the default text color. */
export function priceColor(settings, change) {
    if (!settings.colorEnabled || change == null) return null;
    const up = settings.scheme === "greenUpRedDown" ? UP_COLOR : DOWN_COLOR;
    const down = settings.scheme === "greenUpRedDown" ? DOWN_COLOR : UP_COLOR;
    return change >= 0 ? up : down;
}

/** MenuBarViewModel.priceCoin: the chosen coin, or the first one, once it has a price. */
export function menubarCoin(settings) {
    if (settings.menubarContent !== "price" || !settings.coins.length) return null;
    return coinById(settings.coins.includes(settings.menubarCoin) ? settings.menubarCoin : settings.coins[0]);
}

const el = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
};

const svgUse = (id, className = "pn-glyph") => {
    const ns = "http://www.w3.org/2000/svg";
    const svg = document.createElementNS(ns, "svg");
    svg.setAttribute("class", className);
    svg.setAttribute("aria-hidden", "true");
    const use = document.createElementNS(ns, "use");
    use.setAttribute("href", `#${id}`);
    svg.append(use);
    return svg;
};

function logo(coin, size) {
    const img = el("img", "pn-logo");
    img.src = `/img/coins/${coin.id}.png`;
    img.alt = "";
    img.width = img.height = size;
    img.decoding = "async";
    return img;
}

export class Panel {
    constructor(root, { feed, rates, onChange }) {
        this.root = root;
        this.feed = feed;
        this.rates = rates;
        this.onChange = onChange;
        this.settings = loadSettings();
        this.view = "list";
        this.lastPrices = new Map();
        this.body = root.querySelector("[data-panel-body]");
        this.title = root.querySelector("[data-panel-title]");
        this.back = root.querySelector("[data-panel-back]");
        this.spinner = root.querySelector("[data-panel-spinner]");
        this.footer = root.querySelector(".pn-footer");
        this.back.addEventListener("click", () => this.show("list"));
        root.querySelector('[data-action="settings"]').addEventListener("click", () => this.toggle("settings"));
        root.querySelector('[data-action="watchlist"]').addEventListener("click", () => this.toggle("watchlist"));
    }

    get symbols() {
        return this.settings.coins.map((id) => coinById(id).symbol);
    }

    update(patch) {
        Object.assign(this.settings, patch);
        saveSettings(this.settings);
        this.onChange();
        this.render();
    }

    toggle(view) {
        this.show(this.view === view ? "list" : view);
    }

    show(view) {
        const returning = view === "list" ? this.view : null;
        this.view = view;
        this.render();
        // Keep the keyboard where it was: on the back button in a sub-view, on the button that opened it after.
        if (!this.root.contains(document.activeElement)) return;
        const target = returning ? this.root.querySelector(`.pn-footer [data-action="${returning}"]`) : this.back;
        target?.focus({ preventScroll: true });
    }

    setLoading(loading) {
        this.spinner.hidden = !loading || this.view !== "list";
    }

    bodyHeight() {
        const rows = Math.min(Math.max(this.settings.coins.length, MIN_ROWS), MAX_ROWS);
        if (this.view === "settings") return Math.max(rows, 5) * ROW_HEIGHT;
        if (this.view === "watchlist") return MAX_ROWS * ROW_HEIGHT;
        return rows * ROW_HEIGHT;
    }

    render() {
        const view = this.view;
        this.root.dataset.view = view;
        this.back.hidden = view === "list";
        this.title.textContent = view === "settings" ? t("panel.settings") : view === "watchlist" ? t("panel.watchlist") : "Coinscal";
        for (const button of this.footer.querySelectorAll("[data-action]")) {
            button.setAttribute("aria-pressed", String(button.dataset.action === view));
        }
        this.body.style.height = `${this.bodyHeight()}px`;
        const content = view === "settings" ? this.renderSettings() : view === "watchlist" ? this.renderWatchlist() : this.renderList();
        this.body.replaceChildren(content);
    }

    /** Refreshes prices in place, so a stream update doesn't rebuild the list or the settings controls. */
    refreshPrices() {
        if (this.view !== "list") return;
        if (this.body.querySelector(".pn-empty") || this.body.querySelectorAll(".pn-row").length !== this.settings.coins.length) {
            this.render();
            return;
        }
        for (const row of this.body.querySelectorAll(".pn-row")) this.fillRow(row, coinById(row.dataset.id));
    }

    renderList() {
        if (!this.settings.coins.length) {
            const empty = el("div", "pn-empty");
            empty.append(svgUse("symbol-bitcoinsign", "pn-empty-glyph"), el("p", null, t("panel.empty")));
            const add = el("button", "pn-prominent", t("panel.addCoins"));
            add.type = "button";
            add.addEventListener("click", () => this.show("watchlist"));
            empty.append(add);
            return empty;
        }
        const list = el("div", "pn-list");
        for (const id of this.settings.coins) {
            const coin = coinById(id);
            const row = el("div", "pn-row");
            row.dataset.id = id;
            const text = el("div", "pn-text");
            const top = el("div", "pn-line");
            top.append(el("span", "pn-name", coin.name), el("span", "pn-price", "--"));
            const bottom = el("div", "pn-line");
            bottom.append(el("span", "pn-symbol", coin.symbol), el("span", "pn-change"));
            text.append(top, bottom);
            row.append(logo(coin, 32), text);
            this.fillRow(row, coin);
            list.append(row);
        }
        return list;
    }

    fillRow(row, coin) {
        const quote = this.feed.quote(coin.symbol);
        const rate = this.rates.rate(this.settings.currency);
        const priceEl = row.querySelector(".pn-price");
        const changeEl = row.querySelector(".pn-change");
        if (quote && rate) {
            const price = quote.price * rate;
            const color = priceColor(this.settings, quote.change);
            const text = formatPrice(price);
            if (priceEl.textContent !== text) {
                const previous = this.lastPrices.get(coin.id);
                if (previous != null && previous !== price) {
                    priceEl.classList.remove("is-ticking");
                    void priceEl.offsetWidth;
                    priceEl.classList.add("is-ticking");
                }
                priceEl.textContent = text;
            }
            this.lastPrices.set(coin.id, price);
            priceEl.style.color = color ?? "";
            priceEl.classList.remove("is-missing");
            changeEl.textContent = quote.change == null ? "" : formatPercent(quote.change);
            changeEl.style.color = color ?? "";
        } else {
            priceEl.textContent = "--";
            priceEl.style.color = "";
            priceEl.classList.add("is-missing");
            changeEl.textContent = "";
        }
    }

    renderSettings() {
        const s = this.settings;
        const form = el("div", "pn-settings");

        const row = (labelKey, control) => {
            const line = el("label", "pn-setting");
            line.append(el("span", "pn-setting-label", t(labelKey)), control);
            return line;
        };
        const select = (options, value, onChange) => {
            const node = el("select", "pn-select");
            for (const [optionValue, label] of options) {
                const option = el("option", null, label);
                option.value = optionValue;
                option.selected = optionValue === value;
                node.append(option);
            }
            node.addEventListener("change", () => onChange(node.value));
            return node;
        };
        const toggle = (value, onChange) => {
            const node = el("input", "pn-switch");
            node.type = "checkbox";
            node.setAttribute("role", "switch");
            node.checked = value;
            node.addEventListener("change", () => onChange(node.checked));
            return node;
        };

        form.append(
            row("panel.currency", select(CURRENCIES.map(([code, symbol]) => [code, `${code} (${symbol})`]), s.currency, (currency) => this.update({ currency }))),
            row(
                "panel.menubarCoin",
                select(
                    (s.coins.length ? s.coins : [s.menubarCoin]).map((id) => [id, coinById(id).symbol]),
                    menubarCoin({ ...s, menubarContent: "price" })?.id ?? s.menubarCoin,
                    (menubarCoin) => this.update({ menubarCoin })
                )
            ),
            row(
                "panel.menubarContent",
                select([["price", t("panel.contentPrice")], ["icon", t("panel.contentIcon")]], s.menubarContent, (menubarContent) => this.update({ menubarContent }))
            ),
            row("panel.textColor", toggle(s.colorEnabled, (colorEnabled) => this.update({ colorEnabled }))),
            row("panel.textBackground", toggle(s.background, (background) => this.update({ background }))),
            row(
                "panel.colorScheme",
                select(
                    [["greenUpRedDown", t("panel.greenUpRedDown")], ["redUpGreenDown", t("panel.redUpGreenDown")]],
                    s.scheme,
                    (scheme) => this.update({ scheme })
                )
            )
        );
        return form;
    }

    renderWatchlist() {
        const list = el("div", "pn-watchlist");
        for (const coin of COINS) {
            const added = this.settings.coins.includes(coin.id);
            const row = el("div", "pn-pick");
            const text = el("div", "pn-pick-text");
            text.append(el("span", "pn-name", coin.name), el("span", "pn-symbol", coin.symbol));
            const button = el("button", "pn-pick-toggle");
            button.type = "button";
            button.setAttribute("aria-pressed", String(added));
            button.setAttribute("aria-label", t(added ? "panel.remove" : "panel.add", { name: coin.name }));
            button.append(svgUse(added ? "symbol-checkmark" : "symbol-plus"));
            button.addEventListener("click", () => {
                const coins = added ? this.settings.coins.filter((id) => id !== coin.id) : [...this.settings.coins, coin.id];
                this.update({ coins });
                this.body.querySelector(`[data-id="${coin.id}"] button`)?.focus({ preventScroll: true });
            });
            row.dataset.id = coin.id;
            row.append(logo(coin, 24), text, button);
            list.append(row);
        }
        list.append(el("p", "pn-note", t("panel.catalogNote")));
        return list;
    }
}
