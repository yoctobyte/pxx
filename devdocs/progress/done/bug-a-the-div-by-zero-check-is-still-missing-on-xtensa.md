---
track: A+S
prio: 25
type: bug
blocked-by: []
status: done
summary: "FIXED 2026-09-01. xtensa now raises Runtime error 200 like the other five, in all FOUR shapes (32-bit div/mod, 64-bit div/mod) and under BOTH divide shapes (hardware quos/rems and the --xtensa-cpu=lx6 soft helpers). Before: div answered -1 and mod answered the dividend, and the program carried on. Test test_xtensa_div_zero_check.pas, discriminating on all 8 xtensa rows against pre-fix fc7668c096b2. ORIGINAL: The last target without a pre-divide zero check. The other five landed 2026-08-23; xtensa was left out because it cannot be RUN on this box (bare profile emits an ESP image, not a Linux ELF), its branches carry only an 8-bit displacement, its windowed ABI rotates the register window on a call, and its divide is two shapes depending on XtensaSoftDivide."
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

---

**A sibling arrived 2026-09-01 — take them together.**
[[bug-a-xtensa-has-no-q-plus-overflow-check-emitter-so-it-wraps-silently]] is
this ticket's exact shape one switch over: xtensa is the only backend with no
`{$Q+}` overflow-check emitter either, so `{$Q+}` compiles clean there and
silently wraps where the other five raise Runtime error 215. All four reasons
this ticket gives for xtensa being a different job rather than a sixth copy of
the edit — no bare-profile run, 8-bit branch displacements, the windowed ABI
rotating the register window on a call, two divide shapes — apply to that one
too, and whoever pays that cost should collect both checks for it.

One thing the sibling has that this ticket does not: a **working oracle today**.
`{$Q+}` can be measured on HOSTED xtensa under `qemu-xtensa --platform=posix`,
which is how the wrap was caught. So the emitter can be developed and verified
against a running program first, and the bare-profile question narrowed to
delivery rather than correctness.


---

## Fixed 2026-09-01

`EmitDivZeroCheckXtensa` in `ir_codegen_xtensa.inc`, wired at three sites: the
32-bit `tkDiv` and `tkMod` arms, and the 64-bit divide in `EmitBinop64Xtensa`.
Shaped on `EmitDivZeroCheckRV32`, which is the closest 32-bit model.

### Each of the four listed obstacles, and what it actually cost

- **"cannot be RUN on this box"** — true of the BARE profile only. **Hosted
  xtensa runs under `qemu-xtensa --platform=posix`**, which is the oracle the
  whole fix was developed against. This was the load-bearing one: with a runnable
  target the job stopped being speculative.
- **8-bit branch displacement** — real, and it is why the branch is patched after
  the call rather than computed up front. `XtensaRelCheck` already enforces the
  ±127 range and RAISES rather than truncating, so an over-long call sequence
  becomes a compiler error, never a branch to the wrong address. There is no
  `bnez` in the asm-text emitter either — only two-register forms — so the check
  materialises a zero into a9 and uses `bne`.
- **The windowed ABI rotates the register window on a call** — handled by being
  explicit about lifetime rather than by saving anything. a8/a9 are dead the
  instant the branch is evaluated, which happens BEFORE the call: not taken means
  no call, taken means `PXXDivZero` never returns. The comment says not to hoist
  either write past the branch, because that is the edit that would break it.
- **Two divide shapes** — cost nothing structurally: the check sits BEFORE the
  dispatch, so hardware `quos`/`rems` and the `__pxx_divsi3`/`__pxx_modsi3` soft
  path share one check. Both are still RUN separately, because sharing the
  emitter is not evidence that both run.

### The 64-bit case is not the 32-bit one

The 32-bit form tests a3. The 64-bit form must OR **a2:a3**, because there the
divisor is the pair and a4:a5 hold the dividend — testing a3 alone would let
`10 div (1 shl 32)`-shaped divisors through and, worse, would trap on a
perfectly good divisor whose high word is zero. Same distinction riscv32 draws
with its `divisorInA1Only` parameter.

### Verified, with the control

`test/test_xtensa_div_zero_check.pas`. Shape is selected by ARGUMENT COUNT and
the harness runs it four times, 0..3 args.

**An earlier draft of that test put three of the four shapes in an `else` the
harness never entered** — it passed on every target while exercising exactly one
path. It is recorded here because the green looked identical.

| binary | xtensa hw | xtensa lx6 | riscv32 |
| --- | --- | --- | --- |
| pre-fix `fc7668c096b2` | **4/4 DIFF** (`-1` for div, `10` for mod) | **4/4 DIFF** | pass |
| post-fix `12907805ca46` | 4/4 pass | 4/4 pass | pass |

All 8 xtensa rows discriminate. The five previously-correct targets pass both
before and after — controls, not evidence, and reported as such.

### The 8-bit branch range, measured rather than assumed

The obvious way for this to break is a program big enough that the call to
`PXXDivZero` needs a long-form sequence, pushing the skip branch past its ±127.
Probed with a generated 2,008-line program — 400 procedures, the division LAST
so the distance is near its worst — under both divide shapes:

```
xtensa hw   : sum=0 | Runtime error 200 (division by zero)
xtensa lx6  : sum=0 | Runtime error 200 (division by zero)
```

Both fine. And the failure mode if it ever is not fine is the safe one:
`XtensaRelCheck` RAISES on an out-of-range displacement rather than truncating
it, so this degrades into a compiler error someone must look at, never a branch
to the wrong address. That property is why the branch is patched after the call
instead of being guessed before it.

### What this does NOT close

[[bug-a-xtensa-has-no-q-plus-overflow-check-emitter-so-it-wraps-silently]] is
the same gap one switch over and is still open: xtensa remains the only backend
with no `{$Q+}` overflow-check emitter, so overflow still wraps silently there.
The div-zero work above is the template for it — same branch-patch idiom, same
register-lifetime argument, same two-shapes-must-both-run rule.

## Log
- 2026-09-01 — resolved, commit ff99d6b0d.
