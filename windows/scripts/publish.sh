#!/usr/bin/env bash
# Publishes a Windows release built by the "Windows release" workflow:
# uploads the Velopack feed to the CDN and creates the GitHub release.
#
#   windows/scripts/publish.sh <run-id> [notes.md]
#
# notes.md, if given, opens the release notes; install instructions are added after it.
#
# Needs: gh (logged in), npx wrangler@4.148.0 login.
# Releases are tagged <OS>-v<version>: windows-v0.1.0, macOS-v0.2.7.
set -euo pipefail
cd "$(dirname "$0")/.."

RUN_ID="${1:?usage: $0 <run-id of the Windows release workflow> [notes.md]}"
NOTES_FILE="${2:-}"
[[ -z "$NOTES_FILE" || -f "$NOTES_FILE" ]] || { echo "No notes file: $NOTES_FILE" >&2; exit 1; }
[[ -z "$NOTES_FILE" ]] || NOTES_FILE="$(cd "$(dirname "$NOTES_FILE")" && pwd)/$(basename "$NOTES_FILE")"
REPO="itsberkelium/PR-Checker"
R2_BUCKET="${R2_BUCKET:-gu-cdn-eeur}"
PREFIX="pr-checker/windows"
FEED="https://gu-cdn.berke.dev/$PREFIX"
WRANGLER=(npx --yes wrangler@4.148.0)

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

step "Downloading release files from run $RUN_ID"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
gh run download "$RUN_ID" --repo "$REPO" --dir "$WORK"
# The workflow uploads one artifact per architecture; publish them together.
ARM=$(find "$WORK" -maxdepth 1 -type d -name 'windows-release-*-win-arm64' | head -1)
[[ -n "$ARM" ]] || { echo "No windows-release-*-win-arm64 artifact in run $RUN_ID" >&2; exit 1; }
VERSION="${ARM##*windows-release-}"
VERSION="${VERSION%-win-arm64}"
DIR="$WORK/all"
mkdir -p "$DIR"
for rid in win-arm64 win-x64; do
  [[ -d "$WORK/windows-release-$VERSION-$rid" ]] || { echo "Missing $rid artifact for $VERSION" >&2; exit 1; }
  cp "$WORK/windows-release-$VERSION-$rid"/* "$DIR"/
done
ls -la "$DIR"

for rid in win-arm64 win-x64; do
  [[ -f "$DIR/releases.$rid.json" && -f "$DIR/PRCheckerApp-$rid-Setup.exe" ]] \
    || { echo "Missing $rid feed or installer" >&2; exit 1; }
  grep -qE "\"Version\": *\"$VERSION\"" "$DIR/releases.$rid.json" \
    || { echo "releases.$rid.json doesn't list $VERSION" >&2; exit 1; }
done

step "Uploading $VERSION to $R2_BUCKET/$PREFIX"
# Packages and installers first, feeds last, so a feed never points at a missing file.
for file in "$DIR"/*; do
  name=$(basename "$file")
  case "$name" in releases.*.json|RELEASES*|assets.*.json) continue ;; esac
  "${WRANGLER[@]}" r2 object put "$R2_BUCKET/$PREFIX/$name" --remote --file "$file" 2>&1 | grep -E "Upload complete|rror"
done
for file in "$DIR"/releases.*.json "$DIR"/RELEASES* "$DIR"/assets.*.json; do
  [[ -f "$file" ]] || continue
  "${WRANGLER[@]}" r2 object put "$R2_BUCKET/$PREFIX/$(basename "$file")" --remote --file "$file" \
    --cache-control "no-cache" 2>&1 | grep -E "Upload complete|rror"
done

for rid in win-arm64 win-x64; do
  curl -fsS "$FEED/releases.$rid.json" | grep -qE "\"Version\": *\"$VERSION\"" \
    || { echo "Published $rid feed doesn't list $VERSION" >&2; exit 1; }
done

TAG="windows-v$VERSION"
step "Creating GitHub release $TAG"
# Tag the exact commit CI built, not whatever main points to now.
COMMIT=$(gh run view "$RUN_ID" --repo "$REPO" --json headSha --jq .headSha)
git fetch --quiet
git tag -a "$TAG" "$COMMIT" -m "PR Checker for Windows $VERSION"
git push --quiet origin "$TAG"
gh release create "$TAG" --repo "$REPO" --verify-tag \
  --title "PR Checker for Windows $VERSION" \
  --notes "$( [[ -n "$NOTES_FILE" ]] && { cat "$NOTES_FILE"; printf '\n\n'; }
    echo "### Install"
    echo "Download **PRCheckerApp-win-x64-Setup.exe** for most PCs, or **PRCheckerApp-win-arm64-Setup.exe** for ARM PCs (e.g. Snapdragon, or Windows on Apple Silicon). The installers aren't code-signed yet: Windows SmartScreen asks once, choose **More info → Run anyway**. Installed apps update themselves." )" \
  "$DIR/PRCheckerApp-win-arm64-Setup.exe" "$DIR/PRCheckerApp-win-x64-Setup.exe" \
  "$DIR/PRCheckerApp-win-arm64-Portable.zip" "$DIR/PRCheckerApp-win-x64-Portable.zip"

../scripts/release-badge.sh Windows "$TAG"

step "Done: $VERSION published; installed apps are offered it within a week"
