---
prio: 50
track: N
type: bug
blocked-by: []
---

# `f(1, b=7)` rejected when the def also has `*rest` / `**kw`

- **Type:** bug (NilPy, **valid CPython refused** — upward compatibility) — **Track N**
- **Found:** 2026-08-09 by a differential sweep of class/scoping/argument
  semantics against CPython.
- **Status:** done

## Measured

```python
def f1(a, b=2):                  print(f1(1, b=7))   # (1, 7)   -- always worked
def f2(a, b=2, *rest):           print(f2(1, b=7))   # REJECTED
def f3(a, b=2, **kw):            print(f3(1, b=7))   # REJECTED
def f4(a, b=2, *rest, **kw):     print(f4(1, b=7))   # REJECTED
```

```
error: Nil Python: f2 got multiple values for parameter 'b'
```

The star parameter is the whole difference, which is what made the message
misleading — it names `b`, and `b` is written exactly once.

## Why it rates 50

`def f(a, b=None, **kwargs)` called as `f(x, b=1)` is an ordinary Python shape —
it is how nearly every wrapper, adapter and options-taking helper is written.
And this is the direction that is not negotiable: a program CPython accepts and
runs is refused. Loud, but loud in a place a real file reaches immediately.

## Cause

To place the packed `*args` container at its parameter index,
`PyPackStarArgs` fills the intervening DEFAULTED slots positionally
(`PyFillDefaultsUpTo`). It filled `b`'s default too, and the user's own `b=7`
then landed on the already-occupied slot, so `PyBindKwArgs` reported a
collision.

## Fix, in two halves — the second only surfaced after the first

1. `PyFillDefaultsUpTo` skips a slot that a MATCHED KEYWORD in the same call
   already binds, advancing past it (the slot is accounted for, by the keyword
   rather than by a default).
2. **Once a slot can be skipped, position no longer implies index.** The filled
   defaults and the packed `*args`/`**kwargs` containers now carry an EXPLICIT
   slot (`ASTIVal = slot + 1`) instead of relying on their place in the chain.
   `f(a=1)` is what proved this: it skips slot 0, and a positional filler for
   slot 1 was then counted as slot 0 and collided all over again.

## Verification

`test/test_nilpy_kwarg_with_star_params.{npy,expected}` (`.expected` from
CPython): all four star/kwargs combinations, keywords binding a middle
parameter, keywords binding the FIRST parameter, a def with two defaulted slots
before the star, and the no-star control.

Deliberately not asserted: `i(1, 2, 3, 4, c=9)` where a positional and a keyword
genuinely hit the same slot. CPython raises TypeError and so does pxx — but at
COMPILE time rather than run time. A difference in WHEN, not in whether; left
alone rather than pinned.

## Adjacent, filed separately
[[bug-nilpy-constructor-with-kwargs-rejects-an-unmatched-keyword]] — the same
sweep found `K(1, b=5, z=6)` refused with "K has no field or constructor
parameter named 'z'" although `__init__` declares `**kw`.

## Log
- 2026-08-09 — resolved, commit f37ae57d6.
