---
track: U
prio: 30
type: decide
blocked-by: []
status: backlog
summary: "`VarType(v)` returns pxx's internal tag (0..8), not FPC's varXxx code, and lib/rtl/variants.pas exports no varInteger/varDouble/varString constants at all -- so the FPC idiom `if VarType(v) = varInteger` does not compile. Fork: map VarType onto FPC's codes (compat, changes what existing pxx code comparing to VT_ constants sees) or export a pxx-flavoured constant set (no compat). Needs the owner's call on which surface is public."
---

# Decide: does `VarType` speak FPC's `varXxx` codes or pxx's tags?

- **Type:** decision (Track U). Raised 2026-08-23 by claude-A during the Variant
  differential family.

## What happens today

```pascal
uses variants;
var v: Variant;
begin
  v := 1;
  writeln(VarType(v) = varInteger);   { pascal26: undefined variable (varInteger) }
end.
```

`lib/rtl/variants.pas` declares `TVarType = Word` and `VarType`, but **no
`varXxx` constants at all**. And `VarType` returns pxx's internal tag —
`VT_INT`=1, `VT_INT64`=2, `VT_DOUBLE`=3, `VT_BOOL`=4, `VT_CHAR`=5,
`VT_STRING`=6 — which is a different numbering from FPC's (`varNull`=1,
`varSmallint`=2, `varInteger`=3, `varDouble`=5, `varBoolean`=11,
`varString`=256). Only tag 0 (`varEmpty`) coincides, and the unit header already
says so.

So declaring FPC's constants without changing `VarType` would be worse than
declaring none: `VarType(v) = varInteger` would compile and answer True for a
`VT_DOUBLE`.

## The fork

**A — map `VarType` onto FPC's codes** and export FPC's constant set. The FPC
idiom then works verbatim, which is what a `variants` unit is for and what every
corpus target expects. Cost: any existing pxx code comparing `VarType(v)`
against a `VT_` constant silently changes meaning. (How much exists is a grep,
not a guess — worth doing before deciding.)

**B — export a pxx-flavoured constant set** (`vtInteger`, `vtDouble`, ...) and
document that `VarType` is ours. Cheap, honest, and permanently
non-portable: vendor code keeps not compiling.

**C — both**: `VarType` keeps returning pxx tags, add `VarTypeFPC` (or a
`VarTypeName`) alongside. Two functions for one question, which is the shape
this repo's `normalise-dont-special-case.md` argues against.

## Recommendation

**A**, if the grep shows few or no in-tree consumers comparing against `VT_`
constants — the unit's whole purpose is FPC compatibility, and the pxx tag
numbering is an implementation detail that leaked into a public API. But it
changes the meaning of an exported function, which is the owner's call, not an
agent's.

Related and separate: pxx has no `varNull` distinct from `varEmpty` at all (see
[[bug-a-null-does-not-propagate-through-variant-arithmetic]]'s note on why a
`VT_NULL` tag was not needed for propagation). If A is chosen, `varNull` vs
`varEmpty` becomes visible in a way it is not today, and that may pull the tag
question along with it.
