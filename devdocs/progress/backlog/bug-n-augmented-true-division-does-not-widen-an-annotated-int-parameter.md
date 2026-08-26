---
track: N
prio: 62
type: bug
blocked-by: []
summary: "`def f(x: int): x /= 2; print(x)` prints 4612811918334230528 — the double's bit pattern stored in the Int64 parameter slot. PyNoteLocalType DOES note the float (PXXDBG=n.locals shows tk=19), but a PARAMETER's symbol keeps its declared type, so the note is dropped. No return is involved: the plain print is already wrong."
---

# `x /= 2` on an annotated int parameter keeps the Int64 slot

- **Type:** bug (Track N — Nil Python frontend) — silent wrong value.
- **Filed:** 2026-08-26 by frank1-N-truediv, split out of
  [[bug-n-inferred-return-type-of-true-division-is-int]]. That ticket's fix made
  the def's registered RETURN type correct for this shape; the stored VALUE is
  still wrong, for a reason with nothing to do with return-type inference.

## Repro

```python
def a3(x: int):
    x /= 2
    return x
def a5(x: int):
    x /= 2
    print(x)                    # CPython 2.5   pxx 4612811918334230528
    return 0
def a4(x: int):                 # the control: a LOCAL copy is correct
    y = x
    y /= 2
    return y

print(a3(5))                    # CPython 2.5   pxx 4.612811918334231e+18
a5(5)
print(a4(5))                    # 2.5 both
```

`a5` is the one that localises it: no return type in play, and the value printed
inside the function is already the double's raw bits.

## Cause — measured, not reasoned

```
$ PXXDBG=n.locals ./compiler/pascal26 r7.npy r7
PXXDBG n.locals a3 x tk=19 rec=-1 | sym=437 symtk=13 symrec=0 kind=2
PXXDBG n.locals a4 y tk=22 rec=-1 | sym=<none>
PXXDBG n.locals a5 x tk=19 rec=-1 | sym=437 symtk=13 symrec=0 kind=2
```

The `/=` handler already does the right thing — `PyNoteLocalType` records the
float (`tk=19`) exactly as its comment says it must
(`feature-nilpy-power-operator-and-divmod`). But `kind=2` is a **parameter**,
and the parameter's symbol keeps its declared `symtk=13` (Int64). The note is
recorded and then ignored, so the double is written into the incoming ABI slot.

`a4` works because `y` is a real local with no declared type to defend.

## Why it is not a one-line fix

The parameter's type IS the calling convention: widening `x` to a Double would
change what the caller must push. Python has no typed slots — a parameter that
is REBOUND is simply a local from that point on — so the faithful lowering is to
introduce a shadow local when a parameter is rebound to an incompatible type,
and rewrite the body's references from the rebind onward.

Narrower alternatives, in increasing order of honesty:

1. Reject it: error "cannot rebind an annotated int parameter to a float". Cheap
   and loud, but rejects code CPython runs, which is the one direction the N
   rule forbids.
2. Coerce: store `Trunc(x / 2)`. Wrong value, silently — strictly worse than
   today, because today at least the bits survive.
3. Shadow local. The real fix.

The same question applies to any rebind that changes a parameter's type
(`x = "s"` on `x: int`), so solve it once for the general case rather than for
`/=`.

## Gate

A `.npy` diffed against CPython: `/=` on an annotated int parameter, read back
by `print` AND by `return`; the same on an unannotated parameter and on a plain
local (both must stay correct); `//=` and `%=` on an annotated int parameter
(must stay integer); and a parameter rebound to a string.
