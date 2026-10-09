#!/usr/bin/env bash
# Sets a README release badge's version and link to a release and opens a pull request with
# that change (main only accepts changes through pull requests). Called by the release
# scripts after a release is created. Works in a temporary worktree, so the current checkout
# and branch aren't touched.
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

BRANCH="release-badge/$TAG"
WORKTREE=$(mktemp -d)
trap 'git worktree remove --force "$WORKTREE" >/dev/null 2>&1 || true' EXIT

git fetch --quiet origin main
git worktree add --quiet -b "$BRANCH" "$WORKTREE" origin/main

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
  git branch --quiet -D "$BRANCH"
  exit 0
fi
git -C "$WORKTREE" commit --quiet -m "README: point the $LABEL badge at $TAG" -- README.md
git -C "$WORKTREE" push --quiet -u origin "$BRANCH"
gh pr create --repo itsberkelium/PR-Checker --base main --head "$BRANCH" \
  --title "README: point the $LABEL badge at $TAG" \
  --body "Updates the $LABEL release badge's version and link to [$TAG](https://github.com/itsberkelium/PR-Checker/releases/tag/$TAG). Opened by \`scripts/release-badge.sh\`."
git branch --quiet -D "$BRANCH"
