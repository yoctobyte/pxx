---
summary: "csmith seed 5038: pxx produces a WRONG global checksum vs gcc at -O0 (silent miscompile). Pre-existing (pinned reproduces). Needs creduce to reduce."
type: bug
prio: 55
---

# csmith -O0 miscompile (seed 5038): wrong checksum vs gcc

- **Type:** bug (codegen/frontend — **Track A** most likely; a C program but the
  divergence is at -O0, so it is base codegen or C→IR lowering, not an opt pass).
  Silent wrong output — the worst class.
- **Found:** 2026-07-18, resumed csmith differential campaign
  ([[feature-c-csmith-differential-fuzzing]]), seed range 5000+.

## Symptom

```
gcc -O0 : checksum = D3A7CBC1
pxx     : checksum = C6185196   (all pxx -O levels agree with each other, differ from gcc)
```

csmith programs are UB-free by construction and checksum every global, so a
divergence is unambiguously a pxx bug.

## Reproduce

```sh
csmith --seed 5038 --output t.c
gcc -O0 -w -I<csmith/include> t.c -o t_gcc && ./t_gcc      # D3A7CBC1
compiler/pascal26 -I<csmith/include> t.c t_pxx && ./t_pxx  # C6185196 (wrong)
# or: tools/csmith_fuzz.py --seed 5038
```

A copy of the generating `t.c` (this box's csmith) is preserved in the session
scratchpad `MISCOMPILE_VS_GCC-5038/`.

## Status / notes

- **Pre-existing, NOT a regression:** the pinned stable compiler produces the SAME
  wrong checksum (C6185196). It predates the 2026-07-18 C multi-dim / float work.
- **Blocked on reduction tooling:** the generator is ~2.5k lines. A homemade
  line-delta reducer floored at ~900 lines (csmith's nested expressions need a
  C-aware reducer). `creduce`/`cvise` are not installed (apt/pip need root/PEP-668).
  Install creduce, reduce with the interestingness "gcc runs && pxx runs &&
  checksums differ", then diagnose the single miscompiled global's computation.

## Acceptance

- The reduced repro's pxx checksum matches gcc; a `test/*.c` regression from the
  reduction; C-conformance 220/220 + self-host byte-identical.
