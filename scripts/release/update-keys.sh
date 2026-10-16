#!/bin/bash
# Creates the EdDSA key pair that signs Sparkle updates, or reuses the one already in the login Keychain, and
# exports a backup of the private key. Run it yourself, once: the private key never passes through anything else.
#
# Usage: scripts/release/update-keys.sh <sparkle-bin-dir> <keychain-account> <backup-file>
#   backup-file: where to write the private key backup. It must be outside the repository and must not exist yet.
set -euo pipefail

BIN="$1"
ACCOUNT="$2"
BACKUP="$3"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"

# A "~" in BACKUP=~/… on the make command line reaches here unexpanded
case "$BACKUP" in
    "~"/*) BACKUP="$HOME/${BACKUP#"~"/}" ;;
esac
case "$BACKUP" in
    /*) ;;
    *) BACKUP="$PWD/$BACKUP" ;;
esac
BACKUP_DIR="$(cd "$(dirname "$BACKUP")" 2>/dev/null && pwd)" || { echo "Backup directory doesn't exist: $(dirname "$BACKUP")" >&2; exit 1; }
BACKUP="$BACKUP_DIR/$(basename "$BACKUP")"
case "$BACKUP" in
    "$REPO"/*) echo "Refusing to write the private key inside the repository: $BACKUP" >&2; exit 1 ;;
esac
if [ -e "$BACKUP" ]; then
    echo "Refusing to overwrite an existing file: $BACKUP" >&2
    exit 1
fi

echo "== Creating or reusing the signing key (Keychain account \"$ACCOUNT\")"
echo "   macOS may ask to allow access to the login Keychain; allow it."
"$BIN/generate_keys" --account "$ACCOUNT" >/dev/null

echo "== Exporting the private key backup"
umask 077
"$BIN/generate_keys" --account "$ACCOUNT" -x "$BACKUP" >/dev/null
chmod 600 "$BACKUP"

PUBLIC_KEY="$("$BIN/generate_keys" --account "$ACCOUNT" -p)"
cat <<INFO

Done.
  Private key backup: $BACKUP
    Store it offline (password manager or encrypted drive), then delete this file.
    Losing the key means installed copies can't verify new updates.
    To restore on another Mac: $BIN/generate_keys --account "$ACCOUNT" -f <backup-file>
  Public key (safe to share; goes into Info.plist as SUPublicEDKey):
    $PUBLIC_KEY
INFO
