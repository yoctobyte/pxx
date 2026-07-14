---
summary: "arm32/i386/riscv32: shr/shl on a 32-bit operand ran at 64-bit pair width on the sign-extended value — longint($80000000) shr 9 gave -4194304"
type: bug
prio: 60
---

# 32-bit backends: shr/shl ignored the operand's width in the 64-bit pair path

- **Type:** bug (silent wrong values on all three 32-bit targets). **Track A**
  (EmitBinop64_386 / EmitBinop64Arm32 / EmitBinop64RISCV32 shift arms).
- **Status:** working (fable-nightA) — fixed same session.
- **Opened:** 2026-07-15, found by the FIRST `pasmith_run --wide --cross`
  sweep (enabled tonight by the shortstring-truncation fix): 15/60 seeds
  diverged, ALL fifteen signatures collapsed to this one bug (seed 60
  minimal: `longint($80000000) shr (x and 31)` inside a checksum chain).

## Root cause

Integer binops promote to 64-bit (tyInt64), so on the 32-bit targets a
`longint shr` runs in the lo:hi PAIR path on the SIGN-EXTENDED value:
`longint($80000000) shr 9` = -4194304 instead of FPC's 32-bit logical
4194304. `shl` had the twin defect (`longint(1) shl 31` read 2147483648,
positive). x86-64 fixed this family long ago (bug-shl-signed-integer-width:
zero/sign-extend around the shift by the OPERAND's width); the pair paths
never got the mirror.

## Fix

In all three pair-shift arms:
- Pascal `shr` (tkIdent) with a <8-byte left operand: zero the hi word
  before the shift (32-bit logical semantics).
- `shl` with a <8-byte left operand: re-derive the narrow result after the
  shift (sign-extend signed / zero-extend unsigned low 32 bits).
- C `>>`/`<<` (tkShr, signed arithmetic) untouched — C promotes for real.

## Verification

- test_shift_operand_width.pas: shr/shl on longint + cardinal, byte-identical
  to FPC on x86-64, arm32, i386, riscv32 (aarch64 shares x86-64's model).
- pasmith --seeds 1-60 --wide --cross: 15 divergences -> 0.
