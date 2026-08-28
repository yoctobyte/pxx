---
slug: bug-p-mutually-referencing-generics-are-rejected-as-circular
track: P
prio: 60
type: bug
status: backlog
blocked-by: []
summary: "Two generics that reference each other are refused with `circular generic specialization`, but only one direction is a real declaration-time dependency: the other is a reference from inside a METHOD BODY, which FPC resolves when the method is compiled. `TDelegatedEqualityComparerEvents<T> = class(TEqualityComparer<T>)` (inheritance, genuine) plus `TEqualityComparer<T>`'s method body constructing a `TDelegatedEqualityComparerEvents<T>` (materialisation-time) is rtl-generics' shape, and it is now rung 6's wall in BOTH units. FPC compiles the 22-line repro and prints 7."
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
