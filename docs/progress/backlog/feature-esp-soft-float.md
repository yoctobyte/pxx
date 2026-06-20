# ESP soft-float (xtensa + riscv32 float value model)

- **Type:** feature (cross codegen depth, ESP targets)
- **Status:** backlog
- **Owner:** Track A
- **Opened:** 2026-06-20

## Problem

The two ESP targets have **no float value model at all**. Even trivial float
code errors:

```
$ pascal26 --target=riscv32 'a:=1.5; b:=a+2.0' ...
pascal26: error: target riscv32: unsupported node in IR codegen
$ pascal26 --target=xtensa  ...
pascal26: error: target xtensa: unsupported node in IR codegen: call_ind
```

float literals, loads/stores, arithmetic, comparisons, int<->float conversions,
params, returns and formatting are all absent. (The Linux trio — i386 / aarch64 /
arm32 — got all of this in `feature-cross-float-variant` and float returns in
`feature-cross-float-returns`; the ESP targets were never in scope there.)

## Why it's a separate, larger arc

ESP base parts have no (or limited) hardware FPU:
- ESP32-C3 (riscv32): no FPU → full **soft-float** (IEEE-754 double) needed.
- ESP32-S3 (xtensa): single-precision FPU only; double still needs soft-float.

So unlike the Linux targets (which lean on SSE/VFP hardware), this needs a
software double implementation: add / sub / mul / div / compare / cvt-to-int /
cvt-from-int, plus the formatting path. The portable `builtinheap` float
formatters (PXXWriteFloat*) already exist and are target-independent (the 2^52
round trick) — those can be reused once a double can be produced.

## Approach (sketch)

1. Decide the value model: carry a double as raw bits in a core-register pair
   (riscv32 a-pair / xtensa a-pair), mirroring how arm32 spills d0 to r0:r1 — but
   here there's no FPU to do the math, so every op calls a soft-float helper.
2. Implement (or vendor, license-clean) the soft-float kernels in plain Pascal in
   `builtinheap` so they cross-compile to any target: `__pxx_dadd/dsub/dmul/ddiv`,
   `__pxx_dcmp`, `__pxx_d2i/i2d`, `__pxx_s2d/d2s`. (Compare-only soft-float is
   enough to bootstrap, then widen.)
3. Wire the IR float nodes in `ir_codegen_riscv32.inc` / `ir_codegen_xtensa.inc`:
   literal, IR_LOAD_SYM/STORE (8-byte slot move), binops -> helper calls,
   intrinsics, then params + returns (the `feature-cross-float-returns` recipe
   applies once arithmetic exists).
4. Relax the EmitProcEpilog float guards (symtab.inc ~3713 xtensa / ~3753 riscv32)
   last — only after arithmetic + params land.
5. Add float tests to the ESP/cross suites; QEMU-run.

## Notes

- ESP self-host is NOT a goal (device RAM too small), so the bar is output-equality
  vs the x86-64 oracle on QEMU, not byte-identical self-host.
- Keep the error-not-miscompile rule: leave each piece erroring until it's correct.
- Predecessor context: see `feature-cross-float-returns` (done) for the per-target
  return/param recipe and the arm32 r0:r1<->d0 spill pattern to mirror.
