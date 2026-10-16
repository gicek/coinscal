# Coinscal Website Changelog

Features added, changed, fixed, and removed, newest first. Third-level headings start with Added / Changed / Fixed / Removed; fixes describe the symptom, root cause, fix, and tests.

## 2026-10-16

### Added: Product website with a live menu bar demo
A static site in `Site/`, deployed to `coinscal.app` and `coinscal.gicek.com` on Cloudflare Workers Static Assets. The hero is a Mac menu bar (Coinscal, language, Wi-Fi, appearance, clock) with a reproduction of the app's popover hanging from the Coinscal item, showing live prices from the app's data sources: a Binance WebSocket stream, with 10-second REST polling in the app's source order when the stream fails. The panel's gear and "Manage Watchlist" open web-only demo settings and a coin picker; the menu bar price shows its background by default. Below the hero: four feature cards, a privacy section (no account, no data collection, private by design, open source), and the download section. English, Simplified Chinese, and Traditional Chinese, switchable in place; light and dark. Also a privacy page and a 404 page. Visits are counted with cookieless Cloudflare Web Analytics, which the CSP allows and the privacy page discloses.

- Plain HTML, CSS, and JavaScript modules: no framework, build step, or npm dependencies. Deployed with `make site-deploy CONFIRM=yes`; Wrangler runs on the newest nvm-installed Node 22+.
- Design and data rules: [WEBSITE](../../docs/WEBSITE.md).
- Tests: `Site/test/site.test.js` (7), run by `make test-site` with the localization guards.
