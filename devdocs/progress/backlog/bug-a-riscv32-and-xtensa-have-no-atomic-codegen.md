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

RV32 has the `A` extension (`amoadd.w`, `amoswap.w`, `lr.w`/`sc.w`) and the
ESP32-C3 implements it. Xtensa has `S32C1I` (compare-and-store) on the LX6/LX7
cores. So both are implementable rather than blocked on hardware — the 64-bit
peers are correctly out of scope on a 32-bit target either way.

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
