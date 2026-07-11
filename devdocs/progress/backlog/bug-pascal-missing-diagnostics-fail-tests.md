---
prio: 18  # RAINY-DAY (user call 2026-07-11): conformance-driven diagnostics deprioritized; 10/22 already burned, rest are deep clusters.
---

# pxx accepts invalid programs the FPC suite's %FAIL tests reject

- **Type:** bug umbrella (Pascal frontend, missing diagnostics)
- **Track:** P — tag: compat (FPC-parity diagnostics; see parallel-tracks.md)
- **Status:** backlog, RAINY-DAY — triaged 2026-07-11 (see below): dialect-pass
  entries closed as not-bugs; remaining real gaps parked as reminder tests
  ([[feature-pascal-corpus-fpc-testsuite]]).
- **Owner:** —

## Symptom
13 curated `{ %FAIL }` tests — programs the reference compiler must REJECT —
compile cleanly under pxx. Each is a missing semantic check. Skip-list reason:
`accepts-invalid`. Current list (audit 2026-07-10):

tarrconstr8 tdefault2 tdefault4 tdefault6 tdefault12 tenum4 terecs9 terecs12c
terecs13c tforin11 tgenconstraint38 tgenconstraint39 tgeneric56

Read each test's header comment for what diagnostic is expected (e.g. Default()
on forbidden types, extended-record visibility violations, generic-constraint
violations, invalid array constructors, for-in over non-iterable).

## Method
One test at a time: reproduce → add the check (with a matching `test/*.pas`
negative test in our own suite) → unskip. Split out sub-tickets if any check
turns out deep.

## Progress 2026-07-11 (opus-a)

Batches 1–3 landed (f6908a23, 034ce7ea, 3a601a9a) — 7 of 22 burned:
tdefault2/4/6 (file-type + Default() checks; TextFile now a real record),
tforin11 (string for-in requires Char var), terecs9 (self-containing record),
terecs12c/13c (class var in record rejected). Full sweep 263-ish pass / 0 fail.

Batches 4-5 (3f606750, 625f6114): SymEnumId enum identity plumbing —
toperatorerror (enum vs pointer compare) + tforin20 (for-in over holed enum)
+ tarrconstr8 (.member on array var, was a runtime crash). 10 of 22 burned.

Remaining 12 cluster deep:
- generics: tdefault12, tgenconstraint38/39, tgeneric13/14/20/21/56 (needs a
  generic-template registry lookup / constraint checks)
- enum identity (SymEnumId now EXISTS): tenum2 (inc past range via unit),
  tenum4 ($SCOPEDENUMS)
- tover3: overload AMBIGUITY ranking (cardinal arg vs longint/smallint/word
  candidates must error, needs scored matching not first-hit)
- tclass13c (TRootClass.Integer qualified-type member)

## Gate
`make test` + self-host byte-identical; burn the skip-list entries.

## 2026-07-11 — 24 more exposed by the headerless-program fix

The mandatory `program` header was accidentally rejecting 24 headerless
`{%FAIL}` negative tests before their actual invalid construct was ever
reached. With bug-pascal-headerless-program fixed, pxx now COMPILES them —
each is a real missing-diagnostic gap. From the conformance run (skiplist
reason "missing diagnostic: accepts invalid code"):

tcase3/6/9/10/11/19/20/23/26/27/35/36/39/42/43 (case-of-string validation:
overlapping/inverted ranges, duplicate labels), tclass13c, tenum2, tforin20,
tgeneric13/14/20/21, toperatorerror, tover3.

The tcase cluster is the bulk: case-statement label validation (duplicate
labels, inverted ranges) is simply not checked today.

## Triage 2026-07-11 (user review) — bug vs by-design

User call: PXX is more lax **by design**; a `{%FAIL}` test passing is only a
bug when pxx's semantics are undefined/silently wrong. Split of the 15 that
remained:

**Not bugs — retagged `dialect-pass` in pxx.skip (do not burn):**
- tgeneric14 — %fail encodes an FPC *implementation* limit ("assembler
  symbols not global"), not a language rule. pxx passing is correct.
- tgeneric20, tgeneric30 — generic method impl without `<T>`: pxx's generics
  surface deliberately accepts the stripped form (3d71edcf).
- tgenconstraint38/39 — generic constraints unenforced: pure compile-time
  safety net, runtime semantics well-defined. FPC-strict candidate.
- tenum2 — inc(enum) past range: lax enum-as-ordinal model, deterministic.
- tover3 — overload ambiguity: pxx ranks deterministically (longint for a
  cardinal arg, verified) by design; FPC-parity ambiguity error belongs to
  the existing `--strict-overload`, not the default.

**Real gaps — keep `accepts-invalid`, useful reminder tests, rainy-day:**
- tenum4 — `{$SCOPEDENUMS}` silently ignored → duplicate member name
  resolves to the wrong enum → wrong ordinals at runtime with no error.
  Worst of the list: implement the directive or reject it.
- tgeneric55/56, tdefault11/12, tgeneric13 — bare unspecialized template as
  a var type / Default() arg / type argument: the variable's type is
  undefined. One template-registry lookup at type resolution (registry
  exists since 3d71edcf) likely burns all five.
- tgeneric21 — nested generic-in-generic declaration, semantics unverified.

**Parked (user call):** tclass13c — `TRootClass.Integer` nested-type member,
needs a per-class nested-type registry; near-zero value. Also noted in
feature-pascal-corpus-fpc-testsuite.

## Case-label validation moved behind --strict-case (2026-07-11)

86cf34ea's duplicate/overlap + inverted-range errors were stricter than the
dialect intends: overlapping labels previously worked with first-match
semantics. Reverted the default to lax (first-match; inverted range = never
matches) and gated the FPC-parity errors behind the new `--strict-case` /
`{$STRICT_CASE ON}` (pattern of --strict-overload). Selector-TYPE checks stay
unconditional (the string/ordinal lowering depends on them). The conformance
sweep now passes --strict-case, so the burned tcase {%FAIL} tests stay green;
test_cross_case_range got its deliberate 'y'/'x'..'z' overlap back.
