---
slug: feature-b-classes-has-no-tcollection-family
title: "lib/rtl/classes.pas has no TCollection / TCollectionItem"
track: B
prio: 20
type: feature
status: open
owner: ""
created: 2026-09-09
found-by: frankS
tags: [rtl, classes, enumerators]
blocked-by: []
summary: "TCollection, TCollectionItem and TCollectionEnumerator are not declared anywhere in lib/rtl. Measured 2026-09-09 at compiler 177239049b43: `Collection := TCollection.Create(TCollectionItem)` fails with `a statement cannot start with '.'` -- the parser hitting an unknown type, NOT a for-in or a frontend problem, and the diagnostic points nowhere near the cause. THIS IS THE WHOLE REMAINING RESIDUAL OF conformance row tenumerators1.pp, which is otherwise done: TList/TFPList/TStrings/TComponent enumerators now exist with FPC's own type names and its hand-driven MoveNext/Current protocol (fixture test/lib_classes_enumerators, 25 rows byte-identical to fpc 3.2.2 under BOTH the HEAD and the PINNED compiler), so three of that file's five sections run. Prio 20 and not higher because ONE corpus row wants it and no real source in the tree does -- the search that says so is a grep of lib/, examples/ and test/ for the name, which finds nothing outside the skip list. Rank it up the moment a corpus rung or a real program asks; TCollection is how FPC code models an owned, indexed, notifying child list (TFont.Collection, dataset field defs, and every component-editor idiom), so that ask is likely rather than hypothetical."
---

# Classes has no TCollection family

```pascal
uses Classes;
var Collection: TCollection; Item: TCollectionItem;
begin
  Collection := TCollection.Create(TCollectionItem);   { unknown type }
```

pxx: `pascal26:71: error: a statement cannot start with '.'` — the parser has
already failed on the type name and the message is about the token it stopped
at. fpc 3.2.2 compiles and runs it.

## Why it is filed now

Found while burning the for-in / enumerator cluster of the FPC-testsuite corpus
(tforin8, tforin24, tforin2 all closed 2026-09-09). `tenumerators1.pp` exercises
five containers by hand; four of them now work and the fifth is this. The row's
skip reason names this ticket and says the row **should** pass once the family
exists — *a prediction, not a measurement*, and it says so there too.

## What FPC's shape is

`rtl/objpas/classes/classesh.inc`: `TCollectionItem` (owned by a collection,
carries `Index`, `DisplayName`, `Collection`), `TCollection` (owns items of a
declared `TCollectionItemClass`, `Add`, `Clear`, `Delete`, `Count`, `Items[]`,
plus the `Notify`/`Update` hooks descendants override) and
`TCollectionEnumerator` in the same plain-class shape as the four that landed
today. `TOwnedCollection` adds an owner and is a two-line descendant.

The enumerator half is trivial once the two classes exist — copy any of the four
in `classes.pas`, which are deliberately uniform for that reason.
