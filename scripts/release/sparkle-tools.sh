#!/bin/bash
# Downloads Sparkle's command-line tools (generate_keys, sign_update) at the pinned version into Build/, verifies the
# archive checksum, and prints the bin directory. Idempotent: an existing, verified copy is reused.
#
# Usage: scripts/release/sparkle-tools.sh <version> <sha256> <dest-dir>
set -euo pipefail

VERSION="$1"
SHA256="$2"
DEST="$3"
ARCHIVE="$DEST/Sparkle-$VERSION.tar.xz"
BIN="$DEST/dist/bin"

if [ -x "$BIN/generate_keys" ] && [ -x "$BIN/sign_update" ]; then
    echo "$BIN"
    exit 0
fi

mkdir -p "$DEST"
curl -fsSL --retry 2 -o "$ARCHIVE" "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz"
ACTUAL="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [ "$ACTUAL" != "$SHA256" ]; then
    echo "Sparkle $VERSION checksum mismatch: expected $SHA256, got $ACTUAL" >&2
    rm -f "$ARCHIVE"
    exit 1
fi
rm -rf "$DEST/dist"
mkdir -p "$DEST/dist"
tar -xJf "$ARCHIVE" -C "$DEST/dist"
echo "$BIN"
