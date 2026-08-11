---
summary: "riscv32 (and xtensa) reject every __pxxatomic_* op — 'unsupported node in IR codegen: atomic' — so any unit touching an atomic cannot be compiled for them at all, on the two targets whose OS gives real concurrent tasks"
type: bug
track: A
prio: 45
---

# riscv32 / xtensa: no atomic node in IR codegen

- **Type:** bug — Track A (backends), tagged **S** (ESP32 campaign)
- **Status:** backlog
- **Opened:** 2026-08-05
- **Found by:** cross-checking the new `lib/rtl/palatomic.pas` across targets.

## Repro

```pascal
program il32;
uses palatomic;
var n, r: LongInt;
begin
  n := 10;
  r := InterLockedIncrement(n);
  writeln(r, '|', n);
end.
```

```
i386     11|11   arm32   11|11   aarch64  11|11   x86-64  11|11
riscv32  pascal26:52: error: target riscv32: unsupported node in IR codegen: atomic
```

The same happens for `--target=xtensa`. It is not specific to `palatomic` —
anything reaching `__pxxatomic_xchg/cas/add` fails, including `palsync`'s
mutex and therefore `palthreadobj`.

## Why it is worth more than it looks

These are exactly the two targets where the OS *does* hand out concurrent tasks:
under ESP-IDF, FreeRTOS gives real tasks on both C3 (riscv32) and S2/S3
(xtensa), and Track S's whole point is that ESP is not a Unix but it IS
concurrent. A mutex or a refcount on those targets currently has no primitive
to stand on.

Xtensa has `S32C1I` (compare-and-store, with `SCOMPARE1`) on the LX6/LX7 cores,
so xtensa is implementable rather than blocked on hardware — the 64-bit peers
are correctly out of scope on a 32-bit target either way.

> **CORRECTION 2026-08-11 (claude-A): the riscv32 half of this paragraph was
> WRONG, and implementing it as written would emit an ILLEGAL INSTRUCTION.**
>
> It read: *"RV32 has the `A` extension … and the ESP32-C3 implements it."* The
> ESP32-C3 does **not**. Its core is **RV32IMC** — integer, multiply,
> compressed, **no `A`** — so it has no `amoadd.w`, no `amoswap.w` and no
> `lr.w`/`sc.w`. The repo already agrees: `compiler/rv32enc.inc` is headed
> *"typed instruction encoders for RISC-V RV32IMC codegen"* and carries no AMO
> or LR/SC encoders, and the C3 is what `--target=riscv32` means here (43
> in-repo mentions, vs 1 each for C6 and P4).
>
> `A` does exist on **esp32c6 / esp32h2** (RV32IMAC) and **esp32p4**
> (RV32IMAFC), so an AMO path is legitimate — but as a per-CHIP capability, not
> as an assumption about riscv32.

## What the primitive has to be, per chip

Because it differs *within* riscv32, this cannot be decided per ISA — which is
what raised [[decide-esp-soc-axis-and-capability-table]]. Once a capability
table exists, the three arms fall out of it:

| condition | primitive |
| --- | --- |
| has atomic ISA (xtensa `S32C1I`; riscv with `A`) | emit it — a CAS retry loop |
| no atomic ISA, **1 core** (esp32c3, esp32c2) | interrupt-masked critical section, as ESP-IDF does |
| no atomic ISA, **2 cores** | refuse honestly — and no ESP part is in this box |

A **spinlock fallback is not an option**: a spinlock needs an atomic primitive
to build on, so it does not help where one is missing. Masking interrupts is
what replaces it, and is correct precisely because those parts are single-core.

Nor is single-core a reason to skip atomicity altogether: FreeRTOS preempts
tasks on one core, so `n := n + 1` still tears between two tasks. Single-core
means the CHEAP primitive suffices.

Xtensa needs no chip gate at all — `S32C1I` is on every LX6/LX7 part, single-
and dual-core alike — so the xtensa half can land before the SoC axis does.

## Scope of the fix

Only the 32-bit ops: `ATOMIC_XCHG`, `ATOMIC_CAS`, `ATOMIC_ADD`. The `*64`
variants should keep their existing honest refusal on any 32-bit target, the
way i386 and arm32 already word it ("`__pxxatomic_*64 not supported (32-bit
target)`") — note that message is *better* than the one riscv32 emits, which
names an IR node rather than the feature.

## Gate

Track A: `make test` + self-host fixedpoint (byte-identical), plus the riscv32
cross run. `tools/fpc_diff_probe.sh` case `interlocked-family` is the
native-side check; a cross assertion for the 32-bit half belongs in
`tools/lib_cross_sweep.sh`.
