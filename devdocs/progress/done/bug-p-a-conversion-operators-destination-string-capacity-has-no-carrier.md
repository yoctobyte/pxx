---
track: P
prio: 45
type: bug
blocked-by: []
status: done
owner: frankS
summary: "RESOLVED 2026-09-09, measured 2026-09-08. `operator :=(const a: TTest): TString80` and the same operator returning TString90 were refused as duplicates; fpc 3.2.2 accepts both declarations and refuses at the STORE, if at all. The carrier half (ProcRetStrCap, the fifth member of a four-member family) landed 2026-09-07 for EXPLICIT casts. This closes the implicit half, and the finding is that ONE lookup was answering TWO questions: the DECLARATION asks `is this the same result type` — where String[80], String[90] and ShortString are three results, exactly — and the STORE asks `which operator serves this destination`, where capacity never filters at all. Measured cell by cell, because every obvious reading is wrong in some cell: a lone sized conversion serves ANY string destination (so capacity is not a filter); a generic result BEATS an exact capacity match (so it is not `prefer the closest`); and two sized conversions with no generic are REFUSED rather than resolved by declaration order (so it is not `take the first applicable`). Hence a rank plus a TIE TEST, with a tie raised at the store as fpc raises it. toperator94 burned; toperator92/95 now refuse for fpc's reason instead of by accident — they were %FAIL rows PASSING because pxx refused the wrong thing, which a harness comparing only `did it refuse` cannot see. Two divergences recorded, both measured: with all three operators declared and a plain ShortString destination fpc returns the FIRST-DECLARED sized one (different answers from the same program under two declaration orders — declaration order deciding an overload, not a rule to reproduce; pxx answers the generic for both); and fpc refuses a lone applicable conversion as soon as any OTHER record in the program also converts to a string, which pxx compiles. toperator91 is NOT closed and its remaining rule is now measured on its skip row: an explicit cast with no exact-capacity Explicit operator degrades to the IMPLICIT generic, not the Explicit one."
---

# A conversion operator's destination string capacity has no carrier

`class operator Implicit(const a: TTest): TString80` and the same operator
returning `TString90` are refused as duplicates. FPC accepts both declarations.
The destination of a conversion operator is keyed on the return type's KIND, and
every frozen-string kind compares equal (`OpConvResultMatches`, deliberately, so
that `string[N]` resolving to tyString in one position and tyFixedString in
another still matches — toperator93). The declared CAPACITY is what separates
TString80 from TString90, and the proc's RESULT has nowhere to put it.

## The absent carrier, enumerated

The capacity of a `string[N]` is carried once per carrier:

| carrier | declared |
| --- | --- |
| variable | `SymStrCap` |
| type alias | `AliasStrCap` |
| record field | `UFldStrCap` |
| parameter | `ptypesStrCap` (pasparser_proc.inc) |
| **routine RESULT** | **absent** |

Four present, all agreeing, and the fifth never conceived — the exact shape
`ProcRetSetEnumId`'s own comment describes for a different fact ("an ABSENT copy
has no diff, so reading the five against one another could never have produced
it"), and the shape `ptypesStrCap`'s comment describes for the parameter channel
("the FOURTH member of the return-channel family above, and the one that was
missing"). This file has now recorded the same pattern three times.

`ProcRetPtrAlias` is the precedent for the fix's shape: store the alias index
rather than a copy of the pointee's geometry.

**Needs a defs.inc slot** — frankH messaged before it is taken.

## The other half: the use-site ambiguity

Adding the capacity to the key is not sufficient on its own, and the reason is
the interesting part.

`toperator92` and `toperator95` are `%FAIL` rows that PASS today, and they pass
by refusing the wrong thing. FPC accepts their declarations and refuses at the
USE site — toperator92:32 `s := t;` is `Incompatible types: got "TTest" expected
"TString80"`, i.e. ambiguous. pxx refuses at DECLARATION time, toperator92:28,
`duplicate conversion operator`. Same verdict, different reason, and the harness
compares only whether a refusal happened.

So making the key finer must be paired with a use-site ambiguity refusal, or
those two rows flip from passing-for-the-wrong-reason to failing. Four rows move
together: toperator91 and toperator94 (currently skipped, FPC compiles them)
start passing; toperator92 and toperator95 keep passing and start doing it for
FPC's reason.

## A NEGATIVE RESULT, recorded so nobody repeats it

I censused all 212 `%FAIL` rows the harness runs and does not skip, comparing
pxx's first error LINE against fpc's, on the theory that a wrong-reason refusal
shows up as a line mismatch. **It does not, and the census cannot answer this
question.**

- 99 SAME-LINE, 112 DIFF-LINE, 1 auto-gated.
- Of the 112, 110 are within 10 lines of fpc — indistinguishable from ordinary
  position-reporting differences.
- The 2 rows with a gap above 10 lines are `tgeneric105` and `tgenfunc14`, both
  the ALREADY-KNOWN unit-source vacuity, both already auto-gated by the harness.
- **`toperator92`, the row that motivated the census and is a confirmed
  wrong-reason refusal, sits at a 4-line gap — inside the noise band.**

The instrument cannot see the thing it was built for, and it would have reported
112 rows of nothing as a finding. The line is the wrong channel; the DIAGNOSTIC
is the right one, which is what `run_pascal_conformance.sh`'s own DIAGMAP note
already says about the skip-list version of this question ("the diagnostic is
the channel that can observe this class; the exit code cannot"). The same
sentence holds one level over: for a `%FAIL` row the exit code cannot observe a
wrong-reason refusal, and neither can the line number.

Both confirmed instances (toperator92, toperator95) were found by READING the
duplicate-conversion check while working on toperator91, not by the census.


## 2026-09-09 (frankS) — RESOLVED, measured 2026-09-08. One lookup was answering two questions.

The carrier this ticket is named for landed 2026-09-07 and split EXPLICIT casts
by result capacity. What was left is the implicit half, and it was not a missing
column at all — it was the DECLARATION-time duplicate check and the USE-site
lookup being the same call.

They need different answers:

| | question | capacity |
| --- | --- | --- |
| declaration | is this the SAME RESULT TYPE as one already declared? | compared **exactly**: String[80], String[90] and ShortString are three results |
| store | which operator SERVES this destination? | never filters; ranks only |

Conflating them is what refused the pair fpc compiles. And the generic-fallback
exemption inside `OpConvResultMatches` — a result of DEFAULT_STR_CAP matches any
frozen-string destination — is correct for the store and wrong for the
declaration: with it in force, declaring `: TString90` found the ShortString
operator and called the pair a duplicate, so a generic conversion could not
coexist with a sized one at all. `capExact` turns it off for the declaration.

### The rule at the store, measured cell by cell

Every obvious reading is wrong in some cell, which is why this is a table and
not a sentence:

| declared | destination | fpc 3.2.2 |
| --- | --- | --- |
| sized80 | TString80 | sized80 |
| sized80 | TString90 | **sized80** — capacity is not a filter |
| sized80 + generic | TString80 | **generic** — an exact capacity match LOSES |
| sized80 + generic + sized90 | TString80 / TString90 | generic |
| sized80 + sized90, no generic | either | **refused, ambiguous** |

Row 3 rules out "prefer the closest capacity". Row 5 rules out "take the first
applicable one" — with nothing to prefer, fpc does not choose. So: a rank plus a
TIE TEST, and a tie is a refusal.

**The refusal had to land at the store and not at the declaration**, which is the
whole point of the ticket. Falling through instead was not an option: a store
that finds no conversion sends a record into a string RAW, which is a garbage
length byte and a segfault in WriteLn — the same fall-through that segfaulted
when this family was last touched.

### The two rows that were passing for the wrong reason

`toperator92` and `toperator95` are `%FAIL` rows that PASSED while pxx refused
the wrong thing — the declaration rather than the store. A harness that compares
only *whether* a refusal happened cannot see that, and the earlier census
recorded on this ticket established that the error LINE cannot see it either
(toperator92's gap was 4 lines, inside the noise band). They now refuse at the
store, for fpc's reason.

`toperator94` is burned. `toperator91` is not — see below.

### Two divergences, measured, chosen

- **Declaration order.** With all three operators declared and the destination a
  plain ShortString, fpc returns the FIRST-DECLARED sized one: `sized80` for one
  order and `sized90` for the other, from the same program. Declaration order
  deciding an overload is not a rule to reproduce — it is the same class as the
  ClassName defect closed today in
  [[bug-p-a-nested-specialization-is-named-by-its-alias-so-one-name-serves-every-outer-specialization]].
  pxx answers the generic for both orders. Not asserted in a fixture rather than
  pinned to either answer.
- **fpc is a fragile oracle for this subject.** `s80 := lone` compiles alone and
  fpc refuses it as soon as ANY other record in the program converts to a
  string, including through an unrelated ShortString operator, with exactly one
  operator applicable to a TLone. It appears to resolve by DESTINATION before
  checking which source the operator takes. pxx compiles those; us accepting
  what fpc rejects is not a defect. **It does constrain the fixtures**: each
  holds a single converting record, because a program with several cannot be
  checked against fpc at all. The first draft was not shaped that way and fpc
  rejected rows that are correct.

### What is left, and it is one rule

`toperator91` still halts, and the cause is now measured rather than described.
Its old skip reason named the `ShortString Implicit` SIX TIMES ranking; that is
not it. `s40 := TString40(t)` is an EXPLICIT cast to a capacity no Explicit
operator has, and fpc falls back to the ShortString **Implicit** operator where
pxx falls back to the ShortString **Explicit** one. Once that holds, the six
implicit assignments follow from the generic preference that just landed.

Deliberately not taken here: it changes the explicit-cast FALLBACK, which is the
path whose previous edit segfaulted, and which
`test_conversion_operator_result_capacity_is_part_of_its_identity.pas` pins. One
rule, one landing, with that fixture as its control. Filed as
[[bug-p-an-explicit-cast-with-no-capacity-match-falls-back-to-the-wrong-conversion-operator]].

### Fixtures

- `test_an_implicit_conversion_operator_is_chosen_without_regard_to_declaration_order.pas`
  — the rank, in BOTH declaration orders. Red at HEAD.
- `test_an_ambiguous_implicit_conversion_is_refused_at_the_store.pas` — MUST NOT
  COMPILE, wired on the MESSAGE so a refusal for another reason cannot pass it.
  Red at HEAD (it refused at the declaration).
- `test_a_lone_sized_conversion_operator_serves_any_string_destination.pas` — a
  REGRESSION GUARD that passes at HEAD, deliberately and labelled as such: it
  asserts the behaviour the fix must not break, since the new rank is one edit
  away from being written as a filter and a filter breaks exactly this row,
  silently, into a raw store.

### Verified, and what was NOT

Compiler `0f14028acc04`, `converged after 1 round(s)`.

- `tools/gate.sh quick` — `gate: GREEN (exit 0)`, read from the log, no FAIL rows.
- pascal conformance — 420 pass / 0 fail / 45 gap, 0 `^FAIL` rows. The 419 -> 420
  step is this change's own `toperator94` row and nothing else: the only skip
  diff in the tree was mine, and the last commit touching `pxx.skip` was mine.
- `make test-fgl` — 7 pass / 0 fail, PASS.
- **The full tier has no verdict.** Three attempts, all KILLED by the harness's
  low-memory watchdog rather than failed — an external `tools.import_nl --tiles`
  job held 20.5G with 21G available throughout. What DID run before each kill:
  2268 `ok:` rows with zero FAIL (the whole Pascal fixture set including all
  three new ones, plus the C and float sections), stopped at the round-2
  self-host compile near the end of `test-core`; and a separate `test-nilpy`
  reaching 462 `ok:` rows, zero FAIL, before the same watchdog. A partial log is
  not a verdict and is not reported as one — the NilPy and thread rows past
  those points are UNMEASURED for this change, which matters because the rewrite
  sits in `ir.inc`'s assignment lowering and every frontend shares it.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 039ed97cc.
