---
summary: "C `int op unsigned` does SIGNED arithmetic — the usual arithmetic conversions don't convert the signed operand to unsigned, so `-13 % 61u` yields -13 (should be 3); silent wrong values for %, /, and comparisons"
type: bug
track: C
prio: 50
---

# C usual arithmetic conversions: int operand not converted to unsigned

- **Type:** bug (C integer conversions). **Silent** wrong values.
- **Track:** C (operator signedness selection) — likely shared codegen (Track A):
  the div/mod/compare op picks signed vs unsigned from operand kinds and doesn't
  apply C's "usual arithmetic conversions".
- **Found:** 2026-07-15 while re-triaging the bitfield cluster
  ([[bug-c-bitfield-promotion-and-layout-cluster]]) — NOT bitfield-specific, plain
  literals reproduce it.

## Repro

```c
extern int printf(const char*,...);
int main(void){
  int i = -13; unsigned u = 61;
  printf("%u %u\n", (unsigned)(i % u), (unsigned)(-13 % 61u));  /* gcc: 3 3 */
  return 0;
}
```

pxx prints `4294967283 4294967283` (= `(unsigned)-13`): it computes a SIGNED
`-13 % 61 = -13`, then reinterprets. C's usual arithmetic conversions require the
`int` operand to convert to `unsigned int` (equal rank, one unsigned), making the
operation unsigned: `(unsigned)-13 % 61 = 4294967283 % 61 = 3`.

Affects `%`, `/` (unsigned vs signed division), `>>` (logical vs arithmetic on the
promoted type), and relational/`==` comparisons — any binary op mixing a signed
and an unsigned operand of equal (or the unsigned of higher) rank.

## Likely area

The binary-op lowering / codegen chooses signed-vs-unsigned from one operand's
type (or defaults to signed) instead of applying the usual arithmetic conversions:
if either operand is unsigned and its rank >= the signed operand's, the whole
operation (and result) is unsigned. Centralise a `UsualArithConv(tkA, tkB)` and
have `%`, `/`, `>>`, and comparisons consult it.

## Acceptance

The repro prints `3 3`; unsigned/signed `%` `/` `>>` and comparisons match gcc
across mixed-sign operands; a `test/` regression pins the conversion rule; the
bitfield-cluster member `bitfld-1.c` (whose residual is this bug) passes.
