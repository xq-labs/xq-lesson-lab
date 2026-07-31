#!/bin/zsh
# Builds a release binary and assembles Teacher Workspace.app next to this script.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="Teacher Workspace.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TeacherWorkspace "$APP/Contents/MacOS/TeacherWorkspace"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TeacherWorkspace</string>
    <key>CFBundleIdentifier</key>
    <string>org.xqinstitute.teacher-workspace</string>
    <key>CFBundleName</key>
    <string>Teacher Workspace</string>
    <key>CFBundleDisplayName</key>
    <string>Teacher Workspace</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
