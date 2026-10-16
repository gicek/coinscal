# Desktop Ticker (Price Panel Pinned to the Desktop)

> Status: approved and implemented 2026-10-15. For implementation constraints, see "Desktop Ticker Window" in [TECHNICAL](TECHNICAL.md). For verification on a real Mac, see [VALIDATION](VALIDATION.md).

## Goal

Pin prices to the desktop like a sticky note that blends into the wallpaper: it doesn't block the mouse, doesn't appear in window switching, and is present on every desktop Space. Unlike a system widget, the price updates every 10 seconds along with the app, with no WidgetKit refresh budget. The trade-off is that the app must be running.

| | System widget ([WIDGET](WIDGET.md)) | Desktop ticker |
|---|---|---|
| Refresh | Daily budget assigned by the system, about 15–60 minutes | Follows app polling, 10 seconds |
| After the app quits | The widget fetches prices itself | Disappears with the app |
| Mouse | Clickable, editable | Fully click-through; temporarily draggable during "Adjust Position" |
| Configuration | System "Edit Widget" | Settings → General → "Desktop" |
| Appearance | Desaturated by the system when an app window is in front | Always full color, frosted glass shows the wallpaper through |

## Interaction

- Settings → General → "Desktop": "Show on Desktop" (off by default), "Background Opacity" (0–100%, 100% by default), "Adjust Position" (right-aligned, no description). When off, the other options are grayed out.
- The panel is fixed between the wallpaper and the desktop icons. A "show above desktop icons" option was removed on 2026-10-15: the panel is click-through, so above the icons it only covered them. Bringing it back would need a use for a click-through panel that covers icons.
- Background opacity applies only to the frosted glass background, not to the text. At 0%, only the text floats on the wallpaper. During position adjustment the background is at least 60%, so you can see the panel's extent and drag it as a whole (fully transparent pixels in a borderless window don't receive clicks).
- Below 20%, text readability depends on the wallpaper, so the panel styles text like macOS desktop icon labels (Finder file names): primary text pure white, secondary text such as names and times 85% white, and under each piece of text one faint shadow hugging the glyphs (radius 1.5, opacity 0.45) plus one very faint radius 3 shadow, with almost no visible blur. 24h changes and the stale time are white too; only the leading ▲ / ▼ or ⚠︎ keeps the up, down, or warning color. No red or green reaches enough luminance contrast against both light and dark wallpapers (the default green is about 1.3:1 on a light blue-gray wallpaper), and neither a black shadow nor a lightened color with a same-hue shadow fixed it. This applies only to text; the coin icons and background get none. A full-panel shadow, a feathered backing, and heavier shadows (up to radius 10) were tried and rejected as too heavy. Colors are not sampled from the wallpaper: the sandbox can't read the user's wallpaper file, sampling a screenshot needs screen recording permission, and dynamic wallpapers change.
- One layout, the large widget's list (`WidgetListView`): 364pt wide, the first 16 watchlist coins, and a height that fits them (14pt padding, a 22pt header, 38pt rows with 1pt dividers; 88pt for one coin, 673pt for 16). Before the first prices it is 170pt tall. Style, colors, language, update time, and the stale marker match the widget. The Small / Medium / Large setting was removed on 2026-10-16 (Medium was the default): a list that fits the watchlist replaces choosing between 1, 4, and 8 coins.
- Adjust position: the panel floats to the top layer and shows a dashed border with "Drag to move / Done". Drag it into place and click "Done" (or press Return) to save and return to click-through.
- Turning on "Show on Desktop" in Settings goes straight into position adjustment; the position is only set when you click "Done". Turning it off during adjustment doesn't save. If it is already on when the app launches, the panel starts in click-through. "Adjust Position" in Settings re-enters adjustment at any time.
- Adding or removing coins keeps the panel's top-left corner where it is, so the panel grows or shrinks downward; it is clamped back if it goes past the bottom of its display. The saved point is the top-left corner, so this needs no write-back. Positions saved by earlier versions (the bottom-left corner) are converted once using the size they were saved with, so the top edge stays in place.
- Position: by default, the top-right corner of the main display's visible area, 24pt from the edges. During adjustment it can be dragged to any display. The position is saved in global coordinates, placed on the display it overlaps most, and clamped to that display's visible area. If that display is unplugged, the panel moves temporarily to the nearest display without changing the saved position, and returns automatically when the display is reconnected.

## Not Doing

- Multiple panels (for example, one per display), size options.

## References

Open source implementations: [PerformStat](https://github.com/leniboi643/PerformStat) (MIT, same window configuration), [3D-Earth PR #1](https://github.com/vagdesign/3D-Earth/pull/1) (multiple displays and wake handling), [DeskWidgets](https://github.com/KeiRey/mac-widget) (above-icons option), [DocDesktop](https://github.com/kickereb/DocDesktop) (desktop level and temporary bring-to-front), [Plash](https://github.com/sindresorhus/Plash) (interaction mode switching).

## Measurements (2026-10-15, macOS 26, Debug build)

- Level: the window level is wallpaper +1 (−2147483622), between the Dock wallpaper (−2147483624) and the Finder desktop icons (−2147483603).
- Position: by default in the top-right corner of the main display, 24pt from the menu bar and the right edge; the saved position persists after relaunch.
- Click-through: with the panel temporarily placed above all windows (level 3) and still click-through, the accessibility hit test at its center returns the window of the app below.
- Adjust position: after entering, level 3 and the hit test returns Coinscal (draggable); after moving and clicking "Done", the level is restored and the position is written to settings.
- Size switching: a placed panel switched Small → Large → Medium → Small → Large keeps its top-left corner at (362, 53); the saved bottom-left corner updates with the size, and the position matches after relaunch.
- External display: during adjustment, moved to the portrait display on the right (CG coordinates 1800, −600) and clicked Done. The panel stays on that display, the level is restored, and the saved coordinates convert correctly; it is still on that display after relaunch.
- Background opacity: with the slider at 30%, the setting saves as 0.3; Settings no longer has "show above desktop icons".
- Adjust on enable: turning it off and on again in Settings enters adjustment automatically (level 3); switching to Large during adjustment stays at level 3, the size becomes 364×382, and the top-left corner doesn't move; Done saves. When already on at launch, it doesn't enter adjustment; the hit test at the panel center returns the desktop (Finder), and clicks pass through to the desktop.
