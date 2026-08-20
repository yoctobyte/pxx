---
track: P
prio: 55
type: bug
blocked-by: []
summary: "`(pc + 2)^` on a PChar yields an INTEGER, not a Char: pxx printed 1717920867 where FPC prints 'c'. `pc^` and `pc[2]` — the two other spellings of the same access — are both right, so only the arithmetic form loses the pointee type. Silent."
status: backlog
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
