---
prio: 55
track: P
---

# `QWord div` / `mod` by a literal >= 2^63 divides SIGNED and returns a wrong value

- **Type:** bug (silent wrong value) — **Track P** (Pascal frontend; the fix is
  one predicate in `compiler/pasparser_expr.inc`).
- **Status:** OPEN — found 2026-08-27 by frankA while building the div/mod
  differential for [[feature-opt-o3-register-pressure]]'s `-O2` promotion.
- **Not an optimization bug:** wrong at **`-O0`** and identical at `-O0/-O1/-O2/-O3`,
  so it predates every `-O3` pass and does not block the promotion.

## Repro

```pascal
program q;
var a: QWord;
begin
  a := 18446744073709551615;
  Writeln(a div 9223372036854775808);   { pxx: 0   fpc: 1 }
  Writeln(a mod 9223372036854775808);   { pxx: -1  fpc: 9223372036854775807 }
end.
```

`mod` prints a **QWord as `-1`**, which is the tell that the whole operation
went signed.

## Boundary — measured, not guessed

| shape | result |
| --- | --- |
| `a div b` where `b: QWord := 9223372036854775808` | **correct** (1) |
| `a div 9223372036854775808` (literal) | **wrong** (0) |
| `a div 4611686018427387904` (2^62, fits Int64) | correct (3) |
| `a > / >= / < / = 9223372036854775808` | **correct** — comparisons take another path |
| `a shr 63` | correct |

So: only `div`/`mod`, only a **literal** divisor, only at or above **2^63**. A
variable holding the same value is fine, which is what makes it silent — the
constant-folded form is the one that lies.

## Root cause (verified by reading, then by the boundary above)

`NormalizeUnsignedLiteralOperand` (`compiler/pasparser_expr.inc:8813`) is what
keeps `q div 10` unsigned: it retypes a positive integer literal to `tyUInt64`
when the other operand is unsigned. Its guard is

```pascal
  if ASTIVal[lit] < 0 then Exit;
```

`ASTIVal` is an `Int64`, so the literal `9223372036854775808` is stored as
`-9223372036854775808` and **is** negative. The normaliser bails, the literal
keeps its signed type, `TypeDivideUnsigned` then sees a signed divisor and
selects the signed divide, and `QWord($FFFFFFFFFFFFFFFF)` enters it as `-1`.
`-1 div -9223372036854775808` = 0, which is exactly what is printed.

The guard is right for a genuinely negative literal and wrong for one that
merely wrapped. It cannot tell them apart from `ASTIVal` alone — it needs the
lexer's "this literal did not fit Int64" fact, or a check against the token text
/ the literal's own recorded type.

## Also worth fixing while there

`compiler/symtab.inc:3466` cites **`NormalizeUnsignedDivLiteral`**, which does
not exist anywhere in the tree — the function is `NormalizeUnsignedLiteralOperand`.
A stale name in the one comment that explains this rule is how the next person
loses an hour.

## Why prio 55

Silent wrong arithmetic, so above the default — but the trigger is narrow: an
unsigned literal at or above 2^63 used as a `div`/`mod` operand. Real code that
hits it is hash mixing, PRNGs and 2^63 bit masks, not everyday arithmetic. The
same class of code is exactly where a wrong value propagates furthest before
anyone notices, which is why it is not lower.

## Gate

Track P: `make compiler/pascal26` (self-host fixedpoint) + the repro above
agreeing with `fpc -O2`, plus the `mod` line, at all four `-O` levels. Add the
repro as a test with an `.expected`.
