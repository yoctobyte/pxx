---
slug: bug-p-tobject-root-methods-are-invisible-inside-a-unit
title: "`Equals` / `GetHashCode` / `ToString` resolve in a program but not in a unit"
track: P
prio: 45
type: bug
blocked-by: []
status: done
owner: claude-A
created: 2026-08-25
summary: "TObject's three root methods are synthesised on demand by a pre-scan that only ran over the MAIN program's token range, so `obj.ToString` compiled at top level and failed with `unknown method` from inside a `uses`d unit. FIXED this session; ticket filed for the record with the regression test."
---

# Symptom

```pascal
unit rootmethunit;
interface
type TThing = class public Tag: Integer; end;
function Describe(t: TThing): string;
implementation
function Describe(t: TThing): string;
begin Describe := t.ToString; end;   { <-- unknown method 'ToString' }
end.
```

The identical expression in the main program's body compiles and runs.

# Root cause

`EnsureTObjectRootMethods` materialises `Equals`, `GetHashCode` and `ToString`
into the root VMT lazily — a program is only charged for them if it names one.
The trigger was a token pre-scan for `.equals` / `.gethashcode` / `.tostring`
that ran over the **main program's** token range only. A unit's tokens are
parsed in `ParseUsesUnitBody`, which had no such scan, so by the time the unit's
implementation referenced the method the root VMT had no slot for it — and
whether the program later mentioned `ToString` did not help, because the unit is
parsed first.

Same family as [[bug-p-a-class-const-cannot-take-the-address-of-a-sibling-class-const]]:
a facility that works at top level and is missing on the unit path.

# Fix (landed 2026-08-25)

`ParseUsesUnitBody` (`compiler/pasparser_proc.inc`) gained the same pre-scan over
the unit's own token range, guarded by `RootVMTSlotCount > 0`; on a hit it pulls
in `builtin` via `ParseUsesUnitAmbient` and calls `EnsureTObjectRootMethods`.
Suppressed under `NoDefaultRtl` and for ESP class targets, as at top level.
`EnsureTObjectRootMethods` needed a forward in `compiler/pasparser_name.inc`.

Regression test `test/test_tobject_root_methods_inside_a_unit.pas` +
`test/tobject_units/rootmethunit.pas`, `.expected` taken from fpc 3.2.2.

# Where it was found

Driving `uses generics.defaults` for [[feature-pascal-corpus-generics]] — the wall
at line 1569, after the class-const `@` fix moved it up from 411.

## Log
- 2026-08-25 — resolved, commit bd50e76ed.
