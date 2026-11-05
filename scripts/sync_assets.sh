#!/usr/bin/env bash
# Copy brand assets from the app repo (their source of truth) into the site,
# and derive the site favicon from the logo.
#
#   scripts/sync_assets.sh          # copy
#   scripts/sync_assets.sh --check  # exit 1 if the site copies differ (CI)
set -euo pipefail
cd "$(dirname "$0")/.."

SRC=../partout-app/assets
PAIRS=(
  "$SRC/banner.png:static/images/banner.png"
  "$SRC/logo.png:static/images/logo.png"
  "$SRC/logo.png:static/favicon.png"
)

status=0
for pair in "${PAIRS[@]}"; do
  src=${pair%%:*}
  dst=${pair#*:}
  if [[ ! -f $src ]]; then
    echo "error: missing source $src" >&2
    exit 2
  fi
  if [[ ${1:-} == --check ]]; then
    if ! cmp -s "$src" "$dst"; then
      echo "error: $dst differs from $src — run scripts/sync_assets.sh" >&2
      status=1
    fi
  else
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "synced $dst"
  fi
done
exit $status
