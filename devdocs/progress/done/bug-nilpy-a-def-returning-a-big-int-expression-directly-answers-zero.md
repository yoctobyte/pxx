---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`def f(): return 2 ** 70` answers 0 — as does returning the equivalent literal, or `2 ** n`. Assigning to a local first and returning THAT is correct, and so is returning an expression over a big-int PARAMETER, so it is the return expression's own type inference narrowing an arbitrary-precision value to a machine int"
status: done
owner: claude-AN
---

# A def returning a big-int EXPRESSION directly answers zero

- **Type:** bug (silent wrong value) — **Track N**
- **Found:** 2026-08-12, differential bug hunting against CPython.
- **Sibling:** [[bug-nilpy-class-field-and-recursive-return-narrow-an-arbitrary-precision-int]]
  (done) fixed the class-field and recursive-return arms of the same family.
  This is the plain direct-return arm, still open.

```python
def f():
    return 2 ** 70

print(f())        # pxx: 0            CPython: 1180591620717411303424
print(f() + 1)    # pxx: 1            CPython: 1180591620717411303425
print(f() * f())  # pxx: 0            CPython: 1393796574908163946345982392040522594123776
```

Zero, and then arithmetic continuing from zero — nothing raised, nothing
warned. NilPy ints are arbitrary precision everywhere else, which is what makes
this read as data rather than as overflow.

## Boundary — measured

| def body | result |
| --- | --- |
| `return 2 ** 70` | **0** |
| `return 1180591620717411303424` (the literal) | **0** |
| `return 2 ** n` for `n = 70` | **0** |
| `x = 2 ** 70; return x` | correct |
| `def c(n): return n * n` called with `2 ** 35` | correct |
| the same expression at MODULE level, not in a def | correct |

So the value and the arithmetic are fine; the local-binding route is fine; a
big value arriving through a PARAMETER is fine. It is specifically the return
type inferred from the expression itself.

## Likely cause

`PyInferDefRetType` types `2 ** 70` from its token shape as a machine int
(`tyInt64`), the frame gets a 64-bit Result slot, and the promo value is
truncated into it — 2**70 mod 2**64 is 0, which is exactly the printed answer,
and the literal row confirms it (that literal is also 0 mod 2**64). The
local-binding route works because `PyNoteLocalType` widens the local to
`tyPromoInt64`/variant first and the return then follows the local's type.

The fix is on the same fault line the sibling ticket closed: the return-type
inference must recognise a value that cannot fit a machine int — a `**` whose
result exceeds 63 bits, and an integer literal that does — and answer the promo
type, exactly as the local path already does. Check `PyMethodRetType` in the
same change: the method spelling of this def is where the sibling's ABI-mismatch
warning lives, and both passes have to agree.

## Gate

A `.npy` diffed against CPython: every row of the table above, the method
spelling of the same body, a return inside a branch, `f() + 1` and `f() * f()`
so a zero cannot pass as a plausible total, plus the existing big-int tests
still green.

## Log
- 2026-08-12 — resolved, commit PENDING-COMMIT.
