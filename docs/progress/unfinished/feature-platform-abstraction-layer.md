# Platform Abstraction Layer (PAL): per-platform RTL port at one seam

- **Type:** feature (compiler axis + Track B RTL architecture)
- **Status:** unfinished (halted — was working/Codex)
- **Owner:** — (lock released; last worked by Codex)
- **Opened:** 2026-06-20
- **Relation:** foundation for `lib-text-file-io-assign-rewrite`,
  `feature-networking`, and any IO-bearing stdlib. Backend selection rides the
  Pascal-`uses` search-path slice still open in
  `feature-dynamic-include-paths-config`. Consistent with the "own RTL from
  scratch" + networking "own transport / reuse protocols" strategy.

## Problem

The RTL (`lib/rtl/*`) is flat with **no platform branching**, and historically
the compiler predefined only a **CPU axis** (`CPU32/64`, `CPUXTENSA`, …) plus
`PXX_ESP_BARE` and host `LINUX`. Networking, file IO, time, and threading depend
on the platform (posix-hosted vs ESP-IDF/FreeRTOS-hosted), not the CPU —
aarch64 can be Linux or bare; xtensa/riscv32 ESP code normally rides IDF.
Without an explicit axis and a single porting seam, platform `{$ifdef}`s would
scatter through every IO library.

## Two axes (untwine them)

1. **CPU** — codegen target (exists): x86_64 / i386 / aarch64 / arm32 / xtensa /
   riscv32.
2. **Platform** — `posix` (hosted: syscalls, fd IO, sockets, dlopen) vs `esp`
   (ESP-IDF/FreeRTOS-hosted: vendor VFS/lwIP/tasks/timers), extensible to other
   RTOS later. Bare ESP remains a separate constrained profile, not the default
   PAL assumption.

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
  esp backend IDF-shaped but stubbed/partial where no VFS/lwIP binding exists
  yet. **Track B.**
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
- 2026-06-20 — Track B resumed. User clarified the ESP PAL assumption: ESP means
  ESP-IDF/FreeRTOS-hosted, not bare metal. Bare remains useful for low-level
  compiler tests, but PAL's ESP backend should target IDF services (VFS/lwIP/
  FreeRTOS/timers) as they are bound.
- 2026-06-20 — Added first Track B PAL slice: `lib/rtl/platform.pas` with
  common platform code/capability queries, byte-handle read/write/close,
  unsupported sentinel, and yield/clock hooks. Posix backend implements raw
  read/write/close syscalls; ESP backend is IDF-shaped (`vTaskDelay`,
  `esp_timer_get_time` on ESP CPU targets) and returns unsupported for byte IO
  until VFS/lwIP bindings land. Added `test/lib_platform*.pas` and wired them
  into `make lib-test`; native posix and native `--platform=esp` smokes pass on
  pinned v18. Cross ESP object smoke currently hits the same existing
  target-codegen wall as the ESP hello examples (`unsupported node`/`call_ind`),
  so object-level PAL validation waits on that Track A issue.
- 2026-06-20 — Extended byte-handle PAL with `PalOpen` and portable PAL open
  flags. Posix maps to raw `openat`; ESP-IDF backend returns unsupported until
  VFS binding work lands. `test/lib_platform.pas` now writes and reads a small
  file through PAL, while `test/lib_platform_esp.pas` asserts no host fallback
  for open/read under native `--platform=esp`.
- 2026-06-20 — Replaced the interim `lib/rtl/platform.pas` platform `ifdef`
  switch with a facade plus per-platform `platform_backend` units selected by
  the Pascal unit search path: `lib/rtl/platform/posix/` and
  `lib/rtl/platform/esp/`. `make library-suite-green` now compiles PAL tests with
  explicit `-Fu` backend paths, proving path-selected backend binding while
  keeping callers on `uses platform`.
- 2026-06-21 — Extended PAL file IO beyond open/read/write/close: added
  `PalSeek`/`PalTell`, `PalFlush`, `PalDelete`, `PalRename`, `PalMkdir`, and
  `PalRmdir`. POSIX maps these to raw Linux syscalls (`lseek`, `fsync`,
  `unlinkat`, `renameat`, `mkdirat`). ESP-IDF real CPU targets now use
  IDF/newlib stdio over VFS (`fopen`/`fread`/`fwrite`/`fseek`/`fflush`/
  `fclose`) plus `remove`/`rename`/`mkdir`/`rmdir`; native `--platform=esp`
  remains unsupported to prevent host fallback. Validation: `make lib-test`,
  `make library-suite-green`, and ESP object compile smokes for both
  `--target=riscv32 --platform=esp` and `--target=xtensa --platform=esp`.
  `readelf -Ws` shows the ESP objects importing the expected IDF/newlib symbols.
- 2026-06-21 — Added first PAL network slice: IPv4 TCP socket primitives
  (`PalSocket`, reuseaddr, nonblocking, bind/connect/listen/accept, send/recv,
  shutdown, socket close). POSIX backend uses raw Linux syscalls, including i386
  `socketcall`; ESP-IDF real CPU targets bind to lwIP (`lwip_socket`,
  `lwip_bind`, `lwip_connect`, `lwip_listen`, `lwip_accept`, `lwip_recv`,
  `lwip_send`, `lwip_shutdown`, `lwip_close`, `lwip_fcntl`, `lwip_setsockopt`).
  Native `--platform=esp` still returns unsupported for every network primitive
  to prevent host fallback. Validation: POSIX loopback TCP roundtrip in
  `test/lib_platform_net.pas`, `make lib-test`, `make library-suite-green`, and
  ESP object compile smokes for `--target=riscv32 --platform=esp` and
  `--target=xtensa --platform=esp`; `readelf -Ws` shows the expected lwIP
  imports.
- 2026-06-21 — Re-homed `lib/rtl/asyncnet.pas` transport onto PAL sockets:
  removed the duplicated per-arch Linux socket syscall layer from `asyncnet`,
  and now use `PalSocket`/nonblocking/bind/connect/listen/accept/send/recv/
  close while keeping `scheduler` as the existing coroutine readiness reactor.
  `test/test_asyncecho.pas` now compiles with `-Fulib/rtl/platform/posix` in the
  native and hosted cross Makefile gates. Validation: native async echo via
  pinned v32 and live `compiler/pascal26`, i386 async echo under
  `tools/run_target.sh`, `make lib-test`, and `make library-suite-green`.

- 2026-06-21 — HALTED → `unfinished/`. `working/` lock released (no active agent). No uncommitted code this round; Track A step 1 already done+pinned, Track B PAL layering remains.
