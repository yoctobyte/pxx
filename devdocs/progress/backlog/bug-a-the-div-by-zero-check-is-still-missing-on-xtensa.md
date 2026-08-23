---
track: A+S
prio: 30
type: bug
blocked-by: []
status: backlog
summary: "The last target without a pre-divide zero check. The other five landed 2026-08-23; xtensa was left out because it cannot be RUN on this box (bare profile emits an ESP image, not a Linux ELF), its branches carry only an 8-bit displacement, its windowed ABI rotates the register window on a call, and its divide is two shapes depending on XtensaSoftDivide."
---

# The div-by-zero check is still missing on xtensa

Split out of [[bug-a-the-div-by-zero-check-is-emitted-on-x86-64-only]], which
landed the check on x86-64, i386, arm32, aarch64 and riscv32 on 2026-08-23.
Xtensa is the remainder, and it is a genuinely different job — not the sixth
copy of the same edit.

Implements the tail of [[decide-int-div-zero-behavior-unification]] (user,
2026-07-20: option 1, RE 200 on every target).

## What is already done for you

`DivZeroCheckProc` (`compiler/symtab.inc`) holds the whole policy —
`--no-div-check`, the `FindProc('PXXDivZero')` lookup, and the documented rule
that a missing `PXXDivZero` on a cross target means "emit no check" rather than
a call to an x86-64-only stub. An xtensa arm needs only the instructions:

```pascal
dzProc := DivZeroCheckProc;
if dzProc < 0 then Exit;
<test the divisor>
<branch over>
EmitCallProc(dzProc);   { never returns }
<patch the branch>
```

The four existing helpers (`EmitDivZeroCheck386` / `Arm32` / `A64` / `RV32`) are
the pattern; each is shaped like its backend's `EmitOvfCheck*` twin.

## Why it is not a transcription

1. **No local oracle.** `--esp-profile=bare --target=xtensa` compiles, but the
   output is an ESP image; `qemu-xtensa` will not run it, and the hosted profile
   needs an ESP-IDF tree. Every other backend's arm was verified by *executing*
   the differential under qemu. Do not land this one on inspection.
2. **8-bit branch displacement.** `EncodeXtensaBranch`'s `imm8` gives roughly
   ±127 bytes. A branch over `EmitCallProc` is almost certainly in range — but
   "almost certainly" in the hottest arithmetic path is what a test is for, and
   the windowed ABI's `call8` is longer than `call0`.
3. **The register window.** Under `XTENSA_ABI_WINDOWED`, `EmitCallProc` emits
   `callx8`, which rotates the window. `PXXDivZero` never returns, so nothing
   has to survive it — but the operands live in a2/a3 at the 32-bit site and
   a2:a3 / a4:a5 in `EmitUDivMod64Xtensa`, and the check runs *before* the
   divide, so it must not disturb them on the fall-through path.
4. **Xtensa has no zero register**, unlike riscv32 — the comparison needs a
   scratch holding 0 (`movi a9, 0` then `bne`), or `beqz`/`bnez` if the encoder
   grows them. `xtensaenc.inc` currently has only the two-register forms.
5. **Two divide shapes.** `XtensaSoftDivide` selects a `__pxx_divsi3` /
   `__pxx_modsi3` call instead of hardware `quos`/`rems` (LX6 cores have no
   hardware divide). The software helpers are ordinary routines, so a check
   inside them may be the better place — measure which cores take which path
   before choosing.
6. **`EmitUDivMod64Xtensa`** is the same software long-division story as the
   other 32-bit targets and needs its own guard at entry; one guard covers the
   signed core too, which calls it after negating.

## Gate

`test/test_div_by_zero_raises_on_every_target.pas` (already in `test-core`)
producing `ALL OK` under xtensa on hardware or a working emulator, plus a
`--no-div-check` row showing the opt-out restores today's behaviour, plus the
existing `test_soc_xt26` / `test_soc_s326` bare-profile builds staying green.
