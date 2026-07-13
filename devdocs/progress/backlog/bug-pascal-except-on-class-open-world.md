---
prio: 45
---

# `on E: T` descendant matching is closed-world per UNIT — later units' classes escape

- **Type:** bug (exception semantics — Track A, found via Track P fpjson suite)
- **Status:** backlog — opened 2026-07-13. Root-Exception catch-alls FIXED (b322);
  this ticket is the general case.

## The defect
An `except on E: T do` clause matches T's descendants by ENUMERATING them at the
moment the handler's own unit lowers to IR (ir.inc, AN_TRY_EXCEPT: one
IR_EXC_MATCH_HIT per known descendant). Units compile eagerly in dependency
order, so an exception class declared in a unit compiled LATER is not in the
set — the handler silently lets it escape. Nothing fails at compile time; the
program dies "Unhandled exception" at run time.

Found the hard way: fcl-fpcunit's `AssertException` (`on E: Exception do`)
failed to catch fpjson's `EJSON` purely because fpcunit compiles before fpjson.
Flipping the program's `uses` order flipped the behaviour.

## What b322 already fixed
A ROOT exception target — no parent, named `Exception` — now matches
unconditionally (everything raisable descends from it). That covers the
dominant catch-all and unblocked the suite. See
test/test_except_cross_unit_class_b322.pas.

## What remains
`on E: EMyBase do` where a DESCENDANT of EMyBase is declared in a later unit
still misses. Rare (descendant families usually live in one unit), but the same
silent-escape shape.

The `is` / `as` lowering (IRLowerClassMatch) has the same per-unit enumeration
with the same comment claiming whole-program codegen; same gap, same fix.

## Fix direction — runtime parent-chain walk
The exception state already carries the raising CLASS ID (a UCls index) in a
runtime global. Emit a class-id → parent-class-id table into the binary AFTER
all units are parsed (same late-emission stage as VMTs/RTTI blobs), and lower
IR_EXC_MATCH / the class-match loop as: walk `cur := excId; while cur >= 0: if
cur = target then match; cur := parent[cur]`. Pure IR over a data table — no
new backend ops — but the table address needs a fixup mechanism like IR_VMTADDR
uses, and every backend's IR_EXC_MATCH usage must be re-checked. Full gate +
cross.

## Gate
`make test` + self-host byte-identical + cross (exception paths exist on all
targets).
