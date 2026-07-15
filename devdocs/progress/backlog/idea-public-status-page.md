---
summary: "Publish a live compatibility/corpus status report on the website — the static docs/reference/status.md page exists; wire it to the already-generated tstate reports (twatch_web conformance.html/bench.html/dashboard.html) so public numbers stay current instead of hand-maintained"
type: idea
track: D
tags: []
prio: 30
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
