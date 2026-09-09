---
slug: bug-p-a-variant-cannot-hold-an-interface
title: "A Variant refuses an interface (`Variant := this type not yet supported`)"
track: P
prio: 40
type: bug
blocked-by: []
status: backlog
owner: ""
created: 2026-08-26
summary: "`v := ifc` for any interface does not compile (`Variant := this type not yet supported`). Reproduces at HEAD 2026-09-09 (923ac147a, compiler be9a7fbee4fa). **THE BLOCKER THIS TICKET WAS RANKED ON DOES NOT EXIST.** It said an interface is `a 16-byte fat pointer {IMT, instance}` needing `16 bytes of payload where the slot carries 8` -- taken from `UClsIsInterface`'s comment, which was stale. Measured: SizeOf(IIntf) = 8 in pxx and in fpc 3.2.2, in every aggregate context; an interface value is ONE WORD and a call recovers the IMT from the instance per call (PXXIntfIMTOf). So it fits the existing payload exactly, like VT_OBJECT's class instance pointer, and no payload widening is needed. What IS real: the LIFETIME half. A CORBA interface (pxx default) is not refcounted and needs none; a COM one needs _AddRef/_Release, and the slot has no room for the ifaceId that PXXIntfRelease takes -- which is the actual design question, and it is not the one the ticket asked. See [[refactor-p-the-fat-pointer-interface-representation-left-two-dead-node-kinds]] for the stale-comment group that produced the wrong premise."
---

# `v := ifc`

```pascal
type IIntf = interface ['{11111111-2222-3333-4444-555555555555}'] procedure Q; end;
var v: Variant; ifc: IIntf;
begin
  v := ifc;   { pascal26: Variant := this type not yet supported }
end.
```

Still reproduces at HEAD after
[[bug-p-a-variant-refuses-wide-chars-and-interfaces]] landed. That ticket
measured a 625-pair fpc/pxx assignment cross-product and this, with the two
wide-character kinds, was the *entire* set of "fpc accepts, pxx refuses".
Everything else pxx refuses, fpc refuses too. The wide-character half is fixed;
this is the remainder, split at the seam the original ticket identified.

## Why it is not one more arm

The two wide-character kinds were cheap because they are values: convert to
UTF-8 and the variant's existing string slot holds them. An interface is not a
value. It is REFCOUNTED, and pxx spells it `tyRecord` — a 16-byte fat pointer
`{IMT, instance}`. FPC stores it as `varUnknown` and takes a reference.

Storing the fat pointer with no `AddRef` would trade an honest diagnostic for a
use-after-free the moment the source variable goes out of scope. So the work is
not in the tag table; it is:

- a variant tag for it, and 16 bytes of payload where the slot carries 8;
- `AddRef` at the store, and `Release` in the variant's clear path
  (`EmitVariantClear`) and its copy path (`EmitVariantRetain`) — the two the
  ARC-correct variant-to-variant copy already calls;
- the same in each backend that hand-rolls the store.

## The duplication it will meet

The source-kind-to-`VT_*` mapping is written FIVE times: `VariantTagForTk` in
`compiler/ir.inc` (documented as the shared, target-independent home) and four
hand-rolled copies of the same `case` — two in `compiler/ir_codegen.inc`, two
in `compiler/ir_codegen_aarch64.inc`. That duplication is why the enumeration
grew a hole in the first place. Collapsing the four onto `VariantTagForTk`
belongs with this ticket rather than before it: whoever adds the interface arm
has to touch all of them anyway, and doing the collapse first with full-tier
cross-target gating is the cheaper order.


## Re-measured and re-scoped (frankD, 2026-09-09)

Reproduces at HEAD: `923ac147a`, compiler `be9a7fbee4fa`. The refusal is on the
STORE (`v := ifc`), not the read.

### The stated blocker is false

> pxx spells it `tyRecord` — a 16-byte fat pointer `{IMT, instance}`
> [...] a variant tag for it, and 16 bytes of payload where the slot carries 8

Measured, pxx and fpc 3.2.2 answering identically to all three rows:

    SizeOf(IIntf) = 8
    SizeOf(record of two IIntf) = 16
    SizeOf(array[0..2] of IIntf) = 24

An interface value is **one machine word — the instance pointer**, FPC's ABI.
`RTTI_IFACE_SIZE`'s comment says so directly ("what lets an interface VALUE be a
single instance pointer instead of a fat {IMT,instance} pair"), and
`IRIntfInstanceWord` in `ir.inc` says it again in its body. The fat pointer went
away; `UClsIsInterface`'s comment did not, and this ticket was written from it.

**So there is nothing to widen.** The payload holds an interface value exactly
as it holds VT_OBJECT's class instance pointer, and the tag-table work the
ticket dismissed as "not one more arm" is most of what is left.

### What is actually left

1. **A tag and its arms.** `VariantTagForTk` (ir.inc) is the shared home and
   already serves i386, arm32, riscv32, xtensa and wasm32. x86-64
   (`ir_codegen.inc` ~11653) and aarch64 (~5057) hand-roll a verbatim copy of
   the same `case`, which is the duplication the ticket names and correctly
   wants collapsed FIRST — that part of its plan stands.

2. **The lifetime question, which is the real one and is not what was asked.**
   `PXXIntfRelease(p, ifaceId)` needs an interface id to find the IMT, and a
   16-byte slot holding {tag, instance} has nowhere to put one. Options, none
   measured yet:
   - release through `IInterface`'s id rather than the specific interface's —
     `_AddRef`/`_Release` live on the INSTANCE and every COM interface
     implicitly derives IInterface (IMT slots 0..2), so any implemented
     interface's IMT reaches the same pair. Needs the compiler to resolve
     IInterface's ci at emit time.
   - a raw-instance release helper that takes no ifaceId.
   - refuse COM and accept CORBA, keeping an honest diagnostic for the unsafe
     half.

   `UClsIsComInterface` is set only under `{$interfaces com}`, and its comment
   says "Default off (CORBA, no refcount)" — **which is about the FLAG and not
   about what a program actually gets.** Measured 2026-09-09: a parentless
   interface in `{$mode objfpc}` implicitly derives IInterface, and BOTH
   compilers refuse a class that implements one without QueryInterface/_AddRef
   (`class does not implement interface method: QueryInterface`; fpc says the
   same). So the COM shape is what real code has, and the CORBA-only reading of
   that comment is a third stale premise.

   **This is why the cheap slice is not worth landing.** Boxing a CORBA
   interface as VT_OBJECT would be a frontend-only change with no backend edits
   and borrow semantics that are correct for the non-refcounted case — and it
   would accept almost nothing anybody writes, while adding a second boxing path
   and making the remaining refusal look like a deliberate design position. The
   common idiom `class(TInterfacedObject, IFoo)` is the COM shape.

3. **Reading it back.** `IIntf(v)` was not investigated. The ifaceId at a cast
   site is static, so the payload does not need to carry it.

### What it would take, honestly

A tag with its own retain/release arm — not membership of VT_OBJ_FIRST..
VT_OBJ_LAST, whose release is the heap-block protocol (rc at [p-16]) and not
`_Release` — in the six hand-written emitters plus the portable twins
`PXXVarClear`/`PXXVarRetain` (builtinheap.pas), `PyVarSlotIsObj` (pylib.pas) and
promocore's `ClearVariantSlot`. defs.inc's own note on that range says the
failure mode of missing one is SILENT: no crash, no wrong value, no failing
test, just RSS.

The ifaceId has a likely answer that wants measuring before it is designed
against: `_AddRef`/`_Release` live on the INSTANCE, so any COM entry in the
class's RTTI interface table reaches the same pair, and a raw helper taking only
the instance could find one. That keeps the 16-byte slot layout untouched, which
is the property worth protecting.

### The ranking consequence

This was p40 and unclaimed from 2026-08-26 because its first section says the
work is a lifetime-and-payload overhaul. Half of that is gone. Whoever takes it
should re-cost it against the two items above, not against the original text.
