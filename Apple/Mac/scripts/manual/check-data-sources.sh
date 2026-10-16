#!/bin/bash
# Manual test: checks every price and FX source on the real network (coverage, cross-source consistency, failover). Not part of make test.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
MAC="$ROOT/Apple/Mac"
OUT="$ROOT/Build/macOS/Manual"
mkdir -p "$OUT"
xcrun swiftc -swift-version 6 -O -o "$OUT/check-data-sources" \
    "$MAC/scripts/manual/check-data-sources/main.swift" \
    "$MAC/Services/PriceService.swift" "$MAC/Services/HTTPClient.swift" "$MAC/Services/ExchangeRateService.swift" \
    "$MAC/Shared/WidgetSnapshot.swift" "$MAC/App/Constants.swift" "$MAC/Models/AppSettings.swift" "$MAC/Utilities/LocalizationManager.swift"
exec "$OUT/check-data-sources" "$MAC/Resources/coins.json"
