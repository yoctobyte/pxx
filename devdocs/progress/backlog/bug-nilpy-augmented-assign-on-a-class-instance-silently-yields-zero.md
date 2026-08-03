---
track: N
prio: 45
type: bug
summary: "`obj += n` on a class instance silently produces 0 — neither __iadd__ nor the __add__ fallback is dispatched, and nothing raises"
---

# `obj += n` on a class instance silently yields 0

- **Type:** bug (NilPy, silent wrong answer) — **Track N**
- **Found:** 2026-08-03, by running the reproducer in
  [[feature-nilpy-arithmetic-dunders-full-protocol]] and finding that ticket's
  subject already works. This is the part that does not.

## Measured

```python
class C:
    def __init__(self, v: int):
        self.v = v

    def __add__(self, o):
        return C(self.v + o)

    def __iadd__(self, o):
        return C(self.v + o)


d = C(1)
d += 5
print(d.v)          # CPython: 6      pxx: 0
```

`0`, not an error. Identical with **only** `__add__` declared (CPython falls
back to `__add__` and rebinds the name, giving 6; pxx still gives 0), so this
is not specifically an `__iadd__` gap — the augmented-assignment path on a
class-typed target does not reach either dunder, and whatever it does produce
leaves the target holding zero.

## Why this is filed apart from its parent

`feature-nilpy-arithmetic-dunders-full-protocol` is a 195-line phase-2 feature
ticket, and the rest of it has since landed: `__add__`, `__sub__`, `__mul__`,
`__truediv__`, `__floordiv__`, `__mod__`, `__pow__`, the mixed-type form
(`c + 3`) and the reflected form (`3 + c`) were all measured correct against
CPython in the same pass. Leaving a **silent wrong answer** as one unmarked
line inside a mostly-done feature ticket is how it stays invisible; the
severity here is not "feature incomplete", it is "a normal Python idiom
computes 0 and says nothing".

The failure direction is the bad one — a counter or accumulator built with
`+=` on an instance reads as zero rather than failing, so the program produces
plausible wrong output with no diagnostic.

## Fix direction

Not investigated. The starting point is NilPy's augmented-assignment lowering
(`PyAugBinTok` and the two augmented-assign sites in `pyparser.inc`, which
build an `AN_BINOP` from the target and the operand): a `tyClass` target
presumably falls into the numeric path and the binop yields a handle/zero
rather than dispatching. Python's own rule is `__iadd__` if declared, else
`__add__` then rebind, so both need to route through the same dispatch the
plain `a + b` expression path already uses correctly.

## Gate

A `.npy` diffed against CPython: `+=` with `__iadd__` declared, with only
`__add__` declared, and the same for `-=`/`*=`/`/=`/`//=`/`%=`/`**=`; plus a
class with neither, which must RAISE rather than answer 0; and the existing
plain-binop dunder cases still green.
