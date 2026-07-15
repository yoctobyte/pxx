---
summary: "C long-long bitfields (width 33-64, `unsigned long long u:40`) are not promoted/extended correctly — the width<32 sub-int promotion doesn't cover them; gcc-torture bf64-1/bitfld-3 abort"
type: bug
track: C
prio: 45
---

# C long-long bitfields (width 33-64) mis-promoted

- **Type:** bug (C bitfield promotion for `long long` / `unsigned long long`
  bitfields). **Silent** wrong values.
- **Track:** C (bitfield read lowering) — shared codegen (Track A:
  IRLowerBitFieldRead).
- **Found:** 2026-07-15 re-triaging the bitfield cluster
  ([[bug-c-bitfield-promotion-and-layout-cluster]]). The sub-int promotion fix
  (commit b0999120) handles width < 32 only; wider bitfields keep the storage-type
  extension path, which is not correct for 33-64-bit fields.

## Repro

```
compiler/pascal26 -Ilib/crtl/include -Ilib/crtl/src \
  library_candidates/gcc-torture/execute/bf64-1.c   /tmp/x && /tmp/x   # exit 134
compiler/pascal26 -Ilib/crtl/include -Ilib/crtl/src \
  library_candidates/gcc-torture/execute/bitfld-3.c /tmp/x && /tmp/x   # exit 134
```

`bitfld-3.c` declares `unsigned long long u33:33; u40:40; u41:41; …`. gcc passes;
pxx aborts on the self-checks.

## Likely area

IRLowerBitFieldRead's `width < 32` branch promotes to a 32-bit signed int; the
`else` branch sign-extends in the storage type. For a 33-64-bit bitfield the
storage type and extension must be 64-bit, and the C promotion is to `long long` /
`unsigned long long` (rank > int), not to `int`. Extend the read to handle the
33-64 width band in the tyInt64/tyUInt64 domain with the correct signedness, and
tag the result node accordingly.

## Acceptance

`bf64-1.c` and `bitfld-3.c` compile and exit 0; a `test/` regression pins a
signed and an unsigned 40-bit bitfield round-trip and arithmetic; results match
gcc.
