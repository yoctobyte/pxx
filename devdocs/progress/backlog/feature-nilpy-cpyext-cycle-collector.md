---
track: N
prio: 30
type: feature
blocked-by: []
status: backlog
---

# cpyext: a cycle collector for the extension object model

`lib/cpyext/src/pyruntime.c` is plain refcounting, so it leaks reference
CYCLES. M5b made that concrete rather than theoretical: Cython's function
object owns its inner `PyCFunction`, which holds `self` pointing back at the
function object. Real CPython has the identical cycle and reclaims it with its
collector — which is exactly why `CyFunction` carries `Py_TPFLAGS_HAVE_GC` and
a `Py_tp_traverse` slot.

Today that costs nothing observable: module-level function objects live for the
process. It stops being free at M5c, where a `cdef class` allocates instances
in a loop.

## Why this is small, specifically

A cycle collector needs **no root finding** — the property that separates it
from the tracing GC `devdocs/developer/garbage-collection-thoughts.md` rejected
on bare-metal grounds. CPython's trial deletion copies each refcount, traverses
the tracked set subtracting INTERNAL references, and whatever still has count
left is referenced from outside. The stack is never scanned, because a stack
reference already shows up as leftover refcount. No stack maps, no safepoints.

The expensive half of any collector is knowing an object's outgoing references,
and here **the extension hands it to us**: every heap type Cython builds
carries `Py_tp_traverse` and `Py_tp_clear` in its slot table.
`PyType_FromMetaclass` already stores them and `PyType_GetSlot` already returns
them — they are simply never called. `Py_VISIT` already expands correctly.

## The work

1. `PyObject_GC_Track`/`GC_UnTrack` currently no-op. Make them maintain a list
   of tracked instances (allocation already goes through
   `_PyObject_NewFromType`, so there is one place to hook).
2. A scratch refcount field for the trial-deletion pass.
3. The pass itself: subtract internal references via each object's
   `Py_tp_traverse`, mark what survives (plus everything reachable from it) as
   live, call `Py_tp_clear` on the rest.
4. Trigger: an allocation counter, not a timer — there is no idle here.

## Gate

`make test-nilpy` green + self-host byte-identical. The real check is
differential: the same generated C under real CPython 3.12 must agree, and
`test/test_cpyext_cython.npy`'s existing eighteen assertions must not move.
Add an RSS assertion over a loop that builds and drops cyclic objects — a
collector that never runs and a collector that works are indistinguishable
without one.

## Notes

- Prio is low on purpose. Nothing leaks observably until M5c allocates
  instances in a loop; this is filed so the M5c session finds it already
  scoped rather than rediscovering it.
- This is the cpyext runtime ONLY — a separate object model from NilPy's own,
  never routed through pxx's ARC (recorded since M1). The NilPy-side question
  is [[feature-nilpy-cycle-collector]] and has a different, larger shape.
- Sits in the slot `garbage-collection-thoughts.md` point 4 reserved:
  "cycle collection — the one thing ARC genuinely cannot do", a collector
  ALONGSIDE refcounting, not wholesale GC.
