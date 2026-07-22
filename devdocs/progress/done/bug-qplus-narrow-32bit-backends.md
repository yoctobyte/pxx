---
track: A
prio: 35
type: bug
---

# {$Q+} narrow-width overflow still unchecked on the 32-bit backends

Follow-up to bug-a-qplus-misses-32bit-overflow (fixed on x86-64 + aarch64 at
the narrowing store: a Q-tagged binop feeding a sub-64-bit ordinal store now
range-checks the exact wide result against the destination width).

Still open: **i386 / arm32 / riscv32 / xtensa**. Confirmed on i386: the
32-bit-overflow repro prints -294967296 and exits 0 — despite Integer being
"native width" there, the arithmetic evidently runs wide (ILP32 64-bit =
register pair; see project_32bit_truthiness_and_promotion_landmines) or the
tag never reaches the emitted op. SmallInt/Byte/Cardinal narrows are unchecked
there too.

Fix shape: mirror the store-site range check per backend (the exact-wide-value
+ re-extend + compare pattern in ir_codegen.inc EmitOvfCheckNarrowX64 / the
aarch64 IR_STORE_SYM hook). Measure first per backend whether the tag is
(a) absent, (b) skipped, or (c) width-blind, as the parent ticket insisted.

Gate: test/test_overflow_qplus_narrow.pas prints
`caught=5 clean=4 wrap=-294967296` on each backend; wire it into the four
cross suites next to test_overflow_checks_qplus.pas.

## Log
- 2026-07-22 — resolved, commit 9097042d.
