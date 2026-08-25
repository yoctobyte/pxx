---
slug: chore-doc-pascal-dialect-divergences-pointer-difference
title: "Record two chosen Pascal dialect divergences: pointer-difference units, and the one-tag Null/Unassigned"
track: D
prio: 25
type: chore
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-25
summary: "Re-filed from decide-pointer-difference-unit and decide-should-a-null-variant-raise-like-fpc, both decided 2026-08-25. Two divergences from FPC are now CHOSEN rather than merely inherited, and a chosen divergence that is not written down is indistinguishable from a bug to the next reader. Both entries land in devdocs/dev/pascal-dialect-divergences.md."
---

# Why this is a real ticket and not bookkeeping

`frontend-compat-philosophy.md` draws the whole line here: the dialect *"licenses
different SEMANTICS **chosen on purpose**; it never licenses a wrong answer
nobody chose."* The difference between the two halves of that sentence is
whether the choice is recorded. Undocumented, both of these read to the next
session as bugs and get re-diagnosed.

# Entry 1 — `p - q` counts ELEMENTS, always

Per [[decide-pointer-difference-unit]]. FPC answers **bytes** when either
operand is an untyped `Pointer` — which under its default `{$TYPEDADDRESS OFF}`
includes `@x`. pxx scales by the left operand's stride whatever the right
operand is.

```pascal
var a: array[0..7] of Integer; p, p0: ^Integer; u: Pointer;
p0 := @a[0]; p := @a[2]; u := @a[0];
{ p - p0   : fpc 2   pxx 2  }
{ p - u    : fpc 8   pxx 2  }
{ p - @a[0]: fpc 8   pxx 2  }
```

Say why: the uniform rule is derivable from the language ("a pointer difference
counts elements"), FPC's is derivable only from `{$TYPEDADDRESS OFF}`. Give the
porting advice the rejected diagnostic would have printed — *cast the untyped
operand to the pointer type, or to `PtrUInt` for a byte count* — since a reader
arriving from FPC code is exactly who needs it. Note that FPC's semantics is
available under `--strict-fpc` (see
`compat-pascal-strict-fpc-pointer-difference-bytes`).

# Entry 2 — `Null` and `Unassigned` share one tag, and neither raises

Per [[decide-should-a-null-variant-raise-like-fpc]]. pxx spells FPC's `Null`,
FPC's `Unassigned` and NilPy's `None` with a single `VT_EMPTY` tag. FPC prints
an `Unassigned` as empty but **raises** `EVariantTypeCastError` for a `Null`, in
both `string(v)` and `WriteLn(v)`. pxx prints empty for both and never raises.

Consequences to state, because they are what a reader will hit:
`VarIsNull` and `VarIsEmpty` both answer True for both spellings, and
`VarType` reports `varEmpty` (0). The conflation is currently documented only
in `lib/rtl/variants.pas`' header and in `builtin.pas`' `PXXVarBinOpPas` — note
there that it gives the *right* answer for arithmetic, since FPC propagates both
through arithmetic as themselves and one propagating tag is correct.

# Scope

Prose only. Track D: `devdocs/dev/pascal-dialect-divergences.md`. No
`compiler/**`, no `lib/**`. Verify the code snippets compile against
`$(PXX_STABLE)` rather than transcribing them from the decision tickets.
