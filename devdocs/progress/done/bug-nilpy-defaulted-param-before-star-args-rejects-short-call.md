---
track: N
prio: 60
type: bug
status: done
owner: claude-AN-night
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


## Resolved 2026-08-03 — and the arity check needed NO change

The ticket's fix shape said the two defects had to land together: relax
`ProcArityMatches`, and reorder the default-fill ahead of the star packing. Only
the second was needed, and doing it alone makes the first unnecessary — which is
the better outcome, because the relaxation is precisely what reopened the
segfault when it was tried in isolation.

`PyPackStarArgs` now fills the DEFAULTS of any parameters between the last kept
positional and the slot the `*args` list (or `**kwargs` dict) is about to
occupy, before placing that container. For `def f(a, b=2, *rest)` called as
`f(1)` that means slot 1 gets `b`'s default and the list goes to slot 2 — so the
call arrives at overload resolution **exactly arity-matched**. There is no short
call left for `ProcArityMatches` to accept or reject, so it keeps its current
rule and nothing else that depends on it moves.

The default nodes come from `DefaultArgValueNode`, the same AST-level builder
`PyBindKwArgs` already uses for keyword calls — no new default-materialising
code, and every default flavour (sym / None / str / bool / float / int) is
covered by construction.

The `**kwargs` slot gets the same treatment, so `def k(a, b=3, **kw)` called as
`k(1)` works for the same reason rather than by accident.

### Verified

`test/test_nilpy_default_before_star_args.npy` (+ `.expected`, wired into
`make test-nilpy`), byte-identical to CPython across 17 lines: the repro at 1,
2, 3 and 4 arguments; `def f(a, *rest)` and `def f(a, b=2)` as controls;
`**kwargs` alone; both together (`def m(a, b=2, *rest, **kw)`); and a STRING
default, which exercises a different `DefaultArgValueNode` flavour than the
integer one the repro uses.

Before/after on the same program: pinned rejects it at compile time, HEAD prints
CPython's answers.

`gate.sh quick` GREEN, self-host fixedpoint byte-identical, FPC seed build clean.

## Log
- 2026-08-03 — resolved.
