---
prio: 45
track: A
status: done
owner: frank-optimize
---

# -O3 (x86-64): W1 slice 10 fused the sign-extend and skipped the zero-extend

Found by porting slice 10 to aarch64, where both flavours were handled in one
helper and the asymmetry on the x86-64 side became visible by comparison.

- **Type:** feature (codegen — optimization) — **Track O**, file-ownership
  **Track A** (`compiler/ir_codegen.inc`). Gate: `make compiler/pascal26` plus
  the repro.
- **Worth:** −1 instruction and −2 bytes per occurrence, same as slice 10.

## The gap

A shift's leading widen on a narrow operand has two flavours:

| operand | x86-64 emits | slice 10 |
| --- | --- | --- |
| signed, native-width result | `cdqe` | **fused** into `movsxd rax, rNd` |
| unsigned (or a narrow result) | `mov eax, eax` | **not fused** |

For a register-resident operand the unfused form is `mov rax, rN` (3 bytes) +
`mov eax, eax` (2) = 5 bytes, two instructions. It should be `mov eax, rNd`
— `44 89 C0` for r8-r15, three bytes, one instruction — which zero-extends into
the full 64-bit register by construction, exactly as the 32-bit `mov` always
does.

`W1LeadingCdqe` in `ir_codegen.inc` currently answers False for this case, so
the load is not skipped and the arm falls through to the zero-extend. The
aarch64 twin (`W1LeadingExtA64`) returns 1 for sxtw and **2** for `mov w0, w0`
and fuses both, which is what made the omission obvious.

## Why it was missed

Slice 10's test drives the widen through `LongInt shr k`, and this dialect
promotes that to native width — so every row in it takes the *signed* arm. The
unsigned rows in `test_shr_resident_widen.pas` are marked as controls for a
different property (`u shr 1` on a `LongWord` proves the fold does not claim the
zero-extend site) and they passed, which is correct and also exactly why nobody
looked again: **a control that proves "this pass does not fire here" reads
identically whether not-firing is right or is a missed opportunity.**

## Gate

Its own `-O0`/`-O3` control pair with band rows, an unsigned narrow operand
whose value is above 2^31 (where a sign-extension would give a different
answer), and a deliberate break verified to change the emitted bytes.

## Links

- Sibling that fused the other flavour: `feature-opt-o3-fuse-resident-read-and-widen-into-movsxd`
- The port that surfaced it: `feature-opt-o3-w1-operand-folds-are-x86-64-only-aarch64-has-four-of-fifteen`
- Umbrella: `feature-opt-o3-register-pressure`

## Log
- 2026-08-30 — resolved, commit 34f41beda.
