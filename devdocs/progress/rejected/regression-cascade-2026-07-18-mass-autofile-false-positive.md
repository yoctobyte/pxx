---
track: T
prio: 0
type: regression
blocked-by: []
---

# regression CASCADE: 1414 stub tickets auto-filed on 2026-07-18 — all false positives

One incident, recorded once. This replaces **1414 individual auto-filed stub
tickets** that were rejected and are now deleted; they made up 98% of
`rejected/` and buried the handful of rejections worth reading.

## What happened

The Track T watcher (host `borg`) auto-filed one ticket per red job across the
whole matrix, in a two-hour window:

| hour | tickets |
| --- | --- |
| 2026-07-18T18 | 938 |
| 2026-07-18T19 | 476 |

Every one carried an **empty log tail** and no triage — title, repro line, an
empty code fence, stub footer. Median size 725 bytes.

### By job family

| family | tickets |
| --- | --- |
| `test-core` | 889 |
| `test-arm32` | 120 |
| `test-i386` | 120 |
| `test-aarch64` | 115 |
| `test-riscv32` | 88 |
| `test-threads` | 29 |
| `test-asm` | 15 |
| `test-smoke` | 12 |
| `test-c-conformance` (all targets) | 17 |
| `lib-fpc-clean`, `selfhost-fixedpoint`, `test-cjson`, `test-debug-g`, `test-emit-obj`, `test-float-determinism`, `test-lua`, `test-sqlite-threads-x86_64`, `test-zlib` | 1 each |

## Why they are false positives

The blamed commits cannot have caused a regression:

| blamed sha | tickets | what it actually is |
| --- | --- | --- |
| `f5c8fbec6016` | 938 | `tstate(borg): 2dffbb7c65a2 RED (native) …` |
| `f6cad82e8063` | 476 | `tstate-ticket(borg): regression-….md …` |

Both are **tstate-only commits** — watcher bookkeeping that touches no compiler,
library or test source. A commit that changes nothing but `tstate/` cannot turn
889 `test-core` jobs red. The matrix went red for a host/environment reason and
the watcher attributed it to whatever sha happened to be at HEAD.

This is the same failure mode as the `xeon` enrolment cascade, which *was*
triaged in detail and is kept: see
`regression-cascade-110774a14648.md` in this directory — there the two
root causes were a stale seeded binary (`make seed-from-stable` leaving
`compiler/pascal26` newer than its sources, so nothing rebuilt) and missing host
dev packages. Neither was a code regression either.

## Recovery

The 1414 stubs are deleted, not archived — they are recoverable from git history
at the parent of the deleting commit (`155c41505`). Nothing in them is unique:
each holds a job name, a sha that is not the cause, and an empty log.

## Follow-ups already filed

Suppressing this class at the source is Track T's, and tickets exist:
`task-t-suppress-autoticket-until-host-baselined` and
`task-t-seed-from-stable-defeats-rebuild`. The lesson worth keeping is the
attribution rule — **a tstate-only commit is never a regression suspect**, and
a whole-matrix red is one event, not N findings.
