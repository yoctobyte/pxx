---
track: P
prio: 45
type: bug
blocked-by: []
status: done
summary: "`not Round(1.5)` answers TRUE where FPC answers -3: pxx applies the LOGICAL not (xor 1) to a builtin ordinal function's result. `not Trunc(d)` the same. A user-written `function Two: Int64` is fine, so it is the builtin calls specifically. Silent wrong value AND wrong type."
---

# `not Round(x)` is logical, not bitwise

Found 2026-08-24 while writing the runtime helper for
[[bug-a-not-on-an-integer-variant-answers-a-boolean]] — the helper's own
`not Round(d)` produced 3 instead of -3, which is `2 xor 1`.

```pascal
var v: Int64; d: Double;
begin
  d := 1.5;
  writeln(not Round(d));   { pxx TRUE   fpc -3   WRONG }
  writeln(not Trunc(d));   { pxx FALSE  fpc -2   WRONG }
  v := Round(d);
  writeln(not v);          { pxx -3     fpc -3   ok    }
end.
```

A user-declared `function Two: Int64` is also fine (`not Two` = -3), so this is
not "AN_CALL is untrusted" across the board — it is the BUILTIN ordinal
functions specifically.

**Silent, and wrong twice over**, exactly like the variant `not` it was found
under: the value is wrong and so is the type, so `mask := not Round(x)` puts a
Boolean where an integer was meant and nothing downstream mentions `not`.

## Why it is the way it is, and why that is not a defence

`ParseFactor`'s `tkNot` arm (`compiler/pasparser_expr.inc`, ~line 1105) trusts
an operand's type only for node kinds whose type is authoritative — an integer
literal, an identifier, an ordinal value-cast, a pure arithmetic binop. `AN_CALL`
is deliberately excluded, and the comment there says why: pxx tags some
boolean-returning calls as tyInteger (`not Eat(...)` in `compiler.pas`), and
promoting those to bitwise broke self-host.

So the exclusion is load-bearing. But it is currently a blanket one, and the
blanket covers `Round` and `Trunc`, whose return type is not a guess — it is
fixed by the builtin's own signature. That is the seam: trust the type of a
call whose callee is a BUILTIN with a declared ordinal result, keep distrusting
the general `AN_CALL`. Check `Ord`, `Length`, `Trunc`, `Round`, `High`, `Low`,
`SizeOf`, `Abs` and `Pos` together — they are one list, and fixing one arm of a
double case without grepping for the siblings is the failure mode
`devdocs/dev/normalise-dont-special-case.md` exists to name.

The right fix may instead be upstream: if the mistagging of boolean-returning
calls as tyInteger were repaired, the whole exclusion could go. Measure which
calls actually mistag (`PXXDBG=a.ast:<proc>`) before choosing — the microfix
here adds a case, the root fix deletes one.

## Workaround in the tree

`PXXVarNot` in `compiler/builtin/builtinheap.pas` rounds through a local
`v: Int64` and complements that, with a comment naming this ticket. Revert to
the direct `not Round(...)` when this is fixed.

## Gate

Track P's, plus the three rows above matching fpc 3.2.2 on x86-64 and one cross
target, plus the whole builtin list swept, plus self-host byte-identical (the
exclusion exists because a previous attempt broke exactly that).

---

# Resolved 2026-08-24 — in two halves, and the first was already done

**`not Round(x)` and `not Trunc(x)` were fixed by deleting the whitelist**
(`7a2635cba`, `refactor-centralize-managed-string-pchar-conversion`'s `not`
slice): the arm now trusts `ASTTk[left]`, and a builtin's return type is exactly
the authoritative tag the ticket said it was. Re-measured here: `not Round(1.5)`
= -3, `not Trunc(1.5)` = -2, matching fpc. The ticket's "the right fix may be
upstream" reading was correct — the exclusion went away entirely rather than
growing a builtin list, which is the outcome
`devdocs/dev/root-cause-over-microfix.md` asks for.

**What was left was a different bug wearing the same shape.** Sweeping the whole
builtin list the ticket names showed `Round`, `Trunc`, `Length`, `Abs`, `Pos`
and `SizeOf` all correct, and `Ord`, `High` and `Low` still wrong — but only on
a CONSTANT operand:

```
not Ord('A')      fpc -66      pxx 190     <- constant
not Ord(chVar)    fpc 190      pxx 190     <- variable, both right
not High(Byte)    fpc -256     pxx 0
not Low(Byte)     fpc -1       pxx 255
not High(Word)    fpc -65536   pxx 0
```

FPC evaluates a constant expression in a signed type wide enough for the RESULT,
while `not` over a variable complements at the variable's own width. pxx
complemented the constant inside its small unsigned type, producing a positive
number where fpc gives a negative one — silent, and reachable from any mask
written with a named or builtin constant. The rule was already implemented for
unary MINUS (`ASTConstIntValue` exists to type a negated constant); `not` had
simply never been given it. It now types a constant `not` by its folded value —
the smallest signed type that holds it, `tyInteger` or `tyInt64`, as fpc does —
and `ASTConstIntValue` learned that `Ord(<constant>)` is itself a constant.

**And that uncovered a real arm32 backend bug.** Forcing a blanket `tyInt64`
first (before narrowing to fpc's own answer) made `not 255` an IR_NOT with a
64-bit result over a 32-bit immediate, and arm32 printed
-579161170041110784. `IR_NOT`'s 64-bit arm emitted its operand with
`IREmitNodeArm32` and complemented r0:r1 — so a narrower operand left r1 holding
whatever was there before. IR_NEG's 64-bit arm has always used
`EmitNode64Arm32` for exactly this reason; IR_NOT now does too. x86-64, i386,
aarch64 and riscv32 widen implicitly and were never wrong. The gap predates this
ticket; only the narrower operand shape is new, and it stays reachable at HEAD
through `not High(Cardinal)` (complement does not fit in 32 bits), which the
test pins.

# Verified

- `test/test_not_of_a_constant_widens.pas` — 22 rows, both halves (variables at
  their own width, constants widened), `.expected` IS fpc 3.2.2's output. Eight
  rows are wrong on the pinned compiler. Green on i386 / aarch64 / arm32 /
  riscv32.
- A 47-expression `not` sweep against fpc — variables of every ordinal width,
  casts, comparisons, boolean ops, array elements, record fields, named
  constants, and every builtin the ticket lists: **47/47 agree**.
- `test_variant_bitwise_and_not` still ALL OK with the workaround removed.
- `make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.

# Workaround removed

`PXXVarNot` in `compiler/builtin/builtinheap.pas` is back to the direct
`not Round(PDouble(..)^)`; the local it rounded through is gone.

## Log
- 2026-08-24 — resolved, commit PENDING-COMMIT.
