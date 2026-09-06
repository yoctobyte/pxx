---
track: P
prio: 65
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-09-06
summary: "`{$define X}` written in one unit is still defined while pxx compiles the units that unit USES. FPC scopes conditional symbols to the unit that defines them (only `-d` on the command line is global), so a used unit compiled from a defining parent takes DIFFERENT ARMS under pxx than under FPC. REDUCED TO SIX LINES AND MEASURED BOTH WAYS: unit `ua` does `{$define LEAKED}` then `uses ub`; ub's body is `{$ifdef LEAKED} 'LEAKED-IS-DEFINED' {$else} 'not-defined' {$endif}`. fpc 3.2.2 -Mobjfpc prints `not-defined`, pxx prints `LEAKED-IS-DEFINED`. IT DOES NOT ERROR — it silently selects the other arm, so the failure mode is a used unit compiled with a different interface, different field set or different types from the one FPC would build, and the diagnostic (if any) lands somewhere else entirely. Real code relies on the scoping: fcl-passrc's pparser.pp defines UsePChar, UseAnsiStrings, HasStreams and HasFS and then uses pscanner, which has its own `{$ifdef HasStreams}` and `{$ifdef UsePChar}` arms meaning different things. Found while walking rung 7; NOT established as the cause of any current corpus wall — the reduction is the finding."
---

# A unit's {$define} leaks into the units it uses

- **Type:** bug (silent wrong arm, no diagnostic) — **Track P**
  (conditional handling; `compiler/paslexer.inc` / `compiler/lexer.inc`).

## The reduction, both compilers

```pascal
unit ua;            unit ub;
{$define LEAKED}    interface function Which: string;
interface           implementation
uses ub;            function Which: string;
                    begin
                    {$ifdef LEAKED} Which := 'LEAKED-IS-DEFINED';
                    {$else}         Which := 'not-defined';
                    {$endif}
                    end;
```

    fpc: via ua: not-defined
    pxx: via ua: LEAKED-IS-DEFINED

FPC resets conditional symbols per unit; only `-d` symbols are global. **pxx
carries one table across the whole compilation**, so whether a used unit sees a
symbol depends on who compiled it first and in what order.

## Why this is worse than a wrong answer

It does not error. It picks the other arm — so the used unit is built with a
different interface, a different field set, or different types than FPC would
build, and every later diagnostic is about the consequence. That is the
same shape as the enumerated-predicate family: **the observable is somewhere
other than the cause.** Compilation ORDER is also now semantically significant,
which it is not in FPC, so the same unit can compile differently depending on
which program pulls it in.

## What has NOT been established

Nothing beyond the reduction. It was found while walking fcl-passrc rung 7,
where `pparser.pp` defines four symbols that `pscanner.pp` also tests — but
leaking those four into a driver that uses `pscanner` was measured NOT to
reproduce any current corpus wall, so **do not close this against a corpus
green.** The reduction is the specification; a fix needs a per-unit save and
restore around a used unit's compilation, and a test that asserts the arm taken
in BOTH directions (a symbol defined in the parent and absent in the child, and
one defined in the child and absent in the parent afterwards).

## Gate

Assert a VALUE from each arm, in both directions, and include the reverse leak:
a symbol defined inside `ub` must not still be defined in `ua` after the `uses`.
A one-directional test passes on a fix that clears the table instead of saving
and restoring it.
