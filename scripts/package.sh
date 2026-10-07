#!/usr/bin/env bash
# Builds a Developer ID–signed, notarized and stapled "dist/PR Checker.zip",
# plus a Sparkle update feed in dist/updates/.
#
#   scripts/package.sh            build only
#   scripts/package.sh --publish  build, then upload the update to R2 so
#                                 installed apps offer it to their users
#
# One-time setup:
#   - "Developer ID Application" certificate in the login keychain
#   - xcrun notarytool store-credentials "PRChecker" --apple-id <id> --team-id L4U4H3GS68
#   - Sparkle EdDSA key in the login keychain (generate_keys)
#   - npx wrangler login (for --publish)
set -euo pipefail

PUBLISH=0
[[ "${1:-}" == "--publish" ]] && PUBLISH=1

cd "$(dirname "$0")/.."

TEAM_ID="L4U4H3GS68"
NOTARY_PROFILE="${NOTARY_PROFILE:-PRChecker}"
APP_NAME="PR Checker"
BUILD_DIR="build/release"
ARCHIVE="$BUILD_DIR/PRChecker.xcarchive"
DIST="dist"
APP="$DIST/$APP_NAME.app"
ZIP="$DIST/$APP_NAME.zip"
UPDATES="$DIST/updates"
R2_BUCKET="${R2_BUCKET:-gu-cdn}"
SPARKLE_BIN="build/SourcePackages/artifacts/sparkle/Sparkle/bin"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

step "Generating Xcode project"
xcodegen generate --quiet

step "Archiving (Release, Developer ID)"
rm -rf "$BUILD_DIR" "$DIST"
mkdir -p "$DIST"
xcodebuild archive \
  -project PRChecker.xcodeproj \
  -scheme PRChecker \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  -quiet

ditto "$ARCHIVE/Products/Applications/$APP_NAME.app" "$APP"

step "Signing Sparkle helpers"
# Xcode signs Sparkle.framework but leaves its helpers ad-hoc signed, which
# notarization rejects. Re-sign inside-out, then the app. The identity is looked
# up by fingerprint because codesign can't match the non-ASCII certificate name.
IDENTITY=$(security find-identity -v -p codesigning \
  | awk -v team="$TEAM_ID" '/Developer ID Application/ && $0 ~ team {print $2; exit}')
[[ -n "$IDENTITY" ]] || { echo "No Developer ID Application identity for $TEAM_ID" >&2; exit 1; }
sign() { codesign --force --sign "$IDENTITY" --options runtime --timestamp "$@"; }
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
sign "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
sign "$SPARKLE/Versions/B/Autoupdate"
sign "$SPARKLE/Versions/B/Updater.app"
sign "$SPARKLE"
sign --preserve-metadata=entitlements,requirements,flags "$APP"

step "Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"
SIGNATURE=$(codesign -dvv "$APP" 2>&1)
grep -q "Authority=Developer ID Application" <<<"$SIGNATURE" \
  || { echo "App is not signed with a Developer ID Application certificate" >&2; exit 1; }
grep -q "flags=.*runtime" <<<"$SIGNATURE" \
  || { echo "App is not signed with hardened runtime" >&2; exit 1; }

step "Submitting to Apple notary service (usually 1–5 min)"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

step "Stapling ticket"
xcrun stapler staple "$APP"
rm "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

step "Gatekeeper check"
spctl --assess --type execute --verbose=2 "$APP"

VERSION=$(defaults read "$PWD/$APP/Contents/Info.plist" CFBundleShortVersionString)
FEED_URL=$(defaults read "$PWD/$APP/Contents/Info.plist" SUFeedURL)
[[ "$FEED_URL" == https://* && "$FEED_URL" != *_TBD* ]] \
  || { echo "SUFeedURL is not configured: $FEED_URL" >&2; exit 1; }

step "Generating Sparkle appcast"
xcodebuild -project PRChecker.xcodeproj -scheme PRChecker -derivedDataPath build \
  -resolvePackageDependencies -quiet
mkdir -p "$UPDATES"
UPDATE_ZIP="PR-Checker-$VERSION.zip"
cp "$ZIP" "$UPDATES/$UPDATE_ZIP"
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "${FEED_URL%/*}/" \
  --maximum-deltas 0 \
  -o "$UPDATES/appcast.xml" \
  "$UPDATES"

if [[ $PUBLISH == 1 ]]; then
  # Objects live under the feed URL's path, e.g. gu-cdn.berke.dev/pr-checker/ -> "pr-checker/".
  FEED_PATH="${FEED_URL#https://*/}"
  PREFIX="${FEED_PATH%appcast.xml}"
  step "Publishing $VERSION to R2 bucket $R2_BUCKET/$PREFIX"
  # Upload the archive first so the feed never points at a missing file.
  npx --yes wrangler r2 object put "$R2_BUCKET/$PREFIX$UPDATE_ZIP" --remote \
    --file "$UPDATES/$UPDATE_ZIP" --content-type application/zip
  npx --yes wrangler r2 object put "$R2_BUCKET/${PREFIX}appcast.xml" --remote \
    --file "$UPDATES/appcast.xml" --content-type application/xml \
    --cache-control "no-cache"
  curl -fsS "$FEED_URL" | grep -q "<sparkle:shortVersionString>$VERSION<" \
    || { echo "Published feed doesn't list $VERSION yet: $FEED_URL" >&2; exit 1; }
fi

step "Done: $ZIP (version $VERSION)"
[[ $PUBLISH == 1 ]] && echo "Installed apps will offer $VERSION within a week, or right away via Check for Updates…" \
  || echo "Not published. Run with --publish to push the update."
