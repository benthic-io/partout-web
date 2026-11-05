# PartOut web presence — spec proposal (po-web)

**Status:** PROPOSAL for review, **Rev 2** (2026-11-05). Drafted by `po-web`
at po-boss's direction, per the operator task "full web presence on
partout.pro". Rev 2 folds in **po-security's binding adjudications** (team
handoff `cee9848a` + operator follow-up) — new §11; §5/§6/§8/§10 updated to
match. This document proposes SPEC deltas; it does not implement anything.
`po-spec` owns `partout-app/SPEC.md`; affected members (po-backend, po-app,
po-security, po-docs, po-web) review; the operator approves; only then code.

Sources read: `PARTOUT_STATE.md`, `BASELINE.md`, `BENTHIC_CONTRACT.md`,
`partout-app/SPEC.md` §§4/5/11/12/14/15/16/17, `partout-backend/api/main.py`,
`src/partout_nhtsa/admin_router.py`, `src/partout_nhtsa/oauth_verify.py`,
`partout-app/lib/**` (theme, auth, features, router, web/),
`/home/otherdrums/benthic-site` (Hugo patterns, CI, CSS), live
`https://partout.pro/` and `/health`.

---

## 1. Scope

Operator brief: a full web presence for PartOut on `partout.pro`, following the
app's color scheme, using the provided assets, Hugo static-generated like
benthic.io, **plus** authentication and hosting the Flutter app as a web target
giving the operator and granted admins full administrative access and control.

Decomposed into five deliverables:

| # | Deliverable | Phase |
|---|---|---|
| W1 | `partout-web` repo + Hugo site (brand theme, marketing/docs/legal surfaces) | P1–P2 |
| W2 | Routing plan for `partout.pro` (site `/`, web app `/app`, API untouched) | P2 |
| W3 | Flutter web build hosted at `/app` with Google/email sign-in | P3 |
| W4 | Admin console in the web build, gated on `is_admin` (grants by operator) | P4 |
| W5 | Public catalog shop window (`publish.*` browse pages, per SPEC §16.1) | P5 — blocked until catalog has rows |

SPEC §16.1 (catalog browse) stays as written; this proposal extends §16 with
implementation structure around it rather than replacing it.

## 2. Brand and assets (from SPEC §14 / `theme.dart`)

- Palette is taken verbatim from `partout-app/lib/config/theme.dart` as CSS
  custom properties, generated — not retyped — so the site cannot drift:
  lime `#AAEE61` primary on dark gunmetal: background `#161B1E`, surfaces
  `#1E2529`/`#222B30`/`#2A3439`/`#344047`, outlines `#4C5A61`/`#2E3A40`,
  text `#E7EDEF`/`#A8B6BC`, tertiary gold `#E4C46B`, on-primary `#0A0F06`.
  Dark is default (product default). A light variant
  (`#F5F7F2`/white/`#3D6B14`) ships behind `prefers-color-scheme` **only if**
  the operator asks; default proposal is dark-only.
- Assets from `partout-app/assets/`: `banner.png` (401×89 "PartOut" wordmark,
  header), `logo.png` (512×512, favicon/apple-touch/OG image). The Hugo site
  keeps a copy under `static/images/` with a CI check that the files are
  byte-identical to the app's assets (the app repo is the source of truth).
- Tone follows benthic.io (plain, direct, data-first), not marketing fluff.

## 3. Hugo site (`partout-web`)

Mirror benthic-site patterns, verified against that repo:

- Hugo modules layout: `hugo.toml` (`disableKinds = ["taxonomy","term"]`,
  menus in `[menu]`, `[params]` for email/socials/description),
  `layouts/baseof.html` + `_default` + `partials/seo.html`, single
  `static/css/style.css`, `content/` with `_index.md`, sections.
- Pages (phase P1/P2):

| Path | Content | Source |
|---|---|---|
| `/` | Landing: what PartOut is, "Parts are Everywhere", how it works, join-testers CTA | static |
| `/how-it-works/` | Seller/buyer + crowd-sourced public data engine explanation (SPEC §2.5 framing) | static |
| `/public-data/` | Methodology, transparency, corrections/takedown, retention, license | rendered from `partout-backend/docs/public/*.md` **only when** a page's status flips from `DRAFT — not published` to published (version + content hash gate); until then the pages do not exist |
| `/privacy/`, `/terms/` | same gate, same source | |
| `/obtain/` | tester access: Firebase App Distribution explanation; later app-store links | static |
| `/app/` | (Flutter web — see §5; the site links "Open the app" here) | build artifact |
| `/catalog/…` | SPEC §16.1 browse pages | P5, blocked on `publish.*` |
| `/changelog/` | public changelog (SPEC §2.5.4 / roadmap 28) | optional, po-docs decides |

- CI (GitHub Actions, like benthic-site `docs.yml`): `hugo --minify` build
  check; asset-sync check; link check; *no* page may link `/api/v1/*` doc paths
  that are 404 in production (SPEC §"Recorded discrepancies": `/docs` and
  `/openapi.json` are blocked by the nginx allowlist).
- Secrets: none. Client IDs are public values; no client **secret** ever appears
  in the site or repo (BASELINE rule).

## 4. Routing plan for `partout.pro`

Current verified chain: `droplet nginx 443 → frps 127.0.0.1:8000 → frpc →
thunkah:8000 (FastAPI)`. Root `/` currently returns the backend's service
banner (200 HTML); `/admin` serves a legacy `admin.html` (off-brand blue,
email/password login, uses the same `/api/v1/admin` endpoints).

Proposed target (operator approval required before any nginx/frp change; po-boss
executes):

| Path | Serves | How |
|---|---|---|
| `/`, `/how-it-works/…` | Hugo static | **Option A (recommended): droplet nginx serves `root`** — fastest, cacheable, zero backend load, and static survives backend restarts. Option B (fallback): backend catch-all `StaticFiles` mounted last; fewer moving parts but couples site deploys to API deploys. |
| `/app/*` | Flutter web build (static) | same mechanism as site, own directory + `Cache-Control` |
| `/api/v1/*` | FastAPI (unchanged) | existing frp proxy |
| `/health` | FastAPI (unchanged) | keep — SPEC §16.1 constraint: site must not shadow it |
| `/uploads/*` | FastAPI (unchanged) | signed, owner-scoped |
| `/admin` | redirect → `/app/#/admin` (after W4 parity) | legacy `admin.html` retired once the web console matches its capability list |
| `/docs`, `/openapi.json` | remain 404 via allowlist | unchanged; revisit separately |

Invariant for every option: **site routes are static-first and the API prefix
`/api` can never be shadowed**; a deploy of the site is never a deploy of the
backend.

## 5. Flutter web at `/app` with authentication

- Build: `flutter build web --release --base-href /app/
  --dart-define=API_BASE_URL=https://partout.pro
  --dart-define=GOOGLE_CLIENT_ID_WEB=<web client id>` (BASELINE §5 already
  documents the web target; `web/index.html` + `manifest.json` exist).
- Auth wiring — verified in code, mostly already done:
  - `auth_service.dart` constructs `GoogleSignIn(clientId: googleClientIdWeb)`
    on `kIsWeb` and fails soft (`GoogleSignInUnavailable`) when the id is
    absent; POSTs `id_token` to `/api/v1/auth/google`.
  - Backend `oauth_verify.py` verifies signature + `iss/aud/exp` fail-closed
    against `GOOGLE_OAUTH_CLIENT_IDS`; so the only **missing production pieces**
    are the GCP Web client itself and adding its id to `.env` (see the
    companion runbook `GCP_WEB_OAUTH_STEPS.md`). Email/password login already
    works over the same API.
  - The web app reuses the existing GoRouter screens unchanged; no second
    account system (SPEC §16.1: "no separate web account").
- Web token storage — **decided (po-security, §11)**: memory-only access
  token + refresh flow; no `localStorage`/`sessionStorage`/
  `flutter_secure_storage` on web. A reload means re-login. Persistence, if
  ever required, means an HttpOnly + Secure + SameSite=Strict cookie backend
  change with CSRF + rotation — a separate reviewed spec delta, not a Dart
  flag.
- PWA: existing manifest gets PartOut logo/theme entries (`theme_color
  #AAEE61`/`#161B1E`); offline is *not* promised (no durable outbox yet — SPEC
  known gap AC13).

## 6. Admin console (W4) — "full administrator access and control"

- Who is an admin: the `users.is_admin` flag (exists: `app_schema.sql:181`,
  returned by `/api/v1/auth/me` as `is_admin`). **Grant/revoke policy is
  fixed by §11**: grants only by an existing admin via
  `PUT /api/v1/admin/users/{id}` (two-person approval posture recommended),
  first admin bootstrapped by **SQL only** (po-boss under explicit operator
  request), no self-delete, self-demotion only when another admin exists and
  with re-auth, server-side last-admin guard (409), and an append-only admin
  audit row for every grant/revoke/delete/refresh-vin.
- Server-side gate is already the contract: `/api/v1/admin/*` requires
  `is_admin` (403/401 otherwise; fail-closed). The console enforces the same
  gate client-side only for UX — **the backend check is the security
  boundary**, per SPEC §11.
- Console scope = parity with `admin_router.py` today, restyled in brand:
  users list/get/update(`is_admin`, profile)/delete; cars/parts inventory
  browse; `/system`; `refresh-vin`; logs viewer + SSE stream; verdict events;
  admin audit reader (gate decisions). Plus a clear "acting as admin" indicator
  and an app-side `#/admin` route visible only when `is_admin` is true.
- Delegating "control of everything": the web console is admin to the **same
  API surface only** — no new privileged endpoints in this proposal except the
  admin grant flow above. Any future endpoint (publish toggles, user creation)
  is a new spec delta.

## 7. Repo structure and branch naming (for po-boss confirmation)

New repo `partout-web` at `/home/otherdrums/benthic-io/partout-web`, owned by
po-web (added to SPEC §4 table by po-spec once roster entry is confirmed):

```
partout-web/
├── ARCHITECTURE.md       # this plan as built, deploy contract
├── hugo.toml
├── archetypes/ content/ data/ layouts/ static/   # Hugo site (brand theme in static/css/brand.css)
├── scripts/
│   ├── sync_assets.sh    # copy banner/logo from partout-app/assets (byte-identical check)
│   ├── gen_brand_css.py  # extract palette from theme.dart -> static/css/brand.css
│   ├── build_site.sh     # hugo --minify -> public/
│   └── deploy_check.sh   # curl matrix: /, /app/, /api path invariants (read-only)
├── webapp/               # build-recipe docs for the Flutter web artifact; no Dart here (po-app owns the app)
├── .github/workflows/site.yml
└── public/ (gitignored; deploy artifact via po-boss)
```

- Branches: `po-web-*` only; commits there; **never push** — po-boss reviews,
  merges, pushes, deploys. No commit trailers.
- Ownership boundaries: the Flutter web **build inputs** stay in `partout-app`
  (po-app); `partout-web` holds site source + the deploy recipes/orchestration
  for `/app`; backend changes (if any, e.g. web-serving Option B) belong to
  po-backend.

## 8. Review asks (per-member, for the affected-member review cycle)

- **po-spec**: draft the SPEC delta — §16 gets 16.2 (site + repo), 16.3
  (routing invariants), 16.4 (web app + admin console), §4 repos/team tables a
  `partout-web`/po-web row, roadmap 9 refined + new roadmap item "web admin
  console (W4)"; keep 16.1 intact.
- **po-security**: adjudications received and codified in §11 (Rev 2) — web
  token storage, admin grant/revoke + last-guard + audit, CSP/headers,
  indexing, OAuth consent lifecycle; remaining asks: P2 header application
  sign-off on the nginx template and legacy `/admin` retirement conditions.
- **po-backend**: confirm `GOOGLE_OAUTH_CLIENT_IDS` env update path + any
  CORS/origin change for `https://partout.pro` web app (same-origin, so none
  expected); confirm nothing needed beyond the existing admin router for W4
  parity.
- **po-app**: confirm web build runs clean (`flutter build web --release`) and
  flag any plugin that lacks web support (e.g. `image_picker`/`flutter_secure_storage`
  on web — audit needed before P3).
- **po-docs**: legal/public-data copy stays gated in `docs/public/` until
  counsel; site links per the status gate in §3.
- **po-boss/operator**: routing option A/B + repo creation + GCP runbook.

## 9. Phases and gates

| Phase | Contents | Gate to enter | Gate to exit |
|---|---|---|---|
| P1 | `partout-web` scaffold, Hugo theme, landing/how-it-works/obtain pages, local CI | this proposal approved by operator via po-boss | site builds + checks green locally |
| P2 | routing plan executed on `partout.pro` (Option A/B), first deploy | po-boss + operator approve nginx change; backups taken | `/` serves site, `/health` + `/api/v1/*` byte-identical behavior to before (deploy-check script) |
| P3 | Flutter web at `/app` + sign-in | GCP Web client done by operator; web build plugin audit (po-app); consent screen in Testing with named test users (§11.4) | login works in browser; memory-only token posture verified incl. reload⇒re-login (§11.1); CSP report-only clean; SW excludes API/auth |
| P4 | admin console screens | §11.2 backend prerequisites implemented (last-admin guard, append-only audit, re-auth) by po-backend | operator + granted `is_admin` users can do everything `admin.html` can, brand-consistent; legacy `/admin` redirect only after parity sign-off |
| P5 | catalog browse per §16.1 | `publish.*` populated (roadmap 2) + §16.1 spec approved | separate proposal |

## 10. Open questions (record for SPEC §18)

1. Serving mechanism Option A vs B (operator preference re: droplet complexity;
   Option A recommended by po-boss and template drafted).
2. Is the web app the *general* app surface for all users, or admin/testers
   only? (Operator brief emphasizes admin use; proposal makes no product
   difference — it hosts whichever build — but marketing copy differs.)
3. Analytics and cookie posture — **decided: none** (§11; any change needs a
   separate approval).
4. Domain of email flows (`no-reply@partout.pro`) — out of scope here.
5. Whether `/app` is discoverable by search engines — **decided: no** (§11:
   `noindex` for `/app` and `/admin*`, marketing site indexed).

## 11. Security adjudications (po-security handoff cee9848a + operator
follow-up, 2026-11-05 — binding, folded into SPEC deltas on merge)

**11.1 Token storage (web).** Memory-only access token + refresh flow. No
`localStorage`, no `sessionStorage`, no `flutter_secure_storage` on web (its
web backend is browser storage and XSS-readable). Reload ⇒ re-login. Logout
must clear both in-memory tokens and stale storage keys from earlier builds;
hard-reload and back-button returns land on sign-in. If persistence is ever
needed: backend change to `HttpOnly` + `Secure` + `SameSite=Strict` cookies
with CSRF protection and rotation — reviewed as its own spec delta, never a
Dart-side flag. No tokens in URLs, logs, or DOM attributes.

**11.2 Admin console.** Memory-only session, 15-minute idle timeout, no
remember-me. Server-side enforcement always: client `is_admin` is UX only,
never a trusted role. Backend prerequisites before P4 ships (po-backend):
last-admin guard (409 on final demote/delete); append-only admin audit rows
for grant/revoke/delete/refresh-vin; re-auth (reauthentication) before
destructive actions with typed confirmation; no self-delete; self-demotion
only when another admin exists + re-auth; grants only by an existing admin
via the API — two-person approval posture recommended; first admin
bootstrapped by **SQL only** (po-boss under explicit operator request). No
third-party scripts in the console.

**11.3 CSP and headers.** Marketing site: strict CSP (`default-src 'self'`,
no inline script/style/handlers — CI-enforced). `/app`: tested relaxed CSP —
`'self'` + `'wasm-unsafe-eval'` + `accounts.google.com` origins + inline
styles Flutter requires; roll out `Content-Security-Policy-Report-Only`
first, enforce only after sign-in + CanvasKit pass. `COOP:
same-origin-allow-popups`; **no COEP** until Google sign-in and CanvasKit are
verified under it. Both surfaces: HSTS, `X-Content-Type-Options: nosniff`,
`Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy`
camera/mic/geolocation disabled, site `X-Frame-Options: DENY`. `no-store` on
`/app/index.html` and any admin HTML; immutable caching only for hashed
assets. The Flutter service worker must be scoped to `/app/` and never cache
`/api` or auth responses. Production builds ship without source maps.

**11.4 OAuth consent lifecycle.** Scopes `openid email profile` only. Client
id is public config; a client secret is never embedded anywhere. The consent
screen stays **Testing** with named test users through P3 and P4; publish
only after the privacy, terms, contribution-license, corrections/takedown,
and retention pages are live (the `docs/public` status gate) and Google
verification is complete.

**11.5 Indexing.** `/app` and `/admin*`: `X-Robots-Tag: noindex` + meta
robots, excluded from sitemap; `robots.txt` disallows both (present since
fcc009b — robots is never access control).

**11.6 Supply-chain hygiene.** Third-party GitHub Actions pinned by commit
SHA; CI skips must be visible (warning + job summary), never silent green;
no analytics or cookies.

**11.7 P1 gap list — status.** robots.txt ✅ fcc009b; header assertions in
`deploy_check.sh` ✅ fcc009b (SKIP-mode until P2); Actions SHA-pinned +
visible skip banner ✅ fcc009b; no-inline CI gate ✅ fcc009b; landing
quorum wording (human majority decisive, labelled agent fallback) ✅
fcc009b; Option A nginx template ✅ 97d8980 (`deploy/nginx-site.conf.example`).
Merged by po-boss as `127917a`.
