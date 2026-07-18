---
summary: "csmith seed 31039: pxx prints a wrong global (g_22) checksum vs gcc at -O0, consistent across -O levels. Pre-existing. Needs creduce (line-reducer floors ~90 lines)."
type: bug
prio: 50
---

# csmith -O0 miscompile (seed 31039): wrong g_22 checksum

- **Type:** bug (codegen/frontend — **Track A**; divergence at -O0 and identical
  across all pxx -O levels, so base codegen or C→IR lowering). Silent wrong output.
- **Found:** 2026-07-18, csmith campaign ([[feature-c-csmith-differential-fuzzing]]),
  small/mid complexity (--max-funcs 2 --max-array-dim 3 --max-pointer-depth 3).

## Symptom

```
gcc -O0            : checksum = 6522DF69
pxx (all -O levels): checksum = A988DFF7   (wrong)
```

The checksummed global is `int16_t g_22`. It is mutated through two nested-function
sites (`(*l_21) ^= ...` in func_1's argument list, then `(*l_89) = safe_sub(...)`
inside func_2, which is CALLED from that same argument list) — so the final value
depends on side-effect ordering across a nested call plus pointer chains
(`int8_t **`, `int8_t ***`) and safe_math wrappers.

## Reproduce

```sh
tools/csmith_fuzz.py --seed 31039 --csmith-args "--max-funcs 2 --max-array-dim 3 --max-pointer-depth 3"
```

Reproducer (this box's csmith) + a 90-line line-reduced form preserved in the
session scratchpad (`MISCOMPILE_VS_GCC-31039/`, `reduced31039.c`).

## Status

- **Pre-existing, NOT a regression** — pinned stable reproduces the same wrong
  checksum. Distinct from the two miscompiles fixed 2026-07-18
  ([[project_c_signed_unsigned_compare64]] 574fcac1, struct-array-ptr stride
  4f4aceb3): those reproducers now match gcc; this one still diverges.
- **Blocked on reduction:** a homemade line-delta reducer floors at ~90 lines
  (csmith's nested exprs/blocks need a C-aware reducer). Install `creduce`/`cvise`
  (root/PEP-668 blocked here), reduce with "gcc runs & pxx runs & checksums
  differ", then isolate g_22's diverging mutation (likely the nested-call
  argument-evaluation order or a safe_math/pointer-chain interaction).

## Acceptance

- Reduced repro's pxx checksum matches gcc; a `test/*.c` regression; C-conformance
  220/220 + self-host byte-identical.
