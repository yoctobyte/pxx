---
track: A
prio: 45
type: bug
blocked-by: []
status: backlog
summary: "`not v` on a Variant holding 12 answers False; FPC answers -13 (the bitwise complement). Silent wrong VALUE and wrong TYPE -- pxx applies logical not to every variant regardless of tag, where FPC picks bitwise-vs-logical from the operand. `v shr n` is the loud half of the same gap: `Variant arithmetic: unsupported operator`."
---

# `not` on an integer Variant answers a Boolean

Found 2026-08-23 by the Variant differential family (`fpc 3.2.2 -Mobjfpc -O1`
vs pxx `9074403c0`).

```pascal
var a, c: Variant;
begin
  a := True;  c := not a;  { pxx False    fpc False   ok  }
  a := False; c := not a;  { pxx True     fpc True    ok  }
  a := 12;    c := not a;  { pxx False    fpc -13     WRONG }
  a := 0;     c := not a;  { pxx True     fpc -1      WRONG }
end.
```

**Silent, and wrong twice over**: the value is wrong and so is the TYPE — a
program doing `mask := not flags` on variants gets a Boolean where it expected
an integer, and every downstream use of it is wrong in a way that never mentions
`not`. The boolean rows agreeing is what hides it.

Pascal's `not` is bitwise on an integer and logical on a Boolean; FPC's variant
`not` operator dispatches on the operand's tag. pxx applies the logical form to
every tag.

## The loud half of the same gap

`shr` is not implemented for variants at all:

```
a := 12; c := a shr 1;
  pascal26: error: Variant arithmetic: unsupported operator (string pending)
```

`and`, `or`, `xor`, `shl`, `div`, `mod` and unary `-` all work and all agree
with FPC (measured: 8, 14, 6, 24, 1, 2, -12 for `a=12, b=10`). So it is `shr`
alone, plus `not`'s dispatch — likely one missing arm and one wrong arm in the
same table, which is why they are filed together.

| operator | pxx | fpc |
| --- | --- | --- |
| `a and b` | 8 | 8 |
| `a or b` | 14 | 14 |
| `a xor b` | 6 | 6 |
| `a shl 1` | 24 | 24 |
| `a shr 1` | **REJECT** | 6 |
| `not a` (a=12) | **False** | -13 |
| `-a` | -12 | -12 |
| `a div b` | 1 | 1 |
| `a mod b` | 2 | 2 |

## Where to look

Both implementations, as with every variant-operator defect: `PXXVarBinOp` /
`PXXVarBinOpPas` (`compiler/builtin/`) and x86-64's `EmitVarBinOp`
(`compiler/ir_codegen.inc`). Unary `not` may take a different path from the
binary operators — find it before assuming.

**NilPy must not follow.** Python's `not 12` is `False` (truthiness), which is
exactly what pxx does today — so today's behaviour is CORRECT for NilPy and
wrong for Pascal, which makes this a lowering-seam split (`PyProgramMode` /
which helper is called), not a change of one shared rule. Check what NilPy does
with `~12` (bitwise) separately; it is a different operator.

## Gate

Track A's, plus the nine rows above matching fpc 3.2.2 on x86-64 and one
cross target, and a `.npy` row proving `not 12` still answers `False`.
