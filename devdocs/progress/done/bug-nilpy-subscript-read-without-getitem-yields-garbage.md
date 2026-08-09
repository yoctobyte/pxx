---
prio: 35
track: N
type: bug
blocked-by: []
---

# A subscript READ on a class with no `__getitem__` yields a silent wrong value

- **Type:** bug (NilPy, **silent wrong answer**) — **Track N**
- **Found:** 2026-08-09 while fixing [[bug-nilpy-delitem-dunder-not-supported]]
- **Owner:** —

```python
class W:
    def __setitem__(self, k, v):
        pass

w = W()
print(w["x"])       # CPython: TypeError: 'W' object is not subscriptable
                    # pxx: a number (raw arithmetic on the instance handle)
```

`parser.inc`'s subscript arm is gated on `FindUMeth(mci, '__getitem__') >= 0`.
A class that declares `__setitem__` or `__delitem__` but not `__getitem__`
therefore falls past it to the generic `AN_INDEX` fallback — pointer arithmetic
on the instance. That arm's own comment already names this failure for the
no-dunder case ("a silent WRONG value (`0` observed), not even a crash"); what
is new is that declaring one of the SIBLING members does not rescue it.

## Why it matters more than it looks

The write-only / delete-only class is exactly the shape that now compiles
further than it used to: `__setitem__` and `__delitem__` both work on such a
class, so a program can be most of the way to working and then read one
subscript and get a plausible integer instead of a TypeError.

CPython's rule is simple and worth matching exactly: no `__getitem__` on the
type → `TypeError: 'X' object is not subscriptable`.

## Shape of the fix

A `PyNoGetitemError` raise, mirroring `PyNoSetitemError` / `PyNoDelitemError`,
reached when the receiver is a user class and no `__getitem__` is found. The
gate has to widen so the class arm is entered at all — today a class with no
`__getitem__` never reaches it — which is a `parser.inc` change and so **Track A
file ownership** (the sole-A guard applies), unlike its `__delitem__` sibling
which stayed in `pyparser.inc`.

Careful not to capture non-class receivers: arrays, pointers, strings and
records all use the same generic fallback legitimately.

## Gate

`.npy` diffed against CPython: a read on a `__setitem__`-only class, on a
`__delitem__`-only class, and on a class with no dunders at all, each a
catchable TypeError; plus controls that array/pointer/string/record indexing and
`__getitem__`-declaring classes are unchanged.

## 2026-08-09 — FIXED (sole-A confirmed)

A getter-less user class now raises `TypeError: 'W' object is not subscriptable`
from a subscript READ, which is what CPython raises.

**At RUN time, not compile time, and that is load-bearing:**
`try: obj[k] / except TypeError:` is ordinary Python and must still COMPILE. The
raiser is a `Int64`-returning function so it can stand in for the whole subscript
EXPRESSION, exactly as `PyIndexTypeError` does for the index expression.

**Only a READ is taken over.** The first cut fired on assignments too and broke
`so["k"] = 1`; the same closing-bracket peek the `__getitem__` arm uses now
decides it, and an assignment target falls through to the write path untouched.

Two traps on the way, both worth recording:

- the arm needed a `PyExprMode` gate. Without it, it fired while parsing the
  PASCAL sources of pylib itself, and every `.npy` failed to compile with an
  error 6000 lines into a builtin unit — nothing pointing at the change.
- the new pylib raiser's declaration was inserted immediately ABOVE its own
  body rather than into the unit's top block, giving two consecutive function
  headers. Same landmine recorded earlier that day for a different helper: put
  a new declaration in the TOP block or not at all.

**Found while fixing, filed separately:** `obj[k] = v` does NOT compile when the
class has `__setitem__` but no `__getitem__` — pinned does not compile it either.
The write path lives INSIDE the getter-gated arm, so the gate asks about the
wrong member. See
`bug-nilpy-setitem-without-getitem-write-does-not-compile`, which proposes
collapsing the gate to "declares either" with each half checking what it needs.
