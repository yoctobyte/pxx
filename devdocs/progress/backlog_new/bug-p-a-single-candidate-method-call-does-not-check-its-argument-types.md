---
slug: bug-p-a-single-candidate-method-call-does-not-check-its-argument-types
title: "A single-candidate method call accepts arguments the identical free procedure rejects"
track: P
prio: 48
type: bug
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-26
summary: "`c.M(p)` with p: Pointer and `M(const s: AnsiString)` compiles; `FreeProc(p)` with the identical signature is refused with `no overload of FreeProc matches these arguments`. Method resolution type-checks only when there are 2+ candidates — the single-candidate path checks ARITY and nothing else. Found while closing bug-p-a-descendant-method-does-not-hide-the-inherited-one."
---

# Measured, 2026-08-26, pinned compiler

```pascal
{$mode objfpc}
program margcheck;
type
  TC = class
    procedure M(const s: AnsiString);
  end;
procedure TC.M(const s: AnsiString); begin WriteLn('M [', s, ']'); end;
procedure FreeProc(const s: AnsiString); begin WriteLn('F [', s, ']'); end;
var c: TC; p: Pointer;
begin
  c := TC.Create; p := nil;
  FreeProc(p);   { pascal26: error: no overload of FreeProc matches these arguments }
  c.M(p);        { compiles }
end.
```

Same signature, same argument, two answers. fpc 3.2.2 rejects both:
`Incompatible type for arg no. 1: Got "Pointer", expected "AnsiString"`.

# Root cause

`FindUMethOverloadAhead` type-ranks candidates only when there is more than one
(`if nCand <= 1 then Result := FindUMethArity(...)`), and `FindUMethArity`
filters on ARITY alone. So the one-method case — which is most method calls —
never looks at the argument types at all. The free-call path goes through
`MatchCall*`, which does.

Two resolvers for one concept, and only one of them was ever finished. Same
shape as bug-a-not-on-an-integer-variant-answers-a-boolean and
bug-a-pxxvarbinop-carries-the-same-string-arithmetic-defect-as-x86-64-did.

# Why it is filed rather than fixed with the hiding ticket

CLAUDE.md's parity ceiling: *accepting a form FPC rejects is not a defect*. So
this is a looseness, not a wrong answer — nothing mis-dispatches, the single
candidate IS the right method, and the argument is coerced. It only became
visible because the hiding fix narrowed `d.Add(p)` from **two** candidates
(where it silently picked the parent's — a real wrong answer, now fixed) to
one.

But it is a looseness that HIDES wrong answers: an argument coerced instead of
refused is how `Pointer` reached an `AnsiString` parameter above, and a `nil`
that prints empty today is a crash the day the coercion is not benign.

# The fix

Make the single-candidate method path run the same argument-compatibility check
the free-call path runs, rather than adding a second check beside it. The
ranked path already computes exactly this; the work is to reach it (or the
shared matcher) with one candidate instead of short-circuiting to arity.

Blast radius is the reason for the prio: every method call in the language, and
any pxx-accepted source that currently relies on a coercion this would refuse.
Measure with `tools/run_pascal_conformance.sh`, the fgl rung and the self-host
before believing it.

# Acceptance

- `c.M(p)` above is refused with the same diagnostic `FreeProc(p)` gets.
- Conformance sweep, fgl rung (7/7) and self-host all unchanged.
