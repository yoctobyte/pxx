---
track: T
prio: 15
type: feature
blocked-by: []
summary: "blocktest-elfhash SKIPs in the uforth bench: blocktest.fth needs uforth's block-word preamble (FIRST-TEST-BLOCK / LIMIT-TEST-BLOCK / [?IF]) that tester.fr alone does not supply. It is the tracked ~100x-slow outlier, so while it skips the harness has no visibility on the worst case."
---

# Restore the ELF-HASH workload to the uforth bench

- **Type:** feature (bench workload) — **Track T**
- **Opened:** 2026-08-17
- **Split out of** [[feature-t-uforth-benchmark-harness]], listed there as a
  follow-up "filed, not blocking" and never actually filed.

## What

`--full` is supposed to include the blocktest ELF-HASH section — the known
~100x-slow outlier, and the whole reason the harness tracks a full mode. It
currently **SKIPs**: `blocktest.fth` needs uforth's block-word preamble
(`FIRST-TEST-BLOCK`, `LIMIT-TEST-BLOCK`, the `[?IF]` guards) which `tester.fr`
alone does not provide, so the workload never runs.

Two ways out, either acceptable:

1. assemble the preamble the workload needs, or
2. extract the ELF-HASH section as a standalone snippet.

(2) is likely smaller and less coupled to uforth's suite layout.

## Why it matters more than "one skipped workload"

The outlier is the one number that would move most if a Track O optimisation
landed on the slow path, and the one most likely to regress unnoticed. A
harness whose worst case is skipped reports only the cases that were already
fine — the same shape as a green tier that skipped its corpus.

Note the harness is honest about it: a workload the base runtime cannot run is
SKIPped with a reason, never emitted as a partial row. So this is a coverage
gap, not a wrong number.

## Gate

`tools/uforth_bench.py --full` emits ELF-HASH rows for cpython and pxx rather
than a SKIP.
