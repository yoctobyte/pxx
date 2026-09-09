---
slug: bug-p-the-bare-self-call-in-expression-position-has-none-of-the-doors
title: "The bare implicit-Self call in EXPRESSION position has none of the five doors its statement twin has"
track: P
prio: 45
type: bug
status: open
owner: ""
found-by: frankH
created: 2026-09-09
tags: [methods, arity, array-of-const, variadic]
blocked-by: []
summary: "`pasparser_expr.inc`'s bare implicit-Self factor hand-rolls the same argument loop the STATEMENT site did, and has NONE of the five doors that site has now been given one at a time. Measured 2026-09-09 at b708205d2, all inside the class that declares the callee: `Desc(['a', 1])` answers n=0 (the bracket is still parsed as a SET, no diagnostic); `Desc('a', 1)` SEGFAULTS; `Req(1, 2, 3)` against `Req(x: Integer)` is accepted and returns 3; `Req()` against the same is accepted and reads uninitialised memory. Every one of those is a defect ALREADY CLOSED at the statement twin -- bug-p-an-array-of-const-literal-is-a-set-at-a-bare-self-method-call, bug-p-a-bare-variadic-method-call-segfaults-where-the-bracketed-spelling-works, bug-p-a-bare-method-call-inside-its-own-class-ignores-arity and bug-p-empty-parens-at-a-bare-method-call-reads-a-garbage-argument -- so this is not four bugs, it is one loop that was never given the fixes. The right shape is to EXTRACT the statement loop and call it from both, not to spell a sixth patch: five separate sessions have now each added one door to one copy. `with Self do n := Req()` reaches the same arm and has the same holes."
---

# The bare implicit-Self call in expression position has none of the doors

- **Type:** bug — **Track P**, `compiler/pasparser_expr.inc`, the bare
  implicit-Self factor's argument loop (the `if (idx < 0) and (procIdx < 0) and
  (CurSelfClass >= REC_UCLASS_BASE)` arm).

## Measured, 2026-09-09, one class, one program

```pascal
type TC = class
  function Desc(const a: array of const): Integer;
  function Req(x: Integer): Integer;
  procedure Go;
end;
procedure TC.Go;
begin
  WriteLn(Desc(['a', 1]));   { n=0        -- bracket parsed as a SET }
  WriteLn(Desc('a', 1));     { SEGFAULT                              }
  WriteLn(Req(1, 2, 3));     { 3          -- accepted, arguments shifted }
  WriteLn(Req());            { garbage    -- accepted, uninitialised }
end;
```

The statement spelling of every one of those is correct today. So is every
QUALIFIED spelling (`Self.`, a name, an array element, an interface).

## Why it is one ticket and not four

Each row is a defect that was found, diagnosed and fixed **at the statement
twin**, by a different session, on a different day, one door at a time:

| door | closed at the statement site by |
| --- | --- |
| `[...]` is an open array, not a set | `bug-p-an-array-of-const-literal-is-a-set-at-a-bare-self-method-call` |
| a bare method NAME is a reference | `bug-p-a-bare-method-name-in-argument-position-is-called-instead-of-referenced` |
| arity is checked at all | `bug-p-a-bare-method-call-inside-its-own-class-ignores-arity` |
| an elided `array of const` tail is absorbed | `bug-p-a-bare-variadic-method-call-segfaults-where-the-bracketed-spelling-works` |
| empty parens against a required parameter | `bug-p-empty-parens-at-a-bare-method-call-reads-a-garbage-argument` |

Five doors, five sessions, one copy. **The fix is to extract the statement
loop and call it from both**, which is what that site's own comments have been
arguing for across the last three of those — *"every other call path asks; this
one hand-rolled its loop and asked nothing"* — not a sixth patch here. The
expression arm additionally handles `PyKwDictArgsHere(mpi)` before its loop,
which the extraction has to carry.

## How it was found, which is the transferable part

Not by searching for where the rule is spelled — that returns the correct
copies and is **silent about the missing one**. By enumerating the positions
the rule should COVER (receiver spellings × contexts: bare, `Self.`, a name, an
array element, an interface, inside a `with`; statement and expression) and
subtracting the ones that have it. One probe file, two minutes. Same inversion
frankB reached the same evening from a NilPy constructor mapping.

`bug-p-a-bare-variadic-method-call-segfaults-where-the-bracketed-spelling-works`
carries a correction because its write-up asserted this arm "already had the
tail" before anyone measured it.
