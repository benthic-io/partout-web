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
