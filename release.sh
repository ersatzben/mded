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
#
# Publishing (the default) requires a clean working tree on main, so the tag
# always matches what was built. MDED_NO_PUBLISH=1 builds and notarises only,
# and allows a dirty tree for local testing.

set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?usage: ./release.sh <version>}"
APP_NAME="mded"
TEAM_ID="2F6498S9C9"
NOTARY_PROFILE="${MDED_NOTARY_PROFILE:-mded-notary}"
# Where the homebrew-mded tap lives locally. Used to auto-bump the cask after
# a successful release. Set MDED_TAP_DIR= to override, or MDED_NO_TAP_BUMP=1 to skip.
TAP_DIR="${MDED_TAP_DIR:-${HOME}/dev/homebrew-mded}"

BUILD_DIR="build"
DIST_DIR="dist"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
BUILT_APP="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
TAG="v${VERSION}"

PUBLISH=1
[[ "${MDED_NO_PUBLISH:-0}" == "1" ]] && PUBLISH=0

# Sanity checks before doing anything expensive.
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "✘ version must look like 1.2.3 (got '${VERSION}')" >&2
    exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
    if [[ "${PUBLISH}" == "1" ]]; then
        echo "✘ working tree has uncommitted or untracked changes; the release tag would not" >&2
        echo "  match the shipped binary. Commit or stash first (or set MDED_NO_PUBLISH=1)." >&2
        git status --short >&2
        exit 1
    fi
    echo "⚠ working tree is dirty (MDED_NO_PUBLISH set, so continuing)"
fi
if [[ "${PUBLISH}" == "1" ]]; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD)
    if [[ "${BRANCH}" != "main" ]]; then
        echo "✘ releases are cut from main (on '${BRANCH}')" >&2
        exit 1
    fi
    # Re-running after a failure partway through publishing is fine, as long as
    # the tag is still on this commit. A tag elsewhere means the version is taken.
    if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
        if [[ "$(git rev-parse "${TAG}^{commit}")" != "$(git rev-parse HEAD)" ]]; then
            echo "✘ tag ${TAG} already exists on a different commit" >&2
            exit 1
        fi
    elif git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1; then
        echo "✘ tag ${TAG} already exists on origin" >&2
        exit 1
    fi
fi
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

PLISTS=(mded/Info.plist QuickLookExtension/Info.plist)
# Until the version bump is committed, any exit (failure, or a build-only run)
# puts the plists back exactly as they were, local edits included.
PLIST_BACKUP=$(mktemp -d)
cp mded/Info.plist "${PLIST_BACKUP}/mded.plist"
cp QuickLookExtension/Info.plist "${PLIST_BACKUP}/quicklook.plist"
PLISTS_COMMITTED=0
restore_plists() {
    if [[ "${PLISTS_COMMITTED}" == "0" ]]; then
        cp "${PLIST_BACKUP}/mded.plist" mded/Info.plist
        cp "${PLIST_BACKUP}/quicklook.plist" QuickLookExtension/Info.plist
    fi
}
trap restore_plists EXIT

echo "→ stamping version ${VERSION} into Info.plists"
# CFBundleVersion is what Launch Services and pluginkit compare to choose
# between copies of the app and its Quick Look extension, so it must increase
# with every release; using the version string keeps it monotonic.
for plist in "${PLISTS[@]}"; do
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${plist}"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "${plist}"
done

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
# ourselves before continuing to staple. Echo to stderr (not /dev/tty) so the
# script also works without a terminal, e.g. in CI.
SUBMIT_OUTPUT=$(xcrun notarytool submit "${SUBMIT_ZIP}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait 2>&1 | tee /dev/stderr)
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

# ----- post-build: commit version bump, tag, GitHub release, tap bump ---------

if [[ "${PUBLISH}" == "0" ]]; then
    echo
    echo "✓ ${FINAL_ZIP} (MDED_NO_PUBLISH set — skipping git/release/tap steps;"
    echo "  Info.plists restored)"
    exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
    echo
    echo "✓ ${FINAL_ZIP}"
    echo "  (gh CLI not installed — skipping GitHub release + tap bump;"
    echo "  Info.plists restored)"
    exit 0
fi

SHA=$(shasum -a 256 "${FINAL_ZIP}" | awk '{print $1}')

echo "→ committing version bump and tagging ${TAG}"
git add "${PLISTS[@]}"
if ! git diff --cached --quiet; then
    git commit -m "Release ${VERSION}"
else
    echo "    (Info.plists already at ${VERSION} in git)"
fi
PLISTS_COMMITTED=1
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
    echo "    (tag ${TAG} already exists on this commit)"
else
    git tag -a "${TAG}" -m "mded ${VERSION}"
fi
git push origin HEAD
git push origin "${TAG}"

echo "→ creating GitHub release ${TAG}"
if gh release view "${TAG}" --repo ersatzben/mded >/dev/null 2>&1; then
    echo "    (release ${TAG} already exists — uploading asset only)"
    gh release upload "${TAG}" "${FINAL_ZIP}" --repo ersatzben/mded --clobber
else
    gh release create "${TAG}" "${FINAL_ZIP}" \
        --repo ersatzben/mded \
        --title "mded ${VERSION}" \
        --generate-notes
fi

if [[ "${MDED_NO_TAP_BUMP:-0}" == "1" ]]; then
    echo "  (MDED_NO_TAP_BUMP set — skipping homebrew-mded bump)"
elif [[ -x "${TAP_DIR}/bump-tap.sh" ]]; then
    echo "→ bumping homebrew-mded cask to ${VERSION}"
    "${TAP_DIR}/bump-tap.sh" "${VERSION}" "${SHA}"
else
    echo "  (no bump-tap.sh at ${TAP_DIR} — skipping tap bump; set MDED_TAP_DIR if it lives elsewhere)"
fi

echo
echo "✓ shipped mded ${VERSION}"
echo "  release: https://github.com/ersatzben/mded/releases/tag/${TAG}"
echo "  install: brew install --cask ersatzben/mded/mded"
