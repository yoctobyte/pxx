---
slug: bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface
title: "A unit cycle closed through an `implementation` uses clause cannot see the other unit's interface"
track: P
prio: 70
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
**This is the FIRST failure of 144 of the 207 units** in `fpc-trunk/compiler`
(re-measured 2026-09-09 with `tools/fpc_compiler_corpus_probe.sh`, fpc as the
oracle; the figure this ticket was filed with, 25 of 162, was a grep over
DIRECT cycles and undercounted the ones reached transitively). fpc 3.2.2
compiles and runs the repro. Pre-existing: pin v399 gives the identical error,
so it is not a recent regression.

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

## The guard, read rather than guessed (2026-09-09, second pass)

The hypothesis this ticket was filed with is **confirmed, and the guard has a
line**. `ParseUsesUnitBody` (`compiler/pasparser_proc.inc`) marks a unit
compiled **BEFORE it parses it**:

```pascal
  isCompiled := False;
  for i := 0 to CompiledUnitCount - 1 do
    if CompiledUnitKey[i] = guardIdx then isCompiled := True;
  if isCompiled then ... Exit;          { ~:5700 }
  ...
  CompiledUnits[CompiledUnitCount] := strIdx;    { ~:5742, then the parse }
```

So in the repro the order is: `ua` marked → `ua`'s interface `uses ub` → `ub`
marked → `ub`'s implementation `uses ua` → `ua` is already marked → `Exit`. The
guard is doing the only thing it can: `ua`'s `var hookproc` is declared AFTER
its own `uses ub`, so at that instant the symbol genuinely does not exist yet.
**Nothing is being hidden — it has not been parsed.**

That is why this is not a lookup fix. What makes the cycle legal in FPC is
ORDER: every interface is complete before any implementation is parsed. The
narrow version of that here is to defer a unit's IMPLEMENTATION SECTION when its
implementation `uses` names a unit currently in progress, and replay it once the
load chain unwinds — the state a replay needs (unit index, defines, per-file
directives, modes) is already snapshotted around this call, so the machinery is
half there. **It is still a loader change that affects every program, not only
cyclic ones, and it should be treated as multi-session work rather than a fix
to slip into a session doing something else.**

## Scale, re-measured 2026-09-09 over the WHOLE corpus

Filed on `25 of 162 units` from a grep. The differential probe
(`tools/fpc_compiler_corpus_probe.sh`, fpc as the oracle, FPC's own build flags)
says **144 of 207 units of FPC's compiler stop here as their first failure —
77%**, against 19 for the second-largest cause. The grep undercounted because it
saw only DIRECT cycles; the walls include units that reach one transitively.

## Why prio 70 (was 60 when filed)

Not from the backlog's ranking but from the corpus, and the corpus has since
been measured properly: **144 of 207 units, 77%**, where the filing number was
25 of 162 from a grep over direct cycles. It is the first thing in the way of
the umbrella and nothing behind it can be measured until it moves.

## Adjacent, not filed separately

`{$PACKSET}` warns *"recognised but not implemented"* twice on the same attempt
(`cutils.pas:17`). Noted here because it appeared in the same run; it did not
stop the compile and it is a different mechanism.
