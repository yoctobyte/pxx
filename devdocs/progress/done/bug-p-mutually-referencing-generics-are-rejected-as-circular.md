---
slug: bug-p-mutually-referencing-generics-are-rejected-as-circular
track: P
prio: 60
type: bug
status: done
blocked-by: []
summary: "Two generics that reference each other are refused with `circular generic specialization`, but only one direction is a real declaration-time dependency: the other is a reference from inside a METHOD BODY, which FPC resolves when the method is compiled. `TDelegatedEqualityComparerEvents<T> = class(TEqualityComparer<T>)` (inheritance, genuine) plus `TEqualityComparer<T>`'s method body constructing a `TDelegatedEqualityComparerEvents<T>` (materialisation-time) is rtl-generics' shape, and it is now rung 6's wall in BOTH units. FPC compiles the 22-line repro and prints 7."
owner: frankA
---

# Mutually referencing generics are rejected as circular

- **Track P** (Pascal frontend — generic specialization ordering).
- Found 2026-08-28 by frankA, immediately behind
  [[bug-p-a-generic-class-method-call-is-undefined-inside-another-generics-body]].
- **Pre-existing, not introduced by that fix** — measured both ways, see below.

## Repro (22 lines; FPC prints `7`, pxx refuses)

```pascal
program cyc;
{$MODE OBJFPC}{$H+}
type
  generic TEq<T> = class
    class function Make: LongInt;
  end;

  generic TDel<T> = class(specialize TEq<T>)   // (1) genuine: inheritance
    class function Val: LongInt;
  end;

class function TEq.Make: LongInt;
begin
  Result := (specialize TDel<T>).Val;          // (2) inside a METHOD BODY
end;

class function TDel.Val: LongInt;
begin
  Result := 7;
end;

type TE1 = specialize TEq<LongInt>;
begin
  WriteLn(TE1.Make);
end.
```

```
pascal26:22: error: circular generic specialization: TDel$LongInt requires
             TEq$LongInt, which requires TDel$LongInt back
```

Reproduces identically in `{$MODE DELPHI}`.

## The two references are not the same kind, and that is the whole bug

| # | reference | when it must exist | our treatment |
| --- | --- | --- | --- |
| 1 | `TDel<T>` inherits `TEq<T>` | **declaration** time — you cannot declare the class without its parent | blocking prerequisite — correct |
| 2 | `TEq<T>`'s method body constructs `TDel<T>` | **materialisation** time — when that method is compiled, which is after both classes are declared | blocking prerequisite — **wrong** |

`ParseSpecialization` collects prerequisites from the class body *and* every
method body, and treats them all as things that must be declared BEFORE this
alias. For (2) that is stronger than the language requires, and it manufactures a
cycle out of a program that has none. FPC has no trouble: it specializes on
demand and memoises, so the back-reference resolves when the method is compiled.

**The cycle detector itself is right and must stay.** A genuine cycle exists —
`test/test_generic_cycle_fail.pas` asserts it (`TP$string$Integer` requires
`TP$Integer$string` requires back) and that test must keep failing. This ticket
is not "delete the check"; it is "stop counting a materialisation-time reference
as a declaration-time one".

## Why the method-body scan cannot simply be dropped

The obvious move — go back to scanning only the class body — is wrong and would
reopen a ticket that is already closed. Method-body prerequisites are **needed**:
rtl-generics' dominant comparer idiom lives in a class-constructor body and
nowhere else, and not scanning it is exactly what
[[bug-p-a-generic-class-method-call-is-undefined-inside-another-generics-body]]
fixed. So both are required; what is missing is the *distinction* between
"must be declared first" and "must exist by the time this method is streamed".

**Direction, not a diagnosis** (unmeasured, do not treat as settled): a
method-body prerequisite could be emitted without *deferring* the declaration
that found it — the alias needs to exist before the method is materialised, and
methods are materialised after the type section (`FlushPendingClassSpecializations`).
If that holds, the deferral/cycle machinery would only ever see genuine
declaration-time edges, and the cycle detector would go back to catching only
real cycles. That needs measuring before it is believed.

## Pre-existing, measured in both directions

Worth stating precisely, because this surfaced in the same session that changed
the neighbouring code and the timing invites the wrong conclusion:

| compiler | result on the repro above |
| --- | --- |
| `pinned` | `undefined variable (specialize)` at the method body — cannot get far enough to have an opinion (that is the older, already-fixed defect) |
| this tree **before** the wall-6 fix (rebuilt with it stashed) | **the identical circular error** |
| this tree **after** | the identical circular error |

The wall-6 fix therefore did not introduce this: it made mode Delphi reach the
same wall the objfpc path was already standing at, which is what that fix was
for. The corpus's apparent regression is the same story — `generics.defaults.pas`
now stops at `:994` rather than `:3231`, which is EARLIER in the file but a
truer error: before, a prerequisite was silently never discovered.

## Corpus impact — this is rung 6's wall in both units now

`generics.defaults.pas:994`, reached via the real shape at `:785`
(`TDelegatedEqualityComparerEvents<T> = class(TEqualityComparer<T>)`) and
`:2644` (`Result := TDelegatedEqualityComparerEvents<T>.Create(...)`, inside a
method body). `generics.collections.pas` `uses Generics.Defaults`, so it dies at
the same line without reaching any of its own — as it did behind the previous
wall. Rung 6 is behind this one defect in both units.

## Resolved 2026-08-28 (frankA)

**The distinction needed no new state, and that is what kept this in Track P.**

frank-coordinator's hypothesis was that the two edge kinds arrive from two
different scans, so the kind is known at the moment the edge is recorded and can
be tagged at insertion rather than recovered later. That is correct, and it goes
one better: the scans already run **class body first, method bodies after**, so
the kind is encoded in the *insertion order* and the boundary is a single index.

```pascal
ScanRangeForNestedSpecs(Templates[ti].TokStart, Templates[ti].TokCount, specName);
nDeclEdges := NSpecCount;        { everything below this came from the CLASS BODY }
for gmScan := 0 to GenericMethodCount - 1 do ...
```

That mattered practically, not just aesthetically: the `NSpec*` arrays live in
`compiler/defs.inc`, which is **Track A's shared ground**, and frank-optimize-b4
is live in that area. A per-edge flag would have needed a parallel array there
and tripped the escape condition. Looking for the fact already present — the
question the wall-6 fix had just rewarded — is what made this a P-only change.

**The fix.** A materialisation-time-only prerequisite set (`nDeclEdges = 0`) is
**emitted but not deferred**: this specialization registers now, and the
prerequisite declarations go in at `TokPos`, parsed straight after it and well
before `FlushPendingClassSpecializations` streams any method that needs them.

Deferring was the actual bug. It re-emits this declaration *behind* its
prerequisites, so on the re-parse the method-body reference is still undeclared —
it now sits after this declaration in the stream — the scan finds it again,
defers again, and the round counter eventually calls it a cycle. Two
specializations each waiting for the other to be declared first, when only one of
them ever needed to be.

### The control, run before and after

`test/test_generic_cycle_fail.pas` asserts a GENUINE cycle. Confirmed **failing
before** the change (a control is not a control until it has fired) and still
failing after. Both edges of a real cycle are declaration-time, so `nDeclEdges >
0` on at least one side and the deferral path still runs. The two tests are a
pair: turning the new one green by disabling the detector turns that one red.

### Verification

- New test `test/test_generic_mutual_reference.pas`, FPC-oracled (`7`). Fails on
  this tree with the change stashed — *the exact `circular generic
  specialization` error* — and matches FPC after. Wired into the Makefile beside
  its control.
- Five other Delphi/generic tests named individually still pass, including
  `test_generic_nested_specialize_in_method_body` — the comparer idiom that
  *requires* method-body prerequisites to be found. They are still found; they
  are simply no longer treated as blocking.
- Corpus: `generics.defaults.pas` **`:994` → `:3250`**, past the false
  circularity — 2256 lines.

### Two repros that were the wrong shape, recorded so they are not re-tried

My first two attempts at a minimal case failed for reasons unrelated to this
defect, and both would have read as "the fix does not work":

- `(specialize TDel<T>).Val` — a **parenthesised class reference**. Unsupported
  generally, not a generics matter at all: plain `(TFoo).Val` fails identically
  on `pinned`. Separate pre-existing gap.
- `type TD = specialize TDel<T>;` as a **method-local type section** — also not
  parsed.

The working shape is a `var` of the specialized type, which is one of the five
positions the rewrite's fixed-point comment already names.

## Still open behind this: the prerequisite is emitted before the referenced template exists

`generics.defaults.pas` now stops at **`:3250`**, and it is the same ordering
family rather than a return of this one. Measured:

| | line |
| --- | --- |
| `TGStringComparer<T, THashFactory>` declared | ~985 |
| `TGOrdinalStringComparer<T, THashFactory>` declared | **1002** |
| `TGStringComparer.Ordinal`'s body references it | 3250 |

The rewrite emits a template's alias declaration **right behind that template's
own declaration**, so `TGStringComparer`'s alias — and therefore the
materialisation-time prerequisite this fix now emits with it — lands at ~985,
*before* the referenced template exists at 1002. `undefined variable
(specialize)` follows.

Minimal case (Delphi, FPC prints 7, we do not):

```pascal
type
  TEq<T> = class class function Make: LongInt; end;
  TDel<T> = class(TEq<T>) class function Val: LongInt; end;   // declared LATER
class function TEq<T>.Make: LongInt;
begin
  Result := TDel<T>.Val;        // referenced from a template declared EARLIER
end;
```

**Direction (unmeasured):** emit materialisation-time prerequisites at the END of
the type section rather than immediately after the referencing template, since by
then every template in the section is declared. `FlushPendingClassSpecializations`
already runs at exactly that boundary and is the obvious place to look. Filed
separately rather than folded in here — this ticket's defect (a false cycle) is
fixed and tested, and that one is a different question about placement.

## Log
- 2026-08-28 — resolved, commit 8b7f79470.
