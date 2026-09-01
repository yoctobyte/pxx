---
slug: bug-b-tlist-has-no-list-property
track: B
prio: 45
type: bug
status: done
owner:
blocked-by: []
summary: "FIXED 2026-09-01. `L.List^[i]` on a TList was `\"List\": no such member on this record/class`. FPC's TList exposes its internal pointer array as `property List: PPointerList read FList` (PPointerList = ^TPointerList = ^array[0..N] of Pointer), the standard way real code iterates a TList without the per-element Get call. Missing in lib/rtl/classes.pas. NOT gated on anything -- it fails in a plain default build, 9 lines. fcl-xml's xmlutils.pp:760 uses it, so it is the current wall on rung 3 of feature-pascal-corpus-oop."
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


---

## 2026-08-30 (frankB) — the storage is fine; the IDIOM is broken. Blocked.

frank-rust asked me to record it rather than reshape `TList` if the storage was
not a flat pointer array. **The storage is fine** — measured:

```
Pointer(a) = 128703384258344      @a[0] = 128703384258344      delta @a[1]-@a[0] = 8
```

`FItems: array of Pointer` is a dynamic array whose handle **is** the address of
element 0, with an 8-byte stride, which is exactly the layout `PPointerList`
expects. So `property List: PPointerList read FItems` is implementable as a cast
and needs no reshaping at all.

**I have not added it, and that is the finding.** `p^[i]` where the element type
is pointer-kind **segfaults in a plain default build** — filed as
[[bug-a-indexing-through-a-pointer-to-an-array-of-pointers-segfaults]], with an
FPC oracle and an element-type table (`Integer`/`Int64` work; `Pointer`/`PChar`/
`PInteger` crash, read and write alike). It is not a `TList` problem and not a
dynamic-array problem: a pointer to a *static* `array[0..3] of Pointer` fails the
same way.

So adding the property would produce something that **compiles and then crashes
at the single idiom it exists for**. Today's `"List": no such member` is a
compile-time error that names the problem; the property would move the failure to
run time at the call site and make it look like the caller's bug. That trade is
the wrong way round, and it is the same false-green shape this evening kept
producing.

Land the property **with or after** the Track A fix, in one change, gated by
running `L.List^[i]` rather than building it.


---

## 2026-09-01 (frankH) — the blocker was RENAMED, not lost; unblocked, and landed

**Track B.** Two separate findings, and the first is why this sat for two days
after it was already free.

**The `blocked-by` named a slug that exists nowhere.** `progress.sh check`
reports it as `DANGLING`. It was not a ticket that was never filed — it was
**renamed**: the Track A defect is
[[bug-a-indexing-through-a-pointer-to-an-array-is-wrong-for-several-element-kinds]]
and it has been in `done/` since before this ticket was last read. A rename
breaks the edge silently in exactly the direction that costs the most: the
dependent still reads as blocked, nothing errors, and the event that cleared it
happened on the *other* ticket where nobody was standing.

**The blocker is genuinely fixed, verified by running it and not by the folder**
(`done/` is a claim about the past; the repro is a claim about this binary):

```pascal
type TPointerList = array[0..3] of Pointer; PPointerList = ^TPointerList;
var a: TPointerList; p: PPointerList;
...  p := @a;  for i := 0 to 3 do writeln(PtrUInt(p^[i]));  p^[2] := ...;
```
reads all four elements correctly AND the write through `p^[2]` lands in `a[2]`.
Read and write, the two halves the original element-kind table had failing.

### The fix

`lib/rtl/classes.pas`: `MaxListSize = MaxInt div 16`, `TPointerList` /
`PPointerList`, and `property List: PPointerList read GetList` where `GetList`
is `PPointerList(FItems)`. **A cast, no reshaping** — frankB's 2026-08-30
measurement that the dynamic-array handle is the address of element 0 with an
8-byte stride is what makes it one line, and it still holds.

`nil` on an empty list, as FPC: `Count` is what says whether it may be indexed.
`TFPList` inherits it, which is the spelling fcl sources actually use.

### Gate — Track B, `$(PXX_STABLE)`, and a control that fires

`test/lib_classes.pas` gained four rows (`make lib-test` count 21 -> 25).
Verified green under **both** `stable_linux_amd64/default/pinned` and
`compiler/pascal26`, plus the ticket's own repro and the fcl-xml
`xmlutils.pp:760` walk over ten elements.

**The rows can fail, and the control was drawn from the population the claim is
about** — the way this regresses is not the property vanishing (that is a
compile error and takes the whole file down), it is `GetList` handing back a
COPY. With `GetList` deliberately rewritten to copy: `list-List-writethrough`
goes RED and the Makefile count drops 25 -> 24.

**The two directions are NOT equally strong, and that is recorded in the test.**
Under the same copying control `list-List-alias` stays GREEN — it re-reads
`List^` and gets a fresh copy that already contains the write. `writethrough`
is the row carrying the aliasing claim. A future reader trimming "redundant"
rows would otherwise keep the weak one.

## Log
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change: PENDING-COMMIT.
