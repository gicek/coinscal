# Menu Bar Panel

> Status: approved and implemented 2026-11-18. The menu bar content is shown in an app-managed `NSPanel` instead of an `NSPopover`. Real-mouse checks and the look on macOS 14 are pending verification (see [VALIDATION](VALIDATION.md)).

## Problem

On macOS 27, clicking the status item while the popover was shown didn't close it: the popover disappeared on mouse-down and reappeared on mouse-up. Reproduced on macOS 27.2.1 with the 1.0.1 build and a debug build.

Root cause, confirmed with logs and call stacks:

1. Pressing the status item takes key status from the popover window. The `.transient` popover closed itself on resign key (`_NSPopoverProcessResignKey`) before the button action ran.
2. The press also reached the global mouse monitor `AppDelegate` installed while the popover was shown (for popovers opened from a widget), and the monitor closed the popover as an outside click.
3. The button action fires on mouse-up, found `popover.isShown == false`, and opened it again.

Rejected fixes:

- Vetoing the close in `NSPopoverDelegate.popoverShouldClose(_:)` while the status item is pressed keeps the popover up, but the status item's action is then no longer delivered while the popover is shown, so it can't be closed from the status item at all.
- Swallowing the mouse-up after a press-time close works, but the popover still vanishes on mouse-down, and the guard relies on reading the mouse state during `NSPopover`'s internal close.

## Design

The status item action decides open or close from the panel's own visibility. With an `NSPanel`, the status item action still arrives on mouse-up while the panel is shown (confirmed with a standalone prototype and the app on macOS 27.2.1), so the toggle sees the real state.

### Behavior

- Left click on the status item toggles the panel. Right click closes the panel and shows the context menu.
- The panel closes on a click outside it (other apps, the desktop, other Coinscal windows), on Esc, when another window becomes key (for example after ⌘-Tab), and when Settings opens from the panel.
- A widget click (`coinscal://popover`) opens the panel, including on a cold launch.
- Same content, size rules (320pt wide, 4 to 8 rows), and look (system popover material, 16pt corners, shadow) as before, shown and hidden instantly, no anchor arrow. User-facing docs keep calling it the popover.

### Implementation

- `MenuBarPanelController` (`Apple/Mac/Views/MenuBar/MenuBarPanelController.swift`) owns the panel, its placement, and dismissal. `AppDelegate` keeps the status item and calls `toggle()`, `show()`, `close()`, and `setContentSize(_:)`.
- `MenuBarPanel`: a borderless, non-activating `NSPanel` that can become key (so a panel opened from a widget works without activating the app), level `.popUpMenu`, `hidesOnDeactivate = false`, not released on close, `animationBehavior = .none`, ignored by window cycling. Esc arrives as `cancelOperation(_:)`.
- Look: the panel content is an `NSVisualEffectView` with the system popover material (`.popover`, behind-window blending), the same background the `NSPopover` had. It blurs what is behind the panel heavily, so text and colors behind it don't compete with the price colors. A stretchable mask image clips it to 16pt corners (`Constants.Popover.cornerRadius`); the window is transparent outside the mask and its system shadow follows the rounded shape (recomputed after showing and resizing). `CoinPopoverView` draws no background or shadow of its own, only a 1pt edge line with the same radius.
- Content: `MenuBarPanelHostingView`, an `NSHostingView` whose `acceptsFirstMouse` returns true. macOS 14+ may refuse `NSApp.activate`, and a widget click never activates the app; a plain hosting view then treats the first click as activation only, and the buttons ignore it. `sizingOptions` is empty so the SwiftUI content doesn't resize the window.
- Placement (`MenuBarPanelLayout.frame`): centered under the status item window, 6pt below it, at least 8pt from the left and right edges of that screen's visible frame, and never above the visible frame. A shown panel keeps its top edge when the watchlist size changes its height.
- Dismissal, installed only while the panel is shown:
  - A global mouse-down monitor (other apps, the desktop) closes the panel, except for presses inside the status item window, which macOS 27 also delivers to global monitors.
  - A local mouse-down monitor closes it on presses in any other Coinscal window; presses in the panel and the status item window are left alone.
  - Losing key status closes it, except while the pointer is over the status item window (that click ends in the toggle). The mouse button state isn't checked: after a trackpad tap it already reads as released when the notification arrives.
  - Pressing the status item and releasing outside it leaves the panel open and not key; the next outside click closes it.

## Tests

- `MenuBarPanelLayoutTests`: centering, both screen edges, a secondary display, a status item frame above the visible frame, and a screen narrower than the panel.
- Checked on a real Mac (macOS 27.2.1, debug build, synthetic mouse events and Accessibility): status item clicks toggle open and closed repeatedly; a click in another app, Esc, a right click on the status item, switching to Finder, and a click in the Settings window each close the panel; `coinscal://popover` opens it and an outside click closes it; pressing "Manage Watchlist" through Accessibility opens Settings on the Watchlist pane and closes the panel.
- Look checked on macOS 27.2.1 in light mode: in front of a window full of text, the background stays an even frosted gray and the price colors read clearly; corners, edge line, and shadow match the old popover.
- Real trackpad clicks on the status item toggle the panel reliably (confirmed by the maintainer on macOS 27.2.1).
- Synthetic mouse clicks don't trigger the SwiftUI buttons in either the old popover or the new panel, so clicking the panel's buttons with a real mouse is pending verification.
