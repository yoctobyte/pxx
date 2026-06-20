# Platform Abstraction Layer (PAL): per-platform RTL port at one seam

- **Type:** feature (compiler axis + Track B RTL architecture)
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-20
- **Relation:** foundation for `lib-text-file-io-assign-rewrite`,
  `feature-networking`, and any IO-bearing stdlib. Backend selection rides the
  Pascal-`uses` search-path slice still open in
  `feature-dynamic-include-paths-config`. Consistent with the "own RTL from
  scratch" + networking "own transport / reuse protocols" strategy.

## Problem

The RTL (`lib/rtl/*`) is flat with **no platform branching**, and the compiler
predefines only a **CPU axis** (`CPU32/64`, `CPUXTENSA`, …) plus `PXX_ESP_BARE`
and host `LINUX`. There is no first-class **platform/OS axis**. Networking, file
IO, time, and threading depend on the platform (posix-hosted vs esp32-bare), not
the CPU — aarch64 can be Linux or bare; xtensa is esp. Without an explicit axis
and a single porting seam, platform `{$ifdef}`s would scatter through every IO
library.

## Two axes (untwine them)

1. **CPU** — codegen target (exists): x86_64 / i386 / aarch64 / arm32 / xtensa /
   riscv32.
2. **Platform** — `posix` (hosted: syscalls, fd IO, sockets, dlopen) vs `esp`
   (bare: MMIO, no filesystem/sockets yet), extensible to other RTOS later.

Do **not** derive platform from CPU. Add `--platform=posix|esp` (default derived
from target: esp targets/`--esp-profile=bare` → esp, else posix) and predefine:

- `PXX_PLATFORM_POSIX` / `PXX_PLATFORM_ESP`
- **capability** defines (gate on these, not platform names, for graceful
  degradation): `PXX_HAS_FILES`, `PXX_HAS_SOCKETS`, `PXX_HAS_THREADS`,
  `PXX_HAS_DYNLIB`. A new platform just declares its capability set.

## Layering — abstract at the syscall/transport seam, not per feature

```
3. protocols / high libs   HTTP, JSON, hashing, Synapse-reuse   ← pure, portable, written ONCE
2. OS-services RTL         file-IO, sockets-as-streams, time    ← written ONCE against PAL iface
1. PAL (platform port)     byte-handle IO, transport(connect/   ← ONLY place with per-platform code
                           send/recv/poll), clock, yield/thread
0. builtins / codegen      heap, raw syscall, MMIO              ← exists
```

- The **PAL** is the only place with per-platform code. Keep it **small**: a
  primitive that cannot be implemented on both posix and esp does not belong in
  the PAL.
- File IO (`Assign`/`Rewrite`/`WriteLn(f,…)`) and sockets are written **once** on
  PAL byte-handles / transport — so esp32 gets the same API surface for free
  (backed by UART/flash/driver), even if some ops return "unsupported" until the
  esp backend fills in. This is the funny-but-real side effect: portable stdlibs
  that (at least partly) run on esp32.
- `lib/crtl` (C rtl: stdio/string/malloc hooks) bottoms out on the **same PAL**
  primitives — one port serves both Pascal and C rtl, no separate C split.

**Hard rule:** no platform `{$ifdef}` above layer 1. Every leak above the PAL
defeats the design.

## Backend selection

Preferred: each backend in `lib/rtl/platform/<plat>/`, the platform dir on the
**Pascal unit search path**, so `uses platio` binds to the right implementation
with zero ifdefs in callers. This needs the Pascal-`uses` search-path slice of
`feature-dynamic-include-paths-config` (only C `#include` `-I` landed so far).

Interim (until that lands): a single `lib/rtl/platform.pas` with **one**
top-level `{$ifdef PXX_PLATFORM_ESP}` include switch — one branch point only.

Compile-time selection (not a runtime vtable/interface) — right for embedded.

## Scope

In scope:
- Compiler: the platform + capability define axis (`--platform`, the predefines).
  **Track A, small, foundational — do first.**
- RTL: define the minimal PAL interface (byte-handle IO, transport, clock,
  yield); posix backend (largely exists in the raw syscall layer + `asyncnet`),
  esp backend stubbed/partial. **Track B.**
- Re-home existing IO-ish RTL (`asyncnet`, streams, future file-IO) above the
  PAL. **Track B.**

Out of scope (separate tickets):
- The Pascal-`uses` search-path mechanism (→ `feature-dynamic-include-paths-config`).
- The actual file-IO API (→ `lib-text-file-io-assign-rewrite`, but it should be
  written on the PAL once this exists).
- Full esp socket/filesystem backends (own tickets as drivers land).

## Acceptance

- Compiler predefines `PXX_PLATFORM_*` + `PXX_HAS_*` correctly for posix (native
  + Linux cross) and esp (`--esp-profile=bare` xtensa/riscv32); a test asserts
  the define sets per `--platform` / target.
- A documented minimal PAL interface exists with a posix backend; an IO library
  (e.g. the text-file API, or a socket echo) is written **once** against it and
  runs on posix.
- Capability gating works: building an IO lib for esp without a backend yields a
  clear "unsupported on this platform" compile error, never a silent host
  fallback (same principle as the native-only `/usr/include` gate already in the
  C preprocessor).
- No platform `{$ifdef}` above the PAL layer in any re-homed unit.

## Log
- 2026-06-20 — Opened from RTL-portability design discussion. Key decision: two
  axes (CPU vs platform), one porting seam (PAL), capabilities over platform
  names, compile-time backend selection via the unit search path. Step 1 (the
  compiler define axis) is the small Track-A foundation; the layering is Track B.
- 2026-06-20 — **Step 1 DONE (Track A, commit 6da40d6; pinned v17 in 87250c6).**
  `--platform=posix|esp` in compiler.pas (mirrors `--target=`); default derived
  from target (esp targets / `--esp-profile=bare` → esp, else posix), explicit
  flag overrides via `PlatformExplicit`. Globals `TargetPlatform`/`PlatformExplicit`
  + `PLATFORM_*` consts in defs.inc. `PasApplyPlatformDefines` (lexer.inc)
  predefines `PXX_PLATFORM_POSIX/_ESP` + caps `PXX_HAS_FILES/_SOCKETS/_THREADS/
  _DYNLIB` (posix = all, esp = minimal). Test `test/test_platform_defines.pas`
  wired into test-core (asserts posix + `--platform=esp` define sets).
  LANDMINE: `PasApplyTargetDefines` early-`Exit`s for x86_64, so the platform
  call must NOT live at its tail — it is a separate `PasApplyPlatformDefines`
  call right after it in compiler.pas. Gate green: make test byte-identical
  fixedpoint + `--threadsafe`; make cross-bootstrap (i386/aarch64/arm32
  byte-identical); all 3 cross suites pass.
  **Remaining (Track B):** PAL interface (byte-handle IO / transport / clock /
  yield), posix backend, esp stub, IO re-homing, interim `lib/rtl/platform.pas`
  single `{$ifdef PXX_PLATFORM_ESP}` switch.
