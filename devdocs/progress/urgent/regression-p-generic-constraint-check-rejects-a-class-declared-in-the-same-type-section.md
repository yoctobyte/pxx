---
slug: regression-p-generic-constraint-check-rejects-a-class-declared-in-the-same-type-section
title: "The new generic-constraint check rejects a class declared in the SAME type section as the specialization"
track: P
prio: 70
type: regression
status: urgent
blocked-by: []
owner: ""
summary: "test-fgl went NEW-RED on seven's full tier: objectlist.pas fails `generic constraint violated: TFPGObjectList<T> is constrained to TObject, but TThing is not TObject or a descendant of it` -- and TThing IS `class`, i.e. an implicit TObject descendant. It is declared in the same type section as the specialization that uses it. Introduced by f4fb9d31b (constraints are recorded and checked), which is otherwise a correct and valuable fix. Real FPC-corpus code (fgl); blocked pin v397 from a clean shadow."
---

# The constraint check rejects a class declared in the same type section

**Regression, found by Track T (seven), full tier.** `test-fgl` **passed** at
`a8947307fa98` and went **NEW-RED** at `719bef10ea68` — so this is fresh, not
pre-existing.

```
test-fgl#src:compiler/.pascal26.fixedpoint
  PASS map_str.pas | FAIL objectlist.pas -- compile error:
  pascal26:9: error: generic constraint violated: TFPGObjectList<T> is
    constrained to `TObject`, but TThing is not TObject or a descendant of it
  near: = specialize TFPGObjectList < TThing > >>> ; constructor TThing
```

## The repro is already in the tree: `test/fgl/objectlist.pas`

```pascal
type
  TThing = class            { <- implicit TObject descendant }
    v: Integer;
    constructor Create(av: Integer);
  end;
  TThingList = specialize TFPGObjectList<TThing>;   { <- same type section }
```

`TThing` is a bare `class`, which **is** a `TObject` descendant. The rejection is
wrong on the language, and `near:` shows the check firing while the type section
is still open — the specialization sits between `TThing`'s `end;` and the
`constructor TThing` implementation.

## Almost certainly [[bug-p-generic-constraints-are-checked-before-the-type-section-closes]]

That ticket [P] describes exactly this defect and predates the check that now
exposes it. **Raised 40 → 70**: it was a low-prio one-liner while nothing read a
constraint, and it became a live regression on real corpus code the moment
`f4fb9d31b` made constraints load-bearing.

## The cheap discriminating test — run this FIRST, before reading any code

Split the type section:

```pascal
type
  TThing = class v: Integer; constructor Create(av: Integer); end;
type
  TThingList = specialize TFPGObjectList<TThing>;
```

**Compiles ⇒** the mechanism is confirmed as "checked before the section closes",
and the fix is to defer constraint checking to section close (or to resolve
ancestry lazily at the check).
**Still fails ⇒** the mechanism is something else — ancestry resolution for an
implicit `TObject` base, not section timing — and this ticket's framing is wrong.
Do not skip this; the two produce the identical message.

## What is NOT wrong here

`f4fb9d31b` is a correct and valuable fix and **must not be reverted**:
`TFoo<T: class>` and every other constraint form was parsed and discarded, so no
specialization was ever checked and **all 35 FAIL-marked `tgenconstraint`
fpc-testsuite tests were wrongly ACCEPTED**. The check is right; its *timing* is
wrong. Fix the timing, keep the check.

## Gate

`test/fgl/objectlist.pas` compiles and runs, `map_str.pas` stays green, and the
35 `tgenconstraint` tests stay correctly rejected — that last one is the arm a
naive "loosen the check" fix would silently undo.
