---
track: C
prio: 55
type: bug
blocked-by: []
summary: "csmith seed 79 (1588 lines, UB-free by construction) computes a different global checksum under pxx than under gcc at -O0: gcc B4981522, pxx D1BEECFE. Silent wrong value, saved with its REPRO. One hit in 250 seeds — the first since the campaign's original nine."
---

# csmith seed 79: checksum disagrees with the gcc oracle

- **Type:** bug (silent wrong value) — **Track C**, with the fix likely in
  Track A codegen once reduced
- **Found:** 2026-08-13, resuming
  [[feature-c-csmith-differential-fuzzing]] (`tools/csmith_fuzz.py --iters 250`).
  219/250 agreed, 30 skipped (gcc could not build/run them), **1 miscompile**.
  A 60-seed warm-up run just before found nothing, so this is the tail the
  campaign is for.

## Reproduce

```sh
tools/csmith_fuzz.py --seed 79
```

or by hand (the harness saved everything under `/tmp/csmith-findings/`, which is
volatile — regenerate from the seed, csmith is deterministic):

```sh
csmith --seed 79 --output t.c
gcc -O0 -w -I library_candidates/csmith/include t.c -o t_gcc && ./t_gcc
./compiler/pascal26 -I library_candidates/csmith/include t.c t_pxx && ./t_pxx
```

```
gcc: checksum = B4981522
pxx: checksum = D1BEECFE
```

## Why this is worth the reduction work

csmith output is free of undefined behaviour **by construction** and ends by
checksumming every global, so a checksum difference is a real miscompile in one
of the two compilers and it is not gcc. It is also, by the campaign's own
record, the kind of bug the human-written corpora (lua, sqlite, tcc, zlib,
c-testsuite) never reach — those are written by people who avoid dark corners.

## Next step

Reduce it. 1588 lines is not a diagnosis; `creduce`/`cvise` against the
"checksums differ" property is the standard move, and the campaign ticket
records that the previous nine all reduced to a few lines each. Then the fix
lands in whichever lane the reduction points at (IR/codegen → A, C frontend → C).
