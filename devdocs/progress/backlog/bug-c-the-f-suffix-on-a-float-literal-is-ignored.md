---
track: C
prio: 40
type: bug
status: new
blocked-by: []
owner: ""
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
