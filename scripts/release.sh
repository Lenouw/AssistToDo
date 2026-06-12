#!/usr/bin/env bash
#
# release.sh — build Release + fabrique un DMG distribuable d'AssistToDo.
# Usage : ./scripts/release.sh            (depuis la racine du projet)
# Sortie : dist/AssistToDo-<version>.dmg
#
# App signée ad-hoc (compte Apple gratuit) → NON notarisée. Au 1er lancement, le
# destinataire fait clic-droit › Ouvrir (voir README). Whisper se télécharge au 1er run.

set -euo pipefail
cd "$(dirname "$0")/.."

PROJ="AssistToDo/AssistToDo.xcodeproj"
SCHEME="AssistToDo"
BUILD_DIR="build"
DIST_DIR="dist"

echo "▸ Build Release…"
rm -rf "$BUILD_DIR"
xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$BUILD_DIR" -destination 'platform=macOS' build >/dev/null

APP="$BUILD_DIR/Build/Products/Release/$SCHEME.app"
[ -d "$APP" ] || { echo "✗ App introuvable : $APP"; exit 1; }

VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
echo "▸ Version : $VER"

echo "▸ Fabrication du DMG…"
mkdir -p "$DIST_DIR"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST_DIR/$SCHEME-$VER.dmg"
rm -f "$DMG"
hdiutil create -volname "$SCHEME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "✓ DMG prêt : $DMG"
echo "  Publier : gh release create v$VER \"$DMG\" --title \"$SCHEME $VER\" --notes-file RELEASE_NOTES.md"
