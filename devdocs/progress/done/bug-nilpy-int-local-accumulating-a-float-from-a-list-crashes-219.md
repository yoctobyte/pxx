---
track: N
prio: 55
type: bug
summary: "NilPy: `tot = 0` then `tot += v` over a list holding any float dies with Runtime error 219 (invalid typecast) — averaging a column of mixed ints and floats, ordinary CPython code, crashes"
status: done
owner: claude-A-N
---

# An int-typed local accumulating a float out of a list crashes with 219

- **Type:** bug (runtime crash on accepted CPython code) — **Track N**
- **Found:** 2026-08-07, bughunting with `tools/pydiff.py`.

## Measured (self-hosted fixedpoint at `8f1852f27`)

```python
vals = [1, 2.5]
tot = 0
for v in vals:
    tot += v
print(tot)
# CPython 3.5
# pxx     Runtime error 219        <- invalid typecast
```

The accumulator's *inferred* type is what decides it, not the data:

| variant | result |
| --- | --- |
| `tot = 0`, list `[1, 2.5]` | **Runtime error 219** |
| `tot = 0`, list `[2.5, 1]` (float first) | **Runtime error 219** |
| `tot = 0.0`, list `[1, 2.5]` | correct, `3.5` |
| `tot = 0`, list `[1, 2]` | correct, `3` |

So `tot = 0` types the local as an int, and the first float element arriving
through the for-in variant fails the cast at runtime rather than widening the
accumulator. Order does not matter — it is not a first-value inference.

`sum(vals)` over the same list is **correct** (`3.5`), which is why a probe that
only uses the builtin misses this; the hand-written accumulate loop is the
shape that breaks, and it is the shape NilPy code actually writes.

## The static form is caught at COMPILE time — only the loop escapes

```python
tot = 0
tot += 2.5
# pascal26:2: error: Nil Python: annotate the type / too dynamic [a=28 b=19]
```

So the int-target/float-source combination is already known to be a problem and
is diagnosed when both types are static. The gap is the path where the source is
a **variant** out of a container: the check does not fire, and it reaches the
runtime cast instead. That is a
`devdocs/dev/normalise-dont-special-case.md` double case — one construct
reachable through a static and a variant shape, with only the static arm
handled.

## Related, and worth reading first

[[bug-nilpy-augmented-assign-of-a-variant-param-to-an-int-field-adds-one]]
(done) is the same family — a variant source augmented-assigned into an
int-typed target — but a **field** target and a silent wrong value (`+= v`
added 1). This one is a **local** target and a hard crash. Whatever fixed the
field path is the first place to look, and the fix should cover both targets
rather than growing a third arm.

## What the right answer is

Widen the accumulator, as CPython does — `int + float` is a float, and the
local's type should follow. Note `tot` is also read after the loop, so the
widening has to be visible to `print(tot)`, i.e. it is the local's inferred type
that must change, not just the one assignment. Failing that, the compile-time
diagnostic above is far better than a 219 at runtime.

## Gate

Per-fix loop. A `.npy` test covering: int accumulator over a mixed list (float
first and last), over an all-int list (must stay int), a float accumulator over
a mixed list, and `sum()` over the same data — diffed against CPython with
`tools/pydiff.py`.

## 2026-08-07 — fixed, and the def-scope twin was WORSE than the filed crash

The ticket filed the module-scope crash. Trying the same shape one scope down,
before touching anything, found the more damaging half:

```python
def total(xs):
    t = 0
    for x in xs:
        t += x
    return t
print(total([1, 2.5]))     # CPython 3.5, pxx 3 — silently truncated
```

No crash, no diagnostic — the sum is just wrong. Module scope got RunError 219
only because it promoted first and `PXXPromoFromVariant` refuses a float tag;
inside a def the accumulator stayed a plain Int64 and the store truncated. Same
root cause, two symptoms, and the quiet one is the one that costs.

### Root cause

**An augmented assign never widened its target by its SOURCE's type.** `tot = 0`
types the accumulator from its initialiser alone; `tot += v` with `v` a variant
element never told the target anything.

`PyWiden(promo|int, tyVariant)` was already correct and already being called —
the def-scope site even computes `ASTTk[node]` from it. The gap was that the
result went to the NODE and not to the target's own slot: the node said variant,
the slot said int, and the store split the difference.

- **def scope:** note the local whenever the widened node type differs from the
  target's current type. The site already did exactly this for the promo case
  and for `/=`; it is now the general rule rather than two special cases.
- **module scope:** that arm is a token-shape scan with no node to read, so it
  scans the RHS to the end of statement and widens to variant when any name
  there is one.

### Why this does not cost the promoted-accumulator benchmark

Measured before choosing: `for i in range(n)` binds `i` as a **static tyInt64**
(`PXXDBG=n.locals`, tk=13), not a variant. So `a *= i` never reaches the
widening, and 21! still comes back 51090942171709440000. Only a
**container-sourced** element widens — and that path was already crossing a
variant boundary on every iteration, so there is no fast path being given up.

A widened (variant) accumulator still reaches arbitrary precision: 20 × 10^18
sums to 2×10^19 correctly in both scopes, pinned in the test.

### Gate

`make compiler/pascal26` (fixedpoint, converged 1 round) + `tools/gate.sh quick`
GREEN; Track T UP (`twatch --status`), matrix offloaded.
`test_nilpy_accumulate_float_from_container.npy` added, covering both scopes,
float-first and float-last, the range-loop promoted accumulator, the >Int64
widened accumulator, and the `+=` neighbours (`c += 2000000000`, `xs += [2,3]`,
a float accumulator) that must not have moved. Diffed against CPython.

## Log
- 2026-08-07 — resolved, commit d94acb267.
