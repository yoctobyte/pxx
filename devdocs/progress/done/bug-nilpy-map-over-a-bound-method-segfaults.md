---
track: N
prio: 50
type: bug
blocked-by: []
summary: "map(obj.method, xs) SEGFAULTS — a bound method is one of the four callable representations PyCallKey1 claims to handle, and it is the one that crashes. Pre-existing: measured identical on the eager map (pinned v263) and the lazy one, so laziness neither caused nor fixed it. list(map(f, xs)) with a def, a lambda or a builtin all work."
status: done
owner: claude-AN
---

# `map(obj.method, xs)` segfaults

- **Type:** bug (NilPy) — **Track N**
- **Found:** 2026-08-12, writing the acceptance test for
  [[feature-nilpy-lazy-iterator-objects]]. Not caused by it.

## Repro

```python
class Box:
    def __init__(self, k):
        self.k = k

    def scale(self, x):
        return x * self.k


b = Box(3)
print(list(map(b.scale, [1, 2])))     # CPython: [3, 6]
```

`SIGSEGV` (and `SIGILL` for the inline `map(Box(3).scale, ...)` spelling).

## It is PRE-EXISTING, measured

The control removes the variable rather than renaming it: the same file built
with the **pinned** binary (v263, whose `map` is still the eager list) crashes
identically. So this is the callable dispatch, not the cursor.

| callable passed to `map` | result |
| --- | --- |
| a plain `def` | works |
| a `lambda` (an interpreted pyeval source closure) | works |
| a builtin (`str`) | works |
| **a bound method (`obj.method`)** | **SIGSEGV, both eager and lazy** |

Three of the four representations `PyCallKey1` enumerates are fine; the
bound-pair arm is the one that faults
([[project_nilpy_callable_has_three_representations]]).

## Where to look

`PyCallKey1` (pyeval) branches on `PXXObjIsBoundPair(key)` first and calls
`m1(recv, a0)`. `sorted(key=obj.method)` goes through the same entry, so
whatever is wrong is likely visible there too — worth checking whether that
spelling crashes as well, since it would say whether the fault is in the
dispatch or in how `map`'s arm BUILDS the key from `obj.method`
(`PyGetOrMakeCallableWrapper` vs the bound-method value path).

The acceptance test `test/test_nilpy_lazy_map_filter.npy` covers the other
three shapes and carries a comment pointing here for the fourth; add the row
back when this is fixed.

## 2026-08-13 — FIXED. Three sites, one concept

The ticket's own suggestion — "check whether `sorted(key=obj.method)` crashes
too, since that says whether the fault is the dispatch or how map BUILDS the
key" — was the right first measurement. It does not crash: it raised a
TypeError. That split the bug in two, and a third fell out of the test.

**1. The refusal was obsolete.** `pyvar_callable_ptr` (the coercion every
variant argument to a Pointer parameter goes through) *raised* for a bound
method: "carries a code address only, and a BOUND METHOD also needs its
receiver". True of the bare code address, false of the value it actually has —
the variant's payload is pybound_new's `{code, recv}` PAIR, and PyCallKey1's
FIRST test is `PXXObjIsBoundPair` on exactly that pointer. Every consumer of a
`key: Pointer` parameter here dispatches through PyCallKey1 (sorted/min/max
directly, map/filter via PyIterCallHook), so handing over the pair is what they
want. `sorted(xs, key=obj.method)` works with the refusal removed.

**2. map/filter never coerced at all — that is the segfault.** Their intercepts
build the call by hand, so the generic Pointer-parameter coercion never ran and
the raw VARIANT landed in `key: Pointer`: the TAG word (8) became the code
address, and the call jumped to 8. `PyMakeCallablePtrArg` now wraps a variant
callable argument at both intercepts.

**3. A method read as a VALUE off a VARIANT receiver raised AttributeError.**
Found by the test's last row (`[list(map(x.scale, ...)) for x in boxes]`, where
the comprehension variable is a variant) and confirmed pre-existing on the
pinned binary. CALLING it worked, because the frontend resolves the call; only
the value form reached `pydynattr_get_v`, which knew about fields and dynamic
attributes but not methods. It now binds one via `pybound_new` off the RTTI
method table (`PyFindMethByName`, which `PyFindDunder` was a duplicate of and
now calls). Safe by construction: a method whose name is read as a value is
already normalised to the all-variant ABI by `PyMethodUsedAsValue`, which keys
on this exact spelling.

### Found while sweeping, filed, not fixed here

[[bug-nilpy-min-max-with-a-key-held-in-a-variable-picks-the-numeric-overload]] —
`min(xs, key=f)` with the key in a VARIABLE picks the two-argument numeric
overload and raises "expected a number, got object". Not bound-method specific
(a plain def in a variable fails identically) and identical on the pinned
binary, so it is overload SELECTION rather than this ticket's dispatch.

### Gate

`test/test_nilpy_map_over_a_bound_method.npy` + `.expected` from CPython, wired
into `make test-nilpy`: all four callable representations through `map`, the
inline `Box(4).scale` spelling that used to SIGILL, a bound method through
`filter` and `sorted`, a chained `sum(map(..., filter(...)))`, the method held
in a name, and two instances mapped from one call site (which is what proves the
RECEIVER travels). The row that this ticket removed from
`test_nilpy_lazy_map_filter.npy` is back, so the four representations are
visible together there too. `make test-nilpy` green, `gate.sh quick` GREEN.

## Log
- 2026-08-13 — resolved, commit cf5788933.
