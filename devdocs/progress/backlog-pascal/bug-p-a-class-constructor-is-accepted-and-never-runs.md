---
slug: bug-p-a-class-constructor-is-accepted-and-never-runs
track: P
type: bug
prio: 55
status: backlog
created: 2026-09-06
found-by: frankB
owner: ""
blocked-by: []
title: "`class constructor` compiles, never runs, and cannot be called — class-level state stays at zero with no diagnostic"
summary: "MEASURED 2026-09-06 at 40c0d6491, compiler b85745ae61a3, against fpc 3.2.2 -Mobjfpc. `class constructor TC.Init` that sets `class var N := 5` compiles here and NEVER RUNS: pxx prints N=0 before and after `TC.Create`, fpc prints `class ctor ran` and N=5 both times. WARNED SINCE PENDING-COMMIT, still not run -- both member-loop termini now say so by name; before that there was no diagnostic at any point. The declaration is accepted, the body compiles, and the routine is unreachable: an explicit `TC.Init;` is refused with `expected ':=' before ';'`, so it is dead code the programmer cannot even call by hand. `class destructor` is the same shape. CAUSE IS THE CLASS-BODY LOOKAHEAD ENUMERATION: the `class X` arm tests tkProcedure and tkFunction only, so `class constructor` falls past all four arms to the member-loop terminus, which steps over the `class` and lets the ORDINARY constructor arm take it -- the class-ness is discarded and the resulting ctor is never wired to anything. Sibling of bug-p-the-class-body-class-opener-is-a-hand-maintained-lookahead-list and the concrete cost of it: THAT ticket's measurement said the accident produced no wrong answer, which was measured over generic methods only and is false here. A program that initialises class state in a class constructor runs with it uninitialised."
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

## The interim that neither arm is: WARN (landed PENDING-COMMIT)

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
