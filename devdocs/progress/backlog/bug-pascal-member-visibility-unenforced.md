---
prio: 20
---

# member visibility is not enforced (private/protected/strict readable+writable from anywhere)

- **Type:** bug / policy decision (Pascal frontend — access control)
- **Track:** P — tag: compat
- **Split from:** [[bug-pascal-missing-diagnostics-fail-tests]] (its last open
  entry, tclass12b, is this).

## State
pxx parses all visibility markers (`private`, `protected`, `public`,
`published`, `strict private`, `strict protected`) but enforces none of them —
the class/record parsers say so in comments ("access is not enforced, project
policy"). Only `published` has an effect (RTTI). tclass12b (`strict private`
const reached from a DESCENDANT class) is the conformance reminder test; it is
skip-listed as accepts-invalid pointing here.

## Agreed direction (user + agent discussion, 2026-07-15 morning) — ON HOLD

**Status: user is still considering — do NOT start implementation.**

Plan sketched and tentatively agreed:
1. Per-feature switch `--strict-visibility` / `{$STRICT_VISIBILITY ON}`,
   DEFAULT OFF — the lax dialect keeps its ergonomics (the user's long-
   standing annoyance with locked-down hierarchies is deliberate design
   here, and half the ecosystem works around FPC/Delphi visibility with the
   class-cracker idiom anyway).
2. First slice: enforce ONLY `strict private`/`strict protected`
   (type-scoped, no unit subtlety, burns tclass12b, tiny surface).
3. Second slice: unit-scoped `private`/`protected` — requires tagging
   members with their DECLARING UNIT (UFld*/UMeth* don't carry it today).
   User note: plain `private` is the one that actually matters in practice,
   because of possible NAME CONFLICTS — it is also the costliest to get
   right, hence the sequencing.
4. Promotion into `--mimic-fpc` only AFTER the flag stays green ON across
   the FPC-valid corpora (fgl, Synapse, fpjson, the conformance pass set):
   those compile under real FPC, so any rejection = our semantics bug — a
   mechanical criterion for the user's (justified) side-effect worry.
   Faithful FPC semantics also preserve the community's workarounds
   (same-unit access, the cracker cast), which sloppy class-only scoping
   would break.

## If/when enforced, get the scoping right
- FPC's `private`/`protected` are **UNIT-scoped**: visible to the whole
  declaring unit, not just the type. A naive same-type-only check would
  reject masses of valid FPC code.
- `strict private`/`strict protected` are the type-scoped variants — the only
  ones a minimal first slice should enforce (that alone burns tclass12b).
- Enforcement likely belongs behind the `--strict` umbrella
  (feature-require-forward-strict-mode's flag infrastructure), not the lax
  default dialect.
