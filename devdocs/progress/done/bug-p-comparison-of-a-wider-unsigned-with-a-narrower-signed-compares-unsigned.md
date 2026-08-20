---
track: A
prio: 75
type: bug
blocked-by: []
summary: "A comparison picked its signed-vs-unsigned domain from the WIDER operand — a C rank rule — so `LongWord(3000000000) > SmallInt(-1)` answered FALSE where FPC answers TRUE. Pascal converts by RANGE: the pair widens to a type that holds both, which is signed unless the unsigned side is 8 bytes. Equal-width pairs were right all along, which is what hid it."
status: done
owner: frank1-ACP
---

# A narrower signed operand lost to a wider unsigned one

- **Track A** (`TypeCompareUnsigned` in `symtab.inc`, read by all six backends;
  the literal normalisation is `parser.inc`).
- Found 2026-08-20, immediately after
  `bug-p-div-of-an-unsigned-dividend-by-a-signed-divisor-divides-unsigned`, by
  asking the obvious next question: `div` reads two operands and got the rule
  wrong — what else reads two operands?

## Repro

```pascal
var c: LongWord; si: SmallInt;
begin
  c := 3000000000; si := -1;
  writeln(c > si);     { FPC: TRUE    pxx: FALSE }
end.
```

`LongWord > ShortInt` and `Word > ShortInt` failed the same way, along with the
`<`, `>=` and `<=` spellings.

## Cause

`TypeCompareUnsigned` implemented "the wider operand determines the domain; at
equal width a signed operand wins". That is C's conversion by RANK. Pascal
converts by RANGE — the pair widens to a type that HOLDS BOTH — and Int64 holds
every LongWord, Word and Byte, so the comparison is signed however wide the
unsigned side is. Under the rank rule `si` sign-extended to $FFFF..FF and
3000000000 lost to it.

The widths had to DIFFER for the bug to appear: the equal-width pairs (`c > i`,
`w > si`, `b > sh`) hit the "signed wins at equal width" arm and were right,
which is why the rule read as correct for so long.

## The QWord carve-out is real, and is FPC's

There is one width where no wider signed type exists. FPC 3.2.2, measured both
ways:

| comparison | FPC | domain |
| --- | --- | --- |
| `QWord(9e18) > Integer(-1)` | FALSE | unsigned |
| `QWord(9e18) > SmallInt(-1)` | FALSE | unsigned |
| `QWord(9e18) > Int64(-1)` | TRUE | **signed** |
| `LongWord(3e9) > Int64(-1)` | TRUE | signed |

So an 8-byte unsigned operand takes the pair unsigned against a NARROWER signed
one, and signed against Int64. And `div` does **not** copy that: `q div i` is
signed in FPC where `q > i` is unsigned. The inconsistency is the oracle's, so
`TypeDivideUnsigned` keeps its own plainer rule and the two are documented as
NOT to be merged — the one case in this pair of fixes where two mechanisms for
one concept is the right answer.

## Fix

`TypeCompareUnsigned` grows a Pascal branch (C's rank rule below it is
untouched, and still carries the two csmith fixes it was tuned for):

```pascal
if TypeSigned(lhs) = TypeSigned(rhs) then Result := not TypeSigned(lhs)
else if not TypeSigned(lhs) then Result := (TypeSize(lhs) = 8) and (TypeSize(rhs) < 8)
else                             Result := (TypeSize(rhs) = 8) and (TypeSize(lhs) < 8);
```

The comparison site's existing literal retag — "a non-negative literal compared
against a **QWord** compares unsigned" — was the 8-byte arm of a rule that
applies at every width, and it is exactly what `div`/`mod` needed too. Both now
call one `NormalizeUnsignedLiteralOperand`, so `q > 10` and `c > 10` stay
unsigned while `c > -1` stays signed.

## Gate

`test/test_compare_mixed_signedness.pas` — 28 assertions, all `fpc -O-
-Mobjfpc` 3.2.2's: the mixed widths that broke, the QWord carve-out both ways,
signed-wider and equal-width pairs that had to stay put, all-unsigned pairs, and
the literal cases in both signs. The pinned binary scores 22/28 on it. Wired
into `make test`; `tools/gate.sh quick` GREEN, self-host fixedpoint
byte-identical, and the gcc C probe still identical (C's rule did not move).
