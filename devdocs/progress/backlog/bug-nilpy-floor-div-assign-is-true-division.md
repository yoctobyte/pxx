---
track: N
prio: 55
type: bug
summary: "`self.n //= v` performs TRUE division — 25 //= 3 gives 8.333… instead of 8. The `//=` token is folded onto the same binop as `/=`"
---

# `//=` is true division, not floor division

- **Type:** bug (NilPy — SILENT WRONG VALUE) — **Track N**
- **Found:** 2026-08-02, while gating
  [[bug-nilpy-augmented-assign-to-a-variant-typed-field-corrupts-it]].
  **Pre-existing** — on a stashed baseline the same program produced an empty
  line (a crash) rather than a number, so that fix improved this shape without
  making it correct.

## Repro

```python
class A:
    def __init__(self, n):
        self.n = n
    def idiv(self, v):
        self.n //= v
        return self.n

print(A(25).idiv(3))     # CPython 8     pxx 8.333333333333334
```

`%=` in the same position is correct, so this is specific to `//=`.

## Cause

The compound-assignment tail in the shared expression parser maps its token set
with a `case` whose ELSE arm is `tkSlash`:

```pascal
tkPlusEq:  ...tkPlus
tkMinusEq: ...tkMinus
tkStarEq:  ...tkStar
else       ...tkSlash
```

so anything that is not `+=`, `-=` or `*=` becomes TRUE division. `/` and `//`
are different operators in Python — `tkSlash` vs `tkDiv` — and NilPy's own
augmented path distinguishes them correctly (`PyAugBinTok`). Only this shared
tail collapses them.

## Fix shape

Give `//=` its own arm mapping to `tkDiv`, and make the ELSE an ERROR rather than
a silent fallthrough to division — the current shape means any future compound
token silently becomes `/=`, which is how this one got here.

Check what `//=` actually lexes to first: if it does not have a distinct token
yet, that is the first half of the fix.

## Gate

A `.npy` diffed against CPython: `//=` and `/=` on an int field and on a plain
local; `%=`; each with int and float operands; and `//` / `/` as plain binops as
controls.
