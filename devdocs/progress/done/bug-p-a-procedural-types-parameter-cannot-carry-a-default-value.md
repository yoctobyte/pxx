---
slug: bug-p-a-procedural-types-parameter-cannot-carry-a-default-value
track: P
type: bug
prio: 35
status: done
created: 2026-09-06
found-by: frankB
owner: ""
blocked-by: []
title: "A procedural type's parameter cannot carry a default value — `TCb = procedure(n: Integer = 5)` does not parse"
summary: "MEASURED 2026-09-06 at d51037cf2 against fpc 3.2.2 -Mobjfpc. `TCb = procedure(n: Integer = 5);` is refused with `expected ')' before '='`, for ANY parameter type -- Integer, string, a named dynamic array alike -- so this is not a type question. ParseProcTypeSignature (pasparser_decl.inc) is the ONE of the four parameter parsers with no ParseParamDefaultValue call at all: the other three parse a default, record it in ProcParamHasDefault/ProcParamDefaultVal and let a call omit the argument. fpc compiles the declaration and honours the default at a parenless indirect call (`c1;` prints 5, `c1(9)` prints 9). A LOUD refusal at the declaration, not a wrong value at a call, which is why it is ranked below the crashes in the same neighbourhood. Found while writing the fixture for bug-p-a-named-dynamic-array-default-declared-in-a-class-body-is-lost-if-the-implementation-omits-it, whose proc-type row could not be written; that file says so rather than dropping the row silently."
---

# `TCb = procedure(n: Integer = 5)` does not parse

```pascal
type TCb1 = procedure(n: Integer = 5);      { pxx: expected ')' before '=' }
procedure P1(n: Integer = 5); begin WriteLn('P1 ', n); end;
var c1: TCb1;
begin
  c1 := @P1;
  c1;        { fpc: P1 5 }
  c1(9);     { fpc: P1 9 }
end.
```

**Not a type question.** Integer, `AnsiString` and a named dynamic array are all
refused identically, so nothing about the parameter's shape is involved.

`ParseProcTypeSignature` in `pasparser_decl.inc` is the only one of the four
parameter parsers with no `ParseParamDefaultValue` call. The other three
(`ParseRecordMethodDecl` and the interface- and class-method arms of
`ParseTypeSection`) parse the default, record it in `ProcParamHasDefault` /
`ProcParamDefaultVal` and let a call omit the argument.

## Where the work is

The parse is the small half — one `if CurTok.Kind = tkEq then` beside the others,
passing `mIsArr and (mDyn <= 0)` as the open-array refusal flag, exactly as the
three siblings now do. The half that needs measuring is whether the INDIRECT call
paths fill it: `BuildIndirectCallAST` (`pasparser_lval.inc`) and the parenless
proc-var call would each need to reach `FillDefaultArgs` against the proc type's
signature row, and a parenless `c1;` on a proc variable is its own arm.

**Do not close this on the declaration parsing.** A default that is recorded and
never filled is the shape that segfaulted at four interface arms
([[bug-p-an-interface-dispatched-call-that-omits-a-defaulted-argument-segfaults]]):
`CheckMethodCallArity` accepts the short call *because* the parameter has a
default, and then nothing supplies it.

## Done when

`c1;` prints 5 and `c1(9)` prints 9 through a proc variable, a method-pointer
variable and an anonymous proc-type parameter, with a control that a proc type
whose parameter has NO default still refuses the short call.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

## Resolution (2026-09-06)

Three edits, and the ticket's warning was the right one — the parse was the
small half.

1. **`ParseProcTypeSignature`** (`pasparser_decl.inc`) parses the default like
   its three siblings, passing `mIsArr and (mDyn <= 0)` as the open-array
   refusal flag, and writes all six `ProcParamDefault*` columns at the row-write.
2. **`BuildIndirectCallAST`** (`pasparser_lval.inc`): the arity check stopped
   being an equality, and a short list fills through `FillDefaultArgs`. Order
   matters — the fill writes `ASTLeft[callNode]` itself when the list was empty,
   so the node must exist first.
3. **The statement path's parenless arm** (`pasparser_stmt.inc`): its guard was
   `ParamCount = 0`, which is the *degenerate case* of "nothing left to supply"
   rather than a separate rule. Now `ParamCount = 0 or ParamsDefaultedFrom(sig, 0)`,
   with the fill in the same arm — deliberately, because accepting the short
   call and then supplying nothing is exactly
   [[bug-p-an-interface-dispatched-call-that-omits-a-defaulted-argument-segfaults]].

Also improved the near-miss diagnostic, which was the same class as the
overload-candidate report closed an hour earlier: `c;` on a proc type with a
required parameter said `expected ':=' before ';'`, telling the programmer they
meant an **assignment** when what they wrote was a call missing its arguments.

## The row that caught a defect the fixture was not about

`parenless meth` — `procedure(n: Integer = 11) of object`. While arm 3 was being
split, its method-pointer flag (`ASTSLen := 1` for a {Code,Data} pair) was lost
for one build. That row printed `M-1480588942`, the Data half read as the Code
half, **with the other ten rows green**.

The ten were not weak controls; they were correct controls for a different
question. Every one asserts the default-value machinery, and what broke was the
lowering underneath it. **A fixture that covers its feature completely still
covers one axis, and the axis a refactor breaks is usually the one the file
never thought it was testing.** So when an arm is split, the rows to re-read are
the ones about the SHAPE the arm produces, not the ones about the feature: a
flag was lost, and exactly one row asserted the flag. (frankS's framing.)

`M-1480588942` was loud. The same slip in a row whose Data half held something
printable would have shipped on eleven greens.

## One row is ours and fpc refuses it

`procedure TakesCb(cb: procedure(n: Integer = 5))` — an ANONYMOUS procedural type
in a parameter position — is `Type identifier expected` under fpc 3.2.2, which
accepts the spelling only through a named alias. **Us accepting what FPC rejects
is not a defect**, so the row stays; the fpc cross-check ran on a copy with a
named alias in that one place and matched all eleven rows byte for byte.

Fixtures: `test_a_procedural_types_parameter_carries_its_default_through_every_indirect_call_shape.pas`
(`PROCTYPEDEFAULT OK`, 11 rows) and its must-not-compile control
`test_a_procedural_type_without_a_default_still_refuses_a_short_call_fail.pas` —
which is the row that fails if the arity relaxation is not gated on
`ProcParamHasDefault`, since the positive rows would then pass from a zeroed
column.
