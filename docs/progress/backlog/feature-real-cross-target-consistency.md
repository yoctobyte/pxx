# Verify `real`/Double bit-consistency across targets (x87 divergence?)

- **Type:** feature (verification) — **Track A**
- **Status:** backlog
- **Opened:** 2026-06-22
- **Owner:** — (Track A / "sis")
- **Found by:** Track B, building the float math library.

## Goal

Determine whether the pure-Pascal float math (`lib/rtl/math.pas`) and the `real`/
`Double` type produce **bit-identical** results across all targets, or whether
some targets diverge (notably **i386 x87** may keep 80-bit intermediates vs
x86-64 SSE2 strict 64-bit). This is the "does `real` behave across platforms"
question.

## How

Run `examples/mathf/mathdemo.pas` on each target under qemu:
`make test-i386 / test-aarch64 / test-arm32` machinery (Track A's gate). The
oracle is tolerance-based so it should print `ALL OK` everywhere even with small
divergence; to measure *exact* divergence, add a variant that prints a few raw
`writeln(x)` values and diff across targets.

## Expected / deliverable

- If x86-64/aarch64/arm32/riscv all match and only i386 (x87) drifts: document it,
  decide whether to force SSE/strict-double on i386 or accept tolerance-only
  determinism for floats.
- Update the determinism note in the math demo / a docs page with findings.

## Context

Track B verified `mathdemo` `ALL OK` on native x86-64 (pinned v35). Cross-target
runs are Track A's lane. Float oracles deliberately use tolerance compares, not
byte-identical output, precisely because of this open question.

## Log
- 2026-06-22 — Filed by Track B from the math-library work.
