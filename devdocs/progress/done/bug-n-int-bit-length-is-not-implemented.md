---
track: N
prio: 30
type: bug
blocked-by: []
status: done
owner: claude-A-N
---

# `int.bit_length()` is not implemented

- **Type:** bug (missing method — a compile error, so loud) — **Track N**
- **Found:** 2026-08-11, checking the sibling intrinsics for
  [[bug-nilpy-method-chained-on-open-result-fails-to-parse]]. The chain PARSES;
  the method simply does not exist.

```python
print(int("42").bit_length())
print((255).bit_length(), (0).bit_length(), (-8).bit_length())
```

```
pascal26: error: Nil Python: no class declares a method or callable field .bit_length()
```

CPython prints `6` / `8 0 4`. The diagnostic is honest and names the method, so
this is a gap rather than a trap.

## Semantics to match

`n.bit_length()` is the number of bits needed to represent `abs(n)` in binary,
excluding sign and leading zeros — so `(0).bit_length()` is **0**, and negative
values answer the same as their absolute value. Do not implement it as
"position of the highest set bit + 1" without handling 0 separately.

Worth doing in the same pass, since they are the same family and the same
place: `bit_count()` (CPython 3.10+), and `to_bytes`/`from_bytes` already exist
(`PyParseToBytes`) so the intercept pattern is right there.

## Gate

The values above matching CPython via `tools/pydiff.py run`, including 0 and a
negative, plus a promotable-int (bignum) receiver — `(2**70).bit_length()` is
71, and the machine-int path would answer wrongly for it.
`make test-nilpy` + self-host byte-identical.

## 2026-08-11 — FIXED, with `bit_count()` in the same pass as the ticket suggested

### The intercept was generalised rather than copied

The ticket's "the intercept pattern is right there (`PyParseToBytes`)" was
right, but the pattern had a hazard worth removing first: `.to_bytes(` is
claimed at **three** sites — the lvalue member path (`parser.inc` ~5726),
ParseFactor's grouped-suffix stand-down (~9714), and the postfix-chain loop
(~14868) — and each carried its own `LowerCase(...) = 'to_bytes'` literal. A new
int method spelled that way is three edits that must agree, and per
`normalise-dont-special-case` the site that gets missed is the one that stays
broken.

So the name test is now one function, `PyIsIntMethodName`, consulted by all
three, and the parse dispatches through one `PyParseIntMethod`. Adding an int
method is a line in the former plus an arm in the latter. `PyIsToBytesBaseTk` /
`PyIsToBytesSuffixAhead` became `PyIsIntMethodBaseTk(tk, nm)` /
`PyIsIntMethodSuffixAhead`.

That rename carries a real correctness point, not just tidiness: the base test
asks `PyAnyClassDeclares(nm)` with the **actual** method name where it used to
ask for the literal `'to_bytes'`. Hardcoded, a user class declaring
`bit_length` would have had the intrinsic silently shadow its method on a
variant receiver. Covered now by `test_nilpy_to_bytes_user_class_wins.npy`,
which gained a `Register` class whose `bit_length`/`bit_count` still win.

### Arbitrary precision is exact, not narrowed

`pyint_bit_length` / `pyint_bit_count` take a **Variant**, not an `Int64`. An
Int64 parameter would have narrowed `2**70` mod 2^64 and answered confidently
wrong — the trap `pyvar_to_float` already records for `float(2**64)`. A
heap-tier promotable int is detected by its `VT_PROMO_INT64` tag (8193) and read
through `PXXPromoToBase(slot, 2)`, whose digits after the `0b` prefix ARE the
bit length; no shift loop and no base-1e9 arithmetic.

Both are defined on the **magnitude**, so the sign is ignored. Two edges the
ticket's warning points at are handled explicitly: `(0).bit_length()` is **0**,
not "highest set bit + 1"; and `Low(Int64)` has no positive counterpart, so
negating it would overflow — its magnitude is 2^63, giving 64 and a bit_count
of 1.

### Measured against CPython

Every row diffed against the CPython oracle, all matching:

| | |
| --- | --- |
| `int("42").bit_length()` | 6 |
| `(255)`, `(0)`, `(-8)` `.bit_length()` | 8, 0, 4 |
| `(1)`, `(2)`, `(3)` | 1, 2, 2 |
| `(2**70)`, `(2**70-1)`, `(-(2**70))` | **71, 70, 71** |
| `(1 << 200).bit_length()` | **201** |
| via a variable / untyped param / list element | 10, `8 101`, 9 |
| `bit_count`: `(255)`, `(0)`, `(-8)` | 8, 0, 1 |
| `bit_count`: `(2**70)`, `(2**70-1)` | 1, 70 |
| in an expression / a comprehension | 9, `[1, 2, 8]` |

The bignum rows are the ones a machine-int implementation gets wrong, which is
why they are in the test rather than only in this note. `to_bytes` output is
unchanged throughout — same file, same expectations, extended not rewritten.

### Gate
`make compiler/pascal26` (fixedpoint, converged in 1 round) + `tools/gate.sh
quick` GREEN + `make test-nilpy` as the family sweep. **No re-pin needed**: the
`compiler/builtin/pylib.pas` change is purely additive and nothing in `lib/**`
calls the new routines, so the gate's fixedpoint is unaffected — confirmed by
running it rather than assumed.

## Log
- 2026-08-11 — resolved, commit d0141290a.
