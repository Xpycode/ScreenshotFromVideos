#!/bin/bash
set -e

# Sign an already-built DMG for Sparkle, and print the appcast item.
# Use this if you exported/notarized manually (Xcode Organizer) instead of
# running release.sh. Assumes the DMG is already notarized + stapled.
#
# Usage: ./scripts/sign-for-sparkle.sh /path/to/StillsFromVideo-0.1.dmg [version]

if [ -z "$1" ]; then
    echo "Usage: ./scripts/sign-for-sparkle.sh /path/to/StillsFromVideo-<version>.dmg [version]"
    exit 1
fi

DMG_PATH="$1"
PROJECT_NAME="ScreenshotFromVideos"
cd "$(dirname "$0")/.."

if [ -n "$2" ]; then
    VERSION="$2"
else
    VERSION=$(grep "MARKETING_VERSION:" 01_Project/project.yml | head -1 | cut -d'"' -f2)
fi

DMG_NAME=$(basename "$DMG_PATH")
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
SPARKLE_BIN=$(find "$DERIVED_DATA" -path "*$PROJECT_NAME*/SourcePackages/artifacts/sparkle/Sparkle/bin" -type d 2>/dev/null | head -1)
[ -n "$SPARKLE_BIN" ] || { echo "❌ Sparkle tools not found. Build once in Xcode first."; exit 1; }

# Sanity: the Keychain key must be the o388… key
EXPECTED_KEY="o388Mk7QoQjHQ7PBDGrTQ13HkqvO1nyzkfcnmfVumUQ="
ACTUAL_KEY=$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null || true)
[ "$ACTUAL_KEY" = "$EXPECTED_KEY" ] || { echo "❌ Wrong/no signing key in Keychain (${ACTUAL_KEY:-none}). See docs/sparkle-signing.md."; exit 1; }

echo "=== Signing $DMG_NAME for Sparkle ==="
SIGNATURE=$("$SPARKLE_BIN/sign_update" "$DMG_PATH")
PUB_DATE=$(date -R)

cat << APPCAST

        <item>
            <title>Version $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>FILL_CFBundleVersion</sparkle:version>
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
echo "⚠️  Set sparkle:version to the DMG's CFBundleVersion (release.sh fills this automatically)."
