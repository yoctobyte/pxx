---
prio: 55
track: P
owner: frankB
---

# `QWord div` / `mod` by a literal >= 2^63 divides SIGNED and returns a wrong value

- **Type:** bug (silent wrong value) — **Track P** (Pascal frontend; the fix is
  one predicate in `compiler/pasparser_expr.inc`).
- **Status:** done
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

## FIXED 2026-09-04 (frankB) — and the reported boundary was too narrow in two places

`NormalizeWideUnsignedLiteral` in `compiler/pasparser_expr.inc`, called from the
`div`/`mod` arm and the comparison arm before the existing pair normalisation.
A decimal literal the lexer could not fit in an Int64 (it keeps the digit text;
`ASTSLen > 0`) and that fits UInt64 is retyped `tyUInt64` on its own authority,
so the pair rule then has something to key on.

**Two rows of the boundary table above are wrong, measured against fpc 3.2.2:**

| shape | ticket said | actually |
| --- | --- | --- |
| `a > / >= / < / = <wide literal>` | "correct — comparisons take another path" | correct ONLY with a QWord-typed operand. `9223372036854775808 > 1` answered **FALSE** |
| constant-only `<wide literal> div 2` | not mentioned | **wrong** — `-4611686018427387904`, and `18446744073709551615 div 5` answered **0** |

The common half is the diagnosis: `ASTIVal` cannot tell a wrapped literal from a
negative one. The half the report missed is that a QWord VARIABLE was doing all
the rescuing — every shape it listed as correct had one, and every shape without
one was broken. `a div 18446744073709551615` (its own "max-div" row) is correct
by accident: `-1 div -1` = 1.

**Not fixed at the literal's creation**, which is where it would look tidier.
`IsWideIntLit` keys on `tyInt64`, and every promotable-int path asks it — the
digit text reaching `PXXPromoFromStr`, the variant boxing, the `Write` arm.
Retyping every wide literal up front would make that predicate stop matching,
and those sites do not error, they take the other branch. So the retag happens
only on the two arms that read signedness. `tyPromoInt64` is excluded for the
same reason (NilPy owns its own arithmetic); past UInt64 the literal keeps
`tyInt64` and still reaches `ir.inc`'s out-of-range diagnostic.

`IsWideIntLit` / `IsWideNegLit` moved from `ir.inc` to `ast_arena.inc` so the
parser can ask them — `ir.inc` is included after `pasparser_expr.inc`. They read
only AST arena state.

**HEX IS NOT PART OF THIS AND MUST NOT BE.** `$8000000000000000` is a signed
Int64 in FPC too: it prints the same `0` and `-1` there. The test asserts those
two rows keep diverging from the decimal spelling.

Also fixed: the stale `NormalizeUnsignedDivLiteral` citation, which had drifted
from `symtab.inc:3466` to `:4212` — a stale line number as well as a stale name.

**Gate:** `make compiler/pascal26` converged; `tools/gate.sh quick` GREEN with the
FPC seed canary CONCURRENT (not SKIP), which is the arm that matters when
functions move between `.inc` files. `test/test_qword_wide_literal_div.pas`
matches fpc 3.2.2 byte-for-byte at `-O0`, `-O1`, `-O2` and `-O3`; on pin v403 it
fails at exactly nine of its seventeen rows. `test_promoint.pas` and
`test_nilpy_int_promotion_default.npy` were run as controls on the moved
predicate and both match.

Measured while here and NOT fixed (pre-existing, identical on the pin):
`Writeln(9223372036854775808)` with a bare wide literal argument needs the
promocore unit and errors `runtime helper PXXPromoFromStr not found` without it.
Different ticket shape; not this one.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
