---
track: N
prio: 45
type: bug
blocked-by: []
resolved: PENDING-COMMIT
summary: "`k = h` over `def h(*a)` then `k(1, 2, 3)` handed the body three loose Variants where its compiled signature declares ONE TPyList: len(a) answered 1, and richer bodies segfaulted. The star position now rides the {code, recv} pair (pybound_new_star) and the runtime bridge packs."
---

# A variadic def reached through a function VALUE

```python
def h(*a):
    return len(a)

k = h
print(k(1, 2, 3))        # CPython 3      pxx 1     (richer bodies: SIGSEGV)
```

Measured 2026-08-15 during a CPython differential sweep.

## Root cause

Packing surplus arguments into a `*args` callee's single `TPyList` parameter is
work the **call site** does — `PyPackStarArgs`, at a written call. A call
through a function value has no call site to do it in: the arity is only known
at run time, and the value carried nothing that even said the callee collects.
So `pybound_callv3` dispatched through `function(const a0, a1, a2: Variant)`
into a body whose real signature is `function(l: TPyList)`. The first Variant
was read as the list pointer — `len` of a boxed 1 is 1, and anything that
dereferenced it faulted.

Three representations of a callable, and all three were wrong in their own way:

| shape | what it built | before |
| --- | --- | --- |
| `k = h` (module def) | `pybound_new` pair | loose args |
| `c.take` (bound method) | `pybound_new` pair, via RTTI | loose args |
| `return wrapper` (nested def, nothing to capture) | a bare `AN_PROCADDR` | loose args, and no place to record a star at all |

The last is the decorator shape, which is why this is not an exotic case:
`def wrapper(*args)` returned from a decorator is the single commonest variadic
in Python.

## The fix

`pybound_new_star(code, recv, isFunc, starIdx)` — the pair plus the callee's OWN
star position (Self excluded). `pybound_new` is now a call to it with -1, so
nothing else moved. `PyBoundCallStar` does at run time what `PyPackStarArgs`
does at compile time: everything from `starIdx` on becomes a `TPyList`, marked
as a TUPLE (unmarked, `print(args)` shows brackets and `type(args).__name__`
answers `list`), then dispatches through a signature family that declares the
fixed Variants and the list — function/procedure × receiver/no-receiver ×
star position 0..3.

Emitted from three places: `PyMakeFuncValueFor` and `PyMakeBoundMethod`
(the latter converting from signature space, Self at 0), and pylib's own
attribute-read path, where the index is already in the RTTI meth Flags word.
The bare-address arm in `ParseFactor` now routes a variadic def through
`PyMakeFuncValueFor` instead, since an address cannot carry the star.

## What is still open

- `lambda *a: ...` lifts through the OTHER callable representation
  (`pyboundfn_*`, a word-based bridge in pyeval) and still raises
  `TypeError: <lambda>() takes 1 positional argument but 2 were given` — loud,
  not silent, and its bridge already passes machine words, so the packing
  there is a smaller change than this one was.
  `lambda **kw:` does not compile at all.
- `**kwargs` through a function value is untouched: the bridge packs the star
  list only.
- Star position > 3 raises rather than packing (the dispatcher's arity limit,
  the same one `pybound_callv4` already has).
- `f(*xs)` INTO a variadic callee is a separate refusal —
  [[bug-nilpy-star-unpack-into-a-star-args-callee]] — and it is what still
  blocks the full decorator idiom (`return fn(*args)`).

## Gate

`make compiler/pascal26` + `tools/gate.sh quick` GREEN; pinned v332 (pylib is
a compiled program's runtime).
`test/test_nilpy_star_args_as_a_function_value.npy`, byte-identical to CPython:
arity 0..3 through a value, the tuple the body sees, fixed parameters before
the star, an explicit `-> None` procedure, a bound method (receiver kept), a
nested def returned as a value, and dispatch out of a dict.
