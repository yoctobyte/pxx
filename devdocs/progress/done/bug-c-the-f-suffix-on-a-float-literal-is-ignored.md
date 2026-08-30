---
track: C
prio: 40
type: bug
status: done
blocked-by: []
owner: frankC
summary: "`16777217.0f` keeps its double value where C requires the single-precision 16777216.0, and `0.1f` prints 0.100000000 instead of 0.100000001. The explicit `(float)` cast rounds correctly and a store into a float lvalue rounds correctly -- only the literal SUFFIX is ignored. All five targets, so it is a frontend defect, not an ABI or backend one."
---

# The `f` suffix on a float literal is ignored

Found on 2026-08-30 while building the regression test for
[[bug-c-a-float-to-double-cast-is-a-retag-not-a-conversion]]: the assertion row
`(double)0.1f` disagreed with gcc on all five targets at once, which is the
signature of a frontend defect rather than anything to do with the convention or
ABI work happening around it.

## Measured, all five targets identical, against gcc

```c
float v = 0.1f;
printf("A %.9f\n", (double)v);              /* 0.100000001  ok  */
printf("B %.9f\n", (double)0.1f);           /* 0.100000000  BAD */
printf("C %.9f\n", (double)(float)0.1);     /* 0.100000001  ok  */
printf("D %.1f\n", (double)16777217.0f);    /* 16777217.0   BAD */
printf("E %.1f\n", (double)(float)16777217.0); /* 16777216.0 ok */
```

**Only the suffix form is wrong.** The explicit `(float)` cast rounds (C, E) and
a store into a `float` lvalue rounds (A). `16777217` is the smallest integer a
float cannot represent, so D is not a display question: `16777217.0f ==
16777217.0` answers true here and false in C, and a program can branch on it.

## Why it is a bug in this lane and not Track F

The mechanism is **an ignored type suffix** — the literal is parsed and kept at
double precision, and the `f` never reaches the value. That it happens to be a
float is incidental; the same shape with an integer suffix would be the same
defect. Track F is float MATH and float FORMATTING; this is a literal that does
not have the type the source says it has, and its observable is a comparison,
not a rendered digit. Rank the mechanism, never the datatype.

## The sibling rule, twice on one ticket

This is the third arm of the same double case. The machinery to round a value to
single already exists — the anonymous-`tySingle`-temp round-trip added by
[[bug-c-cast-to-float-in-value-position-does-not-round-to-single]] — and the
widening mirror was added by
[[bug-c-a-float-to-double-cast-is-a-retag-not-a-conversion]]. **The literal
suffix is the arm nobody grepped for**, exactly what
`devdocs/dev/normalise-dont-special-case.md` warns about: fix one arm of a
double case, go find the others. The fix is likely to route the suffixed literal
through the same round-trip rather than to add a fourth path.

## Repro

`test/c_float_to_double_cast_variadic.c` deliberately reads a float VARIABLE in
its row 11 and says why: asserting the literal there would make one red stand
for two mechanisms. A new test for this ticket should assert rows A-E above.

## Resolution — two defects stacked, and the second had nothing to do with C

**The C half went where this ticket predicted.** The rounding lives in the
LEXER (`CFloatBitsRoundedToSingle`, applied in both float scanners — decimal and
the C99 hex tail), because that is the one place the suffix is visible, and it
makes the value right in every context a literal can reach: a global
initializer and a constant expression cannot materialise the anonymous
`tySingle` temp that the `(float)` CAST path round-trips through. No fourth
path, as predicted.

The TYPE half needed one bit: `CAttrFlags` bit 64, set by the lexer, read where
the parser builds `AN_FLOAT_LIT`. That is what moves `sizeof(0.1f)` from 8 to 4.

**Then the type half exposed an older bug underneath it, on riscv32 only.**
Tagging the literal `tySingle` made `float v = 0.1f` read back as
`-0.000000000` there. `ir_codegen_riscv32.inc`'s `IR_CONST_INT` took `Low32` of
the constant's DOUBLE bit pattern — but a float constant carries double bits
whatever its `tk` says (`defs.inc`, `AN_FLOAT_LIT`), so a `tySingle` const has
to be NARROWED, not truncated. `Low32` of a double pattern is the low mantissa
half. x86-64 and aarch64 never noticed (their value model carries a single as
double bits); arm32 loads the whole pattern into `d0` and converts on the way
out; riscv32 is soft-float ILP32 and carries a single as its own 32 bits in a0.

**That path was not new and C was not needed to reach it.** Pure Pascal,
riscv32, pinned binary vs fixed:

```
BASELINE  2.5000|0.0000|0|0.5000|0.0000|0.00 0.00 0.00 0.00
FIXED     2.5000|0.5000|1000000015047466219876688855040|0.5000|1.5000|0.00 -1.50 2.50 …
```

Every `Single` CONSTANT on riscv32 was zero — a bare `const S1: Single = 0.5`
and a whole `array of Single`. Now byte-for-byte FPC's output. Anything on the
ESP32-C3 using Single constants was silently reading zeros.

## Tests

- `test/c_float_literal_f_suffix.c` — rows A–J, all matching gcc on all five
  targets. A/C/E are the control that was always green (the machinery existed;
  only the suffix arm was missing). G is the type half and is NOT redundant with
  B: the value rows were green for one build while G was still 8.
- `test/test_single_const_value.pas` — the Pascal defect underneath, matching
  FPC exactly.
- Both on x86-64 in the ordinary tests, and both across
  aarch64/arm32/riscv32/i386 in the new `test-c-float-const-cross` target
  (8/8 PASS).

Gate: `make compiler/pascal26` converged, `gate.sh quick` GREEN.

## Deliberately NOT fixed here

`float + float` is still evaluated at double width — filed as
[[bug-c-float-plus-float-is-computed-at-double-width]]. Checked against the
pinned binary before filing: pre-existing, not a regression from this work. Kept
out of this test on purpose so that one red does not stand for two mechanisms —
the same reason this ticket's own repro reads a float VARIABLE in row 11 of
`c_float_to_double_cast_variadic.c`.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
