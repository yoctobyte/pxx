---
track: T
prio: 45
type: bug
blocked-by: []
summary: "`lib-test#src:test/crtl_exp2.c` has been STILL-RED since 096da361dd93 with a `(timeout)` verdict, and the bisect named that commit — which touches nothing the job builds (the job uses the PINNED compiler; the commit's Makefile lines went to test-core). Every step of the job runs clean standalone in seconds. A timeout is a DURATION signal, so bisecting it converges on whichever commit happened to straddle the budget, and the report presents that with the same confidence as a real first-failure."
---

# A timeout bisects to an innocent commit, and the report does not say so

Filed 2026-08-16 by the Track A+P session, from the monitor stream. **Not fixing
it — Track T owns the tool.** Filed because the bisect result is currently
pointing at a Track A commit, and the next person to look will go hunting a
compiler regression that is not there.

## What the report says

```
## STILL-RED
- lib-test#src:test/crtl_exp2.c — test/crtl_exp2.c examples/tk/hello.npy +5

## first failure: lib-test#src:test/crtl_exp2.c … (timeout)
repro: tools/testmgr.py --tier full --job 'lib-test#src:test/crtl_exp2.c'
```
```
ok: …/crtl_exp2  [code=228732B …]
  tk-nilpy: ok
```

and `TSTATE.md`: *bad `096da361dd93`, last good `45bc7a43d67c`, 1 commit(s) in
range* — i.e. the culprit is `096da361dd93` ("fix(A): ParamCount carries a
type…").

## Why that commit cannot be the cause

- **It never moved the pin.** `lib-test` builds everything with `$(PXX_STABLE)`
  = `stable_linux_amd64/default/pinned`, last changed by `da44f561e` (v344).
  `096da361dd93` touches `compiler/parser.inc` and `compiler/ir_codegen386.inc`,
  which only affect a compiler built at HEAD — not this job.
- **Its Makefile lines went to a different target.** The 7 added lines land in
  `test-core` (the `test_paramcount_for_limit` steps, one of them an i386 cross
  build). They add no work to the `lib-test` recipe that timed out.

## And nothing in the job actually hangs

Measured each step around the cut point (the capture stops right after
`tk-nilpy: ok`, so the next recipe step is `lib_codecs`):

| step | result |
| --- | --- |
| `pinned test/lib_codecs.npy` build | ok, seconds |
| running it | `codecs ok`, exit 0 |
| `python3 test/lib_codecs.npy` (the CPython oracle beside it) | `codecs ok`, exit 0 |

So no step hangs. The job simply exceeds its total budget: `lib-test` is one
very large make target, and the run `wall` has been pinned at 1142–1145s at
EVERY sha since (`42e147157b60`, `7111221470d4`, `1a181203b094` — all RED, all
`new_red: 0`), which is the shape of a cap being hit rather than of a failure
being reproduced.

## The tool issue, which is the actual ticket

1. **A timeout is a duration signal, so bisecting it is not sound.** Whether the
   job crosses its budget depends on load, not only on the commit — this box also
   ran a dev session's compiles and `gate.sh quick` runs all day, and CLAUDE.md
   already records that concurrent work makes every compile 2-3x slower. Bisect
   converges on whichever commit straddled the threshold and reports it with the
   same confidence as a genuine first failure.
2. **The report does not distinguish them.** `(timeout)` appears as a small
   parenthetical next to `first failure:`; the STILL-RED list does not carry it
   at all. Suggestions, in the owner's hands: refuse to bisect a timeout-only
   job (or mark the result advisory), say `TIMED OUT after Ns` in the STILL-RED
   line, and record the job's measured duration next to its budget so slow-creep
   is visible before it becomes a red.
3. Worth checking separately whether `lib-test` should be SPLIT — one job whose
   sources are `crtl_exp2.c examples/tk/hello.npy +5` is broad enough that its
   name misdescribes what failed, which is the second half of why this reads as
   a C/math regression.

`test-nilpy#src:test/test_nilpy_pow_matches_cpython.npy` is the other STILL-RED
from the same run; its bisect range is 32 commits and it is NOT analysed here —
it may well be a real regression and deserves its own look.

## Gate

Track T's own: `tools/testmgr.py --tier full` green (T escapes the full-suite
hook with `PXX_TRACK=T`), plus whatever the owner adds for the report format.
