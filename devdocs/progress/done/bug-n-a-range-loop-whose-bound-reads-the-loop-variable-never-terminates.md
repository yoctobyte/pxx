---
slug: bug-n-a-range-loop-whose-bound-reads-the-loop-variable-never-terminates
track: N
prio: 75
type: bug
status: done
blocked-by: []
summary: "`for n in range(3, n - 8, -1)` HANGS FOREVER in NilPy where CPython yields 2 items. The bound is re-evaluated every iteration, so with a negative step it recedes exactly as fast as the loop variable falls and the test never fails. Not a wrong count -- a non-terminating program, from code CPython accepts and runs. Pre-existing: reproduces on pinned and on every build tested."
owner: frankA
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

---

## Resolved 2026-08-29 — frankA

### The filing's suspicion was too broad; measurement narrowed it to one arm

The ticket says "pxx re-evaluates the stop bound each iteration". True, but only
on **one of three** range lowerings, and not the one the repro's shape suggests:

| arm | shape | before |
| --- | --- | --- |
| 2-arg → Pascal `AN_FOR` | `range(1, n + 1)` | **correct** |
| 3-arg, **literal** step | `range(3, n - 8, -1)` | **HANG** |
| 3-arg, **runtime** step | `range(3, n - 8, s)` | **correct** |

So the fix went to `pyparser.inc`'s `stepKnown` branch and nowhere else. I had
also written in the filing that this might be the same window as `ir.inc`'s
AN_FOR comment reached through the NilPy path — it is the same *rule*, but the
2-arg arm that uses AN_FOR was never broken, so that part of the filing was
wrong and is corrected here.

### Third instance today of one shape

The runtime-step arm **already** binds the stop to a hidden temp, and its own
comment states the property the literal arm lacked:

> Binding them ALSO evaluates each exactly once for the whole loop, which is
> what CPython does with range()'s arguments — **the previous lowering re-ran
> the stop expression on every iteration.**

The fix was applied to the arm that needed a temp for a *second* reason (the
stop is read twice by the ternary's two arms) and never to the arm that reads it
once — where "reads it once per iteration" is the whole bug. That is the same
double-case failure as
`bug-nilpy-a-def-returning-a-field-is-typed-as-the-receivers-class` (field arm
fixed, method arm not) and `SLLowerFor` (IR arm fixed, stackless arm not), all
three found on the same day. CLAUDE.md's rule — *if you fix a bug on one arm of
a double case, grep for the sibling* — earns its place.

### Why it hangs rather than miscounts

The counted-loop lowering copies its hidden counter into the user's variable at
the top of each body (`PyPrependLoopVarCopy`). With the stop spliced into the
guard, `for n in range(3, n - 8, -1)` re-reads `n` every iteration, so the bound
falls in lockstep with the counter and `i > stop` is never false.

### The fix, and what it costs

Bind the stop to a hidden temp before the loop — **unless it is a literal**,
which cannot change and is free to re-emit. That is the same exemption
`ir.inc`'s AN_FOR makes for `IR_CONST_INT`, so the shape the lowering's own note
calls "overwhelmingly common", `range(n - 1, -1, -1)`, still pays nothing.

Measured per function from the map file (a whole-binary `cmp` is meaningless
here — every address shifts):

| shape | before | after |
| --- | ---: | ---: |
| `range(n - 1, -1, -1)` (literal stop) | 1306 B | **1306 B** |
| `range(0, 10, 2)` (literal stop) | 626 B | **626 B** |
| `range(3, n - 8, -1)` (expression stop) | 1049 B | 1058 B (+9) |

Only the shape that needs the temp pays for it, once at loop entry.

### Verified

Eight rows against **CPython**, including the two that pin the mechanism: a
bound reading a name the loop does *not* rebind (must stay correct) and a stop
with a side effect (`bound()` must be called exactly **once**, not once per
iteration). All match. On the pre-fix build the same file **hangs** — which is
why the Makefile runs it under `timeout 60`: the failure mode here is a hang,
and a runner that waits forever turns a red into a stuck job rather than a test
result.

Canaries by mechanism, not topic: 23 NilPy tests across range lowering,
iteration protocols, comprehensions over range, loop-target scoping and live
mutation. All green. The first canary pass reported 14/14 while silently
skipping three tests whose filenames I had guessed wrong — a clean number over
a population that could not contain the thing. Re-run against the real names,
it is 23/23.

Self-host fixedpoint `15afe4effd79`, converged in 1 round.

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.
