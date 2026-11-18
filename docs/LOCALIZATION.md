# Localization

## Languages

`en` (source), `zh-Hans`, and `zh-Hant`, matching `LANGS` in the Makefile. App strings live in `Apple/Mac/Resources/Localizable.xcstrings`, website strings in `Site/messages/<lang>.json`. Both use semantic keys (for example `menu.quit` in the app), and every key is added in all three languages in the same change.

| Option | Stored value | Shown as |
|---|---|---|
| Follow System | `system` | Localized (`lang.system`) |
| English | `en` | English |
| Simplified Chinese | `zh-Hans` | Its own name (`lang.endonym.zh-Hans`) |
| Traditional Chinese | `zh-Hant` | Its own name (`lang.endonym.zh-Hant`) |

Following the system uses the first preferred system language: Chinese tags resolve to Simplified or Traditional Chinese (`zh-TW`, `zh-HK`, and `zh-MO` to Traditional), anything else to English. Switching applies immediately. Sparkle's update window and the release notes follow the system language, not the in-app choice.

## Writing Strings

- Write user-visible strings in English only, then add the translations to the catalog.
- Read strings only through `loc("key")`; format with `String(format: loc(…), …)`. Use `Text(verbatim:)` for text that isn't translated (the product name, `--`, `%`).
- Strings with several arguments use positional placeholders (`%1$@`, `%2$@`), with the same count in every language.
- Button and menu item labels never end with an ellipsis; placeholders may.
- Prices and numbers use POSIX formatting in every language.
- Traditional Chinese uses Taiwan terminology.

## Guards

`scripts/i18n-guard.py` checks that source files contain no non-English text outside localization calls, that every key has all three languages, and that keys used in code exist. It runs in `make test-mac`, `make test-site`, and CI. It recognizes literal keys in system APIs such as `Text("…")`, and `t("…")` on the website, but not `loc("…")`; confirm new `loc` keys yourself. `WidgetTests.widgetKeysAreTranslated` covers the `widget.*` and `coin.status.*` keys, and `make test-site` checks every `data-i18n` key in the pages.

## Terminology

The Chinese terms are the values of these keys in `Localizable.xcstrings`.

| Concept | English | Key |
|---|---|---|
| Watchlist | Watchlist | `nav.watchlist` |
| Alert: above / below / change / off | Above / Below / Change / Off | `alertKind.above`, `alertKind.below`, `alertKind.change`, `alertKind.notSet` |
| Display currency | Display Currency | `general.display.currency` |
| Price alerts | Price Alerts | `general.notification.priceAlert` |
| Open at login | Open at Login | `general.launch.atLogin` |
| Menu bar | Menu Bar | `general.section.menubar` |
| Settings | Settings | `menu.setting` |
| Quit | Quit Coinscal | `menu.quit` |
| No market data | No market data | `coin.status.delisted` |
| Recommended | Recommended | `watchlist.recommended` |
