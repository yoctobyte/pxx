---
track: N
prio: 60
type: bug
---

# `def f(a, b=2, *rest)` cannot be called as `f(1)`

- **Type:** bug (NilPy, compile error on valid code — and a lurking segfault
  behind it) — **Track N**
- **Found:** 2026-08-02 by a differential sweep against the CPython oracle.
- **Pre-existing:** identical on `stable_linux_amd64/default/pinned`.

## Measured

```python
def f(a, b=2, *rest):
    return (a, b, len(rest))
print(f(1))          # CPython (1, 2, 0)
```
```
error: no overload of f matches these arguments
```

Each half alone is fine — only the COMBINATION fails:

| shape | call | result |
| --- | --- | --- |
| `def f(a, *rest)` | `f(1)` | ok |
| `def f(a, b=2)` | `f(1)` | ok |
| `def f(a, b=2, *rest)` | `f(1, 5)` | ok |
| **`def f(a, b=2, *rest)`** | **`f(1)`** | **rejected** |

## Cause, and why this is TWO defects not one

**1. Arity matching.** `ProcArityMatches` accepts a short call only when every
omitted parameter carries a DEFAULT. A `*args` / `**kwargs` parameter is
inherently optional — it packs whatever is left, including nothing — but it has
no default, so the scan stops at `rest` and the call is rejected.

**2. The call lowering cannot actually handle it.** This is the important half,
and it is why the obvious one-line fix is WRONG.

I tried exactly that fix — treat `ProcPyStarIdx` / `ProcPyKwIdx` as optional in
`ProcArityMatches` — and it compiles, then **misbinds and crashes**:

```
def f(a, b=2, *rest): return b          -> 1            (should be 2: got a's value)
def f(a, b=2, *rest): return a          -> SEGFAULT
def f(a, b=2, *rest): return len(rest)  -> -1962934248  (garbage)
```

The arguments are shifted: `b` receives `a`'s value and `rest` is never
initialised. The star packing runs BEFORE the trailing-defaults fill (see
`PyPackStarArgs` and the default-fill loop that follows it), so with the
defaulted argument omitted there is nothing to tell the packer that slot 1
should be `b`'s default rather than the first surplus argument.

**That change was reverted rather than landed** — turning a loud, correct
rejection into a silent segfault is strictly worse than the current behaviour.

## Fix shape

Fill defaults for parameters BEFORE the star index first, then pack the
remainder into the star parameter — i.e. the default-fill has to run before
`PyPackStarArgs`, not after it, whenever the star index is not the first
omitted slot. Only then is it safe to relax `ProcArityMatches`.

The two changes must land TOGETHER. Relaxing arity alone reopens the segfault
above; fixing the lowering alone leaves the call rejected before it is reached.

## Gate

A `.npy` diffed against CPython covering `def f(a, b=2, *rest)` called with 1,
2 and 3+ arguments; the same with `**kwargs`; both together
(`def f(a, b=2, *rest, **kw)`); and the existing `f(a, *rest)` /
`f(a, b=2)` shapes as controls.
