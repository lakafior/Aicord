#!/usr/bin/env bash
# Builds the signed iOS app for AltStore PAL:
#
#   ./scripts/build-ios.sh archive   archives with Apple Distribution signing and exports the IPA to
#                                    build/ios-export, without sending it anywhere: a check of signing.
#   ./scripts/build-ios.sh upload    the same archive, uploaded to App Store Connect, where
#                                    scripts/asc-notarize.py submits it for notarization.
#
# The unsigned IPA for sideloading is built by .github/workflows/release.yml.
#
# Needs an Apple account that may create App Store profiles: locally the one in Xcode, in CI the
# App Store Connect key (NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID) and the Apple Distribution
# certificate in the keychain. The build is marked AICORD_DISTRIBUTION=altstore-pal, which turns off the
# GitHub update check (AltStore updates it). VERSION overrides the project's MARKETING_VERSION (CI passes the tag).
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-}"
[[ "$MODE" == archive || "$MODE" == upload ]] || { echo "Usage: $0 archive|upload" >&2; exit 2; }

PBX=Aicord.xcodeproj/project.pbxproj
VERSION="${VERSION:-$(sed -nE 's/^[[:space:]]*MARKETING_VERSION = ([^;]+);/\1/p' "$PBX" | head -1)}"
# The app target's team (the project level still carries upstream's).
TEAM="$(grep -B90 'PRODUCT_BUNDLE_IDENTIFIER = net.smigi.aicord;' "$PBX" \
  | sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM = ([A-Z0-9]+);/\1/p' | tail -1)"
[[ -n "$VERSION" ]] || { echo "No MARKETING_VERSION in $PBX" >&2; exit 1; }
[[ -n "$TEAM" ]] || { echo "No DEVELOPMENT_TEAM for net.smigi.aicord in $PBX" >&2; exit 1; }
# App Store Connect refuses a build number it has seen for this version.
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
echo "Aicord iOS $VERSION ($BUILD), $MODE, team $TEAM"

if [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
  AUTH=(-allowProvisioningUpdates
        -authenticationKeyPath "$NOTARY_KEY_PATH"
        -authenticationKeyID "${NOTARY_KEY_ID:?}"
        -authenticationKeyIssuerID "${NOTARY_ISSUER_ID:?}")
else
  AUTH=(-allowProvisioningUpdates)
fi

ARCHIVE="build/AicordIOS.xcarchive"
EXPORT="build/ios-export"
LOG="build/ios-archive.log"
mkdir -p build
rm -rf "$ARCHIVE" "$EXPORT"
xcodebuild archive \
  -workspace Aicord.xcworkspace \
  -scheme Aicord \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -skipMacroValidation -skipPackagePluginValidation \
  "${AUTH[@]}" \
  AICORD_DISTRIBUTION=altstore-pal \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD" > "$LOG" 2>&1 \
  || { grep -E 'error:|\*\* ARCHIVE' "$LOG" | head -40; exit 1; }
grep -E '\*\* ARCHIVE' "$LOG"

[[ "$MODE" == upload ]] && DESTINATION=upload || DESTINATION=export
OPTS="$(mktemp -t aicord-export).plist"
cat > "$OPTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$DESTINATION</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist "$OPTS" \
  "${AUTH[@]}"
rm -f "$OPTS"
if [[ "$MODE" == upload ]]; then
  echo "Uploaded: Aicord iOS $VERSION ($BUILD)"
else
  echo "Exported, not uploaded: $EXPORT"
fi
echo "BUILD=$BUILD"
