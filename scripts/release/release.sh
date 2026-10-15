#!/bin/bash
# Developer ID release: verify code signing -> (optionally notarize the app) -> build zip and DMG -> sign the DMG ->
# (optionally notarize the DMG) -> Gatekeeper check.
# Usage: scripts/release/release.sh <Coinscal.app> <output directory> <work directory> <version> [--notarize]
# Environment: DEVELOPER_ID (signing identity, default "Developer ID Application"), DEVELOPMENT_TEAM;
#   notarization credentials, one of: NOTARY_PROFILE (the keychain profile name saved by notarytool
#   store-credentials), or ASC_KEY_ID + ASC_ISSUER_ID + ASC_KEY_PATH (App Store Connect API key).
# Called by make mac-release / make mac-release-notarized; see "Release" in docs/DEVELOPMENT.md.
set -euo pipefail

APP="$1"
DIST="$2"
WORK="$3"
VERSION="$4"
NOTARIZE=0
[ "${5:-}" = "--notarize" ] && NOTARIZE=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRODUCT="$(basename "$APP" .app)"
ZIP="$DIST/$PRODUCT-$VERSION.zip"
DMG="$DIST/$PRODUCT-$VERSION.dmg"
IDENTITY="${DEVELOPER_ID:-Developer ID Application}"
TEAM="${DEVELOPMENT_TEAM:?Release requires DEVELOPMENT_TEAM in local.mk}"

notary_args() {
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        printf '%s\n' --keychain-profile "$NOTARY_PROFILE"
    elif [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] && [ -n "${ASC_KEY_PATH:-}" ]; then
        printf '%s\n' --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID"
    else
        return 1
    fi
}

# Submit and wait for the result; if rejected, fetch the notarization log and exit with failure
notarize() {
    local file="$1" out id status
    local args=()
    while IFS= read -r line; do args+=("$line"); done < <(notary_args)
    echo "==> Notarizing $(basename "$file") (usually a few minutes)"
    out="$(xcrun notarytool submit "$file" "${args[@]}" --wait --output-format json)" || true
    id="$(/usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' <<<"$out" 2>/dev/null || true)"
    status="$(/usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' <<<"$out" 2>/dev/null || true)"
    if [ "$status" != "Accepted" ]; then
        echo "Notarization failed (status=${status:-unknown}): ${out}"
        [ -n "$id" ] && xcrun notarytool log "$id" "${args[@]}" || true
        exit 1
    fi
    echo "    Accepted (${id})"
}

# App and embedded widget: Developer ID, this Team, Hardened Runtime, secure timestamp, no get-task-allow
verify_app_signature() {
    local bundle info ents
    codesign --verify --deep --strict --verbose=1 "$APP"
    for bundle in "$APP" "$APP"/Contents/PlugIns/*.appex; do
        [ -d "$bundle" ] || continue
        info="$(codesign -dvv "$bundle" 2>&1)"
        grep -q "^Authority=Developer ID Application:" <<<"$info" || { echo "${bundle} is not signed with Developer ID"; exit 1; }
        grep -q "^TeamIdentifier=$TEAM$" <<<"$info" || { echo "${bundle} Team is not ${TEAM}"; exit 1; }
        grep -q "flags=.*runtime" <<<"$info" || { echo "${bundle} does not have Hardened Runtime enabled"; exit 1; }
        grep -q "^Timestamp=" <<<"$info" || { echo "${bundle} is missing a secure timestamp"; exit 1; }
        ents="$(codesign -d --entitlements - --xml "$bundle" 2>/dev/null)"
        if grep -q "get-task-allow" <<<"$ents"; then echo "${bundle} has get-task-allow, which notarization rejects"; exit 1; fi
    done
    echo "    Code signing verified: $(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application.*\)/\1/p')"
}

[ -x "$APP/Contents/MacOS/$PRODUCT" ] || { echo "Missing build product: ${APP}"; exit 1; }
if [ "$NOTARIZE" = 1 ] && ! notary_args >/dev/null; then
    echo "Missing notarization credentials: set NOTARY_PROFILE in local.mk (run xcrun notarytool store-credentials first),"
    echo "or ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH. See \"Release\" in docs/DEVELOPMENT.md."
    exit 1
fi

echo "==> Verifying app code signing"
verify_app_signature

mkdir -p "$DIST" "$WORK"
if [ "$NOTARIZE" = 1 ]; then
    # Notarize and staple the app first so the app inside the zip passes Gatekeeper offline too
    APP_ZIP="$WORK/$PRODUCT-notarize.zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$APP_ZIP"
    notarize "$APP_ZIP"
    rm -f "$APP_ZIP"
    xcrun stapler staple -q "$APP"
    xcrun stapler validate -q "$APP"
fi

echo "==> Building zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> Building DMG"
"$SCRIPT_DIR/../dmg/make-dmg.sh" "$APP" "$DMG" "$WORK/DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
codesign --verify --strict "$DMG"

if [ "$NOTARIZE" = 1 ]; then
    notarize "$DMG"
    xcrun stapler staple -q "$DMG"
    xcrun stapler validate -q "$DMG"
    echo "==> Gatekeeper check"
    spctl --assess --type execute --verbose=2 "$APP"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

rm -rf "$WORK"
echo "==> $ZIP"
echo "==> $DMG"
if [ "$NOTARIZE" = 1 ]; then
    echo "Signed, notarized, and stapled; ready to distribute."
else
    echo "Signed but not notarized: Gatekeeper blocks the first launch on other Macs. Use make mac-release-notarized before distributing."
fi
