# Random library — HW/OS/software tiered RNG (cross-target capability test)

- **Type:** feature
- **Status:** backlog
- **Relation:** a real, reusable RTL library that doubles as a broad
  cross-target test: runtime capability probing, per-target inline asm, a
  syscall entropy path, procedural-type dispatch, an `initialization` section,
  and a deterministic software path that is byte-identical across all 6 targets
  (a perft-style oracle). Touches feature-threadsafe-io-serialization (global
  state under threads) and the ESP profiles (HW RNG register / esp_random).

## Goal

A `Random` unit that gives good random numbers with **no per-platform code from
the caller**: hardware RNG by default when available, OS CSPRNG otherwise,
software PRNG as the fallback — and the deterministic software PRNG whenever the
user seeds. Modern 256-bit-state / 64-bit-output internals, not a legacy
16/32-bit LCG. FPC-compatible surface so existing code (and the Lazarus line)
is unaffected.

## Three-tier entropy source (chosen once at unit init)

| Tier | Source | Selected when |
| --- | --- | --- |
| 1 — HW instruction | x86 `RDRAND`/`RDSEED`; aarch64 `RNDR` (FEAT_RNG); ESP RNG register / `esp_random` | capability probe says present |
| 2 — OS CSPRNG | `getrandom(2)` syscall (Linux, kernel-ABI — fits the no-libc design); `/dev/urandom` fallback | hosted, no usable HW instruction |
| 3 — Software PRNG | seeded from the best available tier above | fallback, **and forced whenever the user seeds** |

The init probe selects a backend and stores it in a **proc-typed var**
(indirect dispatch — exercises procedural types); the `initialization` section
runs the probe once.

## Seed forces software (key rule)

Hardware RNG is not reproducible or seedable. Therefore:
- `Randomize` → uses tier 1/2 (best available, non-reproducible).
- `RandomSeed(x)` / assigning `RandSeed` → switches to **tier 3 deterministic**
  so the stream is reproducible. This is intentional and documented, not a
  limitation.

## PRNG choice

**xoshiro256++** (256-bit state, 64-bit output) — modern, fast, well-tested.
(PCG64 acceptable alternative; decide in design.) No legacy LCG. The seeded
software stream is **identical across all targets** → the cross-target oracle.
Seed expansion via SplitMix64 from the user seed.

## API surface

**FPC-compatible (keep the Lazarus line):**
- `function Random: Double;` — [0,1)
- `function Random(L: Integer): Integer;` — [0, L)
- `procedure Randomize;`
- `RandSeed` variable (assignment → tier 3, reproducible)

**PXX extensions (on top):**
- `function Random64: UInt64;` / `function Random128: <128-bit>;`
- `procedure RandomBytes(var buf; n: Integer);`
- `function RandomRange(lo, hi: Int64): Int64;`
- `procedure RandomSeed(seed: UInt64);` (explicit deterministic entry)

## Per-target capability detail / landmines

- **x86-64 / i386:** `CPUID` leaf 1 ECX bit 30 = RDRAND; leaf 7 EBX bit 18 =
  RDSEED. `RDRAND` can **fail** (CF=0) → bounded retry loop, then fall to next
  tier. Inline asm (CPUID + RDRAND).
- **aarch64:** `RNDR`/`RNDRRS` are **optional** (FEAT_RNG); probe
  `ID_AA64ISAR0_EL1` RNDR field; `MRS` reads the system reg at EL0. Fall back if
  absent.
- **arm32:** no standard user HW RNG instruction → OS tier only.
- **riscv32 (user):** Zkr entropy source is an M-mode CSR, not user-accessible →
  OS tier (or ESP HW register on device).
- **ESP32 (xtensa / riscv32, bare + IDF):** read the RNG data register (bare) or
  `esp_random` (IDF). **Caveat:** ESP RNG is only truly random with the RF/WiFi
  clock enabled — document; do not claim CSPRNG quality in bare profile without
  it.
- **`getrandom`** may be absent (old kernel) or block at early boot → fall to
  `/dev/urandom`, then software.
- **Thread safety:** global PRNG state under threads → per-thread state or a
  lock (coordinate with feature-threadsafe-io-serialization).

## Testing strategy

- **Software path (seeded) — the deterministic oracle.** Fixed seed → a fixed
  stream; assert **byte-identical across all 6 targets** (cross-bootstrap-style
  run). This is the primary regression check.
- **HW / OS path — statistical smoke** (can't byte-compare true randomness):
  nonzero, varies run-to-run, rough uniformity over a large sample.
- **Capability matrix:** a debug override to force each tier; verify the init
  dispatch selects the right backend on each platform and that fallbacks chain
  correctly (HW-fail → OS → software).

## Design mandate: ONE elegant library file (arch hidden in the compiler)

Hard requirement: the unit is a **single elegant `.pas` file**, no per-arch
`{$ifdef}` soup. The per-target instruction mess (RDRAND opcodes, CPUID, RNDR
`MRS`, ESP RNG-reg address) lives in **`builtinheap` compiler intrinsics**, not
in the library. The library then reads clean:

```pascal
unit Random;
// 1. software PRNG core — pure Pascal (xoshiro256++ + SplitMix64). The bulk.
// 2. thin source dispatch (one-liners over intrinsics / syscall):
function HWRand64(out v: UInt64): Boolean;  // = __rdrand intrinsic; compiler emits per target
function OSRand64: UInt64;                  // = getrandom syscall
// software path = the PRNG core
```

`__rdrand`/`__cpuid`/`__rndr` resolve differently per target inside the
compiler; the `.pas` never sees an arch branch. (More elegant than FPC, whose
System-unit random is scattered per platform.)

## Compiler switch: preference, NOT a replacement for the safety fallback

A switch picks the **default UNSEEDED source** — e.g. `{$RNG AUTO|HARDWARE|
SOFTWARE}` (or `--rng=`):

- **AUTO** (default) — runtime probe: HW if present, else OS, else software. The
  portable, safe path.
- **SOFTWARE** — always the deterministic-capable PRNG. Smallest, fully
  reproducible.
- **HARDWARE** — prefer HW.

**Critical safety rule:** on portable (multi-CPU) binaries the switch must NOT
make HW purely compile-time — a `HARDWARE` binary on a CPU without RDRAND would
hit an illegal instruction. So in portable builds, `HARDWARE` still keeps the
**runtime probe + software fallback**. The switch tunes preference; it does not
delete the safety net.

**Exception — fixed platforms (ESP32):** the HW RNG is known to exist, so the
switch MAY **hard-select** HW and **elide the probe + software path** entirely →
smaller code. This is the embedded win: one library source, but on a known
target it compiles down to just the HW read.

**Orthogonal:** the seed rule (`RandSeed`/`RandomSeed` → software) is runtime
state, independent of the switch. The switch sets the *unseeded* default source;
seeding always flips to the deterministic PRNG. No conflict.

## Dependency: HW-instruction emission (and how to avoid blocking on it)

Tiers 1 (HW) need a few fixed CPU instructions emitted (CPUID, RDRAND, `MRS
RNDR`, ESP RNG-reg / MMIO read). **Tiers 2 (getrandom) and 3 (software) need no
asm at all** — so slices 1–3 ship a useful library before any asm work. Only
slices 4–6 touch instructions.

Two ways to satisfy the HW tier; **prefer the second:**

1. **General inline asm** (feature-inline-asm-depth) — currently x86-64-only +
   rudimentary. Heavy: needs a per-target asm frontend to mature. Over-kill for
   ~4 fixed sequences.
2. **Dedicated compiler intrinsics in `builtinheap`** (RECOMMENDED) — emit the
   fixed sequences directly via EmitB as builtins (`__rdrand`, `__cpuid`,
   `__rndr`, raw MMIO read), exactly like the existing `__pxxrawsyscall`. No
   asm-frontend dependency; reuses a proven mechanism; scoped to the handful of
   ops the lib needs.

So this ticket is **not hard-blocked** on feature-inline-asm-depth: slices 1–3
are asm-free, and slices 4–6 use intrinsics (option 2). Full inline-asm-depth is
only needed if a user writes arbitrary asm — out of scope here.

## Slices

1. **Software PRNG core** — xoshiro256++ + SplitMix64 seed; deterministic;
   cross-target byte-identical oracle. Pure, no platform code. Lands first.
2. **FPC surface** — `Random`/`Random(L)`/`Randomize`/`RandSeed` over the core.
3. **OS tier** — `getrandom` syscall (+ `/dev/urandom` fallback); used by
   `Randomize`.
4. **HW tier x86** — CPUID probe + RDRAND (+ retry); inline asm.
5. **HW tier aarch64** — RNDR probe + read.
6. **ESP tier** — RNG register (bare) / esp_random (IDF).
7. **Thread-safe state** — per-thread or locked (with the threadsafe-io work).

## Acceptance

`Random*` works with zero caller platform code; init auto-selects the best tier
per platform; seeding switches to a reproducible software stream that is
byte-identical across all 6 targets; HW/OS tiers pass statistical smoke; the
capability matrix shows correct selection + fallback chaining. FPC-surface
programs compile and run unmodified.

## Log
- 2026-06-18 — opened. Tiered HW→OS→software RNG with init-time capability probe
  (proc-typed dispatch), seed-forces-software rule, xoshiro256++ core, FPC
  surface + PXX extensions. Chosen as a broad cross-target test (CPUID/feature-
  reg probing, per-target HW-instruction emission, getrandom syscall,
  deterministic software oracle). Per-target landmines + dual-mode test
  (deterministic-software-oracle + statistical-HW) recorded.
- 2026-06-18 — clarified asm dependency: only HW tiers (slices 4–6) need
  instruction emission; tiers 2–3 (slices 1–3) are asm-free, so the lib ships
  useful first. HW tier should use dedicated `builtinheap` intrinsics
  (`__rdrand`/`__cpuid`/`__rndr`, à la `__pxxrawsyscall`), NOT block on the
  general feature-inline-asm-depth frontend. Not hard-blocked.
- 2026-06-19 — **interim software slice landed** (track B): `lib/rtl/random.pas`,
  a deterministic 32-bit Numerical-Recipes LCG (`RandSeed`/`RandU32`/`Random(n)`/
  `RandRange`), reproducible-from-seed, asserted in `make lib-test`. Uses an
  `initialization` section for a lively default seed. **NOT** the planned
  256-bit-state / 64-bit-output xoshiro256**: pinned v9 lacks the 64-bit ops
  needed (`xor`, large shifts, 64-bit hex literals) — see
  bug-64bit-shift-xor-literal-gaps. Upgrade the software tier to xoshiro256** +
  splitmix64 seeding once those land; HW/OS tiers (slices 4–6) still as scoped.
- 2026-06-20 — **xoshiro256** software core landed** (track B, slice 1 done):
  `lib/rtl/random.pas` upgraded from the interim LCG to xoshiro256** with
  SplitMix64 seed expansion. 64-bit ops (xor, large shifts, hex literals) now
  available on pinned v20. Output verified byte-identical against a C reference
  implementation. The LCG is retained alongside as `LCGSeed`/`LCGNext` for
  constrained targets (ESP32). Public surface (`RandSeed`/`Random(n)`/`RandRange`)
  now delegates to xoshiro. `RandU32` replaced by `XoshiroNext`/`LCGNext`.
  Slices 1–2 done (software core + FPC surface). Remaining: OS tier (slice 3),
  HW tiers (slices 4–6), thread safety (slice 7).
