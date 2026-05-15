#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="mded"
BUNDLE_ID="com.mded.app"
QL_BUNDLE_ID="com.mded.app.quicklook"
BUILD_DIR="build"
DEST="/Applications/${APP_NAME}.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if command -v xcodegen >/dev/null 2>&1; then
    echo "→ regenerating xcode project"
    xcodegen generate --quiet
fi

echo "→ building Release"
xcodebuild \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}" \
    CODE_SIGN_IDENTITY=- \
    -quiet \
    build

BUILT_APP="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "${BUILT_APP}" ]]; then
    echo "✘ build did not produce ${BUILT_APP}" >&2
    exit 1
fi

echo "→ installing to ${DEST}"
rm -rf "${DEST}"
cp -R "${BUILT_APP}" "${DEST}"
xattr -dr com.apple.quarantine "${DEST}" 2>/dev/null || true

echo "→ refreshing Launch Services + Quick Look"
# Unregister every mded.app bundle macOS knows about (DerivedData, prior installs,
# stray copies), then register the one in /Applications. Without this, xcodebuild's
# default DerivedData output keeps re-claiming the QL extension binding.
while IFS= read -r stray; do
    [[ -z "$stray" ]] && continue
    echo "  - unregistering ${stray}"
    "${LSREGISTER}" -u "${stray}" >/dev/null 2>&1 || true
done < <(find "${HOME}/Library/Developer/Xcode/DerivedData" -maxdepth 6 -name "${APP_NAME}.app" -type d 2>/dev/null)
"${LSREGISTER}" -u "${DEST}" >/dev/null 2>&1 || true
"${LSREGISTER}" -f "${DEST}"
pluginkit -e use -i "${QL_BUNDLE_ID}" >/dev/null 2>&1 || true
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true
# Kill any in-memory Quick Look preview hosts so they reload the new extension.
# `qlmanage -r cache` clears file caches but doesn't restart the XPC services.
pkill -f QuickLookUIService 2>/dev/null || true
pkill -f QuickLookSatellite 2>/dev/null || true
killall Finder >/dev/null 2>&1 || true

echo
echo "✓ installed ${DEST}"
echo "  first launch: right-click → Open (Gatekeeper prompts once for ad-hoc signing)"
echo "  Quick Look: select a .md in Finder and press space"
