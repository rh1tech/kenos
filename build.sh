#!/bin/bash
# Assembles a double-clickable .app around the SwiftPM binary — and, when
# asked, the disk image people install it from and the ZIP the updater
# fetches.
#
#   ./build.sh                 release build, Developer ID signed when available
#   ./build.sh release dmg     + Kenos.dmg, Kenos.zip, appcast.json
#   ./build.sh release ship    + notarised (API key) and stapled
#
# Copyright © 2026 Mikhail Matveev. Published by Elizaveta Fragner.
# Signing and notarisation use the publisher's team WL6TS5H5B4 — the same
# account VideoMonk, Vardaris and Durak ship from. Credentials (never commit):
#
#   ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8   # spare copies in
#                                                        # ~/Documents/private
#   ~/.appstoreconnect/issuer_id                         # ASC issuer UUID
#
#   KENOS_SIGN_IDENTITY   override the Developer ID Application identity
#   ASC_KEY_ID           override AuthKey id (default: first AuthKey_*.p8, else TJ37YW5ULV)
#   ASC_ISSUER_ID        override issuer (default: file above)
#   KENOS_DOWNLOAD_URL    https folder for appcast links (default kenos.rh1.tech/download)
#
# Optional local NOTES.md (gitignored) is what's new: newest release first,
# one paragraph each. The first paragraph goes into the appcast, and from
# there under the version line in Settings. Keep a private copy if you like.
set -euo pipefail

cd "$(dirname "$0")"
CONFIG="${1:-release}"
STEP="${2:-app}"
APP="build/Kenos.app"
NAME="Kenos"
TEAM_ID="WL6TS5H5B4"
DEFAULT_IDENTITY="Developer ID Application: Elizaveta Fragner ($TEAM_ID)"
VERSION="$(tr -d '[:space:]' < VERSION)"
# A build number that only ever goes up, so the updater can tell newer from
# older without parsing version strings.
BUILD="$(date +%Y%m%d%H%M)"
# The oldest macOS this runs on — in the plist, and in the appcast so an
# older Mac is not handed a build it can't open.
MINIMUM="26.0"

# App Store Connect API key — same layout as videomonk / vardaris.
ASC_KEY_DIR="${ASC_KEY_DIR:-$HOME/.appstoreconnect/private_keys}"
ASC_ISSUER_FILE="${ASC_ISSUER_FILE:-$HOME/.appstoreconnect/issuer_id}"
if [ -z "${ASC_ISSUER_ID:-}" ] && [ -f "$ASC_ISSUER_FILE" ]; then
  ASC_ISSUER_ID="$(tr -d '[:space:]' < "$ASC_ISSUER_FILE")"
fi
if [ -z "${ASC_KEY_ID:-}" ]; then
  if [ -f "$ASC_KEY_DIR/AuthKey_TJ37YW5ULV.p8" ]; then
    ASC_KEY_ID="TJ37YW5ULV"
  else
    key_file="$(ls "$ASC_KEY_DIR"/AuthKey_*.p8 2>/dev/null | head -1 || true)"
    [ -n "$key_file" ] && ASC_KEY_ID="$(basename "$key_file" .p8 | sed 's/^AuthKey_//')"
  fi
fi

notarise() {  # notarise <file>
  [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] \
    || { echo "notarisation needs ASC_KEY_ID and ASC_ISSUER_ID (see header)" >&2; exit 1; }
  local key="$ASC_KEY_DIR/AuthKey_${ASC_KEY_ID}.p8"
  [ -f "$key" ] || { echo "missing $key (copy from ~/Documents/private)" >&2; exit 1; }
  echo "notarising $(basename "$1")…"
  xcrun notarytool submit "$1" \
    --key "$key" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
}

swift build -c "$CONFIG"
BINARY=".build/$CONFIG/Kenos"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$NAME"

# SwiftPM resource bundle — Bundle.module looks under Contents/Resources.
BUNDLE_SRC="$(dirname "$BINARY")/${NAME}_${NAME}.bundle"
if [ -d "$BUNDLE_SRC" ]; then
  rm -rf "$APP/Contents/Resources/${NAME}_${NAME}.bundle"
  cp -R "$BUNDLE_SRC" "$APP/Contents/Resources/"
fi

# Symbols stay out of the app. The linker leaves every function's name and a
# map back to the source in the binary — 15,000 entries, more than half of
# what the app weighed (6.5 MB of binary, 2.7 without them), and nothing the
# app reads while it runs. They are kept beside the build instead, as a dSYM
# that turns the addresses in a crash report back into names (Console, or
# atos -o build/Kenos.app.dSYM/Contents/Resources/DWARF/Kenos).
if [ "$CONFIG" = "release" ]; then
  rm -rf "$APP.dSYM"
  dsymutil "$BINARY" -o "$APP.dSYM" 2>/dev/null || echo "no dSYM this time" >&2
  strip -x "$APP/Contents/MacOS/$NAME"
fi

# The icon, drawn fresh each time — it is thirty lines of Swift, not an asset
# to keep in step with anything.
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
swift Icon/icon.swift "$ICONSET" > /dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>app.kenos.browser</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>ru</string>
  </array>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>LSMinimumSystemVersion</key><string>$MINIMUM</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 Mikhail Matveev</string>
  <key>NSHighResolutionCapable</key><true/>
  <!-- Owning http and https is what sends a link clicked in Mail here.
       Appearing in Desktop & Dock → Default web browser also needs the
       XHTML document type below. -->
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>Web address</string>
      <key>CFBundleURLSchemes</key>
      <array><string>http</string><string>https</string></array>
    </dict>
  </array>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Web page</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSItemContentTypes</key>
      <array><string>public.html</string><string>com.apple.web-internet-location</string></array>
    </dict>
    <!-- macOS only lists an app under Desktop & Dock → Default web browser
         when it claims public.xhtml as well as public.html. http and https
         alone, which Kenos already had, are not enough. -->
    <dict>
      <key>CFBundleTypeName</key><string>XHTML page</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSItemContentTypes</key>
      <array><string>public.xhtml</string></array>
    </dict>
  </array>
  <!-- A browser goes wherever it is pointed, including at http sites and at
       whatever is running on localhost. -->
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
  <!-- A browser is asked for these by the pages it shows, not by itself. macOS
       still wants a sentence to put in its own prompt, and touching the APIs
       without one is a crash rather than a refusal. -->
  <key>NSCameraUsageDescription</key>
  <string>Websites you visit can ask to use your camera. Kenos asks you the first time each site does and keeps your answer; Settings › Privacy forgets them.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Websites you visit can ask to use your microphone. Kenos asks you the first time each site does and keeps your answer; Settings › Privacy forgets them.</string>
  <key>NSDownloadsFolderUsageDescription</key>
  <string>Files you download are saved to your Downloads folder.</string>
</dict>
</plist>
PLIST

# Empty .lproj folders so Bundle.main.preferredLocalizations includes ru —
# without them AppKit keeps File / Edit / View in English even when
# AppleLanguages is set to ru.
mkdir -p "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/ru.lproj"
printf '"CFBundleName" = "Kenos";\n' > "$APP/Contents/Resources/en.lproj/InfoPlist.strings"
printf '"CFBundleName" = "Kenos";\n' > "$APP/Contents/Resources/ru.lproj/InfoPlist.strings"

# Prefer Elizaveta Fragner's Developer ID; fall back to any Developer ID
# Application in the login keychain; otherwise ad-hoc for local runs.
IDENTITY="${KENOS_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$DEFAULT_IDENTITY"; then
    IDENTITY="$DEFAULT_IDENTITY"
  else
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
      | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)"
  fi
fi
# Passkeys need an entitlement Apple grants to browsers on request, and a
# Developer ID provisioning profile that carries it. With the profile next to
# this script, both go in; without it, the app is signed as before, because
# a restricted entitlement with no profile behind it is an app that won't open.
ENTITLEMENTS="Kenos.entitlements"
if [ -f "Kenos.provisionprofile" ]; then
  cp "Kenos.provisionprofile" "$APP/Contents/embedded.provisionprofile"
  ENTITLEMENTS="Kenos.passkeys.entitlements"
  echo "passkeys: profile embedded"
fi
if [ -n "$IDENTITY" ]; then
  codesign --force --deep --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" "$APP"
  echo "signed as: $IDENTITY"
else
  codesign --force --deep --sign - "$APP" 2>/dev/null || true
  [ "$STEP" != "app" ] && echo "no Developer ID certificate found — the DMG will only open on this Mac" >&2
fi

echo "built: $APP ($VERSION, build $BUILD)"
[ "$STEP" = "app" ] && exit 0

pack_dmg() {
  # The disk image: the app beside a shortcut to Applications. Prefers dmgbuild
  # (Installer/) when available; otherwise a plain UDZO image.
  local dmg="$1"
  local art="build/installer"
  rm -rf "$art" "$dmg"
  local dmgbuild=".build/dmgbuild/bin/dmgbuild"
  if [ ! -x "$dmgbuild" ]; then
    { python3 -m venv .build/dmgbuild && .build/dmgbuild/bin/pip install --quiet "dmgbuild==1.6.7"; } >/dev/null 2>&1 || true
  fi
  if [ -x "$dmgbuild" ] \
    && swift Installer/background.swift "$art" >/dev/null \
    && tiffutil -cathidpicheck "$art/background.png" "$art/background@2x.png" -out "$art/background.tiff" >/dev/null 2>&1
  then
    "$dmgbuild" -s Installer/dmg.py \
      -D app="$APP" -D background="$art/background.tiff" -D icon="$APP/Contents/Resources/AppIcon.icns" \
      "$NAME" "$dmg" >/dev/null
  else
    echo "note: no dmgbuild — a plain disk image, without its window laid out" >&2
    local stage="build/dmg"
    rm -rf "$stage"
    mkdir -p "$stage"
    cp -R "$APP" "$stage/"
    ln -s /Applications "$stage/Applications"
    hdiutil create -volname "$NAME" -srcfolder "$stage" -ov -format UDZO -quiet "$dmg"
    rm -rf "$stage"
  fi
  rm -rf "$art"
  [ -n "$IDENTITY" ] && codesign --force --timestamp --sign "$IDENTITY" "$dmg"
}

DMG="build/$NAME.dmg"
ZIP="build/$NAME.zip"

# For "ship": notarise a ZIP of the app first, staple the .app, then rebuild
# the DMG from the stapled app and notarise+staple the DMG (same order as
# Assay Desk). For "dmg": pack once, no Apple round-trip.
if [ "$STEP" = "ship" ]; then
  [ -n "$IDENTITY" ] || { echo "can't ship without a Developer ID certificate" >&2; exit 1; }
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  notarise "$ZIP"
  xcrun stapler staple "$APP"
  echo "stapled: $APP"
  pack_dmg "$DMG"
  notarise "$DMG"
  xcrun stapler staple "$DMG"
  echo "stapled: $DMG"
  # Updater ZIP must match the stapled app.
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
else
  pack_dmg "$DMG"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
fi

echo "packed: $DMG"
SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
echo "packed: $ZIP"

# What the updater reads. The first paragraph of NOTES.md, with the two
# characters JSON minds escaped, is the line under the version in Settings.
BASE="${KENOS_DOWNLOAD_URL:-https://kenos.rh1.tech/download}"
BASE="${BASE%/}"
NOTES=""
if [ -f NOTES.md ]; then
  NOTES="$(awk 'NF { printf "%s%s", (n++ ? " " : ""), $0; next } n { exit }' NOTES.md \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
fi
cat > build/appcast.json <<JSON
{
  "version": "$VERSION",
  "build": $BUILD,
  "url": "$BASE/$NAME.zip",
  "dmg": "$BASE/$NAME.dmg",
  "sha256": "$SHA",
  "notes": "$NOTES",
  "minimumSystemVersion": "$MINIMUM"
}
JSON
echo "wrote: build/appcast.json ($VERSION, build $BUILD)"
[ "$STEP" = "dmg" ] && exit 0

echo "shipped: $DMG, $ZIP and build/appcast.json"
spctl --assess -vv --type install "$DMG" 2>&1 | sed 's/^/  /' || true
xcrun stapler validate "$APP" 2>&1 | sed 's/^/  /' || true
xcrun stapler validate "$DMG" 2>&1 | sed 's/^/  /' || true
