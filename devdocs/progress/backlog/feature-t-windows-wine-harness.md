---
summary: "Windows/Wine test bed — scratch-prefix wine runner + mingw-w64 differential oracle, hello-world gate"
type: feature
prio: 45
---

# Windows/Wine test harness (Track T)

- **Type:** feature (Track T — tools & testing infra). Enables [[feature-port-windows-pe]].
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-07-17, OS-portability mapping session. Context:
  [`devdocs/dev/portability-axes.md`](../../dev/portability-axes.md),
  umbrella [[feature-port-multi-os-abstraction]].

## Why

Windows PE output is testable on Linux with **no VM** — Wine runs user-mode PE hitting
kernel32/ntdll faithfully. This ticket stands up that test bed **ahead of the PE
writer** so verification is one command when the writer lands (same pattern as the
FreeBSD linuxulator smoke). T owns the tool; a compiler gap it surfaces is filed to the
owning lane, never fixed here.

## Deliverables

1. **Wine runner** — a `run_wine.sh`-style wrapper (analogue of `run_target.sh`):
   `wine64 out.exe`, capture stdout + exit code, `WINEDEBUG=-all` to silence, a
   **scratch `WINEPREFIX`** (never `~/.wine`), `xvfb-run` wrap (testmgr already models
   the `xvfb` resource, so free). Deterministic, headless.
2. **mingw-w64 differential oracle** — `x86_64-w64-mingw32-gcc` as a *second* Windows
   compiler on Linux. Two uses: (a) validate the wine setup itself (mingw hello → wine →
   green) so "wine broken" is never confused with "pxx PE broken"; (b) differential
   oracle for pxx PE output — compile the same program with mingw→PE and pxx→PE, run
   both under wine, diff. Mirrors gcc-for-C-corpus / FPC-for-pasmith.
3. **Green gate** — a hello-world (mingw-built) runs under the runner and prints the
   expected line; wired so `testmgr` can invoke it as a `qemu`-class-style job once pxx
   PE binaries exist.

## Dependencies (host packages — user installs)

- `wine64` (or the `wine` metapackage on newer Debian/Ubuntu).
- `gcc-mingw-w64-x86-64`.
- `xvfb` — already present.

Install line (user-run): `sudo apt install -y wine64 gcc-mingw-w64-x86-64`.

## Acceptance

- `run_wine.sh <exe>` runs a PE headless, returns its stdout + exit code deterministically.
- mingw hello-world → wine → prints expected output (setup validated).
- Differential mode: mingw-PE vs (later) pxx-PE checksum diff, ready to wire into the
  Windows bring-up.
- Gate for this tooling change: `tools/testmgr.py --tier full` green (test with quick
  tiers + a scratch prefix, never long runs).

## Note

Stands alone — needs no compiler change. Build it whenever; it just waits for
[[feature-port-windows-pe]] to produce a PE to point at.
