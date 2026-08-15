---
track: A
prio: 35
type: feature
blocked-by: []
summary: "lib/rtl/random.pas cites `feature-rdrand-cpuid-compiler-builtins` in a source comment for its tier-1 hardware entropy path — and that ticket was never filed. Tiers 2 and 3 ship; tier 1 needs compiler intrinsics for CPUID + RDRAND (x86), MRS RNDR (aarch64) and the ESP RNG register, because the library's design mandate keeps per-arch instructions OUT of the .pas."
---

# Compiler intrinsics for hardware entropy (CPUID / RDRAND / RNDR / ESP RNG)

- **Type:** feature (intrinsics — **Track A**). Filed by Track B on 2026-08-15,
  which owns `lib/rtl/random.pas` and cannot add per-target instructions to it.
- The library already names this ticket in a comment; the ticket did not exist.
  A `find` for it returns nothing, which is how a dangling reference reads to
  the next person: as if the work were tracked when it is not.

## Why it belongs in the compiler, not the library

[[feature-random-library]] carries a hard design mandate: **one elegant `.pas`
file, no per-arch `{$ifdef}` soup.** The per-target instruction mess is supposed
to live behind intrinsics so the library reads as three one-line tier selections.
Tiers 2 (getrandom/urandom) and 3 (xoshiro256**) satisfy that today because
neither needs a special instruction. Tier 1 does, and that is the whole ask.

## What is needed

| target | mechanism | probe |
| --- | --- | --- |
| x86-64 / i386 | `RDRAND` (and optionally `RDSEED`) | `CPUID` leaf 1 ECX bit 30; leaf 7 EBX bit 18 for RDSEED |
| aarch64 | `MRS` of `RNDR` / `RNDRRS` | `ID_AA64ISAR0_EL1` RNDR field — FEAT_RNG is **optional** |
| arm32 | none in user mode | — (library stays on tier 2) |
| riscv32 | Zkr is an M-mode CSR, not user-reachable | — (tier 2) |
| ESP32 xtensa / riscv32 | RNG data register (bare) or `esp_random` (IDF) | always present on the SoC |

Two landmines worth building into the intrinsic rather than leaving to callers:

- **`RDRAND` can FAIL.** It clears CF instead of returning a value, under load or
  entropy exhaustion. The intrinsic must report success, so the library can
  bound its retries and then fall to tier 2 — a silent zero would be a
  catastrophic and invisible failure in a security context.
- **FEAT_RNG is optional on aarch64.** The probe is mandatory; an unconditional
  `MRS RNDR` is an illegal instruction on most cores.

Shape suggestion, matching how the library already dispatches (a proc-typed var
chosen once in `initialization`):

```
function __pxxCpuHasHwRandom: Boolean;
function __pxxHwRandom64(var v: UInt64): Boolean;   { False = failed, try again/fall back }
```

Two entry points, everything arch-specific behind them.

## Note on the ESP tier

ESP's RNG is only truly random with the RF/WiFi clock enabled. Whatever lands
must not let the library claim CSPRNG quality in the bare profile without it —
[[feature-random-library]] says so explicitly and the intrinsic should make the
distinction reportable rather than assumed.

## Gate

`make test` + self-host byte-identical; the probe reporting correctly on a CPU
that HAS the instruction and on one that does not (qemu can model both); and
`test/lib_random.pas` still producing its byte-identical seeded stream on every
target — tier 1 must not perturb the deterministic path, which is seeded and by
definition does not use hardware entropy.
