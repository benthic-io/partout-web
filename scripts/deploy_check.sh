#!/usr/bin/env bash
# Read-only invariant checks against a deployed PartOut web surface.
# Never mutates anything; safe to run against production any time.
#
#   SITE_URL=https://partout.pro scripts/deploy_check.sh
#
# Modes:
#   - If the Hugo site is not deployed yet (P2 pending), site/header checks
#     report SKIP and the script exits 0 on the API invariants alone.
#   - Once the site answers at /, every site check and every edge header from
#     the po-security contract (handoff cee9848a) is asserted strictly.
#   - CHECK_APP=1 additionally asserts the Flutter web surface (/app) headers
#     and noindex posture (turn on at P3).
set -uo pipefail

SITE_URL=${SITE_URL:-https://partout.pro}
CHECK_APP=${CHECK_APP:-0}
fail=0
skip_note=0

hdr() { # path header-name expected-regex [skip-404]
  local path=$1 name=$2 want=$3 allow404=${4:-0}
  local code val
  code=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' "$SITE_URL$path") || {
    echo "FAIL hdr $path $name (curl error)"; fail=1; return; }
  if [[ $allow404 == 1 && $code == 404 ]]; then
    echo "SKIP hdr $path $name (404 — not deployed yet)"; return
  fi
  val=$(curl -sSI -m 20 "$SITE_URL$path" | tr -d '\r' | awk -v h="${name}: " \
        'BEGIN{IGNORECASE=1} index($0,h)==1 {print substr($0, length(h)+1)}')
  if grep -qE "$want" <<<"$val"; then
    echo "ok   hdr $path $name"
  else
    echo "FAIL hdr $path $name -> '${val:-<missing>}' (want /$want/)"; fail=1
  fi
}

body() { # path expected-status expected-content-regex
  local path=$1 want=$2 grep_for=${3:-} out code
  out=$(curl -sS -m 20 -w '\n%{http_code}' "$SITE_URL$path") || {
    echo "FAIL $path (curl error)"; fail=1; return; }
  code=${out##*$'\n'}
  out=${out%$'\n'*}
  if [[ $code != "$want" ]]; then
    echo "FAIL $path -> $code (want $want)"; fail=1; return
  fi
  if [[ -n $grep_for ]] && ! grep -qE "$grep_for" <<<"$out"; then
    echo "FAIL $path -> $code but body lacks /$grep_for/"; fail=1; return
  fi
  echo "ok   $path -> $code"
}

echo "deploy_check against $SITE_URL"

# --- API invariants (true today and must stay true after P2) ---------------
body /health 200 '"status":"healthy"'
code=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' "$SITE_URL/api/v1/no-such-endpoint")
echo "info /api/v1/no-such-endpoint -> $code (expect 404 from FastAPI, never an HTML site page)"

# --- Site presence detection -------------------------------------------------
landing=$(curl -sS -m 20 "$SITE_URL/" 2>/dev/null || true)
if ! grep -q 'PartOut' <<<"$landing"; then
  echo "SKIP site checks — Hugo site not deployed at / yet (P2 pending)"
  skip_note=1
fi

if [[ $skip_note == 0 ]]; then
  # Site content invariants
  body / 200 'PartOut'
  body /how-it-works/ 200 'Quorum before publish'
  body /obtain/ 200 'Firebase App Distribution'
  body /no-such-page-xyz 404 ''
  body /robots.txt 200 'Disallow: /app/'

  # Edge security headers, site scope (set by droplet nginx, po-boss at P2;
  # po-security handoff cee9848a P1 item 2).
  hdr / Strict-Transport-Security 'max-age=[0-9]{5,}'
  hdr / Content-Security-Policy "default-src 'self'"
  hdr / X-Content-Type-Options 'nosniff'
  hdr / Referrer-Policy 'strict-origin-when-cross-origin'
  hdr / X-Frame-Options 'DENY'
  hdr / Permissions-Policy 'camera=\(\)|microphone=\(\)|geolocation=\(\)'
  hdr /robots.txt X-Content-Type-Options 'nosniff'

  # Flutter web surface
  code=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' "$SITE_URL/app/")
  echo "info /app/ -> $code (200 after the P3 deploy, 404 before it)"
  if [[ $CHECK_APP == 1 ]]; then
    hdr /app/ X-Robots-Tag 'noindex'
    hdr /app/index.html Cache-Control 'no-store'
    hdr /app/ Content-Security-Policy "default-src 'self'.*wasm-unsafe-eval"
    hdr /app/ Cross-Origin-Opener-Policy 'same-origin-allow-popups'
  fi

  # sitemap must not advertise app/admin surfaces
  if curl -sS -m 20 "$SITE_URL/sitemap.xml" | grep -qE '/app/|/admin'; then
    echo "FAIL sitemap.xml contains /app or /admin URLs"; fail=1
  else
    echo "ok   sitemap.xml free of /app and /admin"
  fi
fi

exit $fail
