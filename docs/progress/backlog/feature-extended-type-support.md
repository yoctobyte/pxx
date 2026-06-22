# Proper `Extended` type support (currently aliased to Double)

- **Type:** feature (compiler) — **Track A**
- **Status:** backlog — deferred (low priority by user)
- **Opened:** 2026-06-22
- **Owner:** — (Track A / "sis")

## Goal

Real `Extended` support. Right now `Extended` is **cheated as `Double`**
(see feature-extended-alias-or-reject, done). The user does not want to invest in
true 80-bit Extended yet; libraries must keep working under the alias.

## Constraints / notes

- Until this lands, **RTL libraries target Single + Double only** and assume
  `Extended = Double`. `lib/rtl/math.pas` intentionally provides only Single +
  Double overloads (no Extended).
- True Extended means an 80-bit x87 path on i386/x86-64 (and a decision for
  targets without 80-bit hardware — soft-float or reject). Interacts with
  feature-real-cross-target-consistency.

## Log
- 2026-06-22 — Filed by Track B while building the math library; deferred per user
  (Extended not a priority until properly supported).
