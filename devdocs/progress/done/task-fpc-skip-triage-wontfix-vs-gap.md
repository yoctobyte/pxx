---
prio: 20
---

# FPC conformance: triage the ~237 untriaged skips into gap: / wontfix:

- **Type:** task (testing infra / frontend audit) — **Track T** files it; the
  per-test verdicts are P/B/A knowledge but the tagging lives in T's skip list.
- **Status:** done
- **Opened:** 2026-07-11 (follow-up to
  [[feature-testmgr-fpc-compare-and-web-dashboard]])
- **Owner:** —

## Why

The dashboard's conformance page groups FPC-suite skips by tag, and the adjusted
pass rate excludes `wontfix:` (tests that probe FPC internals / intentional
divergence and can never pass). The taxonomy + rendering shipped, but the ~237
existing `test/pascal-conformance/pxx.skip` entries are all **untriaged** — no
tag yet, so today they all read as "open". The honest picture (what fraction of
the suite is a real pxx gap vs never-applicable) needs each entry classified.

## What

Agentic pass over `pxx.skip`: for each untagged entry, read the test source +
its recorded reason and decide:
- `wontfix: <reason>` — probes FPC-internal behaviour: RTTI/typeinfo layout,
  FPC-specific units (`fgl`, `variants` as FPC ships them), internal-error
  message text, FPC bootstrap intrinsics, pointer-value printing, anything where
  matching FPC would mean copying an implementation detail rather than a language
  feature.
- `gap: <reason>` — a real Pascal feature pxx doesn't implement yet (already
  clustered in [[task-pascal-conformance-long-tail]]: RTL gaps, generics holes,
  case-label edges, custom enumerators, dynarray ops…). Cross-link the cluster
  ticket where one exists.

Batch it (e.g. the investigator subagent per category prefix), commit the
retagged skip list, and the dashboard reflects the split on the next idle bench.

## Notes
- Pure skip-list edits — Track T lane, no compiler change, no gate beyond the
  conformance runner staying green.
- Deprioritized like its parent ([[task-pascal-conformance-long-tail]] prio 12):
  the burndown is paused, but this makes the *reporting* honest, which is cheap.

## Log
- 2026-07-11 — filed.
- 2026-07-12 — resolved, commit 9114ea42.
