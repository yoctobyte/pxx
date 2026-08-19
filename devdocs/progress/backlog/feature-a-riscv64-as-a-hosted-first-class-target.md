---
track: A
prio: 50
type: feature
blocked-by: []
summary: "pxx has no riscv64 target at all — only riscv32, which exists for ESP-class bare metal. Real RISC-V hardware (notebooks, SBCs) is RV64GC running Linux, so today we cannot build for the machines RISC-V actually ships on. The harness is already ready: run_target.sh handles riscv64, install_qemu.sh installs qemu-riscv64, twatch_web lists it in CROSS_TARGETS — nothing can produce a binary for it."
---

# riscv64 as a hosted, first-class target

**Filed 2026-08-19 at the user's prompting:** RISC-V *"is a serious platform… these days there
are notebooks with a riscv processor — it's here to stay."* Today the only RISC-V support we
have is **riscv32, shaped by ESP-class bare metal**, which is not the thing RISC-V hardware
actually ships as.

## Measured

**The compiler knows no riscv64.** `compiler/defs.inc` target mentions: x86-64 (32),
xtensa (11), riscv32 (8), i386 (8), aarch64 (7), arm32 (5). Backend files:
`ir_codegen386` / `_aarch64` / `_arm32` / `_riscv32` / `_xtensa`. **No `ir_codegen_riscv64`.**

**But the harness already expects it**, which is the striking part:

    tools/run_target.sh:8      # arch: x86_64 | i386 | aarch64 | arm32 | riscv32 | riscv64
    tools/run_target.sh:78-80  riscv64) need qemu-riscv64; exec qemu-riscv64 "$bin" "$@"
    tools/install_qemu.sh:24   installs qemu-riscv64
    tools/twatch_web.py:89     CROSS_TARGETS = (..., "riscv32", "riscv64", ...)

**So we can already RUN riscv64 binaries and cannot PRODUCE one.** Side finding worth
checking separately: `twatch_web`'s `CROSS_TARGETS` lists a target that can never be built,
so the dashboard may be carrying a column that is structurally empty rather than failing —
an empty column reads as "no news", not as "impossible".

## Why riscv32 is not this ticket

RV32 and RV64 differ in XLEN — register width, pointer size, and the whole set of `*W`
instructions. Our riscv32 additionally carries **bare-metal assumptions from the ESP work**
and a substantial open-bug list (softfloat subnormals, atomics, byval record params, nested
dynamic arrays, `SetLength` on a string array element, hosted `writeln` hanging, chess-perft
runtime corruption). **Those bugs are riscv32's; they are not automatically riscv64's, and
riscv64 must not be filed behind them.**

## The first question — it decides the size of the job

**Is riscv64 a widening of `ir_codegen_riscv32.inc` (XLEN as a parameter) or a new backend?**
Measure before estimating. RV64 is RV32 with wider registers plus the `W` instruction family,
so a parameterised backend is plausible — but so is the answer that riscv32's bare-metal
assumptions are woven through it deeply enough that sharing costs more than it saves. **This
is the one thing to establish first**, and it is a measurement, not a judgement call.

Useful precedent: we already have both a 32-bit and a 64-bit backend in two other families
(i386/x86-64, arm32/aarch64). **How those two pairs were split — shared or separate — is the
cheapest available evidence** for what to do here.

## Why it is worth doing

- **It is where RISC-V actually is.** Hosted RV64GC Linux is what SBCs and the first notebooks
  run. An MCU-only RISC-V story misses the platform the user is pointing at.
- **A real milestone is reachable: self-hosting on riscv64.** The compiler is written in
  Pascal, so a hosted riscv64 backend plus the Pascal frontend means pxx could compile itself
  natively on RISC-V hardware. That is a much stronger statement than "we cross-compile to it".
- **It composes with
  [[feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets]]** — "a Python
  compiler for RISC-V, reduced" is exactly the use case that ticket is for.

## Honest scoping

The user has **ESP hardware only** right now, so riscv64 would initially be verified under
qemu — which `run_target.sh` already does for every other cross target, so this is normal
rather than a compromise. Real-hardware validation waits for hardware, and that is fine;
qemu-verified is the same bar every other cross target currently meets.

## Gate

Track A's: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`, plus the riscv64
cross tests under qemu once the target exists. Track T sweeps the matrix — note it already
has a `riscv64` slot waiting in `CROSS_TARGETS`.

## Log
- 2026-08-19 — filed. Prio 50 as a strategic target rather than an urgent one; the user may
  well rank it higher, and the "here to stay" framing suggests it should not sit at the
  bottom for long.
