// The landing page: a Mac menu bar at the top of the hero (Coinscal, language, Wi-Fi, appearance, clock) over
// a live demo of the app's panel.
import { LINKS } from "./config.js";
import { formatShort } from "./format.js";
import { detectLanguage, language, onLanguageChange, setLanguage, t } from "./i18n.js";
import { ExchangeRates, PriceFeed } from "./prices.js";
import { Panel, menubarCoin, priceColor } from "./panel.js";

const $ = (selector, root = document) => root.querySelector(selector);

// MARK: Links

for (const a of document.querySelectorAll("[data-link]")) {
    const href = LINKS[a.dataset.link];
    if (href) {
        a.href = href;
    } else {
        a.removeAttribute("href");
        a.setAttribute("aria-disabled", "true");
    }
}

// MARK: Appearance

const THEME_KEY = "coinscal.theme";
const prefersDark = matchMedia("(prefers-color-scheme: dark)");
const isDark = () => (document.documentElement.dataset.theme || (prefersDark.matches ? "dark" : "light")) === "dark";

const appearance = $("[data-appearance]");
if (appearance) {
    appearance.hidden = false;
    appearance.addEventListener("click", () => {
        const next = isDark() ? "light" : "dark";
        // Choosing what the system already shows clears the override, so the page follows the system again.
        const matchesSystem = (next === "dark") === prefersDark.matches;
        if (matchesSystem) delete document.documentElement.dataset.theme;
        else document.documentElement.dataset.theme = next;
        try {
            if (matchesSystem) localStorage.removeItem(THEME_KEY);
            else localStorage.setItem(THEME_KEY, next);
        } catch {}
    });
}

// MARK: Language menu

const langButton = $("[data-lang-button]");
const langMenu = $("[data-lang-menu]");

function closeLangMenu({ focus = false } = {}) {
    if (!langMenu || langMenu.hidden) return;
    langMenu.hidden = true;
    langButton.setAttribute("aria-expanded", "false");
    if (focus) langButton.focus();
}

function renderLangMenu() {
    if (!langMenu) return;
    $("[data-lang-short]").textContent = t("lang.short");
    for (const item of langMenu.querySelectorAll("[data-lang]")) {
        item.setAttribute("aria-checked", String(item.dataset.lang === language()));
    }
}

if (langButton && langMenu) {
    langButton.addEventListener("click", () => {
        const open = langMenu.hidden;
        langMenu.hidden = !open;
        langButton.setAttribute("aria-expanded", String(open));
        if (open) langMenu.querySelector('[aria-checked="true"]')?.focus();
    });
    langMenu.addEventListener("click", (event) => {
        const item = event.target.closest("[data-lang]");
        if (!item) return;
        closeLangMenu({ focus: true });
        setLanguage(item.dataset.lang);
    });
    langMenu.addEventListener("keydown", (event) => {
        const items = [...langMenu.querySelectorAll("[data-lang]")];
        const index = items.indexOf(document.activeElement);
        if (event.key === "ArrowDown" || event.key === "ArrowUp") {
            event.preventDefault();
            const step = event.key === "ArrowDown" ? 1 : -1;
            items[(index + step + items.length) % items.length].focus();
        }
    });
    document.addEventListener("click", (event) => {
        if (!event.target.closest("[data-lang-root]")) closeLangMenu();
    });
    document.addEventListener("keydown", (event) => {
        if (event.key === "Escape") closeLangMenu({ focus: true });
    });
}

// MARK: Clock

const clock = $("[data-clock]");
const clockDate = $("[data-clock-date]");
const clockTime = $("[data-clock-time]");

function renderClock() {
    if (!clock) return;
    const now = new Date();
    const lang = language();
    if (lang === "en") {
        const parts = new Intl.DateTimeFormat("en-US", { weekday: "short", month: "short", day: "numeric" }).formatToParts(now);
        const part = (type) => parts.find((p) => p.type === type)?.value ?? "";
        clockDate.textContent = `${part("weekday")} ${part("month")} ${part("day")}`;
    } else {
        const locale = lang === "zh-Hant" ? "zh-TW" : "zh-CN";
        const date = new Intl.DateTimeFormat(locale, { month: "long", day: "numeric" }).format(now);
        const weekday = new Intl.DateTimeFormat(locale, { weekday: "short" }).format(now);
        clockDate.textContent = `${date} ${weekday}`;
    }
    const locale = lang === "en" ? "en-US" : lang === "zh-Hant" ? "zh-TW" : "zh-CN";
    clockTime.textContent = new Intl.DateTimeFormat(locale, { hour: "numeric", minute: "2-digit" }).format(now);
    clock.dateTime = now.toISOString();
}

function scheduleClock() {
    renderClock();
    setTimeout(scheduleClock, 60000 - (Date.now() % 60000) + 50);
}

// MARK: Prices, the panel, and the Coinscal item

const hero = $("[data-hero]");
const panelRoot = $("[data-panel]");
const item = $("[data-panel-toggle]");
const itemLabel = $("[data-item-label]");
const wifi = $("[data-wifi]");

const rates = new ExchangeRates(() => refresh());
const feed = new PriceFeed({ onUpdate: () => refresh(), onStatus: (status) => renderStatus(status) });
const panel = panelRoot ? new Panel(panelRoot, { feed, rates, onChange: () => settingsChanged() }) : null;

function renderItem() {
    if (!item || !panel) return;
    const settings = panel.settings;
    const coin = menubarCoin(settings);
    const quote = coin ? feed.quote(coin.symbol) : null;
    const rate = rates.rate(settings.currency);
    if (!coin || !quote || !rate) {
        item.dataset.mode = "icon";
        item.style.removeProperty("--item-color");
        itemLabel.textContent = "";
        item.setAttribute("aria-label", t("menubar.item"));
        return;
    }
    const price = formatShort(quote.price * rate);
    const color = priceColor(settings, quote.change);
    item.dataset.mode = settings.background ? (color ? "fill" : "inverse") : color ? "tint" : "plain";
    if (color) item.style.setProperty("--item-color", color);
    else item.style.removeProperty("--item-color");
    itemLabel.textContent = `${coin.symbol} ${price}`;
    item.setAttribute("aria-label", t("menubar.itemPrice", { symbol: coin.symbol, price }));
}

let lastStatus = { online: false, loading: true };

function renderStatus(status) {
    lastStatus = status;
    panel?.setLoading(status.loading);
    if (wifi) {
        wifi.dataset.state = status.online ? "online" : "offline";
        wifi.setAttribute("aria-label", t(status.online ? "menubar.online" : "menubar.offline"));
        wifi.title = wifi.getAttribute("aria-label");
    }
}

function refresh() {
    panel?.refreshPrices();
    renderItem();
}

function settingsChanged() {
    feed.setSymbols(panel.symbols);
    if (panel.settings.currency !== "USD") rates.refresh();
    renderItem();
    layoutPanel();
}

// MARK: Panel open and closed

function setPanelOpen(open) {
    hero.dataset.panelState = open ? "open" : "closed";
    item.setAttribute("aria-expanded", String(open));
    layoutPanel();
}

// Keep the panel on screen: it hangs from the Coinscal item, and moves left when the window is too narrow.
// On narrow layouts the copy moves down by the panel's height instead of sitting under it.
function layoutPanel() {
    if (!panelRoot || !hero) return;
    const slot = $(".panel-slot");
    slot.style.setProperty("--shift", "0px");
    const rect = panelRoot.getBoundingClientRect();
    const gutter = parseFloat(getComputedStyle(hero).getPropertyValue("--gutter")) || 16;
    const overflow = rect.right - (document.documentElement.clientWidth - gutter);
    const scale = rect.width / panelRoot.offsetWidth || 1;
    slot.style.setProperty("--shift", `${Math.max(0, overflow / scale)}px`);
    const open = hero.dataset.panelState === "open";
    hero.style.setProperty("--panel-space", open ? `${Math.ceil(slot.getBoundingClientRect().height)}px` : "0px");
}

if (item && panel) {
    item.addEventListener("click", () => setPanelOpen(hero.dataset.panelState !== "open"));
    $('[data-action="quit"]', panelRoot).addEventListener("click", () => {
        setPanelOpen(false);
        item.focus();
    });
    new ResizeObserver(() => layoutPanel()).observe(panelRoot);
    new ResizeObserver(() => layoutPanel()).observe(item);
    addEventListener("resize", () => layoutPanel());
}

// The wallpaper layers drift slightly with the pointer.
if (hero && matchMedia("(pointer: fine)").matches && !matchMedia("(prefers-reduced-motion: reduce)").matches) {
    hero.addEventListener("pointermove", (event) => {
        const box = hero.getBoundingClientRect();
        hero.style.setProperty("--pointer-x", ((event.clientX - box.left) / box.width - 0.5).toFixed(3));
        hero.style.setProperty("--pointer-y", ((event.clientY - box.top) / box.height - 0.5).toFixed(3));
    });
}

// MARK: Start

onLanguageChange(() => {
    renderLangMenu();
    renderClock();
    panel?.render();
    renderItem();
    renderStatus(lastStatus);
    layoutPanel();
});

await setLanguage(detectLanguage(), { remember: false });
scheduleClock();

if (panel) {
    panel.render();
    feed.setSymbols(panel.symbols);
    if (panel.settings.currency !== "USD") rates.refresh();
    feed.start();
    setPanelOpen(true);
}
