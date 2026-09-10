---
slug: bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface
title: "A unit cycle closed through an `implementation` uses clause cannot see the other unit's interface"
track: P
prio: 70
type: bug
status: done
owner: ""
found-by: frankH
created: 2026-09-09
tags: [units, uses, scope, fpc-corpus]
blocked-by: []
summary: "FIXED 2026-09-10, d52831ed7 + 6e8a821db. `unit A` whose INTERFACE uses B and `unit B` whose IMPLEMENTATION uses A -- the legal, standard form of mutual unit recursion -- was refused, and it was the FIRST failure of 158 of the 207 units of FPC's own compiler, 76%. The guard was never hiding anything: a unit is marked compiled BEFORE it is parsed, so A's declarations genuinely did not exist yet. What makes the cycle legal in FPC is ORDER, so B's implementation section now PARKS and is replayed at A's `implementation` keyword. Corpus re-run per unit: those 158 move to `bitsizeof` and nothing else moves; NO UNIT NEWLY COMPILES, because the next wall was immediately behind this one. Two claims of mine were taken back by their own controls -- the outermost-unit rule is a cost rule and not a correctness one, and a never-replayed park is loud rather than silent except for a routine-less interface."
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

## Resolved 2026-09-10 — the implementation section PARKS and is replayed

`d52831ed7` (the mechanism), `6e8a821db` (the outermost rule and the table).
Fixture: `test/test_p_a_unit_cycle_through_an_implementation_uses.pas` with
`ucycle_a/b/c`, wired in the Makefile, byte-identical to fpc 3.2.2 on all five
rows.

**This ticket's own second pass had the diagnosis right and it is worth
restating as the reason no lookup change would have worked:** the guard was
never hiding anything, it had not read the file yet. `ParseUsesUnitBody` marks
a unit compiled BEFORE parsing it, so on reaching `B`'s implementation
`uses A` the loader correctly answers "already in hand" and exits — and at that
instant `A`'s interface has been read only as far as its own `uses B`, so
`A`'s declarations genuinely do not exist. What makes the cycle legal in FPC is
ORDER, so order is what was restored.

`B`'s implementation section **parks** and is replayed at `A`'s
`implementation` keyword: the narrowest point at which every name `B` needs
exists, and the one that leaves the source's own implementation ordering alone.
A cycle closed through two INTERFACES is deliberately not parked — illegal in
FPC too, no order satisfies it, and a park that can never drain is worse than
the error.

Three rows asked for on purpose (a var, a type, a const): they resolve through
different tables and a fix can reach one and miss the others. `ucycle_a`'s
declarations sit BELOW its own `uses` because hoisting them makes every row
pass while measuring nothing.

### The corpus delta, per unit and not by category arithmetic

Whole probe re-run before (`590e7c100`) and after (`6e8a821db`), fpc as the
oracle, FPC's own build flags.

| | before | after |
| --- | --- | --- |
| units | 207 | 207 |
| **compile under both** | **9** | **9** |
| oracle refuses | 10 | 10 |
| pxx stops | 188 | 188 |

| first failure | before | after |
| --- | --- | --- |
| `undefined variable (internalerrorproc)` — this ticket | **158** | **0** |
| `undefined variable (bitsizeof)` | 5 | **163** |
| everything else, row by row | unchanged | unchanged |

**Exactly 158 units moved and every one of them from this cause to
`bitsizeof`**; a per-unit join says so, and nothing else moved at all. **No unit
newly compiles, and that is the honest headline** — 76% of the corpus was
standing behind this and the next wall was immediately behind it. The unit of
progress here is a wall, not a line number.

### Two claims the measurement took back

Both were mine, both were about the *cost* of getting the wait wrong, and both
are recorded because the corrected version is the useful one.

1. **"Waiting on the innermost open unit quietly does not work for a
   three-unit cycle."** False. The park rewinds to the HEAD of the section, so
   a premature drain re-walks the clause, finds the outer unit still open and
   simply parks AGAIN — on a candidate set smaller by exactly the unit just
   drained on, so it converges. `ucycle_c` passes under both rules. The
   outermost rule stays because the wrong choice costs a table SLOT PER HOP,
   and a full table does not fail loudly: `DefImplPark` declines and hands the
   unit back the pre-fix error. `MAX_DEFERRED_IMPLS` went 32 → 512 and the
   table now compacts when nothing is outstanding.
2. **"A never-replayed park is silent."** Mostly false, and the control said
   so: forcing an undrainable wait makes the fixture fail on `unresolved
   forward`, an existing and loud guard. It is silent only for a unit whose
   interface declares no routines — a const-only interface with an
   `initialization` body — so that is the shape the new guard in
   `compiler.pas` was proven against, and it names the unit.
