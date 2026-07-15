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

- ~~**mandelbrot**~~ — **DONE 2026-07-14**: `bench/portable/mandelbrot.pas`, same window,
  same Double kernel, same positional checksum, **zero units**. Both compilers agree on
  the checksum (which is what makes the timing comparison legitimate — same checksum means
  same work), and it self-checks against the example's pinned `EXPECTED` before timing
  anything. New data: **pxx -O3 1166ms vs fpc 364ms — 3.2x**.
- ~~**raytracer**~~ — **DONE 2026-07-15**: `bench/portable/raytracer.pas`, same fixed
  scene + Double kernel + positional checksum, only `uses math` (Sqrt). Drops
  image/png/hashing/platform — it folds each traced pixel straight into the checksum
  instead of into an image buffer, since the tracing is the part being timed, not the
  storage. Registered as `raytracer-p`, `fpc_ok=True`, canary 96x64 / timed 480x360.
  New data: **pxx -O3 704ms vs fpc 74ms — 9.5x**, the biggest gap in the suite and the
  call-dense-float shape that was missing.
  Two notes: (1) `Power(ndh,32)` was replaced by repeated squaring so the timed inner
  loop is pure codegen, not an RTL transcendental. (2) pxx and FPC checksums differ by
  0.05% (297858362 vs 297697376) — expected two-compiler float drift (association / fused
  multiply-add / x87-vs-SSE intermediates), NOT different work; the self-check uses a
  0.2% tolerance band, so both pass while a real regression (orders of magnitude) still
  Halt(1)s. Not worth a bug ticket per the user; may vanish once float codegen is
  optimised.

Keep the originals as they are — they are Track B/E demos and should stay idiomatic (they
exist to *use* our libraries). The portable variants are bench fixtures, not replacements.

## Why bother

The `fpc` level is our only external speed oracle. Right now it covers one float
benchmark, one call-heavy int benchmark and one memory-bound int benchmark — but not the
**float-heavy call-dense** shape the raytracer represents, which is where an optimiser's
inlining and register allocation actually show up. `nbody` at 565ms (pxx -O2) vs 64ms
(fpc) says there is a large gap to explain; more comparable workloads is how you find out
where it lives.

## Acceptance — MET 2026-07-15

`bench/portable/raytracer.pas` exists, uses only units FPC also has (`math`), is registered
in `BENCH_SUITE` with `fpc_ok=True`, and produces `fpc` rows in `tstate/bench.tsv` alongside
the `-O0/-O2/-O3` ones. Both mandelbrot and raytracer done — ticket ready to resolve.

## Where the gap stands now

Three FPC-comparable rows, and all three say the same thing:

| workload | pxx (best -O) | fpc -O2 | ratio |
| --- | --- | --- | --- |
| sieve (memory-bound int) | 63.8ms | 31.8ms | 2.0x |
| mandelbrot-p (float compute) | 1166ms | 364ms | 3.2x |
| nbody (float) | 565ms | 64ms | 8.8x |
| fib (call-heavy int) | 164ms | 114ms | 1.4x |

nbody's 8.8x is the outlier and the obvious thing to explain — it is the only one using
`math`, so part of that may be RTL rather than codegen. Track O has the material now.
