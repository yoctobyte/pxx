---
slug: bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface
title: "A unit cycle closed through an `implementation` uses clause cannot see the other unit's interface"
track: P
prio: 60
type: bug
status: open
owner: ""
found-by: frankH
created: 2026-09-09
tags: [units, uses, scope, fpc-corpus]
blocked-by: []
---

# A unit cycle through `implementation uses` sees no interface

**Summary.** `unit A` whose INTERFACE uses `B`, and `unit B` whose
IMPLEMENTATION uses `A`, is the legal and standard form of mutual unit
recursion — it is the entire reason Pascal splits `uses` into two clauses. pxx
refuses it: `B`'s implementation cannot see anything from `A`'s interface.
**This is the FIRST failure compiling FPC's own compiler source**, and it is not
an edge case there — **25 of 162 units** in `fpc-trunk/compiler` close such a
cycle. fpc 3.2.2 compiles and runs the repro. Pre-existing: pin v399 gives the
identical error, so it is not a recent regression.

- **Umbrella:** `umbrella-pxx-compiles-fpc-itself`
- **FPC unit and line:** the attempt was `uses cutils`, and the first error is
  `/home/neo/src/fpc-trunk/compiler/constexp.pas:164`,
  `internalerrorproc(200706091)`. The cycle is `cutils` (interface `uses
  constexp`) ↔ `constexp` (implementation `uses cutils`), and
  `internalerrorproc` is declared in `cutils`'s interface at `cutils.pas:39`.

## Minimal repro — 8 + 9 + 4 lines, reduced from the above

```pascal
{ ua.pas }
unit ua;
interface
uses ub;
var hookproc : procedure(i: LongInt);
implementation
procedure defaulthook(i: LongInt); begin WriteLn('hook ', i); end;
begin hookproc := @defaulthook; end.

{ ub.pas }
unit ub;
interface
function BCall(x: LongInt): LongInt;
implementation
uses ua;                       { <- the cycle }
function BCall(x: LongInt): LongInt;
begin hookproc(x); BCall := x + 1; end;   { ua.pas:8: undefined variable (hookproc) }
end.
```

    pxx : pascal26:8: error: undefined variable (hookproc)
    fpc : compiles; prints `hook 7` then `bcall=8`

## The shape was varied, and the cycle is the whole condition

Removing the cycle — `ua` no longer uses `ub`, everything else identical —
**compiles and runs correctly**. So this is not "implementation-uses is
unsupported"; implementation-uses works. It is specifically a cycle *closed*
through one.

## Hypothesis, not a diagnosis

`ParseUsesUnit` (`compiler/pasparser_proc.inc`, around the
`savedCurrentUnitIdx` save at :6165) loads a used unit **fully — interface and
implementation — in one recursive pass**. So when `B`'s implementation reaches
back to `A`, `A` is mid-parse: its interface section has been entered but not
finished, and whatever already-registered guard stops the recursion also stops
the symbols arriving. FPC's model parses **every interface first** and only then
the implementations, which is what makes the cycle legal.

Not verified — the person who takes this should confirm it against the actual
guard rather than inherit it from here.

## Why prio 60

Not from the backlog's ranking but from the corpus: 25 direct
interface↔implementation cycles among 162 units of FPC's compiler, so this is
structural in real Object Pascal rather than incidental. It is the first thing
in the way of the umbrella and nothing behind it can be measured until it moves.

## Adjacent, not filed separately

`{$PACKSET}` warns *"recognised but not implemented"* twice on the same attempt
(`cutils.pas:17`). Noted here because it appeared in the same run; it did not
stop the compile and it is a different mechanism.
