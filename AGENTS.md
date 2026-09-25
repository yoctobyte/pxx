# AGENTS.md — start here

For any agent or person picking up PXX cold. Written at the end of active
development (September 2026, beta 0.1 "Blaise"). Nobody is watching this
repository day to day. What follows is what you need to continue without
asking anyone.

**We are looking for sponsors to continue development.** See the README.

## What PXX is

A from-scratch, self-hosting compiler for Free Pascal's dialect (objfpc and
Delphi modes). It writes finished ELF executables itself: no assembler, no
linker, no libc. The same IR and backends also compile C and Nil Python (a
Python-shaped language, compiled ahead of time).

| Area | State at Blaise |
| --- | --- |
| Pascal | Mostly on par with FPC: classes, interfaces, generics, managed strings, dynamic arrays, exceptions, threads. The compiler compiles itself to a byte-identical binary. |
| Targets | Linux x86-64 (native host), i386, aarch64, arm32, riscv32 (cross, run under qemu-user). ESP32-S3 (xtensa) and ESP32-C3 (riscv32) through ESP-IDF. |
| C | A C99-class dialect with common GNU extensions; c-testsuite 220/220 on x86-64. |
| Nil Python | Best effort, with a real backlog. Not CPython and not aiming at CPython parity now. |
| Memory | Leaks are treated as release blockers. See "Known issues" and the BLAISE LEAK LIST in devdocs/progress/LOGBOOK.md. |

## Build from nothing

    sudo apt install fpc make
    git clone https://github.com/yoctobyte/pxx && cd pxx
    make bootstrap        # FPC builds the seed, then pxx rebuilds itself to a byte-identical fixedpoint

A checkout also ships a working compiler at stable_linux_amd64/default/pinned,
so plain `make` works without FPC:

    make compiler/pascal26   # ~12 s; this IS the self-host fixedpoint check
    ./compiler/pascal26 test/hello.pas /tmp/hello && /tmp/hello

"converged after N round(s)" means it rebuilt and reproduced itself. "verified"
means nothing was rebuilt.

## Test

    tools/gate.sh quick   # ~30 s: the fixedpoint plus a quick tier. Run it before every push.
    make test             # the Pascal/core suite
    make test-c           # C
    make test-nilpy       # Nil Python, differential against python3
    make lib-test         # libraries
    make test-uforth      # a real Python program (github.com/yoctobyte/uforth), 17 corpora vs CPython

The repository's Claude Code hooks refuse the full suites by default (a speed
guard). Prefix PXX_ALLOW_FULL_SUITE=1 when you mean it.

Check verdicts by the job's own printed line (for example "gate: GREEN"), not
by a wrapper's exit status.

## Leaks — how to check

- Pascal/NilPy on the host: build with -dPXX_ALLOC_CENSUS and compare
  tools/census_at_exit.sh at N=1 against N=5 of the same work. Live-at-exit alone
  overstates, because globals are never finalised.
- A regression row: tools/assert_no_leak.sh, ALWAYS with a positive control
  that leaks on purpose and must be caught.
- ESP: see "ESP32" below.
- The fastest way to reduce an xtensa-only leak is the hosted build:
  --target=xtensa --platform=posix --xtensa-soft-mulhigh [--xtensa-abi=windowed],
  run with tools/run_target.sh xtensa.

## ESP32

- Examples: examples/esp32/* (S3 and C3; nilpy-* are Nil Python). docs/targets/esp32.md.
- IDE: ./espide.sh [folder]. It detects the chip, builds and flashes with one button, and opens a folder as a project.
- MicroPython compatibility: docs/library/micropython.md. The driver census
  (tools/mpy_driver_census.sh; drivers from tools/install_lib_candidates.sh
  micropython-drivers) compiles 14 of 16 common drivers unchanged.
- Networking under QEMU: tools/esp_qemu_net/qemueth + tools/esp_qemu_urequests.sh
  (chip 10.0.2.15, host 10.0.2.2; CONFIG_ETH_USE_OPENETH=y,
  CONFIG_LWIP_TCP_MSL=500). Grep the UREQ-QEMU-COMPLETE token.
- Heap soaks: SOAK_BODY=<file.npy> tools/esp_heap_soak_nilpy.sh --passes 40
  --settle 150 nilpy-logger-s3 [--as c3] [--control]; read SOAK-SETTLED.
- If only the S3 leaks and the C3 doesn't, suspect the xtensa codegen
  (compiler/ir_codegen_xtensa.inc, the per-target epilogues in compiler/symtab.inc).

## Where things are

- compiler/ — the compiler (Pascal). compiler/pyparser.inc is the whole Nil
  Python frontend; compiler/builtin/ is the runtime auto-included into programs.
- lib/rtl, lib/pcl, lib/crtl — the runtime and libraries (zlib licence).
  A lib/rtl unit can carry a Pascal AND a Python surface in one file.
- docs/ — public documentation (published at pxxc.org). devdocs/ — internal
  history: tickets, the logbook, the debugging playbook.
- devdocs/dev/parked-patches/ — unfinished work, one .md note per patch saying
  how far it got. Worth reviving first: nilpy-class-body-scope (complete;
  only its full Nil Python run is missing) and nilpy-micropython-native-viper.
  Read the HANGS warning on hoist-inherited-nested-types before touching it.
- devdocs/progress/ — tickets by folder (backlog-*, done, rejected ...).
  tools/progress.sh next shows a ranked entry point.

## How the fleet worked (history, not instructions)

Between June and September 2026 this was built by one person directing several
AI coding agents in parallel. Their operating rules are in
devdocs/dev/fleet-rules-2026.md (formerly CLAUDE.md). They are long and
specific to that setup. Read them for the reasoning, not as rules you must
follow. The parts worth keeping:
- Land only green.
- Never paper over a compiler bug in library code.
- Every guard needs a positive control.
- Say which compiler (sha256) and which tree a number was measured on.

## Known issues at Blaise

The release pin is v441 (commit 5c1696ca79, compiler sha256 4ebfa2d047a2).
The maintained list is docs/reference/known-issues.md; the release notes are
devdocs/release-notes/v0.1.0-beta.1.md. The short version:

- No compiler-caused memory leak is known. The sweep's record is the BLAISE
  LEAK LIST in devdocs/progress/LOGBOOK.md. Not measured: Wi-Fi on real
  hardware. One undetermined reading: about 0.6 B/pass on the ESP Nil Python
  example soaks, below the soak's resolution.
- Silently wrong: C `long double` is 8 bytes (GCC: 16); an initialised C
  `__thread` variable reads 0 outside the main thread (a fix in progress is in
  parked-patches/tls-init-image-reaches-every-thread-wip).
- ESP bare-metal images run under QEMU only; on silicon use the ESP-IDF
  profile. The ESP32-C3 has never run on a physical board. Long network runs
  on the C3 stall under QEMU (an emulated NIC's lost rx interrupt, not a leak).
- -O3 is experimental (two differential shards red at v439); -O2 is the default.
- Nil Python is best effort. CPython compatibility was explicitly not a goal
  of this beta.
- Open work is ranked in devdocs/progress (tools/progress.sh ready). The
  owner's stated goals at the end are in devdocs/dev/the-goal-cross-cross.md.
