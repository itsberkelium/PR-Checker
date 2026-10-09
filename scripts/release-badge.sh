#!/usr/bin/env bash
# Sets a README release badge's version and link to a release, then commits and pushes that
# change. The badges are static shields.io badges ("<logo> macOS | v0.2.7") so they always
# match the release they link to.
# Called by the release scripts after a release is created.
#
#   scripts/release-badge.sh <macOS|Windows> <tag>     e.g. scripts/release-badge.sh macOS macOS-v0.2.8
set -euo pipefail
cd "$(dirname "$0")/.."

LABEL="${1:?usage: $0 <macOS|Windows> <tag>}"
TAG="${2:?usage: $0 <macOS|Windows> <tag>}"
case "$LABEL" in macOS|Windows) ;; *) echo "Label must be macOS or Windows" >&2; exit 2 ;; esac

git diff --quiet -- README.md || { echo "README.md has uncommitted changes; not touching it" >&2; exit 1; }
git pull --quiet --ff-only

LABEL="$LABEL" TAG="$TAG" python3 - <<'PY'
import os, re, sys
label, tag = os.environ["LABEL"], os.environ["TAG"]
version = tag.split("-v", 1)[1]  # macOS-v0.2.7 -> 0.2.7
text = open("README.md").read()
# [![macOS](https://img.shields.io/badge/macOS-v0.2.7-blue?...)](https://github.com/.../releases/tag/macOS-v0.2.7)
pattern = re.compile(
    r"(\[!\[" + re.escape(label) + r"\]\(https://img\.shields\.io/badge/" + re.escape(label) + r"-)v[^-]+(-[^)]*\)\]\()[^)]*(\))")
new, count = pattern.subn(
    lambda m: f"{m.group(1)}v{version}{m.group(2)}https://github.com/itsberkelium/PR-Checker/releases/tag/{tag}{m.group(3)}", text)
if count != 1:
    sys.exit(f"Expected one {label} badge in README.md, found {count}")
open("README.md", "w").write(new)
PY

if git diff --quiet -- README.md; then
  echo "$LABEL badge already links to $TAG"
  exit 0
fi
git commit --quiet -m "README: link the $LABEL badge to $TAG" -- README.md
git push --quiet
echo "$LABEL badge now links to $TAG"
