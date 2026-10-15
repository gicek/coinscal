#!/bin/bash
# Packages the Release build of Coinscal.app into a DMG with a background and icon layout.
# Usage: scripts/dmg/make-dmg.sh <Coinscal.app> <output .dmg> <work directory>
# The Finder layout is written into the volume's .DS_Store via AppleScript. This needs a GUI session, and the
# first run asks for "Automation → Finder" permission.
# Window size and icon coordinates must match render-background.swift.
set -euo pipefail

APP="$1"
OUT="$2"
WORK="$3"
VOLNAME="Coinscal"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Volume icon: the system disk icon with the logo mark (transparent background) laid over it
VOLUME_LOGO="$SCRIPT_DIR/../../design/coinscal-logo-1024-transparent.png"

WIN_W=660; WIN_H=420
ICON_SIZE=112
APP_X=180; APP_Y=250
APPS_X=480; APPS_Y=170
# bounds include the title bar (about 32pt measured on macOS 26); if the content area is shorter than the
# background, Finder scrolls and all icons are misplaced
TITLEBAR_H=32

[ -d "$APP" ] || { echo "Missing build product: $APP"; exit 1; }
if [ -d "/Volumes/$VOLNAME" ]; then
    echo "/Volumes/$VOLNAME is already mounted; eject it before packaging"; exit 1
fi

rm -rf "$WORK"
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"

echo "==> Rendering background"
swift "$SCRIPT_DIR/render-background.swift" "$WORK/bg"
tiffutil -cathidpicheck "$WORK/bg/background.png" "$WORK/bg/background@2x.png" \
    -out "$STAGE/.background/background.tiff" >/dev/null 2>&1

echo "==> Generating volume icon"
ICONSET="$WORK/VolumeIcon.iconset"
mkdir -p "$ICONSET"
swift "$SCRIPT_DIR/render-volume-icon.swift" "$VOLUME_LOGO" "$WORK/volume-icon.png"
for size in 16 32 128 256 512; do
    sips -z $size $size "$WORK/volume-icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$WORK/volume-icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$STAGE/.VolumeIcon.icns"

ditto "$APP" "$STAGE/$(basename "$APP")"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating writable image"
RW="$WORK/rw.dmg"
hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ \
    -format UDRW -size "$(( $(du -sm "$STAGE" | cut -f1) + 20 ))m" "$RW"
DEVICE="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk '/Apple_HFS/ {print $1}')"
trap 'hdiutil detach -quiet "$DEVICE" 2>/dev/null || true' EXIT
# Finder only uses .VolumeIcon.icns when the volume root has the "custom icon" flag
SetFile -a C "/Volumes/$VOLNAME"

echo "==> Setting Finder layout"
osascript <<EOF
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, $((200 + WIN_W)), $((120 + WIN_H + TITLEBAR_H))}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to $ICON_SIZE
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "$(basename "$APP")" of container window to {$APP_X, $APP_Y}
        set position of item "Applications" of container window to {$APPS_X, $APPS_Y}
        -- When the user has "show hidden files" on, hidden items appear too; move them outside the window
        repeat with hiddenName in {".background", ".fseventsd", ".DS_Store", ".Trashes", ".VolumeIcon.icns"}
            if exists item hiddenName of container window then
                set position of item hiddenName of container window to {$((WIN_W + 200)), 100}
            end if
        end repeat
        -- Do not call update: on macOS 26 it deletes .VolumeIcon.icns and clears the volume's custom icon flag
        delay 1
        close
    end tell
end tell
EOF

# Wait for Finder to write .DS_Store back to the volume
for _ in {1..10}; do
    [ -f "/Volumes/$VOLNAME/.DS_Store" ] && break
    sleep 1
done
[ -f "/Volumes/$VOLNAME/.DS_Store" ] || { echo "Finder did not write .DS_Store; the layout did not take effect"; exit 1; }
[ -f "/Volumes/$VOLNAME/.VolumeIcon.icns" ] && GetFileInfo -a "/Volumes/$VOLNAME" | grep -q C || { echo "Volume icon or custom icon flag is missing"; exit 1; }
# The file system event log is useless in an installer; delete it to drop one hidden item (it is not
# recreated on a read-only mount)
rm -rf "/Volumes/$VOLNAME/.fseventsd"
chmod -Rf go-w "/Volumes/$VOLNAME" || true
sync
hdiutil detach -quiet "$DEVICE"
trap - EXIT

echo "==> Compressing"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT"
rm -rf "$WORK"
echo "==> $OUT"
