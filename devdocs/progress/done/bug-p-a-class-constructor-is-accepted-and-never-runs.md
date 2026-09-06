---
slug: bug-p-a-class-constructor-is-accepted-and-never-runs
track: P
type: bug
prio: 55
status: done
created: 2026-09-06
found-by: frankB
owner: ""
blocked-by: []
title: "`class constructor` compiles, never runs, and cannot be called — class-level state stays at zero with no diagnostic"
summary: "FIXED 2026-09-06 by IMPLEMENTING (arm 2), not by refusing. ORIGINAL REPORT: MEASURED 2026-09-06 at 40c0d6491, compiler b85745ae61a3, against fpc 3.2.2 -Mobjfpc. `class constructor TC.Init` that sets `class var N := 5` compiles here and NEVER RUNS: pxx prints N=0 before and after `TC.Create`, fpc prints `class ctor ran` and N=5 both times. WARNED SINCE d754eeef1, still not run -- both member-loop termini now say so by name; before that there was no diagnostic at any point. The declaration is accepted, the body compiles, and the routine is unreachable: an explicit `TC.Init;` is refused with `expected ':=' before ';'`, so it is dead code the programmer cannot even call by hand. `class destructor` is the same shape. CAUSE IS THE CLASS-BODY LOOKAHEAD ENUMERATION: the `class X` arm tests tkProcedure and tkFunction only, so `class constructor` falls past all four arms to the member-loop terminus, which steps over the `class` and lets the ORDINARY constructor arm take it -- the class-ness is discarded and the resulting ctor is never wired to anything. Sibling of bug-p-the-class-body-class-opener-is-a-hand-maintained-lookahead-list and the concrete cost of it: THAT ticket's measurement said the accident produced no wrong answer, which was measured over generic methods only and is false here. A program that initialises class state in a class constructor runs with it uninitialised."
---

# `class constructor` is accepted and never runs

```pascal
type TC = class
  class var N: Integer;
  class constructor Init;
  class destructor Done;
end;
class constructor TC.Init; begin WriteLn('class ctor ran'); TC.N := 5; end;
class destructor TC.Done; begin WriteLn('class dtor ran'); end;
```

| | pxx | fpc 3.2.2 |
| --- | --- | --- |
| before any use | `start, N=0` | `class ctor ran` then `start, N=5` |
| after `TC.Create` | `N=0` | `N=5` |
| explicit `TC.Init;` | `expected ':=' before ';'` | (not needed) |

**Accepted, unreachable, and — until the warning below — silent.** The body is
compiled and nothing can call it.

## Cause

`pasparser_decl.inc`'s class-body member loop recognises `class X` through four
hand-maintained arms — `class const`, `class var`, `class property`, and
`class procedure`/`class function`. **`constructor` and `destructor` are not in
that list**, so `class constructor` falls past all four to the member-loop
terminus, which steps over the `class` keyword; the next iteration sees a bare
`constructor` and the ordinary constructor arm takes it. The class-ness is
discarded, and FPC's semantics for the construct — run once, automatically,
before the class is first used — are never attached to anything.

This is the enumeration in
[[bug-p-the-class-body-class-opener-is-a-hand-maintained-lookahead-list]]
producing a live wrong answer, which is exactly what that ticket's own
measurement said it was not currently doing. That measurement was over generic
METHODS and did not reach constructors.

## The disposition question, which is a fork and not a detail

FPC runs a class constructor once before first use of the class, which needs
initialisation ordering this compiler does not have today. So there are two
landing points and they are not the same size:

1. **Refuse it.** Small, and converts a silent wrong answer into a loud
   refusal — this repo's own preference elsewhere. It breaks programs that
   compile today, all of which are currently running with uninitialised class
   state, so the breakage reveals a defect rather than creating one.
2. **Implement it.** Correct, and needs a once-per-class init hook ordered
   before first use, plus the `class destructor` counterpart at shutdown.

Recommendation: (1) now and (2) ranked separately, so no program keeps silently
skipping its class initialiser while (2) waits. **Not done unilaterally** —
removing a construct people write is worth stating rather than deciding inside
a bug fix.

**Who may take (1): anyone on Track P, without asking.** It is reversible — one
revert restores today's behaviour — and CLAUDE.md's test is reversibility, not
importance. The reason it was not taken here is evidence, not permission: see
the interim below.

## The interim that neither arm is: WARN (landed d754eeef1)

Both member-loop termini in `pasparser_decl.inc` — the class body and the
record body — now emit

```
warning: class constructor/destructor is parsed but NEVER RUNS here
 -- class-level state it sets stays at its zero value
 (bug-p-a-class-constructor-is-accepted-and-never-runs)
```

**Warned rather than refused, deliberately, and the corpus is why.** Refusing
globally would reject `terecs_u1.pp` — a `{$mode delphi}` record with
`class constructor Create` and `class destructor Destroy` that fpc compiles.
That is valid Delphi somebody MEANT to write, so it is compat, not a mistake to
make visible. But accepting in SILENCE is the worse half: class-level state
stays at its zero value and the program runs on it. A warning keeps the code
compiling and stops the failure being silent, which is all the interim has to
do. So arm (1), if taken, wants the narrowing this measured: refuse where the
class-ness is the whole of the programmer's intent, not everywhere the spelling
appears.

In-tree usages of `class constructor`/`class destructor`: **zero real** (the one
grep hit is prose in a comment in
`test/test_generic_nested_specialize_in_method_body.pas`), so nothing in this
repo becomes noisy.

## Done when

The program above either runs the class constructor (matching fpc) or is
refused by name, `class destructor` is handled the same way, and
`class procedure`/`class function` still work.

## Resolution (2026-09-06) — arm (2), implemented, not arm (1)

**The fork closed by disappearing.** The ticket recommended refusing now and
implementing later, on the reading that implementing needed initialisation
ordering this compiler does not have. It has it: `InitProcs[]`/`FiniProcs[]`,
the list a unit's `initialization` section joins, called from
`pasparser_prog.inc` in dependency order before the program body. Refusing would
have removed a construct people write, in order to defer work that turned out to
be three arms and a registration.

**Two halves, and the first alone is not the fix.**

1. Each member loop gains an opener for `class` + `constructor`/`destructor`.
   The class body's is beside the `class procedure` arm; the record body's is
   beside its own. Both register a **static class method and not a
   constructor** — `UMthIsCtor` drives instance allocation, which this must
   never do — so the name resolves like any `class procedure`.
2. `ParseSubroutine` captures the keyword after `class` (it is an IDENT, and the
   `Next` below consumes it whatever it is, so that is the only point where the
   spelling still exists) and registers the finished body in `InitProcs[]` or
   `FiniProcs[]`.

**On FPC's "before first USE".** That is finer than "before the program body",
and the two differ only for a use inside an earlier entry of the same list. The
ordering there is already right: a class constructor's body is parsed in the
implementation section, so it registers **before** its own unit's
`initialization` — the one place a use could plausibly beat it. Measured: fpc
also prints the class constructor's output before the program body's first line.

## Two unrelated refusals had to be kept apart from this one

`terecs_u1.pp` — the corpus file the interim warning existed for — is a **record**,
and two pxx rules were catching it: a parameterless record CONSTRUCTOR is refused
(a record always exists, so a no-argument ctor is indistinguishable from its
default state, terecs17), and a record's class METHODS must be declared `static`.
A `class constructor` is neither. Both rules now exempt it. `RecordMethodClassPrefix`
is True only for a `class X` spelling, so the pair identifies it exactly and no
second flag was needed.

## The interim warning is DELETED, not kept

It said `NEVER RUNS`. That is now false, and a false diagnostic is worse than
none. Its negative control asserted the compile log did **not** contain that
string — a guard that can no longer fail — so it was repurposed to assert that
every other `class X` opener still does its job.

## What this does NOT fix, and the ticket it strengthens

**The list is still a list.** This adds a fifth arm to
[[bug-p-the-class-body-class-opener-is-a-hand-maintained-lookahead-list]]'s
enumeration rather than replacing it with a structural opener. That ticket's
argument is stronger for it, not weaker, and it is now unblocked. Said here
rather than closed over.

## A measured divergence, recorded and not chased

**fpc 3.2.2 does not run a `class destructor` at all** — measured in both shapes,
the class in the program and the class in a unit. pxx runs it at exit from
`FiniProcs[]`, which is what the source says should happen and what Delphi
documents. Neither fixture asserts it, so both stay byte-comparable with fpc.

## Fixtures

`test_a_class_constructor_runs_once_before_the_program_body.pas`
(`CLASSCTORRUNS OK`) and `test_a_record_class_constructor_runs_before_the_program_body.pas`
(`RECCLASSCTORRUNS OK`), both byte-identical under fpc 3.2.2, plus
`test_every_other_class_opener_is_unaffected_by_the_class_constructor_arm.pas`
(`CLASSOPENERS OK`).

**ORDER IS THE CLAIM, NOT THE VALUE.** `N=5 by the time main runs` would also be
true of a class constructor called by hand from main's first line, so each
fixture accumulates a TRACE whose first entry must be the constructor's and whose
second is main's own first act.

**No row calls it by hand.** `TC.Init;` resolves now — that it did not was the
ticket's own evidence of brokenness — but fpc refuses the explicit call
(`identifier idents no member "Init"`) and so does Delphi, so asserting it would
have made the file uncomparable for the sake of an extension nobody asked for.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit d349b85ef.
