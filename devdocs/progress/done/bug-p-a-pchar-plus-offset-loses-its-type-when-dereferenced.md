---
track: P
prio: 55
type: bug
blocked-by: []
summary: "`(pc + 2)^` on a PChar yields an INTEGER, not a Char: pxx printed 1717920867 where FPC prints 'c'. `pc^` and `pc[2]` — the two other spellings of the same access — are both right, so only the arithmetic form loses the pointee type. Silent."
status: done
owner: frank1-ACP
---

# `(pc + 2)^` derefs as an integer

- **Track P** (Pascal frontend: the type of a pointer-arithmetic binop).
- Found 2026-08-20 by an FPC differential probe over PChar.

## Repro

```pascal
var ca: array[0..7] of Char; pc: PChar;
begin
  ca := 'abcdefg'#0;
  pc := @ca[0];
  Writeln(pc^, ' ', (pc + 2)^, ' ', pc[2]);
end.
```

```
FPC: a c c
pxx: a 1717920867 c
```

1717920867 is `$66656463` — the four bytes `dcef` read as an integer. So the
deref happened at the right ADDRESS and read the right memory; it read four
bytes instead of one because the node's type is not Char.

## Why it is the arithmetic form specifically

`pc^` and `pc[2]` both keep the pointee type, and `pc[2]` is defined as
`(pc + 2)^`, so the two spellings of one access disagree — the double case
`normalise-dont-special-case.md` describes. `pc + 2` is typed as a plain
pointer (or an integer) by the binop typing, and the `^` then has nothing to go
on and falls back to the machine word.

## Sketch

The binop that adds an integer to a typed pointer should carry the LEFT
operand's pointer type through, which is also what makes the scaling correct for
a wider pointee. Check `PByte`, `PInteger` and a `^TRec` while fixing it — the
same expression on those is the case where a 4-byte read is not merely the wrong
type but the wrong span.

## Resolution — 2026-08-20

`NodePtrElem` in `parser.inc`: the pointee of a pointer-valued expression, seen
through the arithmetic. A bare identifier is the leaf (`Syms[].PtrElemTk`), an
`arr[i]` recurses, and a `+`/`-` binop takes the pointee from whichever operand
carries one. The parenthesised-suffix `^` arm calls it instead of hand-matching
two node shapes and defaulting the rest to Integer.

The default was the whole bug, and it hid because it is correct for a
`^Integer` — the pointer everyone tests with. Measured against FPC, the four
other pointer widths in the probe were all wrong, in both directions:

| | before | FPC |
| --- | --- | --- |
| `(xb + 3)^` (`^Byte`) | 117835012 | 4 |
| `(pc + 2)^` (`PChar`) | 1717920867 | `'c'` |
| `(xs + 1)^` (`^SmallInt`) | 100992003 | 1027 |
| `(x64 + 0)^ = x64^` (`^Int64`) | False | True |
| `(xi + 2)^` (`^Integer`) | 102 | 102 |

The `^Int64` row is the one that reads SHORT rather than long, so "it reads too
much" is not the invariant — "it reads the machine int" is.

`test/test_pointer_arith_deref_keeps_pointee.pas` — 17 assertions across
`^Byte`, `^Integer`, `PChar`, `^SmallInt` and `^Int64`, each against the two
spellings that were already right (`p^`, `p[k]`), plus nested and
subtracted offsets and the plain `(p)^` grouping.

## Gate

`make compiler/pascal26` fixedpoint + `tools/gate.sh quick`.

## Log
- 2026-08-20 — resolved, commit PENDING-COMMIT.
