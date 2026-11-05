# partout-web

PartOut web presence: the Hugo static site for `partout.pro` (brand theme,
landing/how-it-works/get-the-app pages, generation scripts, CI).

- Hugo site lives here; the Flutter web app is built from `partout-app` — the
  `/app` deploy recipe/orchestration is owned by po-app/po-backend, not this
  repo.
- Branches: `po-web-*`. Workers commit, never push; po-boss reviews/merges/pushes/deploys.
- See `ARCHITECTURE.md` here and `PARTOUT_WEB_PROPOSAL.md` in the `benthic-io`
  workspace for scope, phases, and the routing contract.
