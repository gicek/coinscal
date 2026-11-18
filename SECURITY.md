# Security Policy

## Supported Versions

Only the latest release receives fixes. Coinscal updates itself; check for updates from the right-click menu or Settings → General.

## Reporting a Vulnerability

Please report vulnerabilities privately by email to kk@gicek.com, not in a public issue. Include the affected version, the steps to reproduce, and the impact. Reports are acknowledged and fixed as soon as possible, with credit in the release notes if you want it.

Areas of particular interest:

- The update channel: appcast, archive signatures, and installation.
- Handling of data from price, exchange rate, and logo sources.
- The sandbox, entitlements, and App Group data shared with the widgets.

## Design Notes

- The app runs in the App Sandbox with outgoing network access only, and talks to HTTPS endpoints only.
- Updates are verified twice: Sparkle checks the EdDSA signature of each archive, and macOS checks that the new app is signed by the same Developer ID team.
- No keys, tokens, or signing material are stored in this repository.
