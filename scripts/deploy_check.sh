#!/usr/bin/env bash
# Read-only invariant checks against a deployed PartOut web surface.
# Never mutates anything; safe to run against production any time.
#
#   SITE_URL=https://partout.pro scripts/deploy_check.sh
set -uo pipefail

SITE_URL=${SITE_URL:-https://partout.pro}
fail=0

check() { # path expected-status expected-content-regex
  local path=$1 want=$2 grep_for=${3:-}
  local body code
  body=$(curl -sS -m 20 -w '\n%{http_code}' "$SITE_URL$path") || {
    echo "FAIL $path (curl error)"; fail=1; return;
  }
  code=${body##*$'\n'}
  body=${body%$'\n'*}
  if [[ $code != "$want" ]]; then
    echo "FAIL $path -> $code (want $want)"; fail=1; return
  fi
  if [[ -n $grep_for ]] && ! grep -qE "$grep_for" <<<"$body"; then
    echo "FAIL $path -> $code but body lacks /$grep_for/"; fail=1; return
  fi
  echo "ok   $path -> $code"
}

echo "deploy_check against $SITE_URL"
# Marketing site (P2+): root must be the Hugo landing page, not the API banner.
check / 200 'PartOut'
check /how-it-works/ 200 'Quorum before publish'
check /obtain/ 200 'Firebase App Distribution'
check /no-such-page-xyz 404 ''
# API invariants: the site must never shadow these (SPEC 16.1 constraint).
check /health 200 '"status":"healthy"'
# 404 on an API path must come from the API (JSON), not the site (HTML).
code=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' "$SITE_URL/api/v1/no-such-endpoint")
echo "info /api/v1/no-such-endpoint -> $code (expect 404 from FastAPI)"
# Flutter web (P3+): report, don't fail — 404 before deploy, 200 after.
code=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' "$SITE_URL/app/")
echo "info /app/ -> $code (200 after the P3 deploy, 404 before it)"

exit $fail
