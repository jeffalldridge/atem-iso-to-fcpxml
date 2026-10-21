#!/usr/bin/env bash
#
# Assemble the distributable ATEM ISO to FCPXML.app: one universal Swift
# executable, an icon, and an Info.plist. Nothing is shelled out to at runtime.
#
#   DEV_ID  Developer ID Application identity. When set, the bundle is signed
#           with the hardened runtime, ready for notarization; otherwise it is
#           ad-hoc signed for local use.
#
# Usage: scripts/make-app.sh "build/ATEM ISO to FCPXML.app"
set -euo pipefail

APP="${1:?usage: make-app.sh <path/to/App.app>}"
EXEC_NAME="ATEMISOtoFCPXML"
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --product "$EXEC_NAME" --show-bin-path)"
APP_EXEC="${BIN_DIR}/${EXEC_NAME}"
INFO_PLIST="Resources/Info.plist"
ENTITLEMENTS="Resources/ATEMISOtoFCPXML.entitlements"

for f in "$APP_EXEC" "$INFO_PLIST" "$ENTITLEMENTS" "Resources/AppIcon.icon/icon.json"; do
    [[ -e "$f" ]] || { echo "Error: missing $f. Run 'make build' first." >&2; exit 1; }
done

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$APP_EXEC" "$APP/Contents/MacOS/${EXEC_NAME}"
cp "$INFO_PLIST" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/${EXEC_NAME}"

archs="$(lipo -archs "$APP/Contents/MacOS/${EXEC_NAME}")"
echo "==> Executable architectures: $archs"
for want in arm64 x86_64; do
    [[ "$archs" == *"$want"* ]] || { echo "Error: the executable is missing the $want slice (got: $archs)." >&2; exit 1; }
done

# --- Icon ---
# The Icon Composer source compiles to an Assets.car (Liquid Glass on macOS 26)
# plus a classic .icns for everything older.
ICON_SRC="Resources/AppIcon.icon"
echo "==> Compiling $ICON_SRC"
ICON_TMP="$(mktemp -d)"
trap 'rm -rf "$ICON_TMP"' EXIT
xcrun actool "$ICON_SRC" \
    --compile "$ICON_TMP" \
    --platform macosx \
    --minimum-deployment-target 15.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$ICON_TMP/partial.plist" \
    --output-format human-readable-text >/dev/null
for asset in Assets.car AppIcon.icns; do
    [[ -s "$ICON_TMP/$asset" ]] || { echo "Error: actool did not produce $asset." >&2; exit 1; }
    cp "$ICON_TMP/$asset" "$APP/Contents/Resources/$asset"
done

if [[ -n "${DEV_ID:-}" ]]; then
    echo "==> Signing with Developer ID + hardened runtime"
    codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$DEV_ID" "$APP"
else
    echo "==> Signing ad-hoc (set DEV_ID for a notarization-ready build)"
    codesign --force --entitlements "$ENTITLEMENTS" --sign - "$APP"
fi
codesign --verify --deep --strict --verbose=1 "$APP" >/dev/null

echo "==> Self-check"
"$APP/Contents/MacOS/${EXEC_NAME}" --self-check
echo "==> Built $APP ($(du -sh "$APP" | awk '{print $1}'), $archs)"
