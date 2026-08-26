---
slug: bug-p-a-single-candidate-method-call-does-not-check-its-argument-types
title: "A single-candidate method call accepts arguments the identical free procedure rejects"
track: P
prio: 48
type: bug
blocked-by: []
status: done
owner: opus5-frank1
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

## Outcome

Fixed for the shape the ticket was filed about, and **deliberately abstaining
everywhere else**. `c.M(p)` is now refused with the same diagnostic
`FreeProc(p)` gets; the acceptance criterion is met, and so are the three
"measure before believing it" checks.

### The obvious gate is unsound, and only measuring showed it

First cut: with one candidate, run the probe and refuse whenever
`OverloadArgRank` says impossible — which is exactly `not TypesCompatible`, the
same predicate the free-call path refuses on. The self-host converged, which
felt like evidence. It was not.

| corpus | baseline | naive gate |
| --- | --- | --- |
| self-host | converged | converged |
| `run_pascal_conformance.sh` | 346 pass / 0 fail | **338 / 8** |
| `run_fgl_corpus.sh` | 7 pass / 0 fail | **0 / 7** |

Four distinct classes of **legal** call were refused, and each one traces to a
side channel the speculative probe does not have and `pasparser_lval.inc` fills
for the free path:

| refused call | why the kind pair is wrong | channel |
| --- | --- | --- |
| `CreateFmt('%s', [s])` | an `array of const` parameter's `TypeKind` is its ELEMENT kind | `MatchArgArray` |
| `slist.Add('test', l)` | a generic type parameter is `tyUnknown` at the declaration | — |
| `SetOnKeyPtrCompare(nil)` | nil binds any reference-shaped parameter | `MatchArgNil` |
| `inherited Sort(ItemPtrCompare)` | a routine name as a procedural value types as neither | — |

Seven of the eight conformance failures were `CreateFmt` alone, from one
`sysutils.pas:874`. `SetOnKeyPtrCompare(nil)` took the fgl rung to 0/7 by
itself — and note that `MatchArgNilOk` *exists* and I called it, but it gates on
`MatchArgNil[]`, which only the free path populates, so it answered False for
every nil. Calling the shared predicate is not the same as reaching the shared
answer.

Each of those five channels exists because a previous agent hit this same wall
from the other side. **The kind pair is not a sound predicate on its own**, and
a denylist of exemptions is only ever as complete as the corpora I happened to
run. An unsound gate that refuses a legal program is strictly worse than the
looseness it replaces — the ticket says so itself: nothing mis-dispatches today,
the single candidate IS the right method.

### What landed instead: an allowlist

Refuse only a **reference-shaped argument** (`tyPointer` / `tyClass`, not nil,
not an untyped `var`, not an open array) bound to a **string or numeric
parameter**. That is precisely the shape the ticket describes — *"an argument
coerced instead of refused is how `Pointer` reached an `AnsiString` parameter,
and a `nil` that prints empty today is a crash the day the coercion is not
benign"* — and it cannot arise from any of the four classes above. Everything
else abstains, and the code says so in as many words.

Selection is untouched: the single candidate still resolves through
`FindUMethArity` exactly as before. The probe buys the rejection and nothing
else, which is what keeps the blast radius to "calls that were already wrong".

### Measured after

| check | result |
| --- | --- |
| repro `c.M(p)` | `error: no overload of M matches these arguments` |
| `run_pascal_conformance.sh` | 346 pass / 0 fail — baseline |
| `run_fgl_corpus.sh` | 7 pass / 0 fail — baseline |
| self-host | converged after 1 round |
| every `test/*.pas` compiled | 4 refusals, all of them `*_fail.pas` files that exist to be refused |

### Gate

Two files, both oracled against fpc 3.2.2, both wired into `test-core` beside
`test_method_overload_types_b248`:

- `test/test_method_arg_typecheck_fails.pas` — must NOT compile. FPC agrees:
  *Incompatible type for arg no. 1: Got "Pointer", expected "AnsiString"*.
- `test/test_method_arg_typecheck_ok.pas` — the positive half, one row per class
  the gate abstains on, output diffed against FPC's.

The positive file spells the procedural argument `@ByPtr`. The BARE name in that
position is `undefined variable (ByPtr)` — identical on the pinned compiler, so
a separate pre-existing gap, noted in the file rather than folded in here.

### What is still open, and it is the real fix

Making the full `TypesCompatible` check sound needs the probe to build an
`AN_ARG` chain and run the free path's own populate-and-match, which means
lifting that population out of `pasparser_lval.inc` into a helper both callers
share. That is the version of "reach the shared matcher" this ticket asked for,
it is a refactor of a Track A/P shared file, and the four classes above are the
acceptance test somebody now has for it. Filed as its own ticket.

## Log
- 2026-08-26 — resolved, commit 547163758.
