#!/bin/zsh
# End-to-end distributable release: signed app → notarized → stapled → DMG +
# Sparkle zip + appcast entry. See RELEASING.md for the one-time setup.
#
# Required environment:
#   SIGN_IDENTITY   "Developer ID Application: <name> (TEAMID)"
#   NOTARY_PROFILE  notarytool keychain profile (xcrun notarytool store-credentials)
# The Sparkle public key is baked into make-app.sh (SPARKLE_ED_PUBLIC_KEY
# overrides it); the private key must be in the login keychain for
# generate_appcast.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SIGN_IDENTITY:?Set SIGN_IDENTITY (see RELEASING.md § Signing)}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE (see RELEASING.md § Notarization)}"

PRODUCT_NAME=$(sed -n 's/.*static let productName = "\(.*\)"/\1/p' Sources/TeacherWorkspace/AppInfo.swift)
VERSION=$(sed -n 's/.*static let version = "\(.*\)"/\1/p' Sources/TeacherWorkspace/AppInfo.swift)
BUILD=$(sed -n 's/.*static let build = \([0-9]*\)/\1/p' Sources/TeacherWorkspace/AppInfo.swift)
APP="$PRODUCT_NAME.app"
OUT="release/v$VERSION"
DMG="$OUT/Lesson-Lab.dmg"
ZIP="$OUT/Lesson-Lab-$VERSION.zip"

./make-app.sh "$@"   # pass through --bundle-model if wanted

mkdir -p "$OUT"
rm -f "$DMG" "$ZIP"

# DMG with an Applications symlink, custom volume icon, and a designed
# drag-to-install window: build read-write first, let Finder lay it out,
# then compress. scripts/make-dmg-layout.sh owns that dance so it can be
# tested without signing credentials.
scripts/make-dmg-layout.sh "$APP" "$PRODUCT_NAME" "$DMG"
codesign --force --sign "$SIGN_IDENTITY" "$DMG"

echo "Submitting DMG for notarization (this can take a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

# Sparkle update archive (zip of the .app; generate_appcast signs it).
# It lives in its own subdir because generate_appcast scans a directory and
# refuses duplicates — the DMG next to the zip would count as one.
mkdir -p "$OUT/appcast"
ZIP="$OUT/appcast/Lesson-Lab-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo ""
echo "Release artifacts in $OUT/:"
ls -lh "$OUT"
echo ""
echo "Next steps:"
echo "  1. Regenerate the appcast (tool ships with the Sparkle SPM artifact; private key from login keychain):"
echo "       .build/artifacts/sparkle/Sparkle/bin/generate_appcast --download-url-prefix https://github.com/xq-labs/xq-lesson-lab/releases/download/v$VERSION/ $OUT/appcast/"
echo "  2. Copy $OUT/appcast/appcast.xml over website/appcast.xml and redeploy Vercel."
echo "  3. Create GitHub release v$VERSION and upload: $DMG, $OUT/appcast/*.zip (+ any .delta files)."
