---
track: T
prio: 55
type: bug
summary: "optdiff compiles every test with bare `$(CC) -O<n> file`, so the 9 cmath tests that need `-Ilib/crtl/include -Ilib/crtl/src` (which the Makefile does pass) fail to compile and are silently counted as skips. Half the cmath family — the exact family that produced the only two optdiff DIFFs ever reported — is invisible to the O-level sweep"
---

# optdiff skips the tests whose compile flags live in the Makefile

- **Type:** bug (Track T — tooling gap; coverage hole, not a wrong answer)
- **Opened:** 2026-08-10
- **Found by:** Track A+C+P+N while resolving
  [[bug-o-o3-diverges-on-cmath-sign-bits-and-pascal-hijack]] — re-running that
  ticket's family at HEAD showed 9 of 18 `test/cmath*.c` reporting
  `COMPILEFAIL` at every level.

## Measured

```
$ compiler/pascal26 -O0 test/cmath_trig_family_b385.c /tmp/z
pascal26:1: error: C include file not found: "ctype.c"
```

The Makefile compiles the same file with flags optdiff never passes:

```make
./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cmath_trig_family_b385.c ...
```

With those flags added by hand, all 18 cmath tests compile and are **identical
across -O0 / -O2 / -O3**.

Affected (9): `cmath_cbrt_correct_round_b379`, `cmath_exp_correct_round_b377`,
`cmath_hyperbolic_family_b383`, `cmath_hypot_correct_round_b384`,
`cmath_log2_expm1_family_b382`, `cmath_log_correct_round_b378`,
`cmath_pow_correct_round_b380`, `cmath_rint_lrint_b372`,
`cmath_trig_family_b385`.

## Why it matters

`tools/optdiff.sh` documents the skip as deliberate — "programs that don't
compile ... at -O0" — and the count is reported (`pass=102 skip=16 diff=2`).
That is honest as far as it goes. The gap is that a skip caused by **optdiff
not knowing a test's flags** is indistinguishable from a skip caused by a test
genuinely not being standalone-runnable, so a coverage hole reads as a
deliberate exclusion and nobody looks.

The sharpness here is the coincidence: the correctly-rounded libm tests are
precisely where an `-O3` float pass would show up, and they are precisely the
ones not being swept. The only two DIFFs optdiff has ever reported were both
cmath.

## Options

1. **Teach optdiff the per-test flags.** A sidecar table (or a `/* optdiff:
   -Ilib/crtl/src */` comment the driver greps) is explicit but is a second
   place the flags live — it will drift from the Makefile exactly as the four
   parameter parsers did.
2. **Pass the crtl include dirs unconditionally** for `*.c` tests. One line,
   no new source of truth, and harmless for tests that do not need them.
   **Recommended.**
3. **Make the skip loud**: list skipped-because-uncompilable programs by name
   in the report rather than only counting them. Worth doing *as well as* (2) —
   it is what would have surfaced this without someone stumbling into it.

## Gate

`tools/optdiff.sh --shard 1/12` reporting the 9 as pass rather than skip, with
the skip list itemized; `tools/testmgr.py --tier full` green (Track T's own
gate for tooling changes).
