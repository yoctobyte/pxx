---
slug: bug-p-a-variant-cannot-hold-an-interface
title: "A Variant refuses an interface (`Variant := this type not yet supported`)"
track: P
prio: 40
type: bug
blocked-by: []
status: done
owner: frankH
created: 2026-08-26
summary: "DONE. A Variant holds an interface, and holding one is a REFERENCE: `v := ifc` boxes with an _AddRef (VT_INTF_TAG = 14, deliberately OUTSIDE VT_OBJ_FIRST..VT_OBJ_LAST because it releases through the IMT and not the heap-block protocol), the variant clear and retain paths release and retain it, `g := v` reads it back ARC-correctly, an EMPTY slot reads back as nil, and any other payload halts 220 -- fpc-identical on all eight rows of test_variant_holds_interface, byte for byte, and identical again on i386/aarch64/arm32/riscv32 under qemu. Enabling piece landed first at 8d68c7736 (RTTI_IF_ID_COM, bit 24, flags the REFCOUNTED interface entries so an id-less AddRef/Release pair cannot call a user method). Known gaps recorded in place, not silent: promocore ClearVariantSlot drops the tag without a _Release (leaf unit, no hook, no repro that reaches it -- the same standing gap as VT_OBJECT), and `IFoo(v)` SPELLED AS A CAST still segfaults, which is bug-p-a-variant-typecast-to-an-interface-segfaults and not this."
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

## The duplication it will meet  — DONE, `a770a1dd6`

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

1. **A tag and its arms. THE COLLAPSE IS ALREADY DONE — `a770a1dd6`,
   2026-09-09.** The section above ("The duplication it will meet") is history
   now: all four hand-rolled copies — `ir_codegen.inc`'s IR_VAR_STORE and
   IR_VAR_BOX, and aarch64's two twins — call `VariantTagForTk`, which every
   other backend already did. Verified on the targets it serves, since quick
   cannot see them: `--target=aarch64` and `--target=i386` on
   `test_variant_class_cross.pas` both print `end 7 100`, and every boxable
   kind's tag was read back out of the slot on x86-64. The ticket's plan was
   right to want this first; it is no longer work.

   What is left of this item is the NEW arm itself, and it is not a
   `VariantTagForTk` arm: that function keys on TTypeKind alone, and an
   interface is `tyRecord` — indistinguishable there from a plain record, which
   must keep refusing. The interface case has to be recognised where the recId
   is still in hand (ir.inc's lowering), not at the backend.

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

## 2026-09-09 (frankH) — the ifaceId question is MEASURED, and one of the three options is unsafe

frankD's re-scope named the measurement to run before designing against it:
`_AddRef`/`_Release` live on the INSTANCE, so can a raw helper taking no
ifaceId reach the same pair through any COM entry in the class's RTTI interface
table? **Half yes, and the other half would have called a user method.**

### What was measured

Walking `PXXIntfIMTOf(inst, id)` over every id a class carries and reading IMT
slots 1 and 2 out of each:

```
TImpl(TInterfacedObject, IFoo, IBar)   id=5,7,8   addref=4216231 release=4216331   (all three)
TMix (TInterfacedObject, IFoo, ICorba) id=5,7,10  addref=4216231 release=4216331   (all three)
```

So for a **COM** class every IMT carries the same pair — including a GUID-less
interface's — and any entry would do. That is the half frankD predicted.

Then the other population, `{$interfaces corba}` on a plain `TObject`
descendant:

```
corba id=7  slot0=4259184  slot1=4259296  slot2=4259408
addr of A1..A3: 4259184     4259296       4259408
```

**IMT slots 0/1/2 ARE the interface's own first three methods.** A helper that
took "any entry, slot 2" would call `A3` as `_Release` — right argument count,
no diagnostic, and it does not crash. Confirmed by building that helper: with
the flag test replaced by `if True`, the CORBA guard prints `!! A2 CALLED`
where `_AddRef` belongs and `!! A3 CALLED` where `_Release` belongs.

**Nothing in the entry separates the two populations.** `{GUID:16, IMT:8,
id:8}` — and a CORBA interface may carry a GUID while a COM one may not, so the
zero-GUID reading is not a discriminator either.

### So: a COM flag in the ID word, and the helpers it makes safe

Landed here rather than with the variant work, because it is the enabling piece
and it is testable on its own:

- `RTTI_IF_ID_COM` (bit 24) is set from the INTERFACE's `UClsIsComInterface` —
  the property that decides whether slot 2 is `_Release` or a user method.
- Every reader masks with `RTTI_IF_ID_MASK` first, so an entry written by an
  older emitter (plain index, flag clear) still matches. That is what makes the
  encoding change free across a bootstrap.
- `PXXIntfComIMTOf(inst)` returns the first refcounted IMT or **nil, which is a
  REFUSAL rather than a miss**; `PXXIntfAddRefAny` / `PXXIntfReleaseAny` are
  no-ops returning 0 when it refuses. A variant slot now has a safe way to
  retain and release from the instance alone, with the 16-byte layout untouched
  — the property frankD flagged as worth protecting.

### BIT 24, NOT BIT 32, AND THE FIRST VERSION WAS SILENTLY DEAD ON i386

The flag went in at bit 32 first. Correct on x86-64. On i386 the readers walk
that word through `PMachineWord`, which is **four bytes** there, so the flag was
never read, `PXXIntfComIMTOf` found nothing, and both helpers became no-ops
returning 0 — **a refcount that simply does not happen**, no crash, no wrong
value, and every x86-64 row still green.

Caught only by running the guard test under `--target=i386`, where it printed
`com imt found: FALSE` against x86-64's `TRUE`. This is CLAUDE.md's
native-only-measurement class exactly, and the general form is worth carrying:
**any field packed above bit 31 is invisible to a 32-bit reader and fails
silently.** The low 24 bits hold the index because `MAX_UCLASS` is 2048 —
eleven bits, thirteen of headroom.

### Guards

`test/test_intf_com_flag.pas` and `test/test_intf_com_flag_corba.pas` (two
files because `{$interfaces corba}` is a whole-unit switch). Identical output on
x86-64 and i386; compile clean on arm32, riscv32, aarch64 and wasm32.

**The CORBA file's `A1`/`A2`/`A3` print on purpose, and that is the design.** A
silent `0` cannot tell a refusal from a call that happened to return zero, so
the wrong answer had to be made LOUD rather than merely absent. The `if True`
control above is what proves the file can fail, and it is drawn from exactly the
population that would be mishandled.

The refcount rows assert `1, 2, 1, 0` rather than "non-zero": an `_AddRef` that
reached the wrong slot still returns something, and that sequence is one only
the real pair produces. The `UseIt` row is the ENCODING control — ordinary
interface ARC still goes through the id-keyed path, so its destructor line can
only print if the masked compare still matches.

### What is left on this ticket

1. **The variant tag itself.** Not a `VariantTagForTk` arm — frankD's
   correction, and it is right: that function keys on `TTypeKind` alone and an
   interface is `tyRecord`, indistinguishable there from a plain record, which
   must keep refusing. The interface case has to be recognised in `ir.inc`'s
   lowering while the recId is still in hand.
2. **The clear/retain sites.** Six hand-written emitters plus `PXXVarClear` /
   `PXXVarRetain` (builtinheap), `PyVarSlotIsObj` (pylib) and promocore's
   `ClearVariantSlot`. Its own tag with its own arm, NOT membership of
   `VT_OBJ_FIRST..VT_OBJ_LAST`, whose release is the heap-block protocol and not
   `_Release`. defs.inc's note on that range says missing one is silent: no
   crash, no wrong value, just RSS.
3. **Reading it back** (`IIntf(v)`) — the ifaceId at a cast site is static, so
   the payload still does not need to carry one.

**Assertion classes for (2), and it needs BOTH directions** (frankD): a leak
check sees the missing-release direction and is silent on double-free, while a
variant that outlives its last real reference and is then read fails loudly on a
double-free and is silent under a leak. Neither instrument alone covers it.


## 2026-09-09 (frankH) — DONE, and the two arms that were never entered

Landed: the tag, the boxing arm, the read-back arm, the ARC pairs in every
emitter that has one, the guard test, and the cross-target verification.

### What was actually hard: BOTH lowering arms were written correctly and then never reached

The boxing half went in on the first try. The read-back half compiled clean and
did nothing, **twice, from two different causes**, and neither cause errors:

1. **First placement — the variant-SOURCE unboxing block.** That block is
   reached only after the interface-target arms and it keys on
   `IRVariantUnboxKind`, which answers about SCALAR kinds; an interface is
   `tyRecord` there, indistinguishable from a plain record, which must keep
   refusing. `g := v` still yielded nil.
2. **Second placement — beside the other interface-target arms, but BELOW the
   `interface := nil` arm.** That arm is keyed NEGATIVELY: *"the RHS is neither
   a class nor a record, so it can only be nil"*. A variant RHS is neither, so
   it claimed `g := v` and lowered it to release-then-zero.

The instrument that separated them was a `WriteLn` probe at the TOP of the
`AN_ASSIGN` lowering printing `lhsTk`, `rhsTk` and `ASTKind` for EVERY
assignment — not beside the arm, where it printed one line about a different
statement (`rhsTk=6`, tyClass: only `f := TImpl.Create` got that far) and said
nothing about where `g := w` had gone. The IR dump named the consequence
(`call PXXIntfRelease` then `default_mem ival=8`) and the probe named the arm.

**A negative kind test is a claim about every kind nobody has enumerated yet.**
That is the reusable half, and it is why the new arm carries a comment saying it
must stay above the nil arm.

### And one that was entered on four targets out of five

`test_variant_holds_interface` printed `destroyed=0` where the last reference
drops — on **aarch64 only**. x86-64, i386, arm32 and riscv32 were identical to
FPC. The cross targets other than aarch64 release through the portable Pascal
`PXXVarReleasePayload`, which the tag arm already covered; **x86-64 and aarch64
hand-write their own clear and retain**, and only x86-64 had been given the
VT_INTF arm. This is exactly the failure mode defs.inc predicts for that range —
no crash, no wrong value, only a refcount that never moves — and it was visible
here only because the test counts destructor calls rather than reading values.
Control: a plain interface ARC program with no variant in it destroyed
correctly on aarch64 throughout, so the leak was the variant path and not
interface ARC.

### The refusal is not nil, because FPC splits the population and it is right to

Measured against fpc 3.2.2 for `h := v` with h an interface:

    v := Unassigned   ->  h = nil, no exception
    v := Null         ->  EVariantTypeCastError
    v := 'abc' / 5    ->  EVariantTypeCastError

An unset variant read into an interface is a program saying "nothing here"; a
variant holding a string read into an interface is a program that is already
wrong. Returning nil for the second half is the silent answer — the mistake
surfaces later as a nil dereference arbitrarily far from the assignment. So
`PXXIntfFromVariant` yields nil for VT_EMPTY and `Halt(220)` (FPC's own
invalid-variant-typecast code) for anything else. builtinheap is a leaf with no
exception machinery, so the halt is the diagnostic rather than a raise; a raise
belongs there the day it can reach one.

### Where the arms are

| | |
| --- | --- |
| tag + COM-id mask | `compiler/defs.inc` (`VT_INTF_TAG`, `RTTI_IF_ID_COM`) |
| boxing / read-back lowering | `compiler/ir.inc`, AN_ASSIGN, above the `interface := nil` arm |
| runtime | `compiler/builtin/builtinheap.pas` — `PXXVarSetIntf`, `PXXIntfFromVariant`, `PXXIntfComIMTOf/AddRefAny/ReleaseAny`, arms in `PXXVarReleasePayload`/`PXXVarRetain` |
| x86-64 emitters | `compiler/ir_codegen.inc` — the two blobs, arms in `EmitVariantClearBody`/`EmitVariantRetainBody` |
| aarch64 emitters | `compiler/ir_codegen_aarch64.inc` — `EmitIntfRetainA64`/`EmitIntfReleaseA64`, arms in both A64 bodies |
| registration | `compiler/pasparser_prog.inc` — the id-less pair in the SHARED runtime-proc routine, not only in ParseProgram's superset |

That last row is its own small lesson: the blobs are emitted by
`EmitAnsiStringRuntime` for **every driver**, so registering their callees only
in ParseProgram's Pascal-side superset killed NilPy — `compiler error:
PXXIntfAddRefAny not registered before EmitAnsiStringRuntime`, on a program that
cannot contain an interface. gate.sh quick's NilPy canary caught it; the Pascal
gate could not, and neither could any amount of testing the feature itself.

### Left open, on purpose

- **`IFoo(v)` spelled as a CAST segfaults.** `g := v` is correct; the cast form
  goes through the identifier-cast path, which
  [[bug-p-a-typecast-of-a-variant-reinterprets-it-instead-of-converting]]
  deliberately scoped to scalars. Filed as
  [[bug-p-a-variant-typecast-to-an-interface-segfaults]].
- **promocore's `ClearVariantSlot`** drops a VT_INTF_TAG payload without a
  `_Release`, joining the standing VT_OBJECT gap on identical terms (leaf unit,
  no hook, no repro that reaches it). Recorded in that routine's header so the
  omission reads as the known gap it is.
- **pylib's `PyVarSlotIsObj`** deliberately does not list the tag: NilPy has no
  interfaces, so it cannot reach a Python slot — and widening that RANGE would
  be a silent no-op, not a fix. Recorded there too.
