---
summary: "RESIDUAL (compat, deferred): gcc's exact-bit-PRECISION arithmetic on >32-bit bitfields (bitfld-3.c) needs per-node arbitrary-precision masking in the IR; the valuable half (storage/read/layout, bf64-1.c) landed in 307128d5"
type: bug
track: C
tags: compat
prio: 15  # user-visible disposition 2026-07-15: conformance-only edge, near-zero real-world value; pick up only if a real corpus needs sub-word bitfield wrap
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

## gcc rule nailed (2026-07-15, agent-A) — the investigation the residual needed

Empirically determined gcc's exact bitfield-arithmetic-promotion rule (gcc 13.3,
`-O0`/`-O2` identical). The `-Wformat` diagnostic is explicit: the operand type of
`a.u33` is **`long unsigned int:33`** — an integer type of the field's EXACT
bit-PRECISION (33), carrying the base type's signedness. `a.u33 * a.u41` has type
`:41` (the wider precision governs, per usual arithmetic conversions). Arithmetic
WRAPS modulo 2^precision:

- `a.u33 * a.u33` (2^20·2^20 = 2^40) ≡ 0 (mod 2^33) ✓
- `a.u41 * a.u41` = 2^40 (mod 2^41 = no reduction) = 0x10000000000 ✓
- `a.u33 * a.u41` reduced to :41 → 0x10000000000 ✓
- `sizeof(a.u33 + 0)` = 8 (rounds up to the base type) but the PRECISION is 33.

So a faithful implementation needs **arbitrary-precision integer types** (precision
= field width, not 32/64) propagated through the C expression tree: every binary op
converts both operands to the greater-precision bitfield type and masks the result
to that precision (sign-extend for signed). pxx's IR models only tyInt32/tyInt64
etc. — there is no per-node bit-precision, so this requires new node metadata
(bitfield precision) threaded through arithmetic + a mask-to-precision at each op.

## Disposition — compat conformance edge, deferred (near-zero real-world value)

The valuable half (storage/read/layout, `bf64-1.c`) is DONE (307128d5). The residual
(`bitfld-3.c`) is arithmetic that OVERFLOWS a non-power-of-8 bitfield width — a
construct that appears only in conformance torture tests, never in real C. It is
silent-wrong (pxx gives 2^40, not 0) but for an expression no real program writes.
Implementing arbitrary-precision integer arithmetic in the IR is disproportionate
to the value. Left in backlog at low prio as a **compat** item; pick up only if a
real corpus (not gcc-torture) depends on sub-word bitfield arithmetic wrapping.
Add `bitfld-3.c` to the C skip list with this reason rather than chasing it.

## Effort re-estimate (2026-07-15, agent-ACP — plan correction, prio unchanged)

The "needs arbitrary-precision integer types in the IR" framing above is too
pessimistic. cfront already computes C types for the usual-arithmetic
conversions, so the whole fix can live PARSER-SIDE in the C->IR lowering — no
new IR node metadata:

- Track "bitfield precision N" (34..63 band; width<32 already promotes to int,
  width 64 is plain long long) on the cparser's expression-type bookkeeping,
  starting at a bitfield read and propagating through binops via
  max(precision) per the usual arithmetic conversions.
- After each `+ - * <<` whose result type is a :N bitfield type, emit an
  explicit normalize node: mask to N bits (unsigned) or sign-extend from bit
  N-1 (signed, the existing `(v xor signBit) - signBit` branchless trick from
  IRLowerBitFieldRead).
- Before value-observing ops (`>> / % == <` etc.) operands must already be
  normalized — which mask-after-every-op guarantees.
- Carry out of bit N-1 is DISCARDED by definition (C unsigned arithmetic is
  mod 2^N); signed overflow is UB, so two's-complement wrap matches gcc.
- `sizeof(a.u33 + 0)` = 8 stays right for free (storage type is int64).

Moderate cfront work + a differential test vs gcc, not an IR feature. Value
still low (in-expression overflow of a 33-63-bit field without an intervening
store — real code masks explicitly), hence prio stays 15; but if picked up,
THIS is the plan, not the IR one.
