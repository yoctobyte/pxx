---
slug: bug-b-tlist-has-no-list-property
track: B
prio: 45
type: bug
status: backlog
owner:
blocked-by: []
summary: "`L.List^[i]` on a TList is `\"List\": no such member on this record/class`. FPC's TList exposes its internal pointer array as `property List: PPointerList read FList` (PPointerList = ^TPointerList = ^array[0..N] of Pointer), the standard way real code iterates a TList without the per-element Get call. Missing in lib/rtl/classes.pas. NOT gated on anything -- it fails in a plain default build, 9 lines. fcl-xml's xmlutils.pp:760 uses it, so it is the current wall on rung 3 of feature-pascal-corpus-oop."
---

# `TList` has no `List` property

## Repro

```pascal
program tl;
uses Classes;
var L: TList; p: Pointer;
begin
  L := TList.Create;
  L.Add(Pointer(1));
  p := L.List^[0];        { <-- pascal26:7: "List": no such member }
  WriteLn(PtrUInt(p));
  L.Free;
end.
```

```
pascal26:7: error: "List": no such member on this record/class
pascal26:7: error: dereferenced value is not a pointer     { the cascade, not a second bug }
```

Binary `5d6d4d82091f` (self-host fixedpoint at HEAD `139d5ae14`). Plain default
build — no define, no flag. The second error is the first one's consequence;
treat them as one.

## What FPC has

```pascal
type
  TPointerList = array[0..MaxListSize-1] of Pointer;
  PPointerList = ^TPointerList;
  ...
  property List: PPointerList read FList;
```

It is the ordinary way real code walks a `TList` without paying `Get` per
element, and it is what `fcl-xml`'s `xmlutils.pp:760` writes:

```pascal
for I := 0 to FBindings.Count - 1 do
  TObject(FBindings.List^[I]).Free;
```

`lib/rtl/classes.pas` says TList is *"working and smoked, Sort included"*, which
is true of the surface it has; this is one property short of it.

## Scope note, so it is not oversized

The internal storage already exists — `Add`/`Get`/`Sort` all use it. If it is a
`Pointer` to a heap block of `Pointer`s, this is a property and a pointer-array
type, not a redesign. Check that first; if the storage is NOT a flat array of
Pointer, say so in the ticket rather than reshaping TList to fit the property.

## Provenance

Found probing rung 3 (`fcl-xml` DOM) of [[feature-pascal-corpus-oop]], the wall
after [[bug-p-a-const-array-of-sets-is-rejected-as-too-many-elements]] and
`AllocMem` (`3decbf0c4`, frankB). Reached there only under
`PXX_WIDE_PAYLOAD` — because a wall at `xmlutils.pp:285` stops a default build
first — but the defect itself is unconditional, as the repro above shows.
