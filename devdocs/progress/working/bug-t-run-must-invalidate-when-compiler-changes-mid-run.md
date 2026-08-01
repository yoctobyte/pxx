---
summary: "A test run that spans a compiler rebuild reports PASS/FAIL as if it were one binary; it should hash the binary at start and end and report INVALID on mismatch"
type: bug
track: T
prio: 70
---

# A run whose compiler changed underneath it must report INVALID, not PASS/FAIL

- **Type:** bug (Track T, silent wrong result) — **Track T**
- **Opened:** 2026-08-01. Filed from A+P+C+N; Track T's files.
- Companion to [[feature-t-snapshot-compiler-binary-per-run]]. That one PREVENTS
  the common case; this one DETECTS every case, including the ones prevention
  cannot cover. Land both — a prevention you can forget to apply is not a
  backstop.

## The problem

Nothing in the harness notices when `compiler/pascal26` changes mid-run. A run
that used binary A for its first 200 jobs and binary B for the rest reports a
single PASS/FAIL verdict, and the report format has no way to say "these
results are not from one binary".

That is a **silent wrong result**, which is the failure mode this repo treats as
the expensive one. It is also exactly the shape CLAUDE.md's provenance rule
("any result you report must name the sha of the binary it came from") tries to
prevent by discipline — and discipline is the wrong layer for it, because the
person reporting has no cheap way to check.

Observed 2026-08-01: a `make pxx-debug` rebuilt the compiler 9 minutes into a
`make test-nilpy`. It was caught by noticing an mtime, not by any tooling.

## Fix

Cheap and mechanical:

1. At run start, record a strong hash (or the ELF build-id) of the compiler
   binary, alongside the git sha already recorded.
2. At run end — and ideally per job — re-read it.
3. On mismatch, the run's verdict is `INVALID` with both hashes named. Never
   `GREEN`, never `RED`: a red from a mixed run is as untrustworthy as a green,
   and auto-filing a regression ticket from one manufactures exactly the
   phantom-red noise already tracked in the backlog.

Record the hash in the tstate report too, so a report's binary is identifiable
after the fact rather than inferred from commit timestamps.

## Why INVALID rather than "rerun automatically"

An automatic rerun hides how often this happens, and the frequency is the
signal that tells you whether [[feature-t-snapshot-compiler-binary-per-run]] and
[[bug-t-selfhost-build-uses-fixed-tmp-paths-colliding-across-clones]] actually
fixed it. Surface it first; automate the recovery later if it is still common.

## Gate

A run deliberately raced against a rebuild reports INVALID and files no
regression ticket. A run with no rebuild is unaffected and still reports
GREEN/RED as today.
