---
track: N
prio: 35
type: bug
blocked-by: []
summary: "`def g(**kw)` called as `g(**d)` raises `TypeError: forwarded call got 2 arguments, expected 1 to 1` at RUN TIME. PyStarForwardCall reads Procs[].ParamCount, which counts the `kw` collector as one ordinary named slot, so it tries to spread the dict's keys onto it instead of passing the dict INTO it. ProcPyKwIdx already records the collector — the forwarder just never consults it."
---

# The star forwarder spreads a dict onto a callee that has its own `**kwargs`

- **Type:** bug (NilPy call lowering) — **Track N**
  (`compiler/pyparser.inc`, `PyStarForwardCall`). N's own file; no handoff.
- **Found:** 2026-08-17, verifying the `f(**d)` handoff
  ([[bug-nilpy-a-dict-cannot-be-unpacked-into-a-call]]). Scoped out of the
  parser fix deliberately — this is the runtime half and it is N's.

## Repro (at HEAD, a057789bc, self-host converged)

```python
def g(**kw):
    return len(kw)

d = {"a": 5, "b": 6}
print(g(**d))
```

| | |
| --- | --- |
| CPython | `2` |
| pxx | `TypeError: forwarded call got 2 arguments, expected 1 to 1` (run time) |

`g(*[], **d)` fails identically, so it is not the parse — it is the lowering.
The message tracks the dict's size (one key gave *"has no value for parameter
'kw' — an unexpected keyword argument was passed"*), which is itself the
evidence for the cause below.

## Diagnosed — it counts the collector as an ordinary slot

`PyStarForwardCall` (pyparser.inc:15220) computes

```pascal
total := Procs[procIdx].ParamCount;
required := total;
while ... ProcParamHasDefault[...] do Dec(required);
```

For `def g(**kw)` that is `total = required = 1`: the `kw` **collector** is
counted as one ordinary named parameter. The arity guard then asserts "1 to 1"
against a dict supplying two keys, and the slot-filling below tries to bind keys
`a`/`b` onto a slot named `kw`. Hence both messages.

CPython's rule is the opposite: a `**kwargs` collector does not consume
positional slots and *absorbs* every unmatched keyword.

## The hook already exists

`ProcPyKwIdx[procIdx]` (defs.inc:2064) records the collector's index and is
already consulted elsewhere — pyparser.inc:6178, 6231, 6409, 6867 all branch on
it for the constructor paths. `PyStarForwardCall` simply never looks at it.

So the shape is: when `ProcPyKwIdx[procIdx] >= 0`, exclude that index from
`total`/`required` and from the spread loop, and assign the forwarded dict
straight into that slot instead. The `pystar_check_arity_kw` guard needs the
same adjustment or it will keep counting the dict's keys against named slots.

**Do not** re-derive the key-binding machinery: it is correct for ordinary
callees (`f(*[], **{"b": 9})` preserves `a`'s default — measured). This is
about which slots participate, not how they are filled.

## The sibling case, same root, worth doing together

```python
def h(*args, **kw): return len(args) * 10 + len(kw)
h(**d)        # CPython 2 ; pxx: COMPILE FAIL
```

A callee with `*args` never reaches the forwarder at all — the detection branch
at `parser.inc:15874` is guarded on `ProcPyStarIdx[procIdx] < 0`. That guard is
in **parser.inc (Track A)**, so if the fix needs it relaxed, file rather than
edit. Check first whether `ProcPyKwIdx` alone covers the `**kw`-only case; if it
does, ship that and file the `*args` half separately — it is a smaller ticket
than it looks and the two should not be bundled.

## Not in scope

Constructors whose `__init__` takes `**kwargs`, and methods with defaulted
parameters, both refuse by name with their own diagnostics and are separate.

## Gate

`make compiler/pascal26` + a `.npy` diffed against CPython covering: `g(**d)`
with 0/1/2 keys, `g(a=1, b=2)` direct (must not regress), `f(**d)` on an
ordinary def (must not regress), `f(*[], **{"b": 9})` default preservation,
and `dict(**d)`. Then `tools/gate.sh quick` — **including the FPC seed canary**,
which is what caught a duplicate-forward error PXX tolerated in `a057789bc`.
