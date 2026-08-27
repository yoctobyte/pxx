---
track: N
prio: 65
type: bug
blocked-by: []
summary: "`def __init__(self, items): self.items = items; self.i = 0` typed `self.items` from the `0` after the semicolon — the field pre-pass's right-hand-side span ran to end-of-LINE, not end-of-STATEMENT. A TPyList went into an Int64 field and the first read died with `TypeError: expected a number, got object`."
status: done
---

# A field typed across a semicolon takes the NEXT statement's type

Found 2026-08-27 while fixing
[[bug-n-the-old-style-iteration-protocol-reaches-only-the-for-loop]] — a
one-line `__init__` written in a throwaway repro failed for a reason that had
nothing to do with iteration. **Pre-existing** at
`stable_linux_amd64/default/pinned`.

```python
class C:
    def __init__(self, items): self.items = items; self.i = 0


c = C([1, 2])
print(c.items, c.i)     # CPython [1, 2] 0    pxx TypeError: expected a number, got object
```

## Measured boundary

| shape | pxx |
| --- | --- |
| `self.items = items; self.i = 0` | **fails** |
| `self.i = 0; self.items = items` (reversed) | ok |
| `self.items = items; self.i = "x"` | ok |
| `self.items = items; self.j = items` | ok |
| `self.items = items` (alone) | ok |
| `self.x = a; self.y = 0` where `a` is an `int` | ok |

It is not the semicolon form and not the one-line body: it is the field taking
its type from a token that belongs to the NEXT statement. The rows that "work"
work by luck — the wrong type happened to be compatible.

## Cause and fix

The `self.NAME = expr` pre-pass computed its right-hand side's end with

```pascal
while (k2 < bodyEnd) and not (Tokens[k2].Kind in [tkNewline, tkDedent]) do Inc(k2);
```

`tkSemicolon` was missing, so the expression scanner was handed
`items ; self . i = 0` and answered from the `0`. `PyBlkRhsEndsAt`, three
functions above in the same file, already lists `tkSemicolon` among the
statement terminators — the knowledge was in the file, just not at this scan.

Fixed alongside
[[bug-n-a-field-takes-its-type-from-the-first-token-of-its-right-hand-side]],
which owns the same span: one terminator set, computed once, used by every arm.

## Gate

`test/test_nilpy_field_type_from_whole_rhs.npy` (classes `S` and `S2`), diffed
against CPython.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
