---
track: P
prio: 55
type: bug
blocked-by: []
summary: "When two used units export the same identifier, pxx resolves it to the FIRST unit named; FPC resolves it to the LAST. Measured against the FPC oracle 2026-08-14. Backwards from the reference implementation, silent, and it applies to every duplicated name — types, classes, routines, constants — not just the exception case that exposed it."
---

# Uses-clause name collisions resolve first-match; FPC resolves last-match

Found while landing [[feature-a-one-exception-class-in-a-shared-unit]], which
makes `sysutils` and `pylib` each export a class named `Exception` and so
creates the first collision in this repo that anyone looks at closely.

## Measured against the oracle

```pascal
unit ua;                          unit ub;                { identical, returns 'UB' }
{$mode objfpc}{$H+}
interface
type Thing = class function Who: string; end;
implementation
function Thing.Who: string; begin Result := 'UA'; end;
end.
```
```pascal
program m; {$mode objfpc}{$H+}
uses ua, ub;
var t: Thing;
begin t := Thing.Create; WriteLn(t.Who); end.
```

- **FPC:** prints `UB` — the LAST unit in the clause wins.
- **pxx:** resolves `Thing` to `ua`'s class (first registered wins).

FPC's rule is the ordinary one and it is not an accident of implementation: the
uses clause reads as a sequence of scopes opened in order, so a later unit
shadows an earlier one, exactly as a later declaration shadows an earlier one in
any other scope. pxx's first-match inverts that.

## Why it matters beyond exceptions

Nothing about this is specific to classes or to `Exception`. Any name exported
by two used units resolves backwards: a type, a routine, a constant. It is
silent — no diagnostic, no warning — and the symptom is running the wrong body,
which is the failure mode this repo has repeatedly paid the most for.

It has been invisible only because the RTL had no duplicated names worth
noticing. `feature-a-one-exception-class-in-a-shared-unit` is what made one, and
`test_uses_order_pylib_exception_a/_b` deliberately stopped asserting anything
about the BARE name because of this bug — they assert the qualified form
instead, which is now correct. Fixing this is what would let them assert the
bare name too.

## Scope note — this is NOT the qualified-reference bug

Qualified references (`sysutils.Exception`, in both type and constructor
position, including named constructors like `CreateFmt`) were a separate defect
and are FIXED on `feature-a-one-exception-class-in-a-shared-unit`'s branch. This
ticket is only about the UNQUALIFIED name under a collision.

## Where to look

Symbol/class/type registration is append-order and every `Find*` helper scans
forward and returns the first hit (`FindUClass`, `FindSym`, `FindProc` in
`compiler/symtab.inc`). "Last unit wins" means the search must prefer the
most-recently-opened unit scope, which is a resolution-order change in shared
Track A ground — expect it to be a bigger job than the one-line reversal it
sounds like, because plenty of code depends on first-match for names that are
NOT collisions (a unit's own declarations, builtins).

Worth checking whether `--strict-uses` should make a collision a diagnostic
rather than a silent pick, independently of which side wins.

## Gate

The oracle repro above prints `UB` under pxx. `make test` + self-host
byte-identical — this touches name resolution, so the blast radius is the whole
suite rather than one test.
