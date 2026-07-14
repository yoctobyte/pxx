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

## If/when enforced, get the scoping right
- FPC's `private`/`protected` are **UNIT-scoped**: visible to the whole
  declaring unit, not just the type. A naive same-type-only check would
  reject masses of valid FPC code.
- `strict private`/`strict protected` are the type-scoped variants — the only
  ones a minimal first slice should enforce (that alone burns tclass12b).
- Enforcement likely belongs behind the `--strict` umbrella
  (feature-require-forward-strict-mode's flag infrastructure), not the lax
  default dialect.
