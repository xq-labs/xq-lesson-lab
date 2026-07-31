#!/bin/zsh
# End-to-end distributable release: signed app → notarized → stapled → DMG +
# Sparkle zip + appcast entry. See RELEASING.md for the one-time setup.
#
# Required environment:
#   SIGN_IDENTITY          "Developer ID Application: XQ Institute (TEAMID)"
#   NOTARY_PROFILE         notarytool keychain profile (xcrun notarytool store-credentials)
#   SPARKLE_ED_PUBLIC_KEY  public key from Sparkle's generate_keys
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SIGN_IDENTITY:?Set SIGN_IDENTITY (see RELEASING.md § Signing)}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE (see RELEASING.md § Notarization)}"
: "${SPARKLE_ED_PUBLIC_KEY:?Set SPARKLE_ED_PUBLIC_KEY (see RELEASING.md § Sparkle keys)}"

VERSION=$(sed -n 's/.*static let version = "\(.*\)"/\1/p' Sources/TeacherWorkspace/AppInfo.swift)
BUILD=$(sed -n 's/.*static let build = \([0-9]*\)/\1/p' Sources/TeacherWorkspace/AppInfo.swift)
APP="Lesson Lab.app"
OUT="release/v$VERSION"
DMG="$OUT/Lesson-Lab.dmg"
ZIP="$OUT/Lesson-Lab-$VERSION.zip"

./make-app.sh "$@"   # pass through --bundle-model if wanted

mkdir -p "$OUT"
rm -f "$DMG" "$ZIP"

# DMG with an Applications symlink — the standard drag-to-install layout.
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Lesson Lab" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --sign "$SIGN_IDENTITY" "$DMG"

echo "Submitting DMG for notarization (this can take a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

# Sparkle update archive (zip of the .app; generate_appcast signs it).
ditto -c -k --keepParent "$APP" "$ZIP"

echo ""
echo "Release artifacts in $OUT/:"
ls -lh "$OUT"
echo ""
echo "Next steps:"
echo "  1. Regenerate the appcast (needs Sparkle's generate_appcast + private key):"
echo "       generate_appcast --download-url-prefix https://github.com/xq-labs/xq-lesson-lab/releases/download/v$VERSION/ $OUT/"
echo "  2. Copy $OUT/appcast.xml over website/appcast.xml and redeploy Vercel."
echo "  3. Create GitHub release v$VERSION and upload: Lesson-Lab.dmg, Lesson-Lab-$VERSION.zip (+ any .delta files)."
