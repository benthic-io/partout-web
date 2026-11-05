#!/usr/bin/env bash
# Build the Hugo site into public/ (the deploy artifact).
set -euo pipefail
cd "$(dirname "$0")/.."
hugo --minify "$@"
echo "built: $(find public -name '*.html' | wc -l) html pages, $(du -sh public | cut -f1) total"
