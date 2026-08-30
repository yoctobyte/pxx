---
summary: "Publish a live compatibility/corpus status report on the website — the static docs/reference/status.md page exists; wire it to the already-generated tstate reports (twatch_web conformance.html/bench.html/dashboard.html) so public numbers stay current instead of hand-maintained"
type: idea
track: D
tags: []
prio: 25
---

# Public, live status report on the website

The static [Compatibility status](../../docs/reference/status.md) page (landed
2026-07-15) is hand-written prose: it describes what compiles (c-testsuite, zlib,
SQLite, Lua, tcc, cJSON; the RTL suites; fpjson/Synapse/fgl; the conformance
snapshot) with the correct claims discipline (the two distinct "byte-identical"
meanings, never "clone"). Good as a narrative, but the numbers rot — they are a
manual snapshot of gates that move every day.

## What already exists

`tools/twatch_web.py --static --out DIR` writes self-contained **dashboard.html**,
**bench.html**, and **conformance.html** into `tstate/`, fed by the watcher's
per-SHA `conformance.tsv` / `<host>.json` / bench rows. So the *data pipeline and
renderers already exist* — Track T publishes them to `tstate/`.

## The gap

Those generated pages live in `tstate/` (the watcher's write scope) and are not
surfaced on the public website, which publishes `docs/**` verbatim. So:

1. **Publish path** — expose the generated conformance/bench/dashboard pages (or a
   curated subset) at a stable public URL, linked from `docs/reference/status.md`.
2. **Freshness** — either (a) link out to the live generated report and keep
   `status.md` as the stable narrative, or (b) generate the corpus-matrix section
   of `status.md` from the testmgr/tstate data so the counts self-update.

## Cross-track

Track D owns the website/publishing and the prose; Track T owns the generators and
the `tstate/` data. A clean split: T emits a machine-readable status artifact
(counts per corpus/suite + last-green SHA); D renders/links it. Keep the claims
discipline in whatever is auto-generated — the "output parity vs self-host
reproducibility" distinction must survive templating (see the compatibility-claims
note in the agent guide).

## Not doing yet

Exploratory (user: "we *may* seek a way"). Filed so the static page and the
existing tstate renderers can be joined up when the website build is ready for it.

## RESOLVED 2026-08-30 — premise discharged, not built

**This idea's own argument no longer holds**, verified by frankD before it built anything on
top of it. The idea was filed when `status.md` was hand-written prose, and its case is *"the
numbers rot — they are a manual snapshot of gates that move every day."*

That stopped being true in `ce89ff14b`, *"docs(D): stop hand-writing numbers in status.md."*
The page now opens **"For current numbers, read the live status pages, not this page"** and
states outright: *"Deliberately no figures — a number written here is a number that starts
going stale the day it is written."* **That is this idea's own option (a), already shipped.**
Gap items 1 and 2 are both closed.

Its second concern — that claims discipline must *survive templating* in anything
auto-generated — is also nothing to do, and this was **grepped rather than reasoned**:
`tools/twatch_web.py` and `tools/testmgr.py` carry **no** byte-identical / clone / compatible
/ parity language at all. The generated pages carry numbers; the claims live in `docs/**`
prose; that prose was audited against CLAUDE.md's claims-discipline table on 2026-08-29.
frankD expected this to be a real finding and reported that it was not — *"I'd have reported
it as one if I'd reasoned instead of grepped."*

## What the fix EXPOSED, which is the only live work here

Carried forward as `task-d-verify-the-published-status-urls-docs-now-delegates-all-numbers-to`
[D p30]:

| | before `ce89ff14b` | now |
| --- | --- | --- |
| failure mode | a number goes stale | a URL 404s |
| visibility | **visible** — a reader who checks sees a wrong number | **invisible from this repo** — the link is syntactically fine |
| self-correcting | yes, someone re-measures | no |

**A better trade, not a free one, and never checked once.** `docs/**` references six distinct
`pxxc.org/status/*` URLs across two files; `tools/` has no link checker of any kind
(`docaudit` checks internal citations, `docsnip` compiles code blocks, neither looks at an
`http` URL); and the generated HTML is not in this checkout, since `twatch_web --static`
writes it inside the watcher's clone — so there is no local artefact to diff either.

The sharp version, frankD's: **`status.md` does not merely link to those URLs, it delegates
its entire numeric content to them.** If `/status/conformance/` is missing, the public
compatibility page has no figures and no working pointer to any, **while telling the reader
that is exactly where the figures are** — strictly worse than the snapshot it replaced, and
the one outcome nobody can notice from inside the repo.

**Resolved by the coordinator rather than by the lane**, because closing an idea is a filing
decision and frankD correctly declined to claim a ticket it had been told not to claim.
