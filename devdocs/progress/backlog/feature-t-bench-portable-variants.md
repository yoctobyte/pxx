---
summary: "mandelbrot and raytracer have no FPC comparison — they depend on pxx-only units, not on dialect extensions"
type: feature
prio: 40
---

# Bench: give mandelbrot and raytracer an FPC-comparable variant

- **Type:** feature (Track T — the bench suite in `tools/testmgr.py` + `bench/portable/`).
- **Status:** backlog
- **Opened:** 2026-07-14, from the user's question: "not all benchmark tests are tested
  against FPC — would be nice to have this data, but likely we use compiler extensions
  FPC doesn't support?"

## The answer to that question: it is NOT dialect extensions

Worth recording, because it is the natural assumption and it is wrong. The dialect is
fine — FPC accepts our sources. What blocks the comparison is **unit dependencies on
pxx-only libraries**:

| bench | FPC level today | why |
| --- | --- | --- |
| `nbody` | ✅ compared | `uses math` — portable |
| `fib` | ✅ compared | no uses clause |
| `sieve` | ✅ **fixed 2026-07-14** | `uses sysutils` only; was being skipped by a tooling bug (below) |
| `mandelbrot` | ❌ | `uses baseunix, ansiterm` — **ansiterm** is a pxx RTL unit |
| `raytracer` | ❌ | `uses image, png, hashing, platform` — all pxx lib units |
| `selfcompile` | ❌ | separate issue: `compiler.pas` does not build under FPC at HEAD — the open **fpc-bootstrap** regression (`bad=603cf2bda859`), not a bench problem |

Two of the three gaps were not gaps at all:

- **`sieve` was FPC-comparable all along** and simply not flagged. Now is: **31.8ms (fpc)
  vs 63.8ms (pxx -O2)**.
- **The `fpc` level was compiling in the wrong dialect.** `FPC_FLAGS` lacked `-Mobjfpc`,
  so FPC ran in its default mode where `integer` is a **16-bit smallint** — `sieve` then
  failed outright ("range check error while evaluating constants: 1000000 must be between
  -32768 and 32767") and was quietly dropped, while `nbody`/`fib` were being timed against
  a language pxx does not implement. Fixed; the comparison is now objfpc on both sides.

## What is left

`mandelbrot` and `raytracer` need **portable variants** in `bench/portable/` — same
computation, no pxx-only units:

- **mandelbrot** — the escape-time loop is pure float math; only the *rendering* needs
  `ansiterm`. A `--bench` mode that computes and checksums the pixel buffer without
  drawing it is enough, and that is already roughly what the timed argv does. Cheap; do
  this one first.
- **raytracer** — harder: it leans on `image`/`png` for output and `hashing` for the
  canary. A portable variant would render into a plain array and checksum it, dropping
  PNG entirely. The float/call-heavy inner loop, which is the part worth timing, does not
  touch those units at all.

Keep the originals as they are — they are Track B/E demos and should stay idiomatic (they
exist to *use* our libraries). The portable variants are bench fixtures, not replacements.

## Why bother

The `fpc` level is our only external speed oracle. Right now it covers one float
benchmark, one call-heavy int benchmark and one memory-bound int benchmark — but not the
**float-heavy call-dense** shape the raytracer represents, which is where an optimiser's
inlining and register allocation actually show up. `nbody` at 565ms (pxx -O2) vs 64ms
(fpc) says there is a large gap to explain; more comparable workloads is how you find out
where it lives.

## Acceptance

`bench/portable/mandelbrot.pas` and `bench/portable/raytracer.pas` exist, use only units
FPC also has, are registered in `BENCH_SUITE` with `fpc_ok=True`, and produce `fpc` rows
in `tstate/bench.tsv` alongside the `-O0/-O2/-O3` ones.
