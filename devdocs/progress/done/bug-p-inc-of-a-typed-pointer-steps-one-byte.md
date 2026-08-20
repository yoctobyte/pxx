---
track: P
prio: 80
type: bug
blocked-by: []
summary: "`Inc(p)` on a typed pointer stepped ONE BYTE instead of SizeOf(element), and `Dec(p)` one byte backwards -- silently, so a pointer walk read from the wrong offset and returned a plausible garbage number. `Inc(p, 1)`, `Inc(p, 2)`, `p + 1`, `p[k]` and `(p+k)^` were all correct."
status: done
owner: frank1-ACP
---

# `Inc(p)` on a typed pointer steps one byte

- **Track P** (`compiler/parser.inc`, the `Inc`/`Dec` intrinsic).
- Found 2026-08-20 by an FPC differential probe over pointers.

## The measurement

`fpc -O- -Mobjfpc` 3.2.2 vs pxx at `fe8a34230`. `ar` is
`array[0..7] of Integer` filled with `i * 3`; `p: ^Integer := @ar[0]`.

| expression | FPC | pxx |
| --- | --- | --- |
| `Inc(p)` byte step | 4 | **1** |
| `Inc(p)` then `p^` | 3 | **50331648** |
| `Inc(q)` on `^Int64` | 8 | **1** |
| `Inc(r)` on `^SmallInt` | 2 | **1** |
| `Inc(pr)` on `^TRec` (16 bytes) | 16 | **1** |
| `Dec(p)` | -4 | **-1** |
| `Inc(p, 1)` | 4 | 4 |
| `Inc(p, 2)` | 8 | 8 |
| `p + 1` | 4 | 4 |
| `p[2]`, `(p + 3)^` | correct | correct |

50331648 is `$03000000` — the value one byte into the array, read as an
Integer. Nothing crashed; the walk simply returned a number that looks like a
number.

## Root cause

`Inc(x[, step])` lowers to `x := x + step`. The step node for the **implicit**
1 was allocated without a type tag:

```pascal
stepsNode := AllocNode(AN_INT_LIT);
ASTIVal[stepsNode] := 1;
```

so it read as `tyUnknown`, and the pointer-arithmetic scaling — which keys on
the right operand being an ordinal — declined to scale it. Write the `1`
yourself and it is typed by `ParseExpr`, which is why `Inc(p, 1)` was right and
`Inc(p)` was not: the same step, spelled two ways, through two paths.
`devdocs/dev/normalise-dont-special-case.md` is the note; the fix is the one
missing `ASTTk[stepsNode] := Ord(tyInteger)`, so both spellings now go through
one path.

Dec shares that node and was wrong for exactly the same reason.

## Why it stayed hidden

`Inc(p)` on a pointer is the one shape none of the existing tests used, and the
symptom is a plausible integer rather than a crash — `devdocs/dev/debugging-
playbook.md`'s "the expensive bugs do not crash, they produce a plausible wrong
value far from the cause". It also cannot affect the compiler's own self-host
(the compiler indexes arrays rather than walking pointers), so the fixedpoint
gate had no opinion about it.

## Test

`test/test_typed_pointer_inc_dec.pas`, 34 FPC-verified rows: the byte step and
the value for `^Integer`, `^Int64`, `^SmallInt`, `^Byte`, `^Double` and a
16-byte `^TRec`; `Dec` back down to the base; every spelling that already
worked (`Inc(p,1)`, `Inc(p,2)`, `Dec(p,3)`, `Inc(p,0)`, `p + 1`, `p[k]`,
`(p+k)^`); ordinary integer `Inc`/`Dec` unchanged; and a full eight-element
walk summing through `Inc(p)`. The pinned binary scores 18/34.

## Gate

`make compiler/pascal26` fixedpoint converged after 1 round; `tools/gate.sh
quick` GREEN.
