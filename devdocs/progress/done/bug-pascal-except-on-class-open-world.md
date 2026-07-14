---
prio: 45
---

# `on E: T` descendant matching is closed-world per UNIT — later units' classes escape

- **Type:** bug (exception semantics — Track A, found via Track P fpjson suite)
- **Status:** done
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

## 2026-07-14 — RESOLVED (commit 639525af, b339)

Fixed with the runtime parent-chain walk this ticket proposed — but it needed **no new
data table and no backend change**, because two pieces already existed:

- `IR_EXC_STORE` already materializes the in-flight exception OBJECT from `BSS_EXC_OBJ`
  into a symbol, so the handler can get at the object before deciding to match.
- `__pxxInheritsFrom` already walks the RTTI blobs' parent chain, and `is` / `as`
  (IRLowerClassMatch) were **already** moved onto it. The ticket's claim that they still
  enumerate is stale — only the `except` path did.

So the fix is: materialize the exception object, walk its parent chain, jump to the handler
body on a hit. Pure IR over existing ops. The walk is factored out as
`IRClassMatchRuntime(instSym, targetCi)` and shared with `IRLowerClassMatch`.
`IR_EXC_MATCH` still follows it unchanged — that op is what jumps to the NEXT handler when
nothing matched. Where the walk is unavailable (no builtin unit — ESP), the enumeration
stays as the fallback.

The b322 root-`Exception` shortcut is now subsumed by the general path but left in place: it
is one unconditional jump versus a call, and it is the hot catch-all.

Test `test/test_except_open_world_descendant_b339.pas` (+ two helper units): EDeep sits two
levels below the handler's target, so the walk must really WALK; ENotMine descends from a
SIBLING base and must still not be caught, which is what shows the walk discriminates rather
than matching everything. Confirmed failing ("Unhandled exception") on a pre-fix build.

Gate: `make test` green, self-host byte-identical, `make test-aarch64` green.

## Log
- 2026-07-14 — resolved, commit 639525af.
