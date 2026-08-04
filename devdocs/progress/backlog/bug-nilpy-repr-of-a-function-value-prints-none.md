---
track: N
prio: 25
type: bug
---

# `print(f)` on a function value prints None (or nothing) instead of a repr

```python
def mk(n: int):
    def inner(x: int) -> int:
        return x + n
    return inner

g = lambda x: x + 1
f = mk(10)
print(g)     # CPython: <function <lambda> at 0x...>   pxx: (blank line)
print(f)     # CPython: <function mk.<locals>.inner at 0x...>   pxx: None
print(f(1))  # 11 on both — CALLING it is correct
```

The value itself is right — `f(1)` answers 11 and survives containers and
parameters ([[bug-nilpy-returning-a-nested-def-yields-none]] landed that) — so
this is purely the string form. A lifted bound-fn rides as a bare payload under
tag 0 (`pyvar_of_callable` sets VType 0 when the object is not a pyeval
closure), and tag 0 is VT_EMPTY, which every str/print consumer reads as None.

Cosmetic on its own, but it makes a function value indistinguishable from None
in a debug print, which is exactly when you look.

## Shape of a fix

Give a lifted bound-fn a variant tag of its own rather than riding VT_EMPTY —
the tag block after VT_PYCLOSURE_TAG (9) is free — and teach `pystr_of` /
`print` to render tags 8/9/<new> as `<function ...>`. That also fixes the
neighbouring wrongness that `if f:` is False for a function value. Renumbering
is not an option (see the note above the tag block in `defs.inc`), so this
claims the next free code.

Touches `compiler/defs.inc` and `compiler/builtin/pyeval.pas` — a Track A
shared-internals change, so file/hand off accordingly.

## Gate

`make test-nilpy` plus a `.npy` printing and truth-testing a def, a lambda, a
returned nested def and a bound method, diffed against CPython for the truth
tests (the address in a repr obviously cannot match).


## 2026-08-04 — one probe recorded, so the next session does not repeat it

The fix shape above says "the tag block after VT_PYCLOSURE_TAG (9) is free …
this claims the next free code". Before doing that, check the tag that already
exists — and then check why it does not fit:

**`VT_BOUNDMETHOD = 8` is already defined** (`defs.inc`), documented as
"payload = {code, recv} pair pointer (pylib pybound_new)". A lifted bound-fn IS
such a pair, so reusing it looks right and is the first thing anyone will try.

**It does not fit as-is, for two reasons:**

1. `pyvar_of_callable` (pyeval.pas) sets VType **0** for *both* a lifted
   bound-fn and a **bare compiled code address** — the two are not
   distinguished at that point, and only one of them is a pair. Tagging both 8
   would put a code address behind a tag whose consumers dereference it as a
   pair.
2. `pyvar_callv*` **probes for tag 0** to find these values, by the comment on
   `pyvar_of_callable` itself. Retagging without updating those probes moves the
   bug rather than fixing it.

So the work is: distinguish the two shapes at the boxing site (`PXXObjIsBoundPair`
already answers it for the pair case), give the bare-address shape its own tag,
update the `pyvar_callv*` probes, and only then add rendering and truthiness.
That is a Track A shared-internals change touching variant tags — and variant
tags can never be renumbered, so the choice has to be right the first time.

Not attempted here: adding a variant tag late in a long session is exactly the
change whose failure mode (a leak or a wrong clear/retain) the quick gate does
not catch.
