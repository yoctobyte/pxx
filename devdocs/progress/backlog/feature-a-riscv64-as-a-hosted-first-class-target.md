---
track: A
prio: 50
type: feature
blocked-by: []
summary: "pxx has no riscv64 target at all — only riscv32, which exists for ESP-class bare metal. Real RISC-V hardware (notebooks, SBCs) is RV64GC running Linux, so today we cannot build for the machines RISC-V actually ships on. The harness is already ready: run_target.sh handles riscv64, install_qemu.sh installs qemu-riscv64, twatch_web lists it in CROSS_TARGETS — nothing can produce a binary for it."
status: backlog
owner: ""
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

## 2026-08-21 — the first question, ANSWERED by measurement

The ticket says the widen-vs-fork question *"decides the size of the job"* and is
*"a measurement, not a judgement call"*. Measured. The answer is **widen**, and
two of the ticket's own premises did not survive.

### The precedent points one way, and it is the wrong way

Both existing 32/64 pairs are **entirely separate backends**: `ir_codegen_arm32`
and `ir_codegen_aarch64` share **zero** emitter helper names, and so do
`ir_codegen386` and `ir_codegen`. Cheapest available evidence, as the ticket
said — and it does not transfer, for a reason that is itself measurable:
**those pairs are different instruction sets.** aarch64 is not wide arm32; it is
a new encoding. RV32 and RV64 are the *same* ISA with XLEN as a parameter.

### What the numbers say

| | |
| --- | --- |
| `ir_codegen_riscv32.inc` | **3441 lines** — the smallest hosted backend we have |
| `rv32enc.inc` (pure encoders) | **208 lines**, and RV64's base encodings are the *same bits* |
| `rv32_*` calls inside the backend | **778**, of which **260** are the width-sensitive `lw`/`sw` |
| `rv32_*` calls **outside** the backend | **140**, across five files |

That last row is the finding that decides it. `rv32_*` is not contained in the
backend: `symtab.inc` (47), `cparser.inc` (37), `exception_emit.inc` (31),
`pasparser_proc.inc` (17), `pasparser_prog.inc` (8) — and **87 of those 140 are
`lw`/`sw`**, i.e. exactly the width-sensitive ones. Forking the backend would
leave every one of those five files still needing an XLEN-aware path, so the fork
buys a duplicated 3441-line file and solves none of the actual problem.

### The two premises that did not survive

**"riscv32 carries bare-metal assumptions from the ESP work woven through it."**
It does not. The whole backend contains **one** `EspBareBoot` reference and five
occurrences of the word "bare". The ESP coupling lives in `compiler.pas`,
`elfwriter.inc`, `pasparser_prog.inc` and friends — the driver and the image
writer — not in codegen. So riscv32 is a *clean* base to widen, which is the
opposite of the ticket's expectation.

**"riscv32's open bug list must not block riscv64."** Right conclusion, but the
reasoning changes: if the backend is shared, most of those bugs become *shared*
too. That is an argument in favour, not against — fixing softfloat subnormals or
byval record params once fixes both — but it must be stated, because "riscv64 is
not blocked by riscv32's bugs" stops being automatically true the moment the file
is shared. The bugs that are genuinely riscv32's are the bare-metal ones.

### Shape of the work, in order

1. **`rv32enc.inc` → `rvenc.inc`**, additively. RV64 needs ~15 encoders the file
   does not have: `ld`/`sd` (funct3 3), and the `W` family (`addw`/`addiw`/`subw`/
   `sllw`/`srlw`/`sraw`/`mulw`/`divw`/`remw`, opcodes `$3B`/`$1B`). Everything
   else is bit-identical.
   **One real correctness trap, already located:** `rv32_slli`/`srli`/`srai` mask
   the shift amount to **5 bits** (`sh and $1F`). RV64 shifts take **6**
   (`and $3F`), and the extra bit sits where RV32 puts part of `funct7` — so a
   shift by 32..63 would silently encode as a *different instruction*. Exactly
   the plausible-wrong-value shape this repo keeps paying for.
2. **XLEN-parameterised load/store helpers** (`rv_lx`/`rv_sx`, picking `lw`/`sw`
   or `ld`/`sd` from `TARGET_PTR_SIZE`), then convert the pointer-width call
   sites mechanically — 260 in the backend, 87 outside. The rest of the 918 calls
   are width-neutral.
3. Register width, ABI (LP64 vs ILP32), the `elfwriter` machine/class fields.
4. **Hardware float is a separate slice, and bigger than it looks.**
   `rv32enc.inc` has **zero** F/D encoders — riscv32 is softfloat throughout.
   RV64**GC** has hardware double, so a first-class hosted target wants the whole
   F/D instruction set plus its ABI. Do NOT fold this into the widening; land
   riscv64-with-softfloat first, hardware float second.

### Side finding CONFIRMED, and filed

The ticket flagged it as worth checking separately, and it is real:
`tools/twatch_web.py:89` lists `riscv64` in `CROSS_TARGETS` while the test
manager mentions it **nowhere** — so the dashboard carries a column that cannot
ever be built. An empty column reads as "no news", not as "impossible". Filed as
[[bug-t-twatch-web-lists-a-target-that-cannot-be-built]] (Track T's file, not
mine to fix).

### Status

The question the ticket asks first is answered; the implementation is a
multi-session job and is not started. Back to `backlog` with the plan above
rather than held in a lock nobody is working.
