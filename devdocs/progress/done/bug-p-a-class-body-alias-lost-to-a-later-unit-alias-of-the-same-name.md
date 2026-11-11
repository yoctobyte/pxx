---
track: P
prio: 60
type: bug
blocked-by: []
summary: "Regression from cd6e395484 (2026-11-11, a nilpy class-lookup fix): FindUClassImpl's own-scope alias scan took the LATEST matching row, so a unit-level `type TName = TRed;` declared after a class body's `type TName = TBlue;` won inside that class's methods. test_a_class_body_alias_does_not_leak_to_the_unit failed with \"B: no such member\". A visible class-body alias now wins first; among the rest the latest still wins, which the nilpy fix needs."
status: done
owner: unassigned
---

# A class-body alias lost to a later unit alias of the same name

## Found

A full tier on 2026-11-11 failed test-core#2020:

    pascal26:45: error: "B": no such member on this record/class

in test/test_a_class_body_alias_does_not_leak_to_the_unit.pas. The pinned
v455 compiler passes it. `git bisect` over compiler/ (c9e5029335..55100f9964)
names cd6e395484, "nilpy: super() from an override of an imported class; a
from-imported class beats a same-named one".

## Cause

That commit replaced `FindUClassAliasRow` in FindUClassImpl with a direct
scan of the current scope's alias rows, latest first, so a later Python
binding wins. The old function returned the EARLIEST row. In Pascal the
class body's alias comes first, so it won by order alone, and the new scan
lost that.

## Fix

The scan runs twice. The first pass takes only class-owned rows
(`UClsAliasOwnerCi >= 0`, still behind ClassOwnerVisibleHere, so only a
class we are inside). The second pass takes any row, latest first, as
before. Pascal cannot declare one alias twice in one scope, so the order
inside each pass matters only to Python.

## Checked

- test_a_class_body_alias_does_not_leak_to_the_unit: passes again.
- test_nilpy_a_from_imported_class_beats_a_same_named_one (the commit's
  own test): still passes.
