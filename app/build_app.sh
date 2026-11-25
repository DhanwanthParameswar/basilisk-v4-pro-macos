#!/bin/zsh
# Builds Basilisk.app into app/build/.
#
# Signing is automatic:
#   - If a "Developer ID Application" certificate is installed (or BASILISK_SIGN_ID is
#     set), the app is signed with it + hardened runtime + a secure timestamp, which is
#     what Gatekeeper trusts and what notarization requires.
#   - Otherwise it falls back to an ad-hoc signature so local development still works.
#
# Optional notarization (needs the Developer ID path above):
#   BASILISK_NOTARY_PROFILE=<name> ./build_app.sh
#   ...where <name> is a notarytool keychain profile created once with:
#   xcrun notarytool store-credentials <name> --apple-id you@org.com \
#          --team-id TEAMID --password <app-specific-password>
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID="${BASILISK_BUNDLE_ID:-local.basilisk.v4pro}"

# --- Pick a signing identity -------------------------------------------------
# Prefer a Developer ID cert (distributable + notarizable). Otherwise fall back to an
# Apple Development cert, which is still a *stable* identity — enough to make macOS
# permission grants (Accessibility/Input Monitoring) persist across rebuilds locally,
# though it can't be notarized or distributed. Last resort is ad-hoc.
IS_DEVID=0
if [[ -n "${BASILISK_SIGN_ID:-}" ]]; then
    SIGN_ID="$BASILISK_SIGN_ID"
    [[ "$SIGN_ID" == *"Developer ID Application"* ]] && IS_DEVID=1
else
    # Resolve to the cert's SHA-1 hash, not its name: there can be several certs with
    # identical names, which makes a name-based --sign ambiguous (and silently ad-hoc).
    IDS="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    LINE="$(echo "$IDS" | grep 'Developer ID Application' | head -1 || true)"
    if [[ -n "$LINE" ]]; then IS_DEVID=1; else LINE="$(echo "$IDS" | grep 'Apple Development' | head -1 || true)"; fi
    SIGN_ID="$(echo "$LINE" | awk '{print $2}')"
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Basilisk"
APP="build/Basilisk.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Basilisk"

# Icon, rendered natively from the vector artwork.
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
"$BIN" --render-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Basilisk</string>
    <key>CFBundleDisplayName</key><string>Basilisk</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>Basilisk</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.2</string>
    <key>CFBundleVersion</key><string>3</string>
    <key>LSMinimumSystemVersion</key><string>27.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Basilisk talks to your Razer Basilisk V4 Pro over Bluetooth to show its battery and settings.</string>
</dict>
</plist>
PLIST

# --- Sign --------------------------------------------------------------------
if [[ "$IS_DEVID" == "1" ]]; then
    echo "Signing with Developer ID: $SIGN_ID"
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
elif [[ -n "$SIGN_ID" ]]; then
    echo "Signing with development identity (local, stable): $SIGN_ID"
    codesign --force --options runtime --timestamp=none --sign "$SIGN_ID" "$APP"
else
    echo "No signing identity found — ad-hoc signing (permissions won't persist across rebuilds)."
    codesign --force --sign - --timestamp=none "$APP"
fi

# --- Notarize (optional) -----------------------------------------------------
if [[ -n "${BASILISK_NOTARY_PROFILE:-}" ]]; then
    if [[ "$IS_DEVID" != "1" ]]; then
        echo "Refusing to notarize: notarization needs a Developer ID cert, not a development one." >&2
        exit 1
    fi
    ZIP="build/Basilisk.zip"
    rm -f "$ZIP"
    /usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Submitting to Apple notary service…"
    xcrun notarytool submit "$ZIP" --keychain-profile "$BASILISK_NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    echo "Notarized and stapled."
fi

echo "Built $(pwd)/$APP"
