# Coinscal Localization

> Localization contract and terminology. For implementation details, see "Localization Implementation" in [Technical Architecture](TECHNICAL.md).

## Languages and Source

Supported languages: `en`, `zh-Hans`, `zh-Hant` (matching `LANGS` in the Makefile). The source language is English. App strings live in `Apple/Mac/Resources/Localizable.xcstrings` and website strings in `Site/messages/<lang>.json`, both with semantic keys (such as `menu.change`); add all three languages in the same change. On first launch the app follows the system language and falls back to English if there is no match.

## Manual Switching

| Option | Persisted value | Display name |
|---|---|---|
| Follow System | `system` | Localized (`lang.system`) |
| English | `en` | English |
| Simplified Chinese | `zh-Hans` | Endonym in Simplified Chinese (`lang.endonym.zh-Hans`) |
| Traditional Chinese | `zh-Hant` | Endonym in Traditional Chinese (`lang.endonym.zh-Hant`) |

Sparkle's update window uses Sparkle's own translations and follows the system language, not the in-app setting; release notes are published in all three languages and Sparkle picks the one matching the system language.

Each language's display name is written in that language itself and is not localized (catalog keys `lang.endonym.*`, with the same value in all three languages). Switching takes effect immediately without a restart. The system languages `zh-TW`, `zh-HK`, and `zh-MO` resolve to Traditional Chinese.

## Writing Strings

- In code, get strings only through `loc("key")`; for format strings use `String(format: loc(...), ...)`.
- Use `Text(verbatim:)` for literals that don't need localization (product name, `--`, `%`).
- Numbers and prices always use POSIX formatting and don't change with the language (see "Copy Rules" in DESIGN).

## Guards

The three guards (source scan, complete translations, matching keys) are implemented in `scripts/i18n-guard.py` and run automatically in `make test-mac`, `make test-site`, and CI. For the website, guard 3 checks `t("…")` calls; `make test-site` also checks every `data-i18n` key in the pages. Guard 3 only recognizes literal keys in system APIs such as `Text("…")` and **doesn't check `loc("…")`**: when you add a key, confirm yourself that all three languages have it.

## Additional Writing Rules

- Strings with multiple arguments use positional placeholders (`%1$@`, `%2$@`) so translations can reorder them. All three languages must have the same number of placeholders.
- Button and menu item labels never end with an ellipsis, even when they open a window (`Settings`, not `Settings…`) (2026-10-16; previously an ellipsis per macOS convention). Placeholder text such as the search field's may still end with one.
- Traditional Chinese uses Taiwan terminology for terms such as Settings, Menu Bar, Quit, Add, Symbol (code), Default, and Component.

## Terminology

The Simplified and Traditional Chinese terms are the values of these keys in `Localizable.xcstrings`.

| Concept | English | Catalog key |
|---|---|---|
| Watchlist | Watchlist | `nav.watchlist` |
| Alert condition: above | Above | `alertKind.above` |
| Alert condition: below | Below | `alertKind.below` |
| Alert condition: change | Change | `alertKind.change` |
| Alert condition: off | Off | `alertKind.notSet` |
| Quote currency | Display Currency | `general.display.currency` |
| Price alerts (toggle) | Price Alerts | `general.notification.priceAlert` |
| Open at login | Open at Login | `general.launch.atLogin` |
| Menu bar | Menu Bar | `general.section.menubar` |
| Settings (window / menu) | Settings | `menu.setting` |
| Quit | Quit | `menu.quit` (`Quit Coinscal`) |
| No market data | No market data | `coin.status.delisted` |
| Recommended coins | Recommended | `watchlist.recommended` |
