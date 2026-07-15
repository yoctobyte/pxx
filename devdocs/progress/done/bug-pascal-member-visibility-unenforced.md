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

## Direction (user, 2026-07-15 morning): FULL ROUTE — DESIGN NOTE ONLY, NOT STARTED

Per the user: no cheat-first strict-only slice — implement the real,
unit-scoped semantics from the start (plain `private` is the one that
matters in practice, because of name conflicts). This is Track P, a
compiler change with real prio — but the user has NOT authorized starting;
this section is captured design direction only. Per-feature switch
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

## Progress (2026-07-15, agent-A — FIELD visibility landed behind the flag)

Landed (commit 23fd7574): the real, FPC-faithful, unit-scoped model behind
`--strict-visibility` / `{$STRICT_VISIBILITY ON}`, **default OFF** — self-host
byte-identical (the lax path runs no extra lookup).

- **Data model:** `UClsUnitIdx` (declaring unit, stamped in AddUClass),
  `UFldVis`/`UMthVis` (per-member level VIS_*, stamped from the class-body section
  tracker beside UFldPub), VIS_* constants, the flag (CLI + directive + default
  off, mirroring --strict-case).
- **Enforcement (FIELDS):** `EnforceMemberVis` uses the access context from the
  globals CurrentUnitIdx + CurSelfClass; scoping = private/protected UNIT-scoped
  (protected also grants descendants), strict variants TYPE-scoped. Wired at the
  genuine field-access sites (explicit obj.field read+write, bare implicit-Self),
  guarded on the flag. Unknown declaring class fails OPEN.
- **Verified:** flag rejects an external private access and a strict-private field
  reached from a descendant (the tclass12b shape, on a field); valid patterns
  (same-class other-instance private, descendant-reads-protected, same-unit,
  public) compile; **ZERO false-positives** sweeping the whole class/OOP/interface/
  record test suite with the flag on. Regressions: `test_member_visibility`
  (positive, both modes) + `test_member_visibility_strict_fail` (negative).

### Remaining before full resolution / --mimic-fpc promotion
1. **Method-call enforcement** — same helper + MethDeclClass/UMthVis, wired at the
   obj.method() and bare-Self call sites (numerous; each needs the same
   false-positive sweep the field wiring got). `MethDeclClass` helper already added.
2. **Class-const scoping** — tclass12b's EXACT case is a `strict private const`,
   which pxx models as a GLOBAL (class consts are not scoped members here), so it
   is not yet caught. Needs class-const scoping, a separate mechanism.
3. **Full FPC-corpus validation** — compile fgl / Synapse / fpjson / the
   conformance pass-set with the flag ON; any rejection of that valid code is a
   semantics bug to fix before promoting into `--mimic-fpc`.

## Log
- 2026-07-15 — resolved, commit 23fd7574.

## Resolution (2026-07-15, agent-ACP — commit df41ab5e)

Items 1 and 3 of the remaining list landed; item 2 split out.
1. **Method-call enforcement** — EnforceMethVis wired at all committed dispatch
   sites (never on probes). Negative tests: external private call, descendant
   strict-private (test_method_visibility_strict_fail); positives extended in
   test_member_visibility (private/protected methods, property-over-protected).
2. **Property-backed field exemption** — a public property over a private field
   was false-positived at the property expansion site (TList.Count and 4 more
   Classes tests); the backing-field access is now exempt (viaProp), matching
   FPC (the check belongs to the property, which pxx parses in-section).
3. **Corpus validation + PROMOTION** — flag ON: test/ sweep 745 files clean,
   conformance pass-set 328/328, fpjson 203/203 (binary identical), Synapse
   identical output, real-FPC fgl green. --mimic-fpc now sets StrictVisibility.
Residual (class-CONST scoping, tclass12b's exact case) →
[[bug-pascal-class-const-visibility]] (prio 20, compat).

- 2026-07-15 — resolved, commit df41ab5e.
