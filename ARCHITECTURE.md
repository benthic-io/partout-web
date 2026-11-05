# partout-web — architecture

Hugo static site for `partout.pro`, the web presence of PartOut. Source of
this plan: `/home/otherdrums/benthic-io/PARTOUT_WEB_PROPOSAL.md` (spec
proposal, pending `SPEC.md` §16.2–16.4 via po-spec).

## What this repo owns

- The Hugo site source (`content/`, `layouts/`, `static/`, `hugo.toml`).
- The brand pipeline that keeps the site honest to the app
  (`scripts/gen_brand_css.py`, `scripts/sync_assets.sh`).
- `scripts/deploy_check.sh` — read-only post-deploy invariants.

It does **not** own: the Flutter app or its web build recipe (`partout-app`,
po-app/po-backend own the `/app` deploy orchestration per po-boss), the
backend, nginx/frp config (po-boss + operator approval only), or the legal
copy (`partout-backend/docs/public/*.md`, po-docs, gated on publication).

## Brand rules

- Palette source of truth: `partout-app/lib/config/theme.dart`.
  `static/css/brand.css` is **generated** (`scripts/gen_brand_css.py`), never
  hand-edited; CI `--check` fails on drift. Lime `#AAEE61` on gunmetal
  `#161B1E`, dark-only (the app's product default).
- Wordmark/favicon source of truth: `partout-app/assets/{banner,logo}.png`;
  `scripts/sync_assets.sh` copies byte-identically, CI checks.
- `static/css/style.css` may use only `var()` values from brand.css.

## Content rules

- State only what is true today (see `content/_index.md` status table). No
  live-price, no store, no dates.
- Legal/methodology pages appear **only** when a corresponding
  `partout-backend/docs/public/*.md` flips from `DRAFT — not published` to
  published (version + content-hash gate). Until then: no pages, no links.
- Never link `/docs` or `/openapi.json` (404 by nginx allowlist in
  production).
- The `/app` link may exist in copy before P3 ships (obtain.md notes it is
  under construction); the menu gains an App entry only when it returns 200.

## Routing contract (P2 — needs operator approval; po-boss executes)

| Path | Serves | Owner |
|---|---|---|
| `/` + site paths | this repo's `public/` build | po-web (source), po-boss (deploy) |
| `/app/` | Flutter web build from `partout-app` | po-app/po-backend recipe, po-boss deploy |
| `/api/v1/*`, `/health`, `/uploads/*` | FastAPI on thunkah (unchanged) | po-backend |
| `/admin` | legacy admin.html until P4 parity, then redirect `/app/#/admin` | po-boss retires |

Invariants `deploy_check.sh` enforces: the site never shadows `/health` or any
`/api/v1` path (an API 404 must stay JSON from FastAPI, not HTML from nginx
error pages); site deploy and backend deploy are fully decoupled.

Option A (recommended, po-boss 2026-11-05): droplet nginx serves `public/` and
`/app` static directories directly and proxies `/api` + `/health` + `/uploads`
to frps as today. Option B fallback: backend `StaticFiles` catch-all mounted
after API routes. No nginx/frp change happens without explicit operator
approval.

Header mechanics (cf0d322b HIGH + 55b115bd HIGH-1, fixed in
`deploy/nginx-site.conf.example`): nginx `add_header` does **not** inherit
into any location that declares its own — a single nested `add_header`
silently drops the whole server-level matrix. The two matrices ship as REAL
files, `deploy/snippets/partout-common-security.conf` (HSTS, nosniff,
Referrer-Policy, XFO DENY, Permissions-Policy) and
`deploy/snippets/partout-app-security.conf` (noindex, COOP, app CSP report-
only with `frame-ancestors 'none'`, `worker-src 'self' blob:`,
`object-src 'none'`), and **every** header-adding block includes them
explicitly; the install step copies them to `/etc/nginx/snippets/`.
`scripts/check_deploy_template.py` (CI) fails the build if any include stops
resolving, any `add_header` block omits the common snippet, any /app header
block omits the app snippet, or any CSP string lacks `object-src 'none'`;
`scripts/test_nginx_conf.py` (CI) runs `nginx -t` against the template with
the real snippets, so P2 apply starts from an accepted config. `/admin`
(and the `/admin/` redirect) additionally send `X-Robots-Tag noindex,nofollow`,
`no-store`, and a tailored legacy CSP (`'unsafe-inline'` for scripts/styles —
required by admin.html until P4 retirement; frame-ancestors/object-src hold).
`location = /app` 308s to `/app/`; no `= /app/` exact-match block exists (it
would shadow the prefix block and lose its `alias`).

## Security contract (po-security handoffs `cee9848a` + `cf0d322b` + `55b115bd`, binding per phase)

P1 (this repo, landed):

- `static/robots.txt` disallows `/app/` and `/admin`; marketing stays
  crawlable. robots is **not** access control — the edge also sends
  `X-Robots-Tag: noindex` on `/app` and `/admin*` (P2/P3, po-boss nginx) and
  those paths never appear in the sitemap.
- All GitHub Actions pinned by commit SHA; workflow permissions reduced to
  `contents: read`; hugo pinned 0.169.0 extended.
- No inline `style`/`script`/event-handlers anywhere in the built site — CI
  asserts it case-insensitively for both quote styles so a strict CSP
  (`object-src 'none'`, `frame-ancestors 'none'`) at the edge stays possible;
  `Cross-Origin-Resource-Policy: same-origin` on static assets.
- `deploy_check.sh` asserts the edge header matrix **per path, per nested
  location** (cf0d322b): HSTS, CSP, nosniff, Referrer-Policy, X-Frame-Options
  DENY, **all three** Permissions-Policy directives, `/robots.txt` and
  `/css/style.css` keep the matrix despite `add_header` nesting, `/admin`
  carries noindex + no-store, sitemap cleanliness; `CHECK_APP=1` adds the
  `/app` surface with `CSP_MODE=report-only|enforce` (P3 starts report-only),
  `no-store` on index/`flutter_bootstrap.js`, and immutable only on the
  content-versioned tier (`APP_IMMUTABLE_PATH`, e.g. `canvaskit/`); site
  checks gate on the **Hugo generator marker** or `SITE_DEPLOYED=1|0`, never
  on marketing words. Headers are applied at droplet nginx by po-boss —
  before P2 the checks report SKIP.
- No analytics, no cookies, nothing third-party in the site.

P3 (Flutter web — binding decisions recorded for po-app/po-backend):

- **Memory-only tokens.** No `localStorage`/`sessionStorage`/
  `flutter_secure_storage` on web (its web backend is browser storage and
  XSS-readable). Reload means re-login. Persistence later requires HttpOnly
  + Secure + SameSite cookies with CSRF in the backend — not a Dart flag.
- Logout clears both in-memory tokens and stale storage keys from any earlier
  build; hard-reload and back-button return must land on the login screen.
- Release build without source maps; service worker scoped to `/app/` and
  never caching `/api` or auth responses.
- OAuth client id stays public, client secret never; consent screen remains
  `Testing` with named test users until legal pages + Google verification.
- CSP for `/app`: `'self'` + `wasm-unsafe-eval` + Google Identity origins
  only, rolled out as `Content-Security-Policy-Report-Only` first; COOP
  `same-origin-allow-popups`; no COEP until sign-in + CanvasKit pass.

P4 (admin console):

- Client-side `is_admin` is UX only; the backend gate is the boundary — no
  client-trusted role, ever.
- Backend prerequisites (po-backend): last-admin guard (409 on final
  demote/delete), append-only audit row for grant/revoke/delete/refresh-vin,
  re-auth before destructive actions, typed confirmations, no self-delete.
- Console posture: 15-minute idle timeout, no remember-me, no tokens in
  URLs/logs/DOM attributes, no third-party scripts.
- Legacy `/admin`/`admin.html` retired (redirect or 301 with `no-store`)
  only after parity sign-off.

P5 (catalog): no listing data, seller identity, VIN, or raw corpus; public
labels/license gate from the spec.

## Build & deploy

```bash
scripts/build_site.sh        # hugo --minify -> public/
scripts/deploy_check.sh     # read-only curl matrix (SITE_URL=... after P2)
```

Local toolchain pinned to hugo extended **0.169.0** (same version CI
installs). Hugo is installed at `~/.local/bin/hugo` on thunk; nothing here
needs anything else but python3 and bash.

Deploy flow (P2+): `po-web` builds → po-boss rsyncs `public/` to the droplet
static root under a versioned directory and flips the symlink/root — never
from this session, never without the approved routing change.

## Branch rules

`po-web-*` branches; commit, **never push**; po-boss reviews, merges to
master, pushes, deploys. No commit trailers.
