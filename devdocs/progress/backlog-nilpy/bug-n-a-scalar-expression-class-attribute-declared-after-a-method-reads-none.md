---
track: N
prio: 45
type: bug
blocked-by: []
summary: "A class attribute whose initialiser is a PARENTHESISED or compound SCALAR expression (`P = (1 + 2)`, `P = 1 + 2`) reads `None` through `self` from a method declared EARLIER in the class body than the attribute — CPython gives `3`. Same compile-order root cause as the container case (bug-n-a-container-class-attribute-...-through-self, fixed 2026-09-13) and a DIFFERENT population: that one reads EMPTY and is fixed by typing the field tyClass in the member pre-pass; this one reads None and is NOT, because the fix there is deliberately restricted to tyClass. Taking PyInferExprType's scalar answer here (tyInt64 for `(1 + 2)`) SEGFAULTS — the field narrows but the store path still writes the wide value — so the store path is the thing to fix, not the typing. Reading the same attribute through the CLASS is correct, and declaring it ABOVE the reader is correct."
---

# A scalar-expression class attribute declared after a method reads None through self

## Measured, 2026-09-13 (frankZ) — at HEAD and under pin v408, identically

```python
class Below:
    def r(self):
        return self.P
    P = (1 + 2)

class Above:
    P = (1 + 2)
    def r(self):
        return self.P

class BelowNoParen:
    def r(self):
        return self.P
    P = 1 + 2
```

| | CPython | pxx |
| --- | --- | --- |
| `Below().r()` | `3` | `None` |
| `Above().r()` | `3` | `3` — correct |
| `BelowNoParen().r()` | `3` | `None` |
| `Below.P`, `Above.P` | `3` `3` | `3` `3` — correct |

The parentheses are not the discriminator: `P = 1 + 2` fails identically. What
matters is that the initialiser is an EXPRESSION rather than a single literal
token, so it misses the pre-pass's constant branch (which requires one literal
token followed by end-of-line) and lands in the expression branch, where the
field is recorded as a variant and only retyped later by PyEmitClassAttrExpr —
after any method above it has already been compiled against the variant.

## Why the container fix does not cover this, and must not be widened to

`bug-n-a-container-class-attribute-...` was fixed by asking PyInferExprType in
the member pre-pass and recording tyClass when the answer is tyClass AND the
container's rec can be resolved. Both halves of that restriction were measured:

- **Taking the inference's word for a SCALAR SEGFAULTS.** `(1 + 2)` infers
  tyInt64; typing the field that way narrows the slot while the store path still
  writes the wide value. The pinned compiler merely read None. A crash is worse
  than a wrong value, so the container fix explicitly refuses to widen here.
- tyClass with REC_NONE also segfaulted, on `self.L[0]`, where the variant it
  replaced raised a clean `TypeError: object is not subscriptable`.

So **the fix for this ticket is in the STORE path, not in the typing.** Making
the pre-pass smarter is the move that looks obvious and is measured to crash.

## The instrument, reusable

A field read by TWO methods, one above the declaration and one below, in one
program: before the container fix, `TwoReaders.early()` returned empty and
`late()` returned `[5, 6]` for the same field `C`. One field, two answers, by
method compile order — that is the proof the typing is per-method and not a
property of the field, and it is sharper than any single arrangement.
