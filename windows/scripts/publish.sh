#!/usr/bin/env bash
# Publishes a Windows release built by the "Windows release" workflow:
# uploads the Velopack feed to the CDN and creates the GitHub release.
#
#   windows/scripts/publish.sh [--files <dir>] <run-id> [notes.md]
#   windows/scripts/publish.sh --dev [--files <dir>] <run-id>
#
# notes.md, if given, opens the release notes; install instructions are added after it.
# --dev publishes a dev build (run with a dev_version) to the dev feed only: only apps on
# the dev channel offer it. No tag, no GitHub release.
# --files <dir> publishes the run's windows-release-* artifacts from <dir> (as downloaded
# zips or unpacked folders) instead of downloading them, e.g. over a connection that keeps
# dropping. The run's branch and the versions are still checked.
#
# Needs: gh (logged in), npx wrangler@4.148.0 login.
# Releases are tagged <OS>-v<version>: windows-v0.1.0, macOS-v0.2.7.
set -euo pipefail
cd "$(dirname "$0")/.."

DEV=0
FILES=""
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --dev) DEV=1; shift ;;
    --files) FILES="${2:?--files needs a directory}"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
[[ -z "$FILES" || -d "$FILES" ]] || { echo "No such directory: $FILES" >&2; exit 1; }
RUN_ID="${1:?usage: $0 [--dev] [--files <dir>] <run-id of the Windows release workflow> [notes.md]}"
NOTES_FILE="${2:-}"
[[ -z "$NOTES_FILE" || -f "$NOTES_FILE" ]] || { echo "No notes file: $NOTES_FILE" >&2; exit 1; }
[[ -z "$NOTES_FILE" ]] || NOTES_FILE="$(cd "$(dirname "$NOTES_FILE")" && pwd)/$(basename "$NOTES_FILE")"
# wrangler 4 needs Node.js 20+; an older node first on PATH fails mid-release.
NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)
(( NODE_MAJOR >= 20 )) || { echo "Publishing needs Node.js 20 or later on PATH (found $(node --version 2>/dev/null || echo none))" >&2; exit 1; }

REPO="itsberkelium/PR-Checker"
R2_BUCKET="${R2_BUCKET:-gu-cdn-eeur}"
PREFIX="pr-checker/windows"
# Matches UpdateService.DevFeedUrl in the app.
[[ $DEV == 1 ]] && PREFIX="pr-checker/dev/windows"
FEED="https://gu-cdn.berke.dev/$PREFIX"
WRANGLER=(npx --yes wrangler@4.148.0)

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

# Uploads one file; prints "Upload complete", or wrangler's whole output when it fails.
put() {
  local output
  if output=$("${WRANGLER[@]}" r2 object put "$@" --remote 2>&1); then
    grep -m1 "Upload complete" <<<"$output"
  else
    printf '%s\n' "$output" >&2
    return 1
  fi
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
if [[ -n "$FILES" ]]; then
  step "Using release files from $FILES for run $RUN_ID"
  for item in "$FILES"/windows-release-*; do
    name=$(basename "$item" .zip)
    if [[ "$item" == *.zip ]]; then unzip -q "$item" -d "$WORK/$name"; else cp -R "$item" "$WORK/$name"; fi
  done
else
  step "Downloading release files from run $RUN_ID"
  # Only the two release artifacts; the run's Setup-* artifacts are copies of the installers in them.
  NAMES=()
  while IFS= read -r name; do NAMES+=(--name "$name"); done < <(gh api "repos/$REPO/actions/runs/$RUN_ID/artifacts" \
    --jq '.artifacts[].name | select(startswith("windows-release-"))')
  (( ${#NAMES[@]} == 4 )) || { echo "Run $RUN_ID doesn't have both windows-release-* artifacts" >&2; exit 1; }
  gh run download "$RUN_ID" --repo "$REPO" --dir "$WORK" "${NAMES[@]}"
fi
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
# Releases are built from main, dev builds from dev.
BRANCH=$(gh run view "$RUN_ID" --repo "$REPO" --json headBranch --jq .headBranch)
EXPECTED=main
[[ $DEV == 1 ]] && EXPECTED=dev
[[ "$BRANCH" == "$EXPECTED" ]] || { echo "Run $RUN_ID built $BRANCH; publish only runs from $EXPECTED" >&2; exit 1; }
# A release goes to everyone, so it can't be a dev version, and a dev build can't go to everyone.
if [[ $DEV == 1 ]]; then
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-dev\.[0-9]+$ ]] \
    || { echo "$VERSION isn't a dev version; run the workflow with dev_version, e.g. 0.3.0-dev.1" >&2; exit 1; }
else
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || { echo "$VERSION is a dev version; publish it with --dev" >&2; exit 1; }
fi

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
  put "$R2_BUCKET/$PREFIX/$name" --file "$file"
done
for file in "$DIR"/releases.*.json "$DIR"/RELEASES* "$DIR"/assets.*.json; do
  [[ -f "$file" ]] || continue
  put "$R2_BUCKET/$PREFIX/$(basename "$file")" --file "$file" --cache-control "no-cache"
done

for rid in win-arm64 win-x64; do
  curl -fsS "$FEED/releases.$rid.json" | grep -qE "\"Version\": *\"$VERSION\"" \
    || { echo "Published $rid feed doesn't list $VERSION" >&2; exit 1; }
done

if [[ $DEV == 1 ]]; then
  step "Done: dev build $VERSION is on the dev feed"
  echo "Apps on the dev channel offer it via Check for updates. Nothing was tagged or released."
  exit 0
fi

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

step "Done: $VERSION published; installed apps are offered it within a week"
