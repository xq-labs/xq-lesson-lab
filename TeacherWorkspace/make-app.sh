#!/bin/zsh
# Builds a release binary and assembles XQ Lesson Lab.app next to this script.
#
# Default is the ship-small build: the model is NOT embedded — the app
# downloads it on first launch (ModelDownload.swift). Pass --bundle-model to
# embed the GGUF for offline/USB installs.
#
# Signing: ad-hoc by default (dev only — other Macs will refuse to open it).
# Set SIGN_IDENTITY="Developer ID Application: …" to produce a distributable
# build (hardened runtime); scripts/make-release.sh drives that end to end.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_MODEL=0
for arg in "$@"; do
    case "$arg" in
        --bundle-model) BUNDLE_MODEL=1 ;;
        *) echo "Unknown option: $arg (only --bundle-model)"; exit 2 ;;
    esac
done

MODEL_FILE="Models/Qwen3.5-2B-Q4_K_M.gguf"
LLAMA_FRAMEWORK="vendor/llama.cpp/build-apple/llama.xcframework/macos-arm64_x86_64/llama.framework"
SPARKLE_FRAMEWORK=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

# Single source of truth for name, version and URLs: AppInfo.swift.
PRODUCT_NAME=$(sed -n 's/.*static let productName = "\(.*\)"/\1/p' Sources/TeacherWorkspace/AppInfo.swift)
VERSION=$(sed -n 's/.*static let version = "\(.*\)"/\1/p' Sources/TeacherWorkspace/AppInfo.swift)
BUILD=$(sed -n 's/.*static let build = \([0-9]*\)/\1/p' Sources/TeacherWorkspace/AppInfo.swift)
WEBSITE_URL=$(sed -n 's/.*static let websiteURL = "\(.*\)"/\1/p' Sources/TeacherWorkspace/AppInfo.swift)
APPCAST_URL="$WEBSITE_URL/appcast.xml"
[[ -n "$PRODUCT_NAME" && -n "$VERSION" && -n "$BUILD" && -n "$WEBSITE_URL" ]] || { echo "Couldn't read productName/version/build/websiteURL from AppInfo.swift"; exit 1; }

# Sparkle EdDSA public key for update verification (safe to commit — the
# matching private key lives in the login keychain; RELEASING.md § Sparkle).
SPARKLE_PUBLIC_KEY="${SPARKLE_ED_PUBLIC_KEY:-hilkGndELmBDcg2mWemtLWu6hWoNZtiLtJy0z7l0Ef0=}"

[[ -d "$LLAMA_FRAMEWORK" ]] || { echo "Missing $LLAMA_FRAMEWORK — run scripts/setup-vendor.sh"; exit 1; }
if [[ $BUNDLE_MODEL == 1 && ! -f "$MODEL_FILE" ]]; then
    echo "--bundle-model needs $MODEL_FILE"; exit 1
fi

swift build -c release

APP="$PRODUCT_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/release/TeacherWorkspace "$APP/Contents/MacOS/TeacherWorkspace"
if [[ $BUNDLE_MODEL == 1 ]]; then
    cp "$MODEL_FILE" "$APP/Contents/Resources/"
fi

# App icon. Regenerate it with `swift scripts/make-icon.swift book Resources`
# after editing the drawing script.
[[ -f Resources/AppIcon.icns ]] || swift scripts/make-icon.swift book Resources
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R "$LLAMA_FRAMEWORK" "$APP/Contents/Frameworks/"
[[ -d "$SPARKLE_FRAMEWORK" ]] || { echo "Missing $SPARKLE_FRAMEWORK (swift build fetches it — check Package.swift)"; exit 1; }
cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/"

# The executable references @rpath/…; point rpath at the bundled Frameworks
# directory (the SwiftPM build-dir rpath stays as a dev convenience and
# simply won't resolve on other machines).
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/TeacherWorkspace" 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TeacherWorkspace</string>
    <key>CFBundleIdentifier</key>
    <string>org.xqinstitute.lesson-lab</string>
    <key>CFBundleName</key>
    <string>$PRODUCT_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$PRODUCT_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>$PRODUCT_NAME uses the microphone for on-device dictation into the chat composer.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>$PRODUCT_NAME transcribes your dictation on this Mac — audio never leaves the device.</string>
    <key>SUFeedURL</key>
    <string>$APPCAST_URL</string>
    <key>SUPublicEDKey</key>
    <string>$SPARKLE_PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
</dict>
</plist>
PLIST

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    # Distributable signing: nested-first, hardened runtime throughout.
    # Sparkle's helpers must be signed before the framework, and the
    # frameworks before the app.
    for helper in "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"/*.xpc(N) \
                  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"(N) \
                  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"(N); do
        codesign --force --options runtime --sign "$SIGN_IDENTITY" "$helper"
    done
    codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
    codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP/Contents/Frameworks/llama.framework"
    codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP"
    echo "Signed with: $SIGN_IDENTITY"
else
    codesign --force --sign - "$APP/Contents/Frameworks/Sparkle.framework"
    codesign --force --sign - "$APP/Contents/Frameworks/llama.framework"
    codesign --force --sign - "$APP"
    echo "Ad-hoc signed (dev only — won't open on other Macs)"
fi

MODE=$([[ $BUNDLE_MODEL == 1 ]] && echo "model embedded" || echo "ship-small")
echo "Built $APP v$VERSION ($BUILD, $MODE, $(du -sh "$APP" | cut -f1))"
