---
title: "How it works"
description: "How PartOut turns first-hand observations of real cars into a trustworthy, configuration-keyed public parts database — candidates, swipe verdicts, quorum, and what never leaves your account."
---

## 1. Add a car

Enter a VIN or pick a configuration (year, make, model, trim, drivetrain,
doors). PartOut decodes it against NHTSA's public vPIC data via our upstream,
[benthic.io](https://benthic.io), and settles on the one thing every question
about a part depends on: the exact configuration. The VIN itself is a way *in*
— it is never a key in the public database.

## 2. Meet your candidates

Each car gets a list of **candidate parts** for its configuration — OEM part
numbers pulled from authoritative fitment sources, with human-readable names
where an approved name exists. Candidates are proposals, not facts: nothing
they say becomes public on this page alone.

## 3. Swipe what you see

Open the list and answer one small question per part, over and over:

- **Right** — *present on this car and resaleable.*
- **Left** — *absent, or not resaleable.*
- **Undo / skip** whenever you want; a skip is not a vote.

That's the whole skill requirement. A mechanic and a curious owner answer the
same card, and both answers count.

## 4. Quorum before publish

A part number is marked fit (or not fit) for a configuration only after the
evidence gate decides:

- **Two distinct people** with independent cars is the ordinary floor.
- A **verified completed sale** of the exact part for the exact configuration
  can publish on its own, labeled `sale_verified` — the buyer never counts
  twice.
- Automated and public-agent observations help, but they **cannot outvote a
  human majority**; when they carry a decision alone, the result is labeled
  `agent_only` or `agent_assisted` so readers can weigh it accordingly.
- Every decision is recorded append-only and auditable. Ties, dissent, and
  revocations change what shows.

## 5. What becomes public

The catalog carries **part numbers, fitment relations, structural categories,
labor numerics, and aggregate market observations** — each with an observation
age and an evidence grade. That's it, by design:

- **Never a VIN.** Everything is keyed by configuration.
- **Never your identity.** No seller names, contacts, or locations in public.
- **Never shop-manual prose or images.** Source manuals inform candidates
  privately; their copyrighted text never crosses into the public catalog.

## 6. What is coming

- **Used Market Price** — asking-price samples for used parts from vetted
  sources, always shown with sample counts and checked dates. Not live today;
  no sold-price claims are made.
- **Public catalog browsing** at `/catalog` once it has coverage.
- **The web app** at `/app` — sign-in with Google or email; one account,
  every device.

The license, consent, and correction/takedown texts are drafted and under
review; they will be linked from this site once approved, not before.

Ready to lend your hands? [Get the app →](/obtain/)
