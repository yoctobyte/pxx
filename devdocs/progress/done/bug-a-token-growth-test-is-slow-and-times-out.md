---
track: A
prio: 45
type: bug
---

# `test-core` token-growth job takes 77s and gets killed under load

Observed 2026-07-20 running `make test` natively; the same job is what borg's
20260720T091031Z report attributed a NEW-RED to
(`test-core#src:test/test_interface_mainbody_ascast_temp.pas`, log ending in a
bare `Terminated` right after `test_ast_overflow_large26`). That RED is a
TIMEOUT of the following job, not the named test — that test passes on its own,
here and at that SHA.

## Numbers

`/tmp/test_token_growth.pas` (12000 empty procs, ~72k tokens; Makefile:955):

| compiler | wall |
| --- | --- |
| `stable_linux_amd64/default/pinned` | 51.5s |
| HEAD (2026-07-20) | 77.5s |

Both are slow for 12000 empty procedures, and HEAD is ~1.5x the pinned build,
so something between the pin and HEAD made it worse on top of an already-poor
baseline. A 12000-proc file is ~72k tokens — self-host lexes ~1M per build in
far less time, so this is not lexing.

## Suspicion

A per-proc O(n) scan turning the whole file into O(n²) — the shape
`project_pxx_string_concat_in_loop_is_quadratic` warns about. Find it by SCALING
CURVE (3000 / 6000 / 12000 / 24000 procs, pinned vs HEAD), not by reading code.

## Why it matters beyond speed

At this duration the job is a coin flip against the harness timeout on a loaded
box, and when it loses, the report blames whichever test the log stopped near —
so a slow job manufactures phantom REDs in tstate. Track T sees the symptom;
the cause is here.

## Gate

Scaling curve recorded before/after, `make test` green, self-host byte-identical.

## Log

- 2026-07-20 — measured the RSS, and TIME is the smaller half: the compile of
  `/tmp/test_token_growth.pas` (12000 empty procs) climbs past **2.2 GB RSS**
  and is then SIGTERMed under memory pressure, which is what "Terminated"
  in the log means — not a timeout. Standalone on an idle box it completes in
  77s; concurrently with Track T's own testmgr run it dies. So the phantom
  NEW-REDs appear exactly when two runs overlap.
- That reframes the fix: a per-proc allocation that never shrinks (~180 KB per
  EMPTY procedure) rather than only a quadratic scan. Look at what is reserved
  per Proc entry and whether the per-body arrays are sized per procedure.

## Measurements 2026-07-20 (narrowing, not yet root-caused)

Scaling curve, `procedure qN; begin end;` × n, HEAD:

| n | wall | peak RSS |
| --- | --- | --- |
| 1500 | 0.58s | 103 MB |
| 3000 | 2.55s | 436 MB |
| 6000 | 13.0s | 1743 MB |
| 12000 | 67.6s | 4484 MB |

RSS is **quadratic in the number of PROCEDURES** (4x per doubling); wall is
slightly worse than quadratic. What that rules out:

- **Not the bodies.** 3000 procs × 10 statements = 516 MB vs 3000 empty procs
  = 436 MB. Body content barely matters; proc COUNT is the whole curve.
- **Not registration.** 6000 forward declarations alone: 0.95s / 44 MB. The
  cost is entirely in compiling bodies.
- **Not the optimizer.** `-O0` and `-O2` are identical (11.7s / 1740 MB).
- **Not globals.** 6000 global vars: 0.18s / 34 MB.
- **Not inline retention specifically** — bodies made non-inlinable (a `for`
  loop over a global) cost the same 1795 MB.

RSS climbs steadily (~120 MB/s) throughout, so it is accumulation during body
compilation, not a spike at emit. Arithmetic: ~100 bytes allocated per
ALREADY-REGISTERED proc, per body compiled. That shape says a per-body pass
walks all procs so far and allocates something small per entry (a temporary
string per candidate name is the classic one — see
`project_pxx_string_concat_in_loop_is_quadratic`).

Next step for whoever picks this up: instrument the allocator (or run a build
with symbols under a heap profiler — `perf` is blocked in this sandbox and the
self-hosted binary carries no symtab, which is why this stopped here).

- 2026-07-20 (later, box under concurrent Track T load) — same 12000-proc file:
  **pinned 87s / 5.2 GB, HEAD 122s / 7.0 GB**. Note the earlier HEAD figure in
  the table above was 67s / 4.5 GB on an idle box, so these numbers move a lot
  with system pressure (the allocator appears to take more when more is free) —
  whoever picks this up should compare pinned and HEAD in the SAME conditions
  before concluding anything about a per-commit regression. What is not
  conditional: it is quadratic, and 5-7 GB for 12000 empty procedures is the
  bug.

## Phantom RED, second sighting

tstate now carries `test-core#src:test/test_interface_mainbody_ascast_temp.pas
bad=d46bcff4834b` — the SAME test as the 20260720T091031Z report, and the same
non-failure: it compiles and runs correctly at d46bcff4 (`cast=107 / after nil /
destroy 7`, the expected order), verified directly. It is the job that follows
the 12000-proc token-growth compile in test-core, so when that compile is
SIGTERMed under memory pressure the report blames its neighbour.

**For Track T: do not bisect this one.** Two separate SHAs have now produced it
with the named test passing standalone. Either raise that job's memory headroom,
shrink the generated program, or run it in its own scope — the underlying cost
is this ticket.
- 2026-07-22 — resolved, commit 06219176.
