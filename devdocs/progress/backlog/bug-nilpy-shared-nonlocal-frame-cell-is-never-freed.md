---
track: N
prio: 40
type: bug
summary: "A `nonlocal` capture's shared frame cell (pycell_new) is never freed — ~23 B per escaping closure, the only closure shape still leaking now that the bound-fn object is refcounted"
---

# The shared `nonlocal` frame cell has no owner

Split out of [[bug-nilpy-bound-fn-closure-objects-are-never-freed]], which is
fixed: the lifted bound-fn object is now a refcounted block and its private
bindings (`_bind_obj`'s retained object, `_bind_var`'s variant slot,
`_bind_cell`'s private cell) die with it. Every closure shape is flat except
this one.

## Measured (2026-08-07, at the commit that fixed the parent ticket)

```python
def mk():
    c = 0
    def b():
        nonlocal c
        c = c + 1
        return c
    return b

def run(n):
    i = 0
    while i < n:
        f = mk()
        i = i + 1
```

| | 20 000 | 320 000 |
| --- | --- | --- |
| `nonlocal` capture | 1 472 KB | 8 512 KB |
| every other closure shape | 1 088 KB | 1 088 KB (flat) |

~23 B per closure — matching the parent ticket's own independent figure for the
cell, and consistent with `pycell_new`'s `GetMem(16)` plus allocator overhead.

## Why the parent's fix deliberately does not cover it

`pycell_new` allocates the ONE cell a frame and all its nested defs share, and
`PyNestedDefClosureValue` binds its address with the **plain** binder
(`pyboundfn_bind`, `pyparser.inc` ~6477) precisely because the closure does not
own it: the enclosing frame still writes through it, and a second closure over
the same name holds the same address. So the parent's per-slot ownership map
records it as `BK_PLAIN` and the finalizer leaves it alone — freeing it there
would dangle the frame and every sibling closure.

That is correct as far as it goes; the cell simply has no owner at all.

## Shape of a fix

The cell needs its own refcount, not a different binder. It is already a
16-byte heap slot with a known layout, so the cheap route is to make
`pycell_new` allocate a headered refcounted block (`PXXObjAllocRaw*`, as
`pyboundfn_new` now does) and have both the frame's own scope exit and each
closure's finalizer release it — a `BK_CELLREF` ownership kind alongside the
existing four, so the bookkeeping stays in the one place the parent established.

The catch to measure, not assume: the frame's reference must be released on
EVERY exit path from the enclosing function, including an exception unwind, or
this trades a small leak for a dangling read — which is the failure mode the
plain binder exists to avoid.

## Gate

RSS slope on the repro above at 20k and 320k must go flat (the SLOPE is the
evidence, a single run proves nothing), `test/test_nilpy_closure_lifetime.npy`
and `test_nilpy_nonlocal_escaping_closure.npy` stay byte-identical to CPython,
self-host fixedpoint + `tools/gate.sh quick`.
