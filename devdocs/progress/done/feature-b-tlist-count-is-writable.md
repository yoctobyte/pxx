---
track: B
prio: 45
type: feature
blocked-by: []
status: done
owner: "frankD"
created: 2026-09-06
summary: "FIXED 2026-09-06. `L.Count := N` was refused with `property is read-only`. FPC declares `property Count: Integer read FCount write SetCount` on TList and TFPList alike; lib/rtl/classes.pas declared the getter and no setter, so the ordinary FPC idiom for unwinding a partially built list — release the tail, then assign the old count — did not compile. THE TWO HALVES OF SetCount ARE NOT SYMMETRIC AND THAT IS THE BEHAVIOUR: shrinking goes through Delete so an owning descendant's Notify(lnDeleted) fires once per dropped element, and growing exposes empty slots that must read nil and does NOT notify. The notify half was ABLATED to prove it is load-bearing: with SetCount written as a bare SetLength, every other row of the fixture still passes and only that one moves, 3 -> 0 — right Count, right surviving elements, every dropped element leaked. Measured byte-identical to fpc 3.2.2 -Mobjfpc on all four rows including TFPList, which matters because pxx's hierarchy is INVERTED from FPC's (here TFPList descends from TList; in FPC TList wraps a TFPList). Test `test_tlist_count_is_writable`. Unblocked fcl-passrc rung 7 pparser.pp:4768; the unit now parses to completion."
---

# TList.Count is writable

- **Type:** feature (compat — FPC RTL property has a setter, ours did not) —
  **Track B** (`lib/rtl/classes.pas`), landed by Track P, which hit it.

```pascal
for i := OldListCount to VarList.Count - 1 do
  TPasElement(VarList[i]).Release;
VarList.Count := OldListCount;          { pxx: property is read-only }
```

fcl-passrc `pparser.pp:4768`, in `ParseVarList`'s error path. It is the ordinary
way to unwind a list back to a mark.

## Why the notify row is the whole test

A `SetCount` written as a bare `SetLength` produces the right `Count`, the right
surviving elements and the right nil slots. Every value assertion about the
container passes. What it does is drop elements without telling an owning
descendant, which leaks them — and no output assertion about the list can see
that. **Ablated and measured:** only `notify fired` moves, `3 -> 0`.

This is the same class as the open-array leak that `assert_no_leak.sh` exists
for; the cheap instrument here is that FPC's own `Notify` callback is
observable, so the count of `lnDeleted` calls is directly comparable against the
fpc oracle where a leak is not.

## Log

- 2026-09-06 — fixed, commit 3034ac606.
