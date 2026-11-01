#!/usr/bin/env bash
# Publishes site/ plus the web build to the gh-pages branch. Run after export_all.sh.
set -eu
cd "$(dirname "$0")/.."
REMOTE=$(git remote get-url origin)
TMP=$(mktemp -d)
cp -R site/. "$TMP/"
mkdir -p "$TMP/play"
cp build/web/index* "$TMP/play/"
touch "$TMP/.nojekyll"
cd "$TMP"
git init -q -b gh-pages
git add -A
git commit -q -m "${1:-chore: publish site}"
git push -q --force "$REMOTE" gh-pages
cd - >/dev/null
rm -rf "$TMP"
echo published
