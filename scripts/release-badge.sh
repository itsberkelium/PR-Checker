#!/usr/bin/env bash
# Sets a README release badge's version and link to a release and opens a pull request with
# that change (main only accepts changes through pull requests), or adds it to a badge PR
# that's still open, so releasing both platforms gives one PR instead of two conflicting
# ones. Called by the release scripts after a release is created. Works in a temporary
# worktree, so the current checkout and branch aren't touched.
#
#   scripts/release-badge.sh <macOS|Windows> <tag>     e.g. scripts/release-badge.sh macOS macOS-v0.2.8
#
# The badges are static shields.io badges ("<logo> macOS | v0.2.7") so they always match the
# release they link to.
set -euo pipefail
cd "$(dirname "$0")/.."

LABEL="${1:?usage: $0 <macOS|Windows> <tag>}"
TAG="${2:?usage: $0 <macOS|Windows> <tag>}"
case "$LABEL" in macOS|Windows) ;; *) echo "Label must be macOS or Windows" >&2; exit 2 ;; esac

REPO="itsberkelium/PR-Checker"
WORKTREE=$(mktemp -d)
LOCAL_BRANCH="release-badge-work-$$"
trap 'git worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true; git branch --quiet -D "$LOCAL_BRANCH" >/dev/null 2>&1 || true' EXIT

# Reuse an open badge PR (e.g. when both platforms release together), so two PRs never
# edit the neighbouring badge lines and conflict.
OPEN_PR=$(gh pr list --repo "$REPO" --state open --json number,headRefName \
  --jq '[.[] | select(.headRefName | startswith("release-badge/"))][0] // empty | "\(.number) \(.headRefName)"')
git fetch --quiet origin main
if [[ -n "$OPEN_PR" ]]; then
  PR_NUMBER="${OPEN_PR%% *}"
  BRANCH="${OPEN_PR#* }"
  git fetch --quiet origin "$BRANCH"
  git worktree add --quiet -b "$LOCAL_BRANCH" "$WORKTREE" "origin/$BRANCH"
  # Bring it up to date with main first; badge edits never conflict once it includes main.
  git -C "$WORKTREE" merge --quiet --no-edit origin/main
else
  PR_NUMBER=""
  BRANCH="release-badge/$TAG"
  git worktree add --quiet -b "$LOCAL_BRANCH" "$WORKTREE" origin/main
fi

LABEL="$LABEL" TAG="$TAG" README="$WORKTREE/README.md" python3 - <<'PY'
import os, re, sys
label, tag, path = os.environ["LABEL"], os.environ["TAG"], os.environ["README"]
version = tag.split("-v", 1)[1]  # macOS-v0.2.7 -> 0.2.7
text = open(path).read()
# [![macOS](https://img.shields.io/badge/macOS-v0.2.7-blue?...)](https://github.com/.../releases/tag/macOS-v0.2.7)
pattern = re.compile(
    r"(\[!\[" + re.escape(label) + r"\]\(https://img\.shields\.io/badge/" + re.escape(label) + r"-)v[^-]+(-[^)]*\)\]\()[^)]*(\))")
new, count = pattern.subn(
    lambda m: f"{m.group(1)}v{version}{m.group(2)}https://github.com/itsberkelium/PR-Checker/releases/tag/{tag}{m.group(3)}", text)
if count != 1:
    sys.exit(f"Expected one {label} badge in README.md, found {count}")
open(path, "w").write(new)
PY

if git -C "$WORKTREE" diff --quiet -- README.md; then
  echo "$LABEL badge already links to $TAG"
  exit 0
fi
git -C "$WORKTREE" commit --quiet -m "README: point the $LABEL badge at $TAG" -- README.md
git -C "$WORKTREE" push --quiet origin "$LOCAL_BRANCH:$BRANCH"

LINE="- $LABEL badge → [$TAG](https://github.com/$REPO/releases/tag/$TAG)"
if [[ -n "$PR_NUMBER" ]]; then
  BODY=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json body --jq .body)
  gh pr edit "$PR_NUMBER" --repo "$REPO" --title "README: update the release badges" --body "$BODY
$LINE" >/dev/null
  echo "Added the $LABEL badge to https://github.com/$REPO/pull/$PR_NUMBER"
else
  gh pr create --repo "$REPO" --base main --head "$BRANCH" \
    --title "README: point the $LABEL badge at $TAG" \
    --body "Release badge updates, opened by \`scripts/release-badge.sh\`:
$LINE"
fi
