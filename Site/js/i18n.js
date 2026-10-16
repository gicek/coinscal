// Three UI languages, switched in place. Messages live in messages/<lang>.json (checked by scripts/i18n-guard.py);
// the HTML carries the English text and data-i18n keys, so the page reads fine before any script runs.
export const LANGS = ["en", "zh-Hans", "zh-Hant"];
const STORAGE_KEY = "coinscal.lang";
const HTML_LANG = { en: "en", "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant" };

let current = "en";
let messages = {};
const listeners = new Set();

export function detectLanguage() {
    try {
        const saved = localStorage.getItem(STORAGE_KEY);
        if (LANGS.includes(saved)) return saved;
    } catch {}
    for (const tag of navigator.languages || [navigator.language || "en"]) {
        const lower = tag.toLowerCase();
        if (lower.startsWith("zh")) {
            return /hant|-tw|-hk|-mo/.test(lower) ? "zh-Hant" : "zh-Hans";
        }
        if (lower.startsWith("en")) return "en";
    }
    return "en";
}

export const language = () => current;

/** Looks up a dotted key; {name} placeholders are filled from params. Falls back to the key itself. */
export function t(key, params = {}) {
    const value = key.split(".").reduce((node, part) => (node == null ? undefined : node[part]), messages);
    if (typeof value !== "string") return key;
    return value.replace(/\{(\w+)\}/g, (_, name) => (name in params ? String(params[name]) : `{${name}}`));
}

async function load(lang) {
    const response = await fetch(`/messages/${lang}.json`);
    if (!response.ok) throw new Error(`messages ${lang}: ${response.status}`);
    return response.json();
}

export function apply(root = document) {
    for (const el of root.querySelectorAll("[data-i18n]")) el.textContent = t(el.dataset.i18n);
    for (const el of root.querySelectorAll("[data-i18n-aria]")) el.setAttribute("aria-label", t(el.dataset.i18nAria));
    for (const el of root.querySelectorAll("[data-i18n-title]")) el.title = t(el.dataset.i18nTitle);
    for (const el of root.querySelectorAll("[data-i18n-content]")) el.content = t(el.dataset.i18nContent);
    const titleKey = document.documentElement.dataset.titleKey;
    if (titleKey) document.title = t(titleKey);
}

export async function setLanguage(lang, { remember = true } = {}) {
    if (!LANGS.includes(lang)) lang = "en";
    try {
        messages = await load(lang);
        current = lang;
    } catch {
        // Keep whatever is on screen; the HTML's English stays readable.
        document.documentElement.classList.remove("i18n-pending");
        if (!Object.keys(messages).length) return;
    }
    if (remember) {
        try { localStorage.setItem(STORAGE_KEY, current); } catch {}
    }
    document.documentElement.lang = HTML_LANG[current];
    apply();
    document.documentElement.classList.remove("i18n-pending");
    for (const fn of listeners) fn(current);
}

export function onLanguageChange(fn) {
    listeners.add(fn);
}
