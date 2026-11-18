# Validation

What is verified and what still needs a manual check. Update this file when a check runs or a change adds manual work.

## Automated Checks

Last run Nov 18, 2026.

| Check | Result |
|---|---|
| `make test-mac` | Localization guards (45 files), catalog validation, 118 unit tests in 15 suites: pass |
| `make test-site` | Localization guards (7 files), 9 offline checks: pass |
| `make mac-check-sources` (Oct 16, 2026) | All 4 price and 3 exchange rate sources respond; all 450 catalog symbols priced; failover with Binance unreachable takes one round |
| CI | Repository hygiene, localization guards, website checks |

## Verified on a Real Mac

macOS 27.2.1 with a debug build, unless noted.

- Menu bar price, panel, right-click menu, and all Settings panes; settings survive an upgrade; instant language switching; no alerts on currency changes; notifications; login item; delisted and renamed coins (macOS 26, 1.0).
- Panel: toggles reliably from the status item with a trackpad; closes on outside clicks, Esc, right click, app switching, and Settings; opens from `coinscal://popover`; looks like the system popover in light mode.
- Right-click menu shows text only.
- Menu bar price stays sharp on an inactive display, with and without a background.
- The app no longer requests periodic widget reloads (none in 6 minutes, down from one every 5 minutes); "Coinscal" and "Coinscal Debug" widgets coexist.
- Desktop ticker: level, click-through, positioning across displays, and persistence (macOS 26).
- Update checks request the feed of the in-app language (`appcast.en.xml` in English, `appcast.zh-Hans.xml` after switching to Simplified Chinese).
- Release: notarized zip and DMG pass `spctl`; 1.0 and 1.0.1 published; downloads match the local builds; the website serves the latest DMG.

## Pending

**Widgets**
- With a widget placed, the update time keeps advancing through the evening and the next day.
- Changing the display currency, language, or menu bar coin updates placed widgets soon after.
- The gallery preview shows the user's coins with live prices, and offline falls back to sample prices.
- All sizes in light, dark, and monochrome modes.

**Panel and menu bar**
- With a real mouse, the panel's buttons ("Settings", "Manage Watchlist", "Quit", "Add Coins", "Update Available") work on the first click, from the status item and from a widget.
- The panel's look in dark mode, and on macOS 14.
- VoiceOver reads the panel and its rows.
- The panel over a full-screen app and on a display without a menu bar.
- The colored price without a background on an active display; the background with coloring off on light and dark menu bars; a non-Retina display.
- The right-click menu shows no icons on macOS 14 and 26.

**Settings and desktop ticker**
- Settings layout and title bar in all three languages, and on macOS 14 and 15.
- Add panel: hover and click to remove and re-add; Return adds the first result.
- Desktop ticker: resizing in place when text size or the watchlist changes, at most 16 coins, pulled back on screen near the bottom edge, readability over a dark wallpaper.

**Updates and release**
- An update from 1.0 to 1.0.1 end to end: release notes in the system language, relaunch, settings and widgets intact.
- After the next release publishes the per-language feeds: release notes appear in the in-app language, including after switching languages.
- A scheduled check shows "Update Available" without opening a window; a tampered archive is rejected; offline checks stay silent.
- First launch from the DMG on another Mac is not blocked by Gatekeeper.

**Website**
- Safari on macOS and iOS: glass panel, `light-dark()` colors, menus.
- Lighthouse ≥ 90 in all four categories.
