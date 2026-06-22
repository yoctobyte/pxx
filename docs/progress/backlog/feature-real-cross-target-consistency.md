# Verify `real`/Double bit-consistency across targets (x87 divergence?)

- **Type:** feature (verification) — **Track A**
- **Status:** backlog
- **Opened:** 2026-06-22
- **Owner:** — (Track A / "sis")
- **Found by:** Track B, building the float math library.

## Goal

Confirm the pure-Pascal float math (`lib/rtl/math.pas`) and the `real`/`Double`
type produce **bit-identical** results across all targets. Strict IEEE-754 Double
is deterministic on modern CPUs (x86-64 SSE2, AArch64/ARM VFP) and software float
emulation, so the results **should match exactly** — a mismatch is a BUG, not
expected divergence. Suspects if any target drifts: legacy **i386 x87** 80-bit
intermediates, or non-strict FMA contraction. (Earlier framing of "floats vary,
use tolerance" was wrong — corrected: identical width ⇒ identical result.)

## How

Best exact probe: **`examples/mandelbrot/mandelbrot.pas`** — its integer
escape-count CHECKSUM (`3745966` on x86-64, FPC-confirmed) must be identical on
every target. Run it under qemu on i386/aarch64/arm32 and diff the checksum. Any
difference localises a float-determinism bug. (`examples/mathf/mathdemo.pas` also
runs everywhere; it uses tolerance, so it's a weaker probe — the mandelbrot
checksum is the strict one.)

## Expected / deliverable

- All targets produce checksum `3745966`. If one diverges (likely i386 x87),
  that's a bug to fix (force strict SSE/64-bit, disable 80-bit intermediates /
  FMA contraction), not something to paper over with tolerance.
- Record findings; if all match, this closes as "float determinism verified".

## Context

Track B verified `mathdemo` `ALL OK` on native x86-64 (pinned v35). Cross-target
runs are Track A's lane. Float oracles deliberately use tolerance compares, not
byte-identical output, precisely because of this open question.

## Log
- 2026-06-22 — Filed by Track B from the math-library work.
