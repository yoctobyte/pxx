---
prio: 55  # user 2026-07-15: real prio — compiler change, full route
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

## Direction (user decision, 2026-07-15 morning): FULL ROUTE, in progress

Per the user: no cheat-first strict-only slice — implement the real,
unit-scoped semantics from the start (plain `private` is the one that
matters in practice, because of name conflicts). Per-feature switch
`--strict-visibility` / `{$STRICT_VISIBILITY ON}`, DEFAULT OFF (the lax
dialect keeps its ergonomics — the locked-hierarchy annoyance is deliberate
design here). Promotion into `--mimic-fpc` only after the flag stays green
ON across the FPC-valid corpora (fgl, Synapse, fpjson, conformance pass
set) — those compile under real FPC, so any rejection = our semantics bug;
a mechanical criterion, and faithful semantics preserve the community's
workarounds (same-unit access, the cracker cast).

## Recon: the tagging mechanism already exists (user was right)

- SymUnitIdx / ProcUnitIdx / CurrentUnitIdx already track declaring units.
- Members need no own tag: a class is declared in ONE unit — a single new
  UClsUnitIdx[ci] (stamped from CurrentUnitIdx at class parse) covers all
  its fields/methods.
- Genuinely missing: per-member VISIBILITY storage (only published exists,
  UFldPub) — add UFldVis/UMethVis with section tracking in the class
  parser; and the resolver-side check (FindUField/FindUMeth callers are
  legion, so enforce IN the resolvers with a clear 'cannot access' error,
  gated on the flag + access-site context: CurrentUnitIdx for unit scope,
  the enclosing method's class for protected/descendant scope).

## If/when enforced, get the scoping right
- FPC's `private`/`protected` are **UNIT-scoped**: visible to the whole
  declaring unit, not just the type. A naive same-type-only check would
  reject masses of valid FPC code.
- `strict private`/`strict protected` are the type-scoped variants — the only
  ones a minimal first slice should enforce (that alone burns tclass12b).
- Enforcement likely belongs behind the `--strict` umbrella
  (feature-require-forward-strict-mode's flag infrastructure), not the lax
  default dialect.
