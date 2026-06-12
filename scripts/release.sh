#!/bin/bash
set -e

# Stills From Video — Release Script
# Run on the Mac that holds the o388… Sparkle private key (see docs/sparkle-signing.md)
# and a notarytool keychain profile (see docs/RELEASE.md).
#
# Usage: ./scripts/release.sh [version]
# Example: ./scripts/release.sh 0.1
#
# Produces a notarized, stapled, Sparkle-signed DMG in ./releases/ and prints
# the appcast.xml <item> to paste in.

cd "$(dirname "$0")/.."
PROJECT_ROOT=$(pwd)
PROJECT_NAME="ScreenshotFromVideos"      # Xcode target / scheme / .app name
DISPLAY_NAME="Stills From Video"         # DMG volume name (matches CFBundleDisplayName)
DMG_BASENAME="StillsFromVideo"           # DMG filename stem → StillsFromVideo-<version>.dmg
XCODEPROJ="01_Project/$PROJECT_NAME.xcodeproj"

# --- Version (arg, else project.yml MARKETING_VERSION) ---
if [ -n "$1" ]; then
    VERSION="$1"
else
    VERSION=$(grep "MARKETING_VERSION:" 01_Project/project.yml | head -1 | cut -d'"' -f2)
fi
echo "=== Releasing $DISPLAY_NAME $VERSION ==="

# --- Paths ---
BUILD="$PROJECT_ROOT/build"
ARCHIVE_PATH="$BUILD/$PROJECT_NAME.xcarchive"
EXPORT_PATH="$BUILD/export"
APP_PATH="$EXPORT_PATH/$PROJECT_NAME.app"
DMG_NAME="$DMG_BASENAME-$VERSION.dmg"
DMG_PATH="$BUILD/$DMG_NAME"
RELEASES_DIR="$PROJECT_ROOT/releases"

# --- Regenerate project (the .xcodeproj is gitignored / xcodegen-driven) ---
echo ""
echo "🛠  Step 0: xcodegen generate..."
( cd 01_Project && xcodegen generate >/dev/null )
echo "✅ Project regenerated"

# --- Sparkle tools (present after the project has resolved packages once) ---
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
SPARKLE_BIN=$(find "$DERIVED_DATA" -path "*$PROJECT_NAME*/SourcePackages/artifacts/sparkle/Sparkle/bin" -type d 2>/dev/null | head -1)
if [ -z "$SPARKLE_BIN" ]; then
    echo "❌ Sparkle tools not found. Build the project in Xcode once first to resolve packages."
    exit 1
fi

# --- Verify the signing key on THIS Mac is the expected one ---
EXPECTED_KEY="o388Mk7QoQjHQ7PBDGrTQ13HkqvO1nyzkfcnmfVumUQ="
ACTUAL_KEY=$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null || true)
if [ "$ACTUAL_KEY" != "$EXPECTED_KEY" ]; then
    echo "❌ Sparkle private key mismatch."
    echo "   Keychain public key: ${ACTUAL_KEY:-<none found>}"
    echo "   Expected:            $EXPECTED_KEY"
    echo "   Import the o388… key first — see docs/sparkle-signing.md."
    exit 1
fi
echo "✅ Signing key verified ($EXPECTED_KEY)"

rm -rf "$BUILD"; mkdir -p "$BUILD" "$RELEASES_DIR"

# --- Step 1: Archive ---
echo ""
echo "📦 Step 1: Archiving..."
xcodebuild archive \
    -project "$XCODEPROJ" \
    -scheme "$PROJECT_NAME" \
    -archivePath "$ARCHIVE_PATH" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    | grep -E "(Archive|error:|warning:.*$PROJECT_NAME)" || true
[ -d "$ARCHIVE_PATH" ] || { echo "❌ Archive failed"; exit 1; }
echo "✅ Archive created"

# --- Step 2: Export (Developer ID, automatic signing) ---
echo ""
echo "📤 Step 2: Exporting (developer-id)..."
cat > "$BUILD/ExportOptions.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$BUILD/ExportOptions.plist" \
    | grep -E "(Export|error:)" || true
[ -d "$APP_PATH" ] || { echo "❌ Export failed"; exit 1; }
echo "✅ App exported"

BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP_PATH/Contents/Info.plist")

# --- Step 3: Build DMG (app + Applications symlink) ---
echo ""
echo "💿 Step 3: Building DMG..."
STAGE="$BUILD/dmg-stage"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$DISPLAY_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG_PATH" >/dev/null
echo "✅ DMG created: $DMG_PATH"

# --- Step 4: Notarize + staple the DMG ---
echo ""
echo "🔏 Step 4: Notarizing (a few minutes)..."
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "notarytool" \
    --wait 2>&1 | tee "$BUILD/notarize.log"
xcrun stapler staple "$DMG_PATH"
echo "✅ Notarized + stapled"

# --- Step 5: Sign for Sparkle ---
echo ""
echo "🔑 Step 5: Signing for Sparkle..."
SIGNATURE=$("$SPARKLE_BIN/sign_update" "$DMG_PATH")   # → sparkle:edSignature="…" length="…"
echo "   $SIGNATURE"

cp "$DMG_PATH" "$RELEASES_DIR/"
PUB_DATE=$(date -R)

# --- Output appcast item ---
echo ""
echo "=== Add this to appcast.xml (newest first) ==="
cat << APPCAST

        <item>
            <title>Version $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$BUILD_NUMBER</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            <enclosure
                url="https://github.com/Xpycode/ScreenshotFromVideos/releases/download/v$VERSION/$DMG_NAME"
                $SIGNATURE
                type="application/octet-stream"
            />
        </item>
APPCAST

echo ""
echo "=== Next steps ==="
echo "1. Paste the <item> above into appcast.xml (newest first), commit + push to main."
echo "2. Create GitHub Release v$VERSION on Xpycode/ScreenshotFromVideos."
echo "3. Upload releases/$DMG_NAME to that release."
echo "4. Done — installed v0.1 apps will see the next release via the feed."
echo ""
echo "✅ Release build complete!"
