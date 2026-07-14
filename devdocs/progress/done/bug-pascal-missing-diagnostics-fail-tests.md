---
prio: 18  # RAINY-DAY (user call 2026-07-11): conformance-driven diagnostics deprioritized; 10/22 already burned, rest are deep clusters.
---

# pxx accepts invalid programs the FPC suite's %FAIL tests reject

- **Type:** bug umbrella (Pascal frontend, missing diagnostics)
- **Track:** P — tag: compat (FPC-parity diagnostics; see parallel-tracks.md)
- **Status:** working
  entries closed as not-bugs; remaining real gaps parked as reminder tests
  ([[feature-pascal-corpus-fpc-testsuite]]).
- **Owner:** trackAP-b342

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

## 2026-07-14 — the "real gaps" from the triage are BURNED (b342, b343)

User call: take it even though it was flagged rainy-day. Both of the clusters the
2026-07-11 triage kept as *real* gaps are done, and neither was what the ticket thought.

### tenum4 — the directive was fine; the missing TYPE CHECK was the bug (b342, 4e55e07d)
`{$SCOPEDENUMS}` is **honoured** (landed since the triage): a scoped member is not
reachable unqualified. That is precisely what made tenum4 dangerous — `En1 := first`
resolves `first` to the OTHER, unscoped enum, and pxx then **silently took its ordinal**.

The real hole was general and had nothing to do with the directive: **two enum types were
not distinct**. `c := banana` (TFruit into a TColor) stored the RHS's ordinal, so the
TColor read back as `green`. `c = apple` compared across enums and answered. Fixed both.

Two sub-findings worth keeping:
- `AddConst` never reset `SymEnumId` — a const inherited whatever the recycled symbol slot
  last held. The parallel-array landmine, again ([[project_symtab_alloc_parallel_array_landmine]]).
- An unscoped enum member folds to a bare ordinal literal at use, which drops the symbol and
  with it the only evidence of which enum minted it — so the identity had to be carried on
  the NODE (`ASTEnumId`) for the check to be possible at all.

The check sits at the IR lowering of AN_ASSIGN (every syntactic assignment funnels through
it), which needed a new `ErrorAt(line, msg)`: at that point the parser is long past EOF, so
`Error`'s line and `near:` window both pointed at the end of the program.

### The template cluster — 5 entries, ONE of them needed code (b343, 9cd57ddf)
`Default(<bare template>)` was the only live gap (tdefault11/12): a template has no size and
no zero value, so the expression is undefined. Rejected via the template registry, with
`Default(TBox<Integer>)` / `Default(specialize TBox<Integer>)` still legal.

**tgeneric55, tgeneric56 and tgeneric13 were already rejected** — their skip notes were
stale. Burned them from the skip-list rather than leaving them claiming a gap that no longer
exists.

### Conformance now
265 -> **270 pass**, 20 fail, 226 skip. `make test` green, self-host byte-identical.

## What is actually left

- **tgeneric21** — nested generic-in-generic declaration; semantics unverified (from the
  triage; not touched).
- **The sweep is RED by 20**, and this ticket never listed them: `terecs2/5/12a/12b/13a/13b/
  13d/17/17a/19`, `tsealed1/2/3`, `toperator71/92/95`, `tclass12b/14b` (all accepted-invalid)
  plus `tdefault8` / `tset4` (compile: `unknown type: TSysCharSet`, and an unknown type in a
  record — unrelated to diagnostics). These are NOT in the skip-list, so they fail the sweep
  today. The `tsealed` and `terecs` visibility/sealed clusters look like the next coherent
  batch if this is picked up again.
- Everything the user triaged as `dialect-pass` (tgenconstraint38/39, tover3, tenum2,
  tgeneric14/20/30) stays closed by design — strictness belongs behind `--strict-*`.

## 2026-07-14 (later) — the RECORD cluster is burned (b347); and a correction

Landed b347: what a RECORD may legally CONTAIN. Ten of the sweep's failures, five rules —
no `published`, no `protected`/`strict protected` (records do not inherit), a record's
`class` method must be `static`, a record constructor needs a MANDATORY parameter
(`Create(I: Integer = 0)` is the same hole spelled differently), and a LOCAL or ANONYMOUS
record type gets fields only (a method there could never be given an implementation).

**Correction — do not repeat this:** a triage pass claimed *"13 of the 17 failures are ONE
bug: member visibility is not enforced"*. That was **wrong**, and it would have sent someone
to write an access-control checker to fix tests that have nothing to do with access control.
The `terecs*` cluster is **declaration legality**, not visibility. Exactly ONE of the
seventeen (`tclass12b` — `strict private` reached from a descendant) is really visibility.

Visibility genuinely IS unenforced (`private` fields are readable and writable from outside
the type, and the record parser said so in a comment) — it is simply not what those tests
were failing on. Worth its own ticket when someone takes it; note FPC's rule is UNIT-scoped
(`private` = visible to the whole unit), not type-scoped, so the naive "same type only"
check would be wrong.

Sweep now **283 pass / 7 fail** (from 273/17). Remaining: `tclass12b`, `tclass14b`,
`toperator71/92/95`, and the two real compile gaps `tdefault8` (nested type reference) and
`tset4` (`TSysCharSet` missing from the RTL).

## 2026-07-14 (later still) — SWEEP GREEN: 289 pass / 0 fail (b369). Ticket CLOSED.

User unparked the rainy-day flag. The final five:
- **tdefault8 / tset4** — already fixed by 5649c749 (class-nested types by
  qualified name + TSysCharSet); the sweep just hadn't been re-run.
- **tclass14b** — `published` class property now rejected ("a class property
  cannot be published"). Keyed on an EXPLICIT `published` marker only — the
  implicit default section stays lenient (pxx treats every class as $M+).
- **toperator71** — overloading `=`/`<>` for CLASS operands rejected (they are
  predefined reference equality).
- **toperator92 / toperator95** — a second `:=`/Implicit/Explicit conversion
  from the same source type to a result of the same TYPE KIND rejected as a
  duplicate (String[80] vs String[90] are indistinguishable at use sites);
  distinct result kinds stay legal. Catches the class-operator + global-
  operator split form too (one shared overload table).
- **tclass12b** — the one true visibility test: NOT fixable under the
  "access control unenforced" project policy. Split out to
  [[bug-pascal-member-visibility-unenforced]] (with FPC's unit-scoped
  private/protected caveat) and skip-listed pointing there.

Conformance: 285 -> 289 pass, 0 fail. tgeneric21 (nested generic-in-generic,
semantics unverified) remains noted in feature-pascal-corpus-fpc-testsuite.
