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
summary: "`v := ifc` for any interface does not compile. Split off from bug-p-a-variant-refuses-wide-chars-and-interfaces, which fixed the two wide-character kinds and left this at the seam the ticket itself named: an interface is REFCOUNTED and pxx spells it tyRecord (a 16-byte fat pointer {IMT, instance}). Storing the fat pointer without the AddRef/Release pairing would trade an honest diagnostic for a use-after-free, so this is not one more tag arm — it is a lifetime problem."
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
