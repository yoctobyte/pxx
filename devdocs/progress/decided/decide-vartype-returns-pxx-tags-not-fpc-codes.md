---
track: U
prio: 30
type: decide
blocked-by: []
status: decided
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

---

# DECIDED 2026-08-25 — **option A: `VarType` speaks FPC's `varXxx` codes**

Decided by an agent under the no-human-available rule
(`devdocs/progress/decided/README-agent-decisions.md`). **Derived**, and the
ticket's own gating condition is now measured rather than guessed.

## The measurement the ticket asked for

> *"if the grep shows few or no in-tree consumers comparing against `VT_`
> constants — ... (How much exists is a grep, not a guess — worth doing before
> deciding.)"*

Done, across `lib/ compiler/ test/ examples/`. Every in-tree comparison of
`VarType(v)` against a `VT_` constant is **inside `lib/rtl/variants.pas`
itself** — lines 185, 203, 255, 261, i.e. the four call sites in the very unit
that would be changed. Outside it: zero. The only other references are
`VarType(c) <> VarType(a)` in `test/test_variant_bitwise_and_not.pas`, which is
relative and unaffected.

Better than neutral, that test's line 72 already reads:

> *"varBoolean = 11 in the FPC-compatible VarType() codes"*

— so the in-tree test suite has **already** been written against option A's
world. The status quo is the thing that disagrees with the tree.

The ticket's condition for A is met with room to spare, so A is a derivation.

## Why not B or C

B (a `vtXxx` set of our own) is *"cheap, honest, and permanently
non-portable"* by the ticket's own description — and permanent non-portability
in the unit whose entire reason to exist is FPC compatibility is a contradiction
in the deliverable, against the standing goal of compiling real code.

C is refused by `normalise-dont-special-case.md` — two functions answering one
question is the double case the note exists to prevent, and the ticket already
says so.

## The line this shares with two sibling decisions

The RTL **facade** speaks FPC's public numbering; the compiler's internal tags
stay ours and stay private. `VarType` returning `VT_INT` is an implementation
detail that leaked through a public API, exactly as the RTTI blob's kind fields
did — see [[decide-rtti-kind-numbering]] and
[[decide-classinfo-returns-our-blob-or-nothing]]. Three tickets, one policy,
recorded in `README-agent-decisions.md`.

## Scope note, so this stays a Track B job

The translation belongs **in `variants.pas`**, not in the tag emit: `VarType`
maps the internal tag to the FPC code on the way out, the `VT_` constants stay
private to the unit, and no compiler change is needed. That is the facade seam
doing its job.

## The `varNull` tail the ticket flags

pxx has no `varNull` distinct from `varEmpty`, and A makes that visible where it
was not. It does **not** pull the tag question along: `VarType` reports
`varEmpty` (0) for `VT_EMPTY`, which is honest about what the dialect
distinguishes. Whether `Null` becomes its own tag is
[[decide-should-a-null-variant-raise-like-fpc]], decided the same day as "no".

## Re-filed as work

Track **B**: `feature-b-vartype-speaks-fpc-varxxx-codes`, prio 45 — export FPC's
`varXxx` constant set from `variants.pas` and map `VarType`'s result onto it,
updating the four internal call sites.

## Log
- 2026-08-25 — decided, commit PENDING-COMMIT.
