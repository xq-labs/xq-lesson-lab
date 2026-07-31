#!/bin/zsh
# Builds the drag-to-install DMG: app + Applications symlink, custom volume
# icon (the app icon), and a Finder window laid out over the branded
# background from make-dmg-background.swift.
#
#   scripts/make-dmg-layout.sh <App.app> <volume name> <out.dmg>
#
# Runs unsigned — make-release.sh signs/notarizes the result. Needs Finder
# automation (first run prompts once for permission). Any mounted volume with
# the same name is detached first so the Finder scripting can't hit the
# wrong disk.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=$1
VOLNAME=$2
DMG=$3

STAGE=$(mktemp -d)
RWDMG=$(mktemp -d)/rw.dmg

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
swift scripts/make-dmg-background.swift "$STAGE/.background"
rm "$STAGE/.background/bg.png" "$STAGE/.background/bg@2x.png"

# Read-write image first so Finder can write .DS_Store into it.
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDRW \
    -fs HFS+ "$RWDMG" >/dev/null
MOUNT="/Volumes/$VOLNAME"
[[ -d "$MOUNT" ]] && hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
hdiutil attach -readwrite -noverify -noautoopen "$RWDMG" >/dev/null

APPNAME=$(basename "$APP")
osascript <<EOF
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        -- 660x400 content; y offset leaves room for the title bar
        set the bounds of container window to {200, 140, 860, 568}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 110
        set text size of opts to 13
        set background picture of opts to file ".background:bg.tiff"
        set position of item "$APPNAME" of container window to {165, 185}
        set position of item "Applications" of container window to {495, 185}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

# Volume icon AFTER the Finder pass — Finder cleans up a bare
# .VolumeIcon.icns while it lays out the window, so copying it earlier
# silently loses it. The icnC creator code marks it as the real thing.
cp Resources/AppIcon.icns "$MOUNT/.VolumeIcon.icns"
if command -v SetFile >/dev/null; then
    SetFile -c icnC "$MOUNT/.VolumeIcon.icns"
    SetFile -a C "$MOUNT"
else
    xattr -wx com.apple.FinderInfo \
        "0000000069636E43000000000000000000000000000000000000000000000000" \
        "$MOUNT/.VolumeIcon.icns" 2>/dev/null || true
    xattr -wx com.apple.FinderInfo \
        "0000000000000000040000000000000000000000000000000000000000000000" \
        "$MOUNT"
fi

sync
hdiutil detach "$MOUNT" >/dev/null
rm -f "$DMG"
hdiutil convert "$RWDMG" -format UDZO -o "$DMG" >/dev/null
rm -rf "$STAGE" "$(dirname "$RWDMG")"
echo "wrote $DMG"
