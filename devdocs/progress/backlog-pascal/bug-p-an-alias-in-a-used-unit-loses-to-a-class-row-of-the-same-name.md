---
track: P
prio: 45
type: bug
---

# An alias in a used unit loses to a same-named class row from another unit

The remaining half of
[[bug-p-a-unit-redeclaring-a-builtin-interface-alias-types-it-as-a-record]].
That one fixed alias-vs-alias and alias-vs-class *at the current scope*. This
is alias-in-a-used-unit vs a class row somewhere else, and it is unfixed.

## Repro, measured at compiler `4bfd73d70588`

```pascal
unit u_f;
{$mode objfpc}
interface
type
  IMine = interface ['{00000000-0000-0000-C000-000000000049}'] end;
  IInterface = IMine;          { alias name collides with builtinheap's CLASS row }
implementation
end.
```
```pascal
{$mode objfpc}
program p_f; uses u_f;
procedure Take(a: IMine); begin end;
var v: IInterface;
begin Take(v); end.
{ pascal26:5: error: no overload of Take matches these arguments
    argument types: (record)      candidates: Take(record) }
```

`v` binds to builtinheap's `IInterface`, not to `u_f`'s alias.

## Why the sibling fix does not reach it

`FindUClass` scans the `UCls` rows to completion — current unit first, then
ranked by `UsesRankOf` — and consults the alias table only when that scan finds
NOTHING. builtinheap has a real `IInterface` class row, so the scan always
succeeds and the alias is never reached. The sibling fix added a current-scope
alias check before the ranked scan, which is why the same shape written in the
PROGRAM works today; it cannot help a unit's alias, because that one has to be
ranked against foreign class rows rather than preferred outright.

**So the fix is to rank the two tables TOGETHER** — one scan over class rows and
alias rows with a shared `UsesRankOf` comparison — not another preference arm.
Deliberately not done in the sibling: it changes name resolution for every
alias in the compiler, and that is not a change to land unmeasured hours before
a pin.

## Scope

Not what test-fpjson hits. `lib/rtl/classes.pas` *declares* `IInterface` (a
class row) and *aliases* `IUnknown`, so it takes the alias-vs-alias path that
is now fixed. This shape needs a unit to alias a name that some other unit
declares as a real class — reachable, and unreported so far.

The guard is in
`test/test_a_redeclared_interface_alias_resolves_in_its_own_scope.pas`, which
names this ticket in its header and says it does NOT cover this cell, so the
file cannot be read as covering the family.
