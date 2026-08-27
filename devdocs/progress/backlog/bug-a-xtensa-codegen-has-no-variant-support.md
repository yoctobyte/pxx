---
slug: bug-a-xtensa-codegen-has-no-variant-support
track: A+S
prio: 22
type: bug
blocked-by: []
status: backlog
summary: "`var v: Variant; v := 1;` does not compile for --target=xtensa: `unsupported node in IR codegen: var_store`. The exact sibling of bug-a-riscv32-codegen-has-no-variant-support, which was fixed 2026-08-27 -- xtensa is the last backend with no IR_VAR_STORE / IR_VAR_BOX / IR_VAR_BINOP arm at all."
---

# xtensa codegen has no Variant support

The sibling of [[bug-a-riscv32-codegen-has-no-variant-support]], found by the
grep that ticket's fix should have ended with — and did:
`grep -c IR_VAR_STORE` over the five backend files answered zero for exactly two
of them, and one of those two got fixed.

## Repro

```
$ ./compiler/pascal26 --target=xtensa --esp-profile=bare -Fulib/rtl test/test_cross_variant.pas /tmp/o
pascal26:55: error: target xtensa: unsupported node in IR codegen: var_store
```

x86-64, i386, arm32, aarch64 and (since 2026-08-27) riscv32 all compile it.

## The work is already scoped

The riscv32 fix landed the same day and is the template — same 32-bit 16-byte
slot (tag +0, zero word +4, 8-byte payload +8), same helper set
(`EmitVarHelperCall*`, `EmitVariantPayload*`, `EmitVariantFill*`,
`EmitLoadVariantAddr*`), same four pieces to add, in the order they surface:

1. `IR_VAR_STORE` — the one the error names;
2. `IR_LOAD_SYM` for a `tyVariant` symbol must yield the slot **address**, not
   load 16 bytes into one register;
3. the **write dispatch** (`writeln(v)` → `PXXWriteVariant` with the slot addr);
4. `IR_VAR_BOX` / `IR_VAR_BINOP`, reachable only once a store compiles.

And the same 32-bit payload hazards, each of which has been a real bug on a
sibling: an Int64 must reach the payload whole; the high word comes from the
payload's TYPE and not the tag (signed sign-extends, unsigned zero-fills, since
`tyNativeInt` maps to `VT_INT64`); a float widens to `VT_DOUBLE`'s 8 bytes of
IEEE bits on a target with no FPU; a boxed string skips the retain when the
source is an already-owned concat/call result.
`test/test_cross_variant_payload_widths.pas` covers one row per hazard and is
already green on the other four.

Note also that `PXXVarReleasePayload` (not `PXXVarClear`) is what the
variant-to-variant arm must call —
[[bug-a-a-variant-assigned-to-itself-becomes-empty]].

## Priority, and the honest caveat

Low: xtensa is a bare-metal profile and variants are not what an MCU program
reaches for. Loud, not silent — the compiler refuses, so nothing wrong can be
produced.

**And it cannot be VERIFIED here.** xtensa has no execution oracle on plexus,
and `test_cross_variant` needs the RTL, which no ESP-class target gets. So this
is gated behind
[[feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle]] the same way the
div-by-zero and Int64-to-float tickets are — not blocked-by (it can be written
and reviewed), but do not close it on inspection.

## Gate

Track A's, plus `test_cross_variant`, `test_cross_variant_single`,
`test_cross_variant_payload_widths` and
`test_variant_self_assign_is_a_no_op` running green on xtensa against the
x86-64 oracle — which needs a hosted xtensa profile to be buildable at all.
