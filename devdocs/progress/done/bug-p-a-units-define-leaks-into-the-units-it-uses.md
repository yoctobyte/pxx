---
track: P
prio: 65
type: bug
blocked-by: []
status: done
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

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

## Resolution

Fixed by a COMMAND-LINE BASELINE: `PasSnapshotDefineBaseline` freezes the define
table once, after `-d` and the target/frontend defines and before a byte of
source is read; `ParseUsesUnitBody` calls `PasResetDefinesToBaseline` on the way
IN, in addition to the save/restore it already did on the way out. `{$CLAIM}`
survives by construction rather than by a site anyone remembered to patch --
it was deliberately built outside this table for exactly this reason.

**The ticket's title names half of it.** `{$PACKRECORDS}` leaked identically and
that half is worse: a used unit's `record a: Byte; b: LongInt` was FIVE bytes
where fpc builds eight. An ABI, in a unit that never asked, with no `{$ifdef}`
anywhere in it. Found by pointing this ticket's own six-line reduction at the
OTHER unsaved per-file globals -- the existing save list around a used unit
covers `CaseSensitiveMode`, `NestedComments`, `DelphiMode` and `PyExprMode` and
stops there. `{$SCOPEDENUMS}` was probed and did not leak; the rest of that list
(`{$H+}`, `{$ASSERTIONS}`, `{$R+}`, `{$Q+}`, `{$I-}`) is **unprobed and is a
named blank, not a clear.**

## The root source is a DELIBERATE exception, and it is not FPC's rule

A MAIN program's or main unit's defines still reach the units it uses. pxx's own
RTL is configured that way: `{$undef PXX_MANAGED_STRING}` on line 1 of a program
selects the frozen-string model and `compiler/builtin/*.pas` -- units the
compiler appends, that the user never wrote -- read it. Cutting it turned
`test_frozen_string_reentrant.pas` into *"call to a runtime stub that was never
emitted"* inside `builtinheap.pas`, which is what a configuration define
silently losing its effect looks like from the far end. That file is the
positive control for the exception and it is already wired in the QUICK tier.

The defect is UNIT-to-unit, where `uses` ORDER decides the answer. The root is
one source, lexically ordered, and order-independent by construction. Anyone
wanting a genuinely cross-unit symbol has `{$CLAIM}`.

## Gate, as the ticket asked for it

`test/test_a_units_define_and_packing_do_not_reach_the_units_it_uses.pas`,
seven rows, all byte-identical to `fpc 3.2.2 -Mobjfpc -dCLIDEF -Futest/units`.
FOUR directions, because a fix that CLEARS the table instead of saving and
restoring it passes the obvious two: **down** (the bug), **up** (the reverse
leak the ticket asked for), **in** (a `-d` must still reach the child), and
**self** (a unit's own define and its own packing must survive its own `uses`).
The two pre-existing `test_pascal_define_unit_scope_order*` rows cover SIBLINGS
and stay green; this is the parent-to-child direction they could not see.

gate.sh quick GREEN including both lib/rtl rows; the native tier at this tree is
2382/2387 with four reds, none of them this change (`test_libwriteln_parity` and
`test_promoint_bitwise` are older open regressions, and the two generic rows are
`b2a41d5f4fb9`, which does not contain this commit).
