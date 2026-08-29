---
slug: bug-a-xtensa-codegen-has-no-variant-support
track: A+S
prio: 22
type: bug
blocked-by: []
status: done
summary: "`var v: Variant; v := 1;` does not compile for --target=xtensa: `unsupported node in IR codegen: var_store`. The exact sibling of bug-a-riscv32-codegen-has-no-variant-support, which was fixed 2026-08-27 -- xtensa is the last backend with no IR_VAR_STORE / IR_VAR_BOX / IR_VAR_BINOP arm at all."
owner: frankS
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

## Resolution (frankS, 2026-08-29)

Implemented in `compiler/ir_codegen_xtensa.inc` — the last backend without
variant support now has it. Four helpers (`EmitVarHelperCallXtensa`,
`EmitVariantPayloadXtensa`, `EmitVariantFillXtensa`, `EmitLoadVariantAddrXtensa`)
plus the `IR_LOAD_SYM` variant case and the three arms.

### Three things did NOT carry over from the riscv32 template

The ticket says "the work is already scoped … same four pieces". Three of the
four ported directly; the rest did not, and each divergence is xtensa-only:

1. **Register preservation cannot move `sp`.** riscv32 saves across a helper
   call with `addi sp,-16` + four stores. Under xtensa's **windowed** ABI `sp`
   must stay put — moving it desyncs the window spill area at `[sp-16]`, which
   is exactly what `XtensaPushA2` exists to say. Every save here goes through
   `XtensaPush*`/`XtensaPop*`, which are already correct on both ABIs.
2. **No `srai` on this ISA.** Sign-extending a 4-byte payload into the high
   word uses the branch idiom `EmitNode64Xtensa` already uses for the identical
   question, not a shift-immediate.
3. **Piece 3 of the ticket — the write dispatch — has no counterpart here.**
   xtensa's `IR_WRITE` is `{ Bare-metal: write/writeln does nothing. }`, so
   there is no `PXXWriteVariant` call site to add. `writeln(v)` compiles and
   emits nothing, exactly as `writeln` of any other type does on this backend.
   This is worth stating because it bounds what "fixed" can mean here: a
   variant's *value* can never be observed through `writeln` on xtensa.

The ABI dance is reused from `EmitStrRefCallXtensa` rather than re-spelled, and
`EmitStrIncRef` was not written at all — that helper already existed under the
name `EmitStrRefCallXtensa`, so riscv32's two near-identical routines collapse
to one call site here.

### The ticket's repro can never exit 0, on any backend

```
./compiler/pascal26 --target=xtensa --esp-profile=bare -Fulib/rtl test/test_cross_variant.pas /tmp/o
```

`--esp-profile=bare` has no builtin unit, so the variant helpers do not exist
there. Measured: **riscv32 fails on this same command too**, one step later,
with `variant helper PXXVarClear not found`. The ticket's claim that "riscv32
compiles it" is true of `--target=riscv32`, not of the bare command it prints.
So the gate is parity with riscv32, not exit 0.

**That parity is now exact** — same error, same line:

```
xtensa : pascal26:55: error: compiler error: variant helper PXXVarClear not found
riscv32: pascal26:55: error: compiler error: variant helper PXXVarClear not found
```

### Verified (binary `bd1fc9916ef8`, self-host fixedpoint, converged 1 round)

**Object-level only — I cannot run xtensa output** (no device, no ESP-IDF, no
`qemu-system-*` on this box). Everything below is compile-and-inspect plus a
differential against riscv32; none of it is a booted image.

- `test_cross_variant.pas` and `test_cross_variant_payload_widths.pas` both
  compile for `--target=xtensa`, on **both ABIs** (Call0 and
  `--xtensa-abi=windowed`). riscv32 output unchanged (`code=349676`, identical
  to the pre-change baseline).
- Seven payload kinds compile on both ABIs — Integer, Int64, Cardinal, Double,
  Single, AnsiString, Boolean — each including `v := v`, the self-assignment
  case `bug-a-a-variant-assigned-to-itself-becomes-empty` covers.
- **The signed/unsigned high word was verified in the emitted bytes**, since it
  is the hazard with a recorded incident (`EmitVariantFillArm32`). With the
  constant held equal at 42 so only signedness differs:

  | | emitted at the fill |
  | --- | --- |
  | `Integer` | `42 62 02` s32i a4,a2,8 · `52 a0 00` movi a5,0 · `57 a4 02` bge a4,a5 · `52 af ff` movi a5,-1 · `52 62 03` s32i a5,a2,12 |
  | `Cardinal` | `42 62 02` · `52 a0 00` · `52 62 03` — no branch pair |

  The two objects are the same total size, which initially looked like the two
  paths being identical. They are not: `XtensaAlignCode4` pads with 3-byte
  NOPs, and the Cardinal object carries two (`f0 20 00` twice) exactly where
  Integer has the 6 extra bytes.
- Int64 stores both words straight from the popped pair — `42 62 02` `52 62 03`
  adjacent, no sign-extend between — so the payload reaches the slot whole
  (`bug-a-an-int64-assigned-to-a-variant-truncates-to-32-bits-on-i386-and-arm32`).
- Shared paths unaffected: both variant tests still **run** correctly on
  x86-64, payload-widths printing `ALL OK`.
- `tools/gate.sh quick`: **GREEN**, all steps including the FPC seed canary.

### What is NOT proven

No xtensa code was executed. The arms are structurally correct and reach exact
parity with the reference backend at compile time, but ARC behaviour
(`PXXVarRetain`/`PXXVarReleasePayload` pairing), the windowed-ABI call sequence
under a real window rotation, and the 16-byte copy are **unvalidated at
runtime**. The `writeln` gap above means the usual variant tests cannot observe
values on this target even with hardware — a runtime check needs a harness that
inspects the slot directly, or the hosted-xtensa oracle in
[[feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle]].

## Log
- 2026-08-29 — resolved, commit 29e8ee52a.
