---
slug: bug-c-struct-operands-to-scalar-operators-compile-silently
track: C
prio: 75
type: bug
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (checking that _Complex arithmetic is refused, feature-c-complex-types-as-layout)
tags: [cfront, diagnostics, silent-miscompile]
summary: "`struct S a, b; r = a + b;`, `a == b`, `-a`, `!a`, `if (a)`, `(double)a`, `a = 1.0` and the same on a union all COMPILED (exit 0, no diagnostic) where gcc refuses each, and the binary computed with whatever the IR made of record addresses. Real code never writes these, so nothing showed it. It became a real hazard when _Complex became a struct: complex arithmetic IS real code, and it would have compiled to nonsense. Now refused at the operator (CMakeBinop, unary - + ~ !, CCondOf, casts to a scalar, simple assignment between a struct and a scalar), with a _Complex-specific message. The comma operator and ?: with struct arms stay legal. Test c_structop26 / c_structop26_ref."
---

# Struct operands to scalar operators compiled silently

Measured, before the fix (pxx exit code / gcc exit code):

```
a + b;               pxx=0 gcc=1
r = a * 2.0;         pxx=0 gcc=1
r = -a;              pxx=0 gcc=1
if (a == b) r = 1;   pxx=0 gcc=1
r = (double)a;       pxx=0 gcc=1
a = 1.0;             pxx=0 gcc=1
if (a) r = 1;        pxx=0 gcc=1
```

C11 6.5 requires a scalar (or arithmetic, or integer) operand for each of
these. Valid code never has them, which is why the gap stayed silent. A
build that accepts invalid code and emits a binary that computes garbage is
still the wrong answer, and with `_Complex T` laid out as a struct
(feature-c-complex-types-as-layout) every `z + w` in valid complex code
would have been one.

Fix (cparser.inc): `CRefuseRecordOperand(e, what)`, called where each
kind of node is made: `CMakeBinop` (every binary and compound-assignment
operator, except the comma), unary `-`, `+`, `~`, `!`, `CCondOf` (if,
while, for, ?:, && and || conditions), a cast of a record to a scalar type,
and a simple assignment with a record on exactly one side. A complex
operand gets "complex arithmetic is not supported (pxx models _Complex as
layout only)". A cast of a scalar to a complex type is refused too:
without the check it would take the GNU cast-to-union path.

Test test/c_struct_operand_refused.c: CASE 0 (struct assignment, a struct
through `,` and `?:`, member access, complex copies and calls) runs and
matches gcc (c_structop26). CASE 1–13 are each refused with the message
(c_structop26_ref). 1–8 are also refused by gcc; 9–13 are valid complex
code that pxx refuses as not modelled.
