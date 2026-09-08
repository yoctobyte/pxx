---
track: P
prio: 45
type: bug
status: done
owner: frankS
summary: "FIXED 2026-09-08. FindUClass scanned the CLASS rows to completion and asked the alias table only when that scan found NOTHING, so an alias in a used unit was unreachable while ANY unit anywhere declared a real class of the name. Fixed as the ticket prescribed -- the alias rows now rank in the SAME scan by UsesRankOf, strictly greater so a tie keeps the class row and the ordinary case moves nothing. Wider than the recorded repro: measured pre-fix, the PROGRAM's own `uses ... , d` clause also resolved to the earliest class row rather than d's alias, so it was not only a used unit that could not be heard. Fixture test_an_alias_in_a_used_unit_ranks_with_the_class_rows.pas, four rows against the fpc 3.2.2 oracle, of which two are controls that a bare `prefer aliases` fix fails: a REVERSED uses clause where the class must win, and a unit's OWN alias which must beat both used units. Pre-fix it answers TShared/TShared/TShared/TOwnAlt against fpc's TOwnAlt/TAlt/TShared/TOwnAlt."
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


## 2026-09-08 — fixed, and the defect was wider than this repro

The remedy is the one this ticket named: **rank the two tables together**, one
scan over class rows and alias rows sharing the `UsesRankOf` comparison. Strictly
greater, so a tie keeps the class row and nothing moves for the ordinary case of
one declaration or for two ambient rows.

**It was not only a used unit that could not be heard.** The fixture's first row
is the PROGRAM's own `uses uclsranka, uclsrankb, uclsrankc, uclsrankd` clause,
whose last entry aliases the name — pre-fix that answered `TShared`, the earliest
class row, where fpc answers `TOwnAlt`. Same cause, and it needed no unit of its
own to appear.

### The two controls are the point

| row | fpc | pre-fix pxx |
| --- | --- | --- |
| `prog` — the program's own clause, ending in an alias | `TOwnAlt` | `TShared` |
| `used-unit-alias` — class earlier, alias later | `TAlt` | `TShared` |
| `reversed` — alias earlier, CLASS later | `TShared` | `TShared` |
| `own` — the unit's own alias beats both | `TOwnAlt` | `TOwnAlt` |

A fix that simply PREFERRED aliases passes rows 1 and 2 and fails row 3. The
sibling fix, which preferred a CURRENT-SCOPE alias outright, passes rows 3 and 4
and cannot reach 1 or 2. Ranking is the only answer that satisfies all four, and
without the two green-before-and-after rows the fixture could not say so.

`ClassName` is the readout because it names WHICH class was bound in one word. A
field access only reports a wrong binding by failing to compile, which cannot be
a row of an output comparison — the shape the original repro had, and why its
diagnostic (`argument types: (record)` against a candidate also printing
`(record)`) told the reader so little.
