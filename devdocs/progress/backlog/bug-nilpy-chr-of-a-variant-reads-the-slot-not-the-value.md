---
track: N
prio: 65
type: bug
---

# `chr()` of a variant returns the wrong character — the slot is read as an ordinal

```python
xs = [97, 98]
print(chr(xs[0]))     # CPython: a     pxx: X

out = ""
for o in [97, 98]:
    out = out + chr(o)
print(out)            # CPython: ab    pxx: (empty)
```

`ord()` is fine; only `chr()` is affected.

## Measured

| expression | CPython | pxx |
| --- | --- | --- |
| `chr(97)` (literal) | `a` | `a` ✓ |
| `o = 97; chr(o)` (int var) | `a` | `a` ✓ |
| `chr(int(xs[0]))` (explicit unbox) | `a` | `a` ✓ |
| **`chr(xs[0])`** (list element) | `a` | **`X`** |
| **`chr(o)` where `o` is a loop variable** | `a` | **empty** |
| **`chr(o)` where `o` is an unannotated param** | `a` | **empty** |
| **`chr(xs[0] + 1)`** | `b` | **`x`** |
| `ord(xs[0])`, `ord(<param>)`, `ord(<loop var>)` | correct | correct ✓ |

The explicit `chr(int(v))` working is the tell: the value is fine, the unboxing
is missing.

## Cause

`parser.inc`, the shared `Ord`/`Chr` soft-keyword intrinsic. `Ord` has a
special case that routes a non-ordinal operand to pylib:

```pascal
        { Python has no char type: `ord("a")` takes a 1-length STR, which the
          ordinal intrinsic would read as the string's pointer. Route a string
          operand to pylib instead ... }
        if (op = Ord(tkOrd)) and PyExprMode and
           ((IntToTypeKind(ASTTk[CurASTNode]) = tyString) or
            (IntToTypeKind(ASTTk[CurASTNode]) = tyAnsiString)) then
```

`Chr` has no equivalent arm, so a `tyVariant` argument falls through to the
`-tkChr` intrinsic, which reads the 16-byte variant slot as an ordinal — hence a
character derived from the tag/handle rather than from the payload.

Same "the sibling grew a case and this one did not" shape as
[[bug-nilpy-indexing-an-unannotated-str-parameter-segfaults]].

## Fix

Give `Chr` the mirror arm: when `PyExprMode` and the argument is `tyVariant`,
wrap it in `pyvar_to_int` before the intrinsic (that helper already applies
Python's numeric rules and raises TypeError for a non-number). Keep the literal
and int-typed paths untouched so ordinary `chr(65)` stays a single instruction.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` of the table above
against CPython's own output, and a caesar-cipher round trip
(`chr(((ord(c) - 97 + k) % 26) + 97)` over a loop variable) as the end-to-end
case — that is the program this was found in.
