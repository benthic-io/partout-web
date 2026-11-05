#!/usr/bin/env bash
# Read-only invariant checks against a deployed PartOut web surface.
# Never mutates anything; safe to run against production any time.
#
#   SITE_URL=https://partout.pro scripts/deploy_check.sh
#
# Modes (po-security handoff cf0d322b MED-3):
#   SITE_DEPLOYED   auto | 1 | 0   site-check gate. auto detects the Hugo
#                                  generator marker on / — never a word that
#                                  a future API banner could contain.
#   CHECK_APP=1     assert the /app Flutter web surface (turn on at P3).
#   CSP_MODE=report-only|enforce   which CSP header /app must carry (P3
#                                  starts report-only; enforce after the
#                                  sign-in + CanvasKit pass).
set -uo pipefail

SITE_URL=${SITE_URL:-https://partout.pro}
CHECK_APP=${CHECK_APP:-0}
CSP_MODE=${CSP_MODE:-report-only}
SITE_DEPLOYED=${SITE_DEPLOYED:-auto}
# content-versioned asset to prove the immutable-caching tier; adjust to the
# live build (canvaskit path carries the engine version):
APP_IMMUTABLE_PATH=${APP_IMMUTABLE_PATH:-/app/canvaskit/canvaskit.wasm}

fail=0

hdr() { # path header-name expected-regex [allow-404-skip]
  local path=$1 name=$2 want=$3 allow404=${4:-0}
  local code val
  code=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' "$SITE_URL$path") || {
    echo "FAIL hdr $path $name (curl error)"; fail=1; return; }
  if [[ $allow404 == 1 && $code == 404 ]]; then
    echo "SKIP hdr $path $name (404 — path not deployed yet)"; return
  fi
  val=$(curl -sSI -m 20 "$SITE_URL$path" | tr -d '\r' \
        | awk -v h="${name}: " 'BEGIN{IGNORECASE=1} index($0,h)==1 {print substr($0, length(h)+1)}')
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

echo "deploy_check against $SITE_URL (CHECK_APP=$CHECK_APP CSP_MODE=$CSP_MODE SITE_DEPLOYED=$SITE_DEPLOYED)"

# --- API invariants (true today; must stay true after P2) -------------------
body /health 200 '"status":"healthy"'
code=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' "$SITE_URL/api/v1/no-such-endpoint")
echo "info /api/v1/no-such-endpoint -> $code (expect 404 from FastAPI, never an HTML site page)"

# --- site presence: explicit flag, else the Hugo generator marker ------------
case $SITE_DEPLOYED in
  1) site_live=1 ;;
  0) site_live=0 ;;
  *)
    landing=$(curl -sS -m 20 "$SITE_URL/" 2>/dev/null || true)
    if grep -qE 'name="?generator"? content="Hugo' <<<"$landing"; then
      site_live=1
    else
      site_live=0
      echo "SKIP site checks — no Hugo generator marker at / (P2 pending)"
    fi ;;
esac

if [[ $site_live == 1 ]]; then
  # Site content invariants
  body / 200 'PartOut'
  body /how-it-works/ 200 'Quorum before publish'
  body /obtain/ 200 'Firebase App Distribution'
  body /no-such-page-xyz 404 ''
  body /robots.txt 200 'Disallow: /app/'
  body /robots.txt 200 'Disallow: /admin'

  # Edge security headers, site scope (droplet nginx applies at P2; the
  # add_header inheritance trap makes the per-path assertions load-bearing).
  hdr / Strict-Transport-Security 'max-age=[0-9]{5,}'
  hdr / Content-Security-Policy "default-src 'self'.*object-src 'none'.*frame-ancestors 'none'"
  hdr / X-Content-Type-Options 'nosniff'
  hdr / Referrer-Policy 'strict-origin-when-cross-origin'
  hdr / X-Frame-Options 'DENY'
  # all three directives, not any one of them (cf0d322b MED-3a):
  hdr / Permissions-Policy 'camera=\(\)'
  hdr / Permissions-Policy 'microphone=\(\)'
  hdr / Permissions-Policy 'geolocation=\(\)'
  # nested locations must not drop the matrix:
  hdr /robots.txt X-Content-Type-Options 'nosniff'
  hdr /robots.txt Strict-Transport-Security 'max-age=[0-9]{5,}'
  hdr /css/style.css X-Content-Type-Options 'nosniff'
  hdr /css/style.css Strict-Transport-Security 'max-age=[0-9]{5,}'
  hdr /css/style.css Cross-Origin-Resource-Policy 'same-origin'

  # Legacy admin: noindex + no-store while proxied, redirect-safe (cf0d322b MED-2):
  hdr /admin X-Robots-Tag 'noindex'
  hdr /admin Cache-Control 'no-store'
  hdr /admin/ X-Robots-Tag 'noindex'

  # sitemap must not advertise app/admin surfaces
  if curl -sS -m 20 "$SITE_URL/sitemap.xml" | grep -qE '/app/|/admin'; then
    echo "FAIL sitemap.xml contains /app or /admin URLs"; fail=1
  else
    echo "ok   sitemap.xml free of /app and /admin"
  fi

  # --- Flutter web surface (P3) ---------------------------------------------
  code=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' "$SITE_URL/app/")
  echo "info /app/ -> $code (200 after the P3 deploy, 404 before it)"
  if [[ $CHECK_APP == 1 ]]; then
    hdr /app/ X-Robots-Tag 'noindex'
    hdr /app/ Cache-Control 'no-store'
    hdr /app/ Cross-Origin-Opener-Policy 'same-origin-allow-popups'
    hdr /app/ X-Frame-Options 'DENY'
    if [[ $CSP_MODE == report-only ]]; then
      hdr /app/ Content-Security-Policy-Report-Only "default-src 'self'.*wasm-unsafe-eval.*worker-src"
    else
      hdr /app/ Content-Security-Policy "default-src 'self'.*wasm-unsafe-eval.*worker-src.*frame-ancestors 'none'"
    fi
    # entry documents must be no-store; versioned tier immutable (cf0d322b 3d):
    hdr /app/index.html Cache-Control 'no-store'
    hdr /app/flutter_bootstrap.js Cache-Control 'no-store'
    hdr "$APP_IMMUTABLE_PATH" Cache-Control 'immutable' 1
    # service worker must never cache API/auth: asserted functionally in P3
    # tests (cf. ARCHITECTURE 11.3), not from the edge.
  fi
fi

exit $fail
