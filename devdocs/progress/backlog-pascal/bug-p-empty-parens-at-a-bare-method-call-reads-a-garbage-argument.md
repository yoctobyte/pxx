---
slug: bug-p-empty-parens-at-a-bare-method-call-reads-a-garbage-argument
title: "`Desc()` written bare inside its own class is accepted and reads a garbage argument"
track: P
prio: 35
type: bug
status: open
owner: ""
found-by: frankH
created: 2026-09-09
tags: [methods, arity, array-of-const]
blocked-by: []
summary: "`Desc();` -- empty parens against a REQUIRED parameter -- is accepted at the bare implicit-Self statement site and the callee reads whatever was in the argument slot. Measured 2026-09-09 on `procedure Desc(const a: array of const)`: `Length(a)` answers 8 with no diagnostic, identical on HEAD and on pin v399, so this is pre-existing and not a regression. The qualified spelling `Self.Desc()` in the same program refuses it -- `Desc() requires 1 argument(s), none given` -- and fpc 3.2.2 refuses the bare one too (`Wrong number of parameters specified for call to \"Desc\"`). One concept, two paths, and the bare path is the one that stayed broken. The site's own hand-rolled argument loop has no FillDefaultArgs and no all-defaulted test, which is why a naive `no arguments parsed and ParamCount > 1 -> error` would break `Def()` on `Def(x: Integer = 3; y: Integer = 4)`, which works today and matches fpc (`def 34`). Found while fixing bug-p-a-bare-variadic-method-call-segfaults-where-the-bracketed-spelling-works, which touches this exact loop and deliberately left the shape alone rather than reshape it from a fix aimed at the segfault."
---

# Empty parens at a bare method call reads a garbage argument

- **Type:** bug — **Track P**, `compiler/pasparser_stmt.inc`, the bare
  implicit-Self statement call site's hand-rolled argument loop.

## The repro

```pascal
type TC = class
  procedure Desc(const a: array of const);
  procedure Go;
end;
procedure TC.Desc(const a: array of const);
begin WriteLn('n=', Length(a)); end;
procedure TC.Go;
begin
  Desc();        { accepted -> prints n=8 }
  Self.Desc();   { refused: Desc() requires 1 argument(s), none given }
end;
```

Both are the same call. fpc refuses the bare one as well, so there is no
"we accept more than fpc" reading here — the value is simply garbage.

## Why it is not a one-line arity check

`ParamCount > 1` with nothing parsed is **not** the condition. The same loop
serves `Def()` on `Def(x: Integer = 3; y: Integer = 4)`, which prints `def 34`
under both pxx and fpc. The loop never grew a `FillDefaultArgs` step, so a
check written from the arity alone would delete that. The condition wanted is
the one `CheckMethodCallArity` already spells for the **no-paren** shape
(`pasparser_call.inc`): refuse only when the first unsupplied parameter has no
declared default. This is that guard's empty-parens twin, and reusing it is
the fix rather than a fourth hand-written one — see
`devdocs/dev/normalise-dont-special-case.md`.

## What is already known about this loop

Three omissions have been found in it and all three read the same:
*every other call path asks; this one hand-rolled its loop and asked nothing.*
The bracket door, the arity fallback, and the variadic tail
([[bug-p-a-bare-variadic-method-call-segfaults-where-the-bracketed-spelling-works]],
which recorded this defect at its `-1` guard and left it deliberately
untouched). A fourth patch here is weaker than routing the site through the
shared tail, which is where the other seven loops already ask.
