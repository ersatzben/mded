#!/usr/bin/env bash
# Build, sign with Developer ID, notarize, and staple a shareable mded.app.zip.
#
# One-time setup (stores credentials in your login keychain):
#   xcrun notarytool store-credentials "mded-notary" \
#       --apple-id "you@example.com" \
#       --team-id "2F6498S9C9" \
#       --password "xxxx-xxxx-xxxx-xxxx"   # app-specific password from appleid.apple.com
#
# Usage:
#   ./release.sh <version>            e.g. ./release.sh 1.0.0
#
# Output:
#   dist/mded-<version>.zip   notarized, stapled, ready to upload to a GitHub Release

set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?usage: ./release.sh <version>}"
APP_NAME="mded"
TEAM_ID="2F6498S9C9"
NOTARY_PROFILE="${MDED_NOTARY_PROFILE:-mded-notary}"

BUILD_DIR="build"
DIST_DIR="dist"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
BUILT_APP="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"

# Sanity checks before doing anything expensive.
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "✘ No 'Developer ID Application' identity in keychain. Install your cert first." >&2
    exit 1
fi
if ! xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
    echo "✘ Notary profile '${NOTARY_PROFILE}' not found in keychain." >&2
    echo "  Run: xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" \\" >&2
    echo "         --apple-id <your-apple-id> --team-id ${TEAM_ID} --password <app-specific-password>" >&2
    exit 1
fi

if command -v xcodegen >/dev/null 2>&1; then
    echo "→ regenerating xcode project"
    xcodegen generate --quiet
fi

echo "→ stamping version ${VERSION} into Info.plists"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" mded/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" QuickLookExtension/Info.plist

echo "→ building Release with Developer ID signing + Hardened Runtime"
rm -rf "${BUILD_DIR}"
xcodebuild \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}" \
    -quiet \
    build

if [[ ! -d "${BUILT_APP}" ]]; then
    echo "✘ build did not produce ${BUILT_APP}" >&2
    exit 1
fi

echo "→ verifying signature chain"
codesign --verify --deep --strict --verbose=2 "${BUILT_APP}" 2>&1 | sed 's/^/    /'

echo "→ confirming Hardened Runtime + Developer ID on the main binary"
codesign -d --verbose=4 "${BUILT_APP}" 2>&1 | grep -E "(Authority|flags|TeamIdentifier|runtime)" | sed 's/^/    /'

mkdir -p "${DIST_DIR}"
SUBMIT_ZIP="${DIST_DIR}/${APP_NAME}-${VERSION}-prestaple.zip"
FINAL_ZIP="${DIST_DIR}/${ZIP_NAME}"

echo "→ zipping for notarization submission"
rm -f "${SUBMIT_ZIP}"
ditto -c -k --keepParent "${BUILT_APP}" "${SUBMIT_ZIP}"

echo "→ submitting to Apple notary service (this takes 1–5 minutes)"
# notarytool exits 0 even when status=Invalid, so capture output and check status
# ourselves before continuing to staple.
SUBMIT_OUTPUT=$(xcrun notarytool submit "${SUBMIT_ZIP}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait 2>&1 | tee /dev/tty)
SUBMISSION_ID=$(echo "${SUBMIT_OUTPUT}" | awk '/^[[:space:]]*id:/ {print $2; exit}')
STATUS=$(echo "${SUBMIT_OUTPUT}" | awk '/^[[:space:]]*status:/ {s=$2} END {print s}')

if [[ "${STATUS}" != "Accepted" ]]; then
    echo "✘ notarization status: ${STATUS:-unknown}" >&2
    if [[ -n "${SUBMISSION_ID}" ]]; then
        echo "→ fetching log for submission ${SUBMISSION_ID}" >&2
        xcrun notarytool log "${SUBMISSION_ID}" --keychain-profile "${NOTARY_PROFILE}" >&2 || true
    fi
    exit 1
fi

echo "→ stapling the ticket onto the .app"
xcrun stapler staple "${BUILT_APP}"
xcrun stapler validate "${BUILT_APP}"

echo "→ producing final stapled zip"
rm -f "${FINAL_ZIP}" "${SUBMIT_ZIP}"
ditto -c -k --keepParent "${BUILT_APP}" "${FINAL_ZIP}"

echo "→ Gatekeeper assessment on the stapled app"
spctl -a -vvv -t install "${BUILT_APP}" 2>&1 | sed 's/^/    /'

echo
echo "✓ ${FINAL_ZIP}"
echo "  upload to a GitHub Release; colleagues unzip and double-click — no warnings."
