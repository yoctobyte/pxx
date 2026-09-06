---
slug: bug-p-a-procedural-types-parameter-cannot-carry-a-default-value
track: P
type: bug
prio: 35
status: backlog
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
