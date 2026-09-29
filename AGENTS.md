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
| Targets | Linux x86-64 (native host), i386, aarch64, arm32, riscv32 (cross, run under qemu-user). ESP32-S3 (xtensa LX7), ESP32 classic (xtensa LX6) and ESP32-C3 (riscv32) through ESP-IDF; the ESP32-S2 compiles but has not been run. |
| C | A C99-class dialect with common GNU extensions; c-testsuite 220/220 on x86-64. |
| Nil Python | Best effort, with a real backlog. Not CPython and not aiming at CPython parity now. |
| Memory | Leaks are treated as release blockers. See docs/reference/known-issues.md ("Memory leaks") and the BLAISE LEAK LIST in devdocs/progress/LOGBOOK.md. |

## Build from nothing

    sudo apt install fpc make
    git clone https://github.com/yoctobyte/pxx && cd pxx
    make bootstrap        # FPC builds the seed, then pxx rebuilds itself to a byte-identical fixedpoint
                          # (62 s with FPC 3.2.2 on 2026-09-29; the same binary as the route below)

A checkout also ships a working compiler at stable_linux_amd64/default/pinned,
so you do not need FPC. A fresh checkout has no compiler/pascal26 yet, and make
refuses until you seed it from the pin:

    cp stable_linux_amd64/default/pinned compiler/pascal26
    make compiler/pascal26   # this IS the self-host fixedpoint check (47 s from the v451 seed, 2026-09-29)
    ./compiler/pascal26 test/hello.pas /tmp/hello && /tmp/hello

The pin in a checkout is the last line of stable_linux_amd64/default/pin.log:
its name, the binary's sha256, and the source commit it was built from.

"converged after N round(s)" means it rebuilt and reproduced itself. "verified"
means nothing was rebuilt.

## Test

    tools/gate.sh quick   # the fixedpoint plus a quick tier. Run it before every push.
    make test             # the Pascal/core suite
    make test-c           # C
    make test-nilpy       # Nil Python, differential against python3
    make lib-test         # libraries
    make test-uforth      # a real Python program (github.com/yoctobyte/uforth), 17 corpora vs CPython

Timings depend on machine load: on 2026-09-29, on a shared machine at a load
average of about 12, `tools/gate.sh quick` took 182 s for the fixedpoint and
186 s for the quick tier. On an idle machine expect much less.

Some suites need trees a clone does not have, and skip without them:

- `make test-c` runs the c-testsuite battery only if
  `tools/install_lib_candidates.sh c-testsuite` has fetched it; otherwise it
  prints "c-conformance SKIPPED".
- `make test-uforth` needs a uforth checkout at ~/projects/uforth (or pass
  `UFORTH_SRC=<dir>`): `git clone https://github.com/yoctobyte/uforth
  ~/projects/uforth`. Without one it prints "test-uforth: SKIP".
- More generally, `tools/testmgr.py --tier full --list` starts with a
  "CORPUS MISSING" banner naming what is absent (in a fresh clone, 42 jobs
  across library_candidates/* and external/synapse). Those jobs SKIP, and a
  green verdict does not cover them. `tools/install_lib_candidates.sh <name>`
  fetches one library_candidates tree; the names are in the script's header
  comment. With no argument it fetches all of them.

The repository's Claude Code hooks refuse the full suites by default (a speed
guard). Prefix PXX_ALLOW_FULL_SUITE=1 when you mean it. The hook also refuses
`tools/testmgr.py --tier full --list`, so give that the prefix too.

Check verdicts by the job's own printed line (for example "gate: GREEN" or
"testmgr: GREEN"), not by a wrapper's exit status. One failing job alone:
`tools/testmgr.py --tier full --job '<name>'`, with the name from
`tools/testmgr.py --tier full --list` (names look like `test-nilpy#01`; the
`--tier` is required).

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

- Examples: examples/esp32/* (S3, C3, and hello-esp32 for the classic LX6 part;
  nilpy-* are Nil Python). docs/targets/esp32.md has the per-chip table.
- IDE: ./espide.sh [folder]. It detects the chip, builds and flashes with one button, and opens a folder as a project.
- MicroPython compatibility: docs/library/micropython.md. The driver census
  (tools/mpy_driver_census.sh; drivers from tools/install_lib_candidates.sh
  micropython-drivers) compiles 15 of 16 common drivers unchanged (pin v451,
  2026-09-29, 230 s; st7789 needs @micropython.viper).
- Networking under QEMU: tools/esp_qemu_net/qemueth + tools/esp_qemu_urequests.sh
  (chip 10.0.2.15, host 10.0.2.2; CONFIG_ETH_USE_OPENETH=y,
  CONFIG_LWIP_TCP_MSL=500). Grep the UREQ-QEMU-COMPLETE token; each
  UREQ-ROW line (transcript, census, control) must say OK.
  `tools/esp_qemu_urequests.sh nilpy-s3` took 213 s on 2026-09-29 (pin v451),
  all three rows OK. Prefer the S3: under QEMU the C3 (`nilpy-c3`) can stall
  after a few hundred requests, because the emulated network card loses a
  receive interrupt (a QEMU limit, not a leak; the diagnosis is in the BLAISE
  LEAK LIST). On 2026-09-29 the chip went silent after 500 of its 1000
  requests; the script waits for UREQ_TIMEOUT (1800 s) before it reports that,
  so this run was stopped by hand after 794 s.
- Heap soaks: SOAK_BODY=<file.npy> tools/esp_heap_soak_nilpy.sh --passes 40
  --settle 150 nilpy-logger-s3 [--as c3] [--control]; read the
  `SOAK <example> <chip> settled delta=<bytes>` line (bytes still gone after
  the settle), then SOAK-COMPLETE. With
  SOAK_BODY=tools/esp_soak_nilpy/leak-mixed-sizes.npy it took 284 s under
  QEMU on 2026-09-29, used the pin by default (v451) and settled at
  delta=-1716 (a negative delta means more heap free than at the start).
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
  how far it got. Worth reviving first: nilpy-micropython-native-viper (the
  one driver of the 16 that does not compile needs it). nilpy-class-body-scope
  has landed (cdb8162bfd) and is no longer parked.
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

## Known issues and the release

Do not trust a pin number or a list of bugs written here; they go stale.
The sources of truth are:

- docs/reference/known-issues.md: what is wrong, since which pin, what to do
  instead, and what was fixed and when. Each row names the compiler (sha256)
  it was measured with.
- devdocs/release-notes/v0.1.0-beta.1.md: the beta release notes. Its header
  comment and its "This release is" line name the release pin, and its
  "Since v441" list marks each fix with the first pin that carries it
  ("(next pin)" when none does yet). docs/release-notes/index.md is the
  public version.
- stable_linux_amd64/default/pin.log: the pins, newest last.

The release pin (v441 at the beta) and the newest pin are different things.
After a new pin is cut, `python3 devdocs/release-notes/restamp.py markers`
rewrites the "(next pin)" markers to it. `restamp.py identity --pin vNNN`
changes which pin IS the release (it edits CLAUDE.md, the release notes,
known-issues.md and the public release page), and `restamp.py check --pin vNNN`
lists what is left for a person. None of them commits; read the diff.

What changes slowly, as of the beta:

- Nil Python is best effort, and CPython compatibility was not a goal of the
  beta. A reference cycle is never freed: there is no cycle collector.
- C `long double` is 8 bytes (GCC: 16).
- ESP bare-metal images run under QEMU only; on a chip, use the ESP-IDF
  profile (the default).
- -O2 is the default and the level the compiler proves on itself; -O3 is
  experimental.
- Open work is ranked in devdocs/progress (tools/progress.sh ready). The
  owner's stated goals at the end are in devdocs/dev/the-goal-cross-cross.md.
