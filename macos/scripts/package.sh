#!/usr/bin/env bash
# Builds a Developer ID–signed, notarized and stapled "dist/PR Checker.zip",
# plus a Sparkle update feed in dist/updates/.
#
#   scripts/package.sh            build only
#   scripts/package.sh --publish [notes.md]
#                                 build, upload the update to R2 so installed
#                                 apps offer it, create the GitHub release
#                                 macOS-v<version> (notes from notes.md, or
#                                 generated)
#   scripts/package.sh --local    sign with Developer ID and install into
#                                 /Applications for testing; no notarization,
#                                 nothing published. Don't distribute this build.
#
# One-time setup:
#   - "Developer ID Application" certificate in the login keychain
#   - xcrun notarytool store-credentials "PRChecker" --apple-id <id> --team-id L4U4H3GS68
#   - Sparkle EdDSA key in the login keychain (generate_keys)
#   - npx wrangler@4.148.0 login and gh auth login (for --publish)
#
# Releases are tagged <OS>-v<version>: macOS-v0.2.7, windows-v0.1.0.
set -euo pipefail

PUBLISH=0
LOCAL=0
NOTES_FILE=""
case "${1:-}" in
  --publish) PUBLISH=1; NOTES_FILE="${2:-}" ;;
  --local) LOCAL=1 ;;
  "") ;;
  *) echo "usage: $0 [--publish [notes.md] | --local]" >&2; exit 2 ;;
esac
[[ -z "$NOTES_FILE" ]] || NOTES_FILE="$(cd "$(dirname "$NOTES_FILE")" && pwd)/$(basename "$NOTES_FILE")"

cd "$(dirname "$0")/.."

if [[ $PUBLISH == 1 ]]; then
  # The release is tagged at HEAD, so it must be exactly what's on GitHub.
  git diff --quiet && git diff --cached --quiet \
    || { echo "Uncommitted changes; commit them before publishing" >&2; exit 1; }
  git fetch --quiet
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse @{u})" ]] \
    || { echo "HEAD isn't the pushed upstream; push or pull first" >&2; exit 1; }
  [[ -z "$NOTES_FILE" || -f "$NOTES_FILE" ]] || { echo "No notes file: $NOTES_FILE" >&2; exit 1; }
  # wrangler 4 needs Node.js 20+; an older node first on PATH fails mid-release.
  NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)
  (( NODE_MAJOR >= 20 )) || { echo "Publishing needs Node.js 20 or later on PATH (found $(node --version 2>/dev/null || echo none))" >&2; exit 1; }
fi

TEAM_ID="L4U4H3GS68"
NOTARY_PROFILE="${NOTARY_PROFILE:-PRChecker}"
APP_NAME="PR Checker"
BUILD_DIR="build/release"
ARCHIVE="$BUILD_DIR/PRChecker.xcarchive"
DIST="dist"
APP="$DIST/$APP_NAME.app"
ZIP="$DIST/$APP_NAME.zip"
UPDATES="$DIST/updates"
R2_BUCKET="${R2_BUCKET:-gu-cdn-eeur}"
SPARKLE_BIN="build/SourcePackages/artifacts/sparkle/Sparkle/bin"
SPARKLE_VERSION="2.10.0" # keep in sync with project.yml
# Exact version so publishing never runs a newly released, unreviewed wrangler.
WRANGLER=(npx --yes wrangler@4.148.0)

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
BUNDLED_SPARKLE=$(defaults read "$PWD/$SPARKLE/Versions/B/Resources/Info.plist" CFBundleShortVersionString)
[[ "$BUNDLED_SPARKLE" == "$SPARKLE_VERSION" ]] \
  || { echo "Bundled Sparkle is $BUNDLED_SPARKLE, expected $SPARKLE_VERSION" >&2; exit 1; }
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

if [[ $LOCAL == 1 ]]; then
  step "Installing into /Applications"
  INSTALLED="/Applications/$APP_NAME.app"
  osascript -e 'tell application id "dev.berke.PRChecker" to quit' 2>/dev/null || true
  for _ in 1 2 3 4 5; do pgrep -f "$APP_NAME.app/Contents/MacOS" >/dev/null || break; sleep 1; done
  if pgrep -f "$APP_NAME.app/Contents/MacOS" >/dev/null; then
    echo "$APP_NAME is still running; quit it and try again." >&2; exit 1
  fi
  rm -rf "$INSTALLED"
  ditto "$APP" "$INSTALLED"
  open "$INSTALLED"
  step "Done: local build installed (not notarized, not published)"
  exit 0
fi

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
  "${WRANGLER[@]}" r2 object put "$R2_BUCKET/$PREFIX$UPDATE_ZIP" --remote \
    --file "$UPDATES/$UPDATE_ZIP" --content-type application/zip
  "${WRANGLER[@]}" r2 object put "$R2_BUCKET/${PREFIX}appcast.xml" --remote \
    --file "$UPDATES/appcast.xml" --content-type application/xml \
    --cache-control "no-cache"
  curl -fsS "$FEED_URL" | grep -q "<sparkle:shortVersionString>$VERSION<" \
    || { echo "Published feed doesn't list $VERSION yet: $FEED_URL" >&2; exit 1; }

  TAG="macOS-v$VERSION"
  step "Creating GitHub release $TAG"
  git tag -a "$TAG" -m "PR Checker for macOS $VERSION"
  git push --quiet origin "$TAG"
  NOTES=(--generate-notes)
  [[ -n "$NOTES_FILE" ]] && NOTES=(--notes-file "$NOTES_FILE")
  gh release create "$TAG" --verify-tag --title "PR Checker for macOS $VERSION" "${NOTES[@]}" \
    "$UPDATES/$UPDATE_ZIP"
fi

step "Done: $ZIP (version $VERSION)"
[[ $PUBLISH == 1 ]] && echo "Installed apps will offer $VERSION within a week, or right away via Check for Updates…" \
  || echo "Not published. Run with --publish to push the update."
