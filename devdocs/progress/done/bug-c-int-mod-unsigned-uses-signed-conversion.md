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

## Recon (2026-07-15, agent-A — parked, needs frontend-aware fix)

Narrowed to `/` and `%` (and `>>`); relational comparisons already do the right
thing. In `ir_codegen.inc` the div/mod emit keys signedness on the LEFT operand
only — `if TypeDivideUnsigned(IntToTypeKind(IRTk[left]))` (idiv vs div) — so it is
order-dependent (`Integer div Cardinal` signed, `Cardinal div Integer` unsigned).
Comparisons use `TypeCompareUnsigned(IRTk[left], IRTk[right])` (both operands),
which is why they're correct.

The catch: the equal-rank rule DIFFERS by frontend, so a naive shared-codegen
change (e.g. "either operand unsigned → unsigned") would break Pascal:
- **C**: `int % unsigned int` (equal rank, one unsigned) → **unsigned**.
- **Pascal/FPC**: `Cardinal`/`Integer` mixed (both 32-bit) widen to **Int64
  (signed)**. `TypeCompareUnsigned` encodes the Pascal rule ("at equal width a
  signed operand wins"), which is wrong for C.

So the fix must be frontend-aware. Cleanest: apply C's usual arithmetic
conversions in the **C frontend** when building `%` / `/` / `>>` — cast the
operands to the common type (unsigned int for int-vs-uint at equal rank) so the
binop's operand/result types already carry the right signedness; the codegen then
picks div vs idiv correctly with no shared-rule change. Verify whether C `%`
currently routes through a runtime helper vs a raw IR_BINOP (the `--dump-ir` of a
`%` showed a `call`) and fix the chosen path. Do NOT change `TypeCompareUnsigned`
(shared with Pascal). Guard any codegen change on `CProgramMode` if it can't be
done purely in the frontend.

## Acceptance

The repro prints `3 3`; unsigned/signed `%` `/` `>>` and comparisons match gcc
across mixed-sign operands; a `test/` regression pins the conversion rule; the
bitfield-cluster member `bitfld-1.c` (whose residual is this bug) passes.

## Log
- 2026-07-15 — resolved, commit 2453057b.
