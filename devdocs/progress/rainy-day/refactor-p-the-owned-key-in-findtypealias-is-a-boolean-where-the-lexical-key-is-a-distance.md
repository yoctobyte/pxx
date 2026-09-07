---
prio: 30
track: P
status: open
summary: "FindTypeAlias ranks candidates on three keys in order -- lexical hop (a DISTANCE), class ownership (a BOOLEAN), uses rank. The Boolean is sound only while AliasVisibleHere admits rows from at most one class, which symtab.inc:408 states as an invariant. Any widening of the class axis retires that sentence and the key silently degrades to first-row-wins, which is declaration order, which is the BASE class. NOT A DEFECT TODAY and not one after the inheritance widening either: fpc refuses the only program that can observe it (`Duplicate identifier \"TSel\"` -- a derived class may not re-declare a base's nested type name). Recorded because the replacement is known and belongs somewhere a reader will find it: `owned` becomes hops up UClsParent, mirroring what ScopeHopsToProc already does for the lexical key one position over."
---

## The ranking, as it stands

`FindTypeAlias`, `compiler/symtab.inc`:

```pascal
owned := AliasOwnerCi[i] >= 0;
hop   := ScopeHopsToProc(AliasOwnerProc[i]);
if (hop >= 0) and
   ((Result < 0) or (hop < bestHop) or
    ((hop = bestHop) and (owned and (not bestOwned))) or
    ((hop = bestHop) and (owned = bestOwned) and (r > bestRank))) then
```

Three keys, compared in order. The first is a DISTANCE and the second is a
BOOLEAN, and that asymmetry is the whole of this ticket.

## Why the Boolean is sound today, and what makes it stop being sound

The comment above it says so explicitly:

> AliasVisibleHere has already excluded every OTHER class's rows, so any owned
> row still here is owned by the scope we are in.

With at most one class's rows surviving the filter, "is it class-owned" IS "is
it owned by us" and two values suffice. **The moment `AliasVisibleHere` admits
rows from more than one class the two questions come apart**, and the key
degrades without any diagnostic: two class-owned rows at equal hop take
`owned = bestOwned`, fall through to `r > bestRank`, tie when both classes are
in one unit, and a tie keeps the FIRST row. First in `AliasCount` order is
declaration order, and a base class is necessarily declared before the class
that inherits from it. So the base wins and the derived class's nested type
loses.

## Why this is not a bug, measured

fpc 3.2.2 refuses the only program that can reach it:

```pascal
type
  TBase = class type TSel = LongInt;    end;
  TDer  = class(TBase) type TSel = AnsiString; end;
```
```
shadow.pas(9,15) Error: Duplicate identifier "TSel"
```

A derived class may not re-declare a base's nested type name at all, so there is
no correct program in which the two rows compete. pxx answers 4 / 8 on the
equivalent pair today and is right for a reason that will not survive the
widening — which is exactly the kind of green that certifies nothing.

## The replacement, so it is written down somewhere with a reader

`owned` becomes a DISTANCE: hops from `MethImplOwnerCi` (or
`ParsingClassBodyCi`) up `UClsParent` to `AliasOwnerCi[i]`, with a sentinel for
"not in this hierarchy" — precisely what `ScopeHopsToProc` already is for the
lexical key one position over. Then a derived class's own row is 0 hops, a
base's is 1, and nearest wins the way the lexical key already makes nearest win.

**The trap is recorded two paragraphs above the code and applies unchanged:**
`UsesRankOf` returns MaxInt for a row in the CURRENT unit — a sentinel, not a
count — so nothing can be encoded as "larger than any rank", and the distance
must be a separate key compared in order, never a bonus folded into `r`. That
mistake was made once here already and inverted the answer.

## Why it is filed rather than done

The class axis is being widened right now by frank-optimize
(`AliasVisibleHere` arm 3 walking `UClsParent`, so a nested type declared in a
BASE class is visible inside a DERIVED class's method implementation). The
immediate obligation on that change is the COMMENT at symtab.inc:408, which
their diff makes false; the distance version is a separate, larger change with
no failing program behind it. Doing it now would be a refactor in a file two
sessions are editing, for an observable fpc rejects.

Take this when someone widens the class axis a second time, or when a real
program needs an inherited nested type to lose to a nearer one.

## Provenance

Found 2026-09-07 while holding both halves of a collision frank-coordinator
routed: [[bug-p-routine-local-name-scoping-is-implemented-in-one-of-three-tables]]
added the lexical key and wired `ScopeReachesProc` into `FindTypeAlias`; the
inheritance widening arrived at the predicate that feeds it. The composition of
the two turned out to be already specified BY the ranking — a routine-local type
shadows a class's nested type because hop is the first key — and this asymmetry
is the only thing the pair left unsettled.
