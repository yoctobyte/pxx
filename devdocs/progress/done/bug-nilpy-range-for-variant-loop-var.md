---
track: N
prio: 30
type: bug
status: resolved
---

# NilPy: range for-loop with a pre-existing VARIANT loop variable corrupts it

Found while landing feature-nilpy-comprehension-if-filter. If `x` was earlier
a container-loop target (typed tyVariant), a later `for x in range(n):` drove
the variant slot RAW with the counted-for/while lowering: an untagged integer
under a stale tag. `x > 2` matched nothing (silent!), `x % 2` raised
"expected a number, got str". Repro: comp over a list, then plain
`for x in range(6): if x > 2: n += 1` → n = 0 (CPython 3). Pre-existing —
reproduces on the pinned compiler.

Fix (same commit as the comprehension filter): when the range target is a
variant, count with a hidden int local and box it into the variant at the top
of each iteration (`x = __py_i`), for both the step-while and counted-for
lowerings. Covered by test_nilpy_comp_filter.npy.
