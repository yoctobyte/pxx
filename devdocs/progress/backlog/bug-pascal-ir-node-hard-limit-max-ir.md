---
summary: "pxx rejects very large valid programs with 'IR overflow' — MAX_IR is a fixed 131072-node array, not dynamic"
type: bug
prio: 25
---

# `IR overflow`: a fixed MAX_IR node limit rejects very large (valid) functions

- **Type:** bug / scalability limit (Track A — `compiler/ir.inc`, `defs.inc`). A capacity
  limit, **not** a miscompile: pxx rejects a program FPC compiles, with
  `error: IR overflow` — it never emits wrong code.
- **Status:** backlog (low priority)
- **Found:** 2026-07-17, pasmith non-interface high-complexity run (seed 60030,
  `pxx-reject_overflow`, 13 hits).

## Cause

`ir.inc:25`: `if IRCount >= MAX_IR then Error('IR overflow')`. `MAX_IR = 131072`
(`defs.inc:48`) sizes the global IR arrays (`IRKind`/`IRA`/`IRB`/`IRC`/`IRIVal`/`IRTk`,
each `array[0..MAX_IR-1]`). A single function body that lowers to > 131072 IR nodes
overflows the array and is rejected. FPC has no such fixed cap.

The trigger here is pathological: pasmith's exit checksum hashes every element of every
variable (14 scalars + 4×`array` + 4×`record` + strings + objects) into one `main`, so
`main` alone exceeds 131072 nodes. Hand-written code rarely reaches this in one function —
hence low priority — but a large generated/amalgamated function (or a huge `case`, a big
unrolled initializer) legitimately can.

## Status: cheap tier DONE, proper fix open

`MAX_IR` bumped 131072 → 262144 (`5a067617`) — seed 60030 now compiles and matches the
FPC checksum (the cap was not hiding a miscompile), self-host byte-identical. The hard
cap still exists at 2× — a large enough function still overflows. Ticket stays open for
the **dynamic-array** proper fix; deprioritised (the wall just moved).

## Fix direction

- **Cheap, partial:** bump `MAX_IR` (e.g. 131072 → 262144). Byte-identical-safe (the
  compiler's own bodies stay well under the cap, so self-host output is unchanged; only
  the array sizes — and global memory ~+6 MB — grow). Just moves the wall.
- **Proper:** make the IR arrays **dynamic** (grow on demand), removing the hard cap.
  Bigger change; touches every backend that indexes the IR arrays. Related scalability
  work: [[perf-c-parse-codegen-large-file-superlinear]].

## Acceptance

- Seed 60030 compiles (or a hand-written function with > 131072 IR nodes does).
- Gate: `make test` + self-host byte-identical.

## Note

Low severity — a capacity ceiling, no wrong code. Filed for the record; the pasmith
trigger is an unusually large single function, not typical source.
