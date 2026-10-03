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

## 2026-08-07 — baseline re-measured, and the blocking constraint located

Baseline at HEAD (after the bound-fn object was given a lifetime): **1 476 KB
@ 20k → 8 516 KB @ 320k**, ~23 B/closure. Every other closure shape is flat, so
this is the whole remaining closure leak.

The constraint that stops the obvious fix, found by reading `PyPromoteCell`
(pyparser.inc ~14332): the cell is stored in a **plain `tyPointer` local**
(`ps := AllocVar('', tyPointer)`), and a pointer local has **no finalization**.
The frame therefore has no existing hook that could release the cell on the way
out — the compiler's managed-local cleanup is driven by symbol TYPE, and this
symbol is deliberately a raw pointer because `PyMakeCellPtr`/`AN_DEREF` read
through it.

So giving the cell a refcount is not the hard part; giving the FRAME's reference
a release site is. That needs either a new "free at scope exit" list for NilPy
frames, or making the cell slot managed (which changes what every cell read
compiles to). Both must be correct on **every** exit path including an exception
unwind — and a missed release merely leaks (today's behaviour) while a double
release DANGLES, which is strictly worse than the 23 bytes.

Not started for that reason. The suggested `BK_CELLREF` ownership kind from the
original write-up is still right for the CLOSURE half — that half is easy, since
the per-slot ownership map already exists — but it only pays off once the frame
half has a safe release site, because until then the count never reaches zero.

## Fixed 2026-10-03

The frame half got its release site without a new mechanism: the cell is a
refcounted RAW2 block (`pycell_new_owned`), and the FRAME's reference lives in
a hidden class local, the ordinary ARC local every NilPy class value gets. So
it is released at scope exit on exactly the paths any other class local is,
an exception unwind included, and the pointer local the reads go through
stays a plain copy that owns nothing. Every cell read and write is unchanged,
because the payload stays at offset 0. A marker at offset 16 lets the RAW2
finalizer recognise the block, asked after the bound-fn and closure magic.
A variant cell releases its payload when it dies.

The closure half needed no new ownership kind either: a closure binds the
cell through `pyboundfn_bind_obj` (retain, released as BK_OBJ by the existing
finalizer). PXXObjRelease is magic-guarded, so a cell made by the remaining
plain-GetMem users (generator variant arguments) is left alone as before.

Gate, as this ticket set it: RSS over 20k and 320k closures from the repro
above went from 1.2 MB -> 8.2 MB to 648 KB -> 648 KB; a list-valued cell from
5.0 MB -> 70.7 MB to 648 KB -> 648 KB. Under -dPXX_HEAP_DEBUG,
test_nilpy_closure_lifetime matches its .expected and
test_nilpy_nonlocal_escaping_closure (which has no .expected) matches CPython
byte for byte; a HEAP_DEBUG sweep over every NilPy test shows no new
divergence. Regression test:
test/test_nilpy_a_nonlocal_frame_cell_is_freed_with_its_last_owner.npy --
census through the list-valued cell (a scalar cell is a raw block the census
does not count), 28957 live after 5000 passes before, 31 after; a counter
outliving its frame, two closures over one cell, a generator's helper.

NOT verified on the lekkerzeilen demo (no display here); it is the program
where the last ownership change to closure state crashed, so it is the first
thing to run.
