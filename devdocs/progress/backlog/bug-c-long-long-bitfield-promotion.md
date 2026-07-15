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

## Progress (2026-07-15, agent-A)

**Storage / read / layout FIXED** (commit 307128d5). `IRBitStorageTk` now returns
tyUInt64 for a >4-byte unit; the C bitfield packing sizes the storage unit by the
field's declared-type size (`sz`) instead of a hardwired 32-bit/4-byte cap, and a
long-long field reserves a full 8-byte unit so neighbours don't overlap (a signed
store was clobbering an unsigned neighbour). `bf64-1.c` passes; 40/33/41-bit
round-trip + 40-bit sign extension verified. Regression:
`test/cbitfield_longlong_b359.c`. int/short bitfields unchanged (sz<=4 path is a
no-op).

**Residual — arithmetic promotion TYPE:** `bitfld-3.c` still aborts. It tests the
promoted TYPE of arithmetic on a >32-bit bitfield (e.g. `a.u33 * a.u33` with
`a.u33 == 0x100000` must equal 0 on gcc — the operation reduces mod 2^32, i.e. the
33-bit field promotes to a 32-bit arithmetic domain in gcc's model, NOT to 64-bit
unsigned long long as a naive "width>32 keeps declared type" reading would give).
This is a distinct, subtle promotion-type semantic separate from storage; needs
its own investigation of gcc's exact bitfield-arithmetic promotion rule before
implementing.

## Acceptance

`bf64-1.c` and `bitfld-3.c` compile and exit 0; a `test/` regression pins a
signed and an unsigned 40-bit bitfield round-trip and arithmetic; results match
gcc.
