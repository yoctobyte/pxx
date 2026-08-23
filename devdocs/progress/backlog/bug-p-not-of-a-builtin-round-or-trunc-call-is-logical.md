---
track: P
prio: 45
type: bug
blocked-by: []
status: backlog
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
