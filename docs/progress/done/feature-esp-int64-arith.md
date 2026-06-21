# 64-bit integer arithmetic for the ESP backends (riscv32 + xtensa)

- **Type:** feature (cross codegen depth, ESP targets)
- **Status:** DONE 2026-06-21 (riscv32 2026-06-20 / xtensa 2026-06-21)
- **Owner:** Track A
- **Opened:** 2026-06-20
- **Blocks:** [[feature-esp-float]] (soft-float kernels are heavy Int64) — now UNBLOCKED

## xtensa DONE 2026-06-21 (commit 3114bc9)

Full a2:a3 (lo:hi) 64-bit value model on xtensa, mirroring the riscv32 work.
Xtensa has no condition flags (like riscv/arm), so carries/borrows are
synthesised with the unsigned branches bgeu/bltu: add/sub (carry/borrow), mul
(MULUH + the three 32-bit limb partials), and/or/xor, shl/shr (cross-word via
the SAR ssl/ssr+sll/srl shifts, incl. n>=32 / n==0), all six compares
(hi-then-unsigned-lo), and restoring-division div/mod (unsigned core + signed
sign-fixup). A word's MSB is extracted with `srl` after presetting SAR=31 (no
EXTUI needed). 64-bit IR_NEG / IR_NOT too (the old paths only touched the low
word — broke unary minus on Int64; same latent bug still present on riscv32
IR_NEG, harmless for softfloat which never negates an Int64). Word-based call
marshalling + callee spill (Int64 = 2 words lo:hi, ≤6 words) and 64-bit returns
in a2:a3 (windowed a10:a11). Added: the MULUH encoder (xtensaenc.inc) and the
muluh / ssl / ssr / sll / srl / bltu / bgeu mnemonics to the asmtext_xtensa
assembler (all encodings verified vs xtensa-esp32s3-elf-as).

Validated on esp32s3 QEMU vs the x86-64 oracle: 64-bit add/sub/mul/div/mod
(signed+unsigned), all six compares, Int64 params/returns, unary neg, AND the
full softfloat library (test_esp_softfloat_probe.pas) byte-identical. New
`make test-esp-softfloat` runs the probe on esp32c3 + esp32s3 (folded into
test-esp-bare). x86-64 self-host byte-identical (no reseed), make test green,
cross-bootstrap (i386/aarch64/arm32) byte-identical, ESP bare-boot intact.

## riscv32 DONE 2026-06-20 (commit 54c5ed7)

Full a0:a1 (lo:hi) 64-bit value model on riscv32: add/sub (sltu carry/borrow,
no flags), mul (mulhu + 32-bit limb partials), and/or/xor, shl/shr (cross-word
incl. n>=32 / n==0, via the EmitAsmRv32 label assembler), all six compares
(hi-then-unsigned-lo), and restoring-division div/mod (unsigned core + signed
sign-fixup, mirrors arm32 EmitUDivMod64). Word-based call marshalling + callee
spill (Int64 = 2 words lo:hi, ≤8 words) and 64-bit returns in a0:a1. Encoders
mulhu/slli/srli/srai added. Also fixed: ESP no longer pulls the `builtin`
Str/Val unit on a bare `uses` clause (its frozen-string concat can't lower on
riscv32 — the last blocker for `uses softfloat`).

Validated on esp32c3 QEMU vs the x86-64 oracle: 64-bit add/sub/mul/div/mod
(signed+unsigned), compares, Int64 params/returns, AND the full softfloat
library (test_esp_softfloat_probe.pas) byte-identical. x86-64 self-host
unchanged, make test green, ESP bare-boot intact.

**Remaining: xtensa.** Same value model but the Call0/windowed ABI, different
register set (a2..a15, a-pair for 64-bit), and the xtensa text assembler
(asmtext_xtensa.inc). Mirror the riscv32 EmitBinop64 structure; xtensa has no
flags either. Then feature-esp-float can wire single→HW-FPU / double→soft on
xtensa. (riscv float wiring — Real resolver, value model, IR lowering — is now
the immediate next step there, since its Int64 substrate is ready.)

## Problem

The riscv32 and xtensa IR backends do **runtime integer arithmetic in 32 bits
only**. The `IR_BINOP` handler (`ir_codegen_riscv32.inc` ~457-503,
`ir_codegen_xtensa.inc` ~491+) loads each operand into a single 32-bit register
(`a0`/`a1`) and emits a single 32-bit op (`rv32_add`/`rv32_mul`/`rv32_sll`/…).
There is no register-pair (lo:hi) path. So a runtime 64-bit `add`/`sub`/`mul`/
`and` **silently truncates to the low 32 bits**.

Demonstrated on esp32c3 QEMU vs the x86-64 oracle:

```
a := 1000000; b := 1000000; c := a * b;   { 10^12 }
  x86-64: 1000000000000   riscv32: garbage (low 32 bits)
a := Int64(1) shl 33; c := a + 5;          { 8589934597 }
  x86-64: 8589934597      riscv32: 5 (low 32 bits)
```

(Constant-only 64-bit expressions appear to "work" because ConstEval folds them
at compile time — e.g. `(Int64(1) shl 40) shr 36` = 16. Only **runtime** 64-bit
values truncate. Don't be fooled by constant test cases.)

Secondary: some Int64 expressions inside a function (seen in softfloat's
`sRoundPack`/`dRoundPack`) are mis-typed by the ESP path and hit
`target xtensa/riscv32: frozen tyString concat unsupported` (a tyString
misclassification of an Int64 `+`), rather than truncating. That errors rather
than miscompiles (safe), but indicates the 64-bit type propagation is incomplete
on the ESP path too. The simple `function f(m: Int64): Int64` cases compile;
the exact trigger in sRoundPack is not yet isolated.

## Why it matters now

`feature-esp-float` lands soft-float by having the ESP codegen call the validated
`compiler/builtin/softfloat.pas` kernels. Those kernels are almost entirely 64-bit
integer math (double: `shl 52`, 53x53 mul via 26-bit limbs; single: 48-bit
products + guard/round/sticky in Int64). They **cannot run correctly** on the ESP
backends until runtime Int64 arithmetic works. softfloat itself is target-
independent and fully validated on x86-64 — the gap is purely the ESP backends.

## Approach

Mirror the arm32 model (`ir_codegen_arm32.inc` ~213+, `EmitNode64Arm32` /
`EmitUDivMod64Arm32`): a 64-bit value lives in a register pair (riscv `a0:a1` =
lo:hi; xtensa an `a`-reg pair), 32-bit sources widen into it, and each op has a
pair lowering:

- add/sub: lo add/sub + carry/borrow into hi.
- and/or/xor: independent on each half.
- shl/shr (incl. >=32 and by-register): the cross-word shift sequence.
- mul: 64x64 low-64 via 32-bit limb partials (arm32 has the recipe).
- div/mod: restoring long division (arm32 `EmitUDivMod64Arm32`), or route to a
  builtinheap soft helper (xtensa LX6 already has `__pxx_*divsi3` 32-bit; a
  64-bit `__pxx_udivdi3` would be the analog).
- compares: hi-then-lo.

Dispatch on `IntToTypeKind(IRTk[node])` being a 64-bit kind (Int64/UInt64) at the
top of the `IR_BINOP` handler, before the 32-bit fall-through. Also fix the
tyString misclassification so Int64 `+` isn't mistaken for frozen-string concat.

Order within: load/store + add/sub + and/or/xor/shifts + compares first (covers
most of softfloat), then mul, then div/mod. Validate each on QEMU vs the x86-64
oracle with `tools/esp_run_bare.sh` (the `test_esp_softfloat_probe.pas` harness is
ready and currently the gating test).

## Notes

- error-not-miscompile: until a 64-bit op is implemented, leave it erroring (the
  string-concat misclassification already does, which is why softfloat currently
  refuses rather than truncating — good). Add an explicit "ESP: 64-bit <op> not
  yet implemented" error for the truncating add/sub/mul cases so they stop
  silently producing wrong results.
- x86-64 untouched -> `make test` byte-identical; reseed via `make bootstrap` if
  a shared-IR change perturbs the fixedpoint.
- ESP self-host is NOT a goal (device RAM); validation is QEMU output-equality.
