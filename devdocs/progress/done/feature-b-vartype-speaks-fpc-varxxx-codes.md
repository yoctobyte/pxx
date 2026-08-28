---
slug: feature-b-vartype-speaks-fpc-varxxx-codes
title: "variants.pas exports FPC's varXxx constants and VarType maps onto them"
track: B
prio: 45
type: feature
blocked-by: []
status: done
owner: ""
created: 2026-08-25
summary: "Re-filed from decide-vartype-returns-pxx-tags-not-fpc-codes, decided 2026-08-25 (option A). VarType currently returns pxx's internal tag (VT_INT=1, VT_DOUBLE=3, ...) and the unit exports no varXxx constants at all, so the FPC idiom `if VarType(v) = varInteger` does not compile. Measured: zero in-tree consumers compare VarType against a VT_ constant outside variants.pas itself, so the ticket's own gating condition for option A is met."
---

# What to build

In `lib/rtl/variants.pas`, and **only** there — no compiler change:

1. Export FPC's constant set: `varEmpty=0`, `varNull=1`, `varSmallint=2`,
   `varInteger=3`, `varDouble=5`, `varBoolean=11`, `varString=256`, and the
   neighbours a real program uses.
2. Make `VarType` translate the internal tag to the FPC code on the way out.
   The `VT_` constants stay **private** to the unit.
3. Update the four internal call sites that compare against `VT_` constants
   (lines 185, 203, 255, 261 as of 2026-08-25) — they can keep using the private
   tag by reading the raw tag word directly, or move to the FPC codes; either is
   fine as long as one numbering is public.
4. Fix the unit header, which currently documents the tag numbering as the
   public answer.

## Why the translation lives in the unit

This is the facade seam. Standing policy from the same day's decisions: **the
RTL facade speaks FPC's public numbering; the compiler's internal tags stay ours
and stay private** — see [[decide-rtti-kind-numbering]] and
[[decide-classinfo-returns-our-blob-or-nothing]]. Keeping it in `variants.pas`
is what makes this a Track B job rather than a compiler change.

## Note on varNull

pxx has one `VT_EMPTY` tag serving `Null`, `Unassigned` and NilPy's `None`, and
[[decide-should-a-null-variant-raise-like-fpc]] decided (same day) that it stays
that way. So `VarType` reports `varEmpty` (0) for it. That is honest about what
the dialect distinguishes; do **not** add a `varNull` tag as part of this
ticket.

## Acceptance

- `uses variants; ... if VarType(v) = varInteger` compiles and is True for
  `v := 1`, False for `v := 1.5`.
- `VarType(v) = varDouble` for a float, `varBoolean` for a Boolean,
  `varString` for a string, `varEmpty` for `Unassigned`.
- `test/test_variant_bitwise_and_not.pas` line 72's existing comment
  (*"varBoolean = 11 in the FPC-compatible VarType() codes"*) becomes true
  rather than aspirational.

## RESOLVED 2026-08-28 (frankB) — landed as part of one job

Done together with `bug-b-the-fpc-vartype-constants-are-missing`, which carries
the full write-up. The three tickets were one defect and one already-fixed twin,
and doing the headline one alone would have broken this one rather than left it
stale: after `VarType` translates, a comparison against an internal `VT_` tag is
false for *every* value of that kind, not just the reported case.

Landed in `lib/rtl/variants.pas` only, no compiler change: FPC's `varXxx`
constants exported (measured from fpc 3.2.2, not transcribed), a private
`RawTag` for the eight internal call sites, and `VarType` translating at the
facade seam. 11 of 12 rows now match FPC exactly; the documented divergence is
`v := 1` (FPC narrows the literal to `varShortInt`).

Gated by `test/lib_variants_vartype_codes.pas` in `make lib-test`, sentinel
`VARTYPECODES OK`, negative-controlled.

## Log
- 2026-08-28 — resolved, commit PENDING-COMMIT.
