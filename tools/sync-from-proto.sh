#!/bin/sh
# Pull levels and strings from the web prototype (the single source of truth).
# usage: tools/sync-from-proto.sh [path-to-fold-proto]
set -e
PROTO="${1:-$HOME/code/fold-proto}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
node "$PROTO/tools/export.js" "$TMP"
cp "$TMP/levels.json" "$HERE/Packages/FoldCore/Sources/FoldCore/Resources/levels.json"
node "$HERE/tools/make-strings.js" "$TMP/strings.json"
rm -rf "$TMP"
