---
track: A
prio: 40
type: bug
blocked-by: []
summary: "`C(**d)` and `C(*lst)` on a class with an ordinary `__init__` fail with `expected expression` — on the PINNED compiler too, so this is not a regression. The ctor path in pyparser.inc:45097 builds its own AN_ARG chain and never consults the star-forwarding branch that plain calls use. Routing it there needs the receiver prepended, which PyStarForwardCall's signature does not take."
---

# A `*`/`**` argument in a NilPy constructor call does not parse

- **Type:** bug (parser) — **Track A** (`compiler/pyparser.inc` ctor path).
- **Filed by:** opus5-frank1, 2026-08-26, while closing
  [[bug-a-nilpy-double-star-in-a-mixed-argument-list]], whose Gate section names
  `C(**d)` as a case to keep green. Measured: it was never green.

## Repro

```python
class C:
    def __init__(self, a=1, b=2, c=3):
        self.t = a + b * 10 + c * 100

d = {"b": 5}
print(C(**d).t)
```

| compiler | result |
| --- | --- |
| pinned (`stable_linux_amd64/default/pinned`) | `pascal26:5: error: expected expression` |
| HEAD `cd5d54964` | same |
| CPython 3 | `351` |

`C(7, **d)` → 357 and `C(*[7, 8], **{"c": 4})` → 487 in CPython; both are the
same error in pxx. **Not a regression** — identical before and after the mixed
argument-list fix, which is why it is its own ticket rather than a follow-up.

## Why it is not a routing change

Plain calls take the branch at `pyparser.inc` ≈45340, which now hands the whole
argument list to `PyStarMixedForwardCall` and gets back a
`PyStarForwardCall(procIdx, list, dict)` — a run-time dispatch on `len(args)`
over the arities `__init__` accepts.

The ctor path (`pyparser.inc:45097`) is a separate loop: it parses expressions
into its own `AN_ARG` chain, then allocates the object and calls `__init__` with
the instance prepended as `self`. `PyStarForwardCall` has no receiver parameter,
so the forwarding lowering cannot be reused as-is — every arm of its arity
dispatch would need the extra leading argument threaded through.

So the work is either (a) give `PyStarForwardCall` an optional receiver node
that every arm prepends, and let the ctor path call it like any other, or
(b) allocate the instance into a temp first and route the `__init__` call
through the ordinary named-callee path, where the star branch already lives.
(b) is the `normalise-dont-special-case.md` move and is probably smaller, but it
changes when the object is allocated relative to argument evaluation — which is
observable, so it needs its own CPython-oracled rows.

Do not bolt a third star parser onto the ctor loop. The ticket above removed two.

## Gate

`make compiler/pascal26`, then a `.npy` diffed against CPython covering
`C(**d)`, `C(7, **d)`, `C(*lst)`, `C(*lst, **d)`, argument evaluation order
relative to allocation, and a class whose `__init__` has no defaults, plus the
existing `test_nilpy_ctor_kwargs` / `test_nilpy_ctor_star_and_kwargs` staying
green. Then `tools/gate.sh quick`.
