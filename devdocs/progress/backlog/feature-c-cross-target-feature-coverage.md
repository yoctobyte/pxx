# C frontend + lua — cross-target / ESP feature coverage

- **Type:** feature (test coverage) — Track C (+ A for any backend gap found)
- **Status:** backlog
- **Owner:** unassigned
- **Opened:** 2026-06-27

## Problem

The C frontend's bring-up — pointer model, double/float value model, va_arg,
struct-by-value returns, goto/labels, the whole lua arc — was verified almost
entirely on **x86-64 only**. The C `make test` entries and the pxx-compiled lua
smoke run against the x86-64 oracle. We have **no** evidence the same C programs
(and lua) produce correct results on the 32-bit and ESP targets.

Body lowering goes through shared IR, so cross *should* hold — but the
generator/for-in work already proved x86-64-only testing misses real cross
regressions ([[feature-c-desktop-lua-sqlite-path]] testing note). Float/double,
va_arg FP-save-area, struct-by-value return slots, and pointer-width assumptions
are exactly the areas where i386/arm32 (32-bit pairs) and xtensa/riscv32 (soft
float, windowed/Call0 ABI) diverge.

## Scope

- Run the existing C test programs (`test/c*.c`, `test/cnested_*`, the value-model
  bN tests) under the cross harness: i386, arm32, aarch64, riscv32, and the ESP
  bare/QEMU path (`tools/esp_run_bare.sh`), each diffed vs the x86-64 oracle.
- Run pxx-compiled **lua** (the functional script set — control flow, closures,
  varargs, generic-for, string lib, table.sort, metatables, pcall, **float**)
  on each target where it can run; at minimum the 32-bit + aarch64 native/QEMU.
- File a per-target Track A backend ticket for each gap (do not bloat this one).

## Acceptance

- A `make`-driven C cross matrix (analogous to the Pascal cross harness) that
  compiles + runs the C suite on i386/arm32/aarch64/riscv32 and diffs the
  x86-64 oracle; ESP via the bare/QEMU harness.
- lua float + core script set verified on ≥ the 32-bit and aarch64 targets.
- Gaps found are filed as backend tickets and linked here.

## Notes

- Deliberately deferred (2026-06-27, user): not blocking the sqlite milestone;
  Track C+A is proceeding to sqlite (M5) first. File-and-park.
- Related value-model landmines already mapped: 32-bit pair widths, FP save
  area for va_arg(double), struct/union-with-double byval return (r10), float
  negate = sign-bit flip, cmp NaN. See the done C double-value-model tickets.

## Log

- 2026-06-27 - Filed while wrapping the FPC-seed fix. C/lua proven on x86-64
  only; cross + ESP coverage is an open gap. Park behind the sqlite push.
