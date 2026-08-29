---
slug: bug-n-a-range-loop-whose-bound-reads-the-loop-variable-never-terminates
track: N
prio: 75
type: bug
status: backlog
blocked-by: []
summary: "`for n in range(3, n - 8, -1)` HANGS FOREVER in NilPy where CPython yields 2 items. The bound is re-evaluated every iteration, so with a negative step it recedes exactly as fast as the loop variable falls and the test never fails. Not a wrong count -- a non-terminating program, from code CPython accepts and runs. Pre-existing: reproduces on pinned and on every build tested."
owner: unassigned
---

# A `range` bound that reads the loop variable never terminates

Found 2026-08-29 by frankA while fixing
[[bug-a-for-loop-limit-is-evaluated-after-the-control-variable-is-assigned]].
Same family, different lowering, and **filed separately because it is not the
same code**: that ticket is Pascal's `AN_FOR` in `ir.inc`, this is NilPy's
`range` loop.

## Repro

```python
def plain2(n):
    c = 0
    for n in range(3, n - 8, -1):
        c += 1
    return c

print(plain2(9))          # CPython: 2      pxx: HANGS
```

`n` is rebound by the loop and also appears in the stop bound. Reduce further
and it still hangs; it is **not** generator-specific — the same shape inside a
`def` with no `yield` hangs identically. A generator spelling hangs too, which
is how it was found.

| shape | CPython | pxx |
| --- | ---: | --- |
| `for n in range(3, n - 8, -1)` in a plain def | 2 | **HANG** |
| the same inside a generator | 2 | **HANG** |
| `for k in range(3, n - 8, -1)` (different loop var) | 2 | 2 |
| `for n in range(1, n + 1)` (positive step) | 5 | 5 |

## Why it hangs rather than miscounts

CPython evaluates all three `range` arguments **once**, before the loop. pxx
re-evaluates the stop bound each iteration, so with `step = -1` the bound
`n - 8` falls in lockstep with `n` and the exit test `n > stop` is never true.
With a positive step the same re-evaluation is harmless for the shapes tried,
which is why only the negative-step row hangs.

That makes this the *other* end of the window `ir.inc`'s AN_FOR comment
describes — "evaluate the limit exactly once (Pascal requires it; FPC does it)"
— reached through the NilPy path, where the fix was never applied.

## Severity

NilPy is **upward compatible with CPython**: code that works on CPython must
work on NilPy. This is code CPython accepts and runs, so it is squarely a bug
and not a divergence. A hang is worse than the wrong count its Pascal sibling
produced — there is no wrong answer to notice, and nothing to diff against an
oracle, because the program never reaches the compare.

## Not caused by the AN_FOR fix

Measured on three binaries: `pinned`, a build at HEAD before the AN_FOR fix,
and one after. All three hang. Pre-existing, and untouched by that change.

## Gate

`make test-nilpy`'s relevant tests plus a new test asserting the four rows
above against CPython, self-host fixedpoint byte-identical. Note the test must
carry a timeout — a hang is the failure mode, so a runner that waits forever
turns a red into a stuck job.
