---
prio: 65
blocked-by: []
track: P
status: working
owner: "frankS"
summary: "Rung 1 of the Pascal corpus ladder: FPC 3.2.2's own `tests/test` suite (1447 `.pp`, fetched by `tools/install_lib_candidates.sh fpc-testsuite`, gitignored) run as a conformance corpus, burning the skip list one narrowed frontend bug at a time. Last full census **391 pass, 0 fail, 109 skip, 50 auto-gated of 550** at compiler `5dec56ae8b3f`, re-confirmed at `88a0b3d93835` (frankS, 2026-09-06), superseding 377 at `e929e720f` and 368 at `36d7e5fd4`. THE 2026-07-10 PARK IN THE BODY IS SUPERSEDED AND IS NOT A LIVE BLOCK -- its three named tickets are in `done/` and sole-A confirmation no longer exists in this repo. **IT WENT UP ACROSS A RUNNER CHANGE THAT REMOVES ROWS**: `109fbebb1` auto-gates a unit source (FPC's `dotest` compiles a unit standalone, pxx refuses, and a refusal satisfies `%FAIL` whatever the file holds, so those rows passed vacuously — 17 rows gated as `unit-source` here), and the generic-method work outran it. The 377 is a NET and has NOT been decomposed into newly-gated versus newly-passing; that needs the old runner at the old commit and nobody has run it (frankS's caveat, and they declined to guess). `--report` now writes a per-row TSV, so the next delta is a diff rather than a re-derivation. THE TWO `blocked-by:` EDGES ARE STALE AS BLOCKERS: `erroraddr`, `TFPCHeapStatus` and `GetFPCHeapStatus` all resolve from user code at `855356445cd7` and the heap counters are genuinely always-on (measured by delta, not by declaration), so `erroru.pp` — the suite helper whose absence gated `tobject1 tstring2 tstring4 tstring5 texception3` as three unrelated-looking clusters — now compiles. Four of those five compile; `tobject1` has a different wall behind it (`bug-p-object-value-types-standard-meaning`). The B rows stay open on their own criterion, which is a march over the separate FPC compiler-source corpus, so this row is gated by paperwork rather than by capability. Known trap on any burn: exit-clean is not correct — the runner compares exit codes, not output."
---

# Pascal corpus rung 1 — FPC test-suite subset (conformance)

## 2026-09-06 (frank-coordinator) — the two `blocked-by:` edges are CUT, and the reason is measured

**This row was in `working/` with an empty `owner:` AND gated by two edges its own summary
calls stale. Both states hid it, in opposite directions, from the instrument the Track P
campaign is counted with.** `working/` kept it out of `ready`; the edges would have kept it
out even after parking. **At p65, with four sessions contributing to it tonight, it appeared
in no count of remaining Track P work.**

**Parked** (nobody holds it — the section below says so in as many words: *"frontmatter
`owner:` deliberately left unset rather than assigned by a passing seat"*), **and the two
edges removed.**

**The edges are cut on a measurement, not on impatience.** frankD verified both Track B
features at `f38359248`: `ErrorAddr := nil` compiles and runs, and `GetFPCHeapStatus` is live
and always-on in an ordinary build — **`0 -> 1048576` across a 1 MB `GetMem`**, against fpc's
`0 -> 1048608`, measured as a **delta** rather than by a single call that could not tell a
stub from an empty heap. `erroru.pp` — the suite helper whose absence gated `tobject1
tstring2 tstring4 tstring5 texception3` as three unrelated-looking clusters — now compiles.

**The two B tickets stay OPEN and that is correct**: their own completion criterion is a march
over `cclasses` / `comphook` / `finput` / `cfileutl`, the **FPC compiler-source** corpus, a
*different candidate* from `fpc-testsuite` and not fetched. **Feature implemented, four
consumers unverified.** But that residual is theirs and it does not gate this row, which
needed the features to WORK and not to be signed off.

**Consequence worth stating rather than leaving to be discovered:** those two B rows no longer
inherit this row's p65 through `effective_prio`, so they will rank lower. That is the correct
answer — a ticket whose feature is implemented should not be carrying the urgency of a row it
no longer blocks.

**Reversible, and here is the trigger to reverse it:** if a `fpc-testsuite` burn hits a wall
that traces to `ErrorAddr` or `GetFPCHeapStatus`, re-add the edge and say which row failed.

- **Type:** feature (frontend conformance corpus)
- **Track:** P (Pascal frontend)
- **Status:** working — filed 2026-07-10. Rung 1 of
  [[feature-pascal-corpus-expansion]].
- **Owner:** frankS

## Idea
FPC ships `tests/test/**` — thousands of small `.pp` programs, each exercising
one language feature (`tbs*`, `tobject*`, `tgeneric*`, `terror*` for expected
failures, etc.). It is the **c-testsuite analog for Pascal**, but authoritative
(the reference compiler's own suite) and far larger. PXX is FPC-faithful, so most
should compile + run to the same result — and every one that doesn't is a sharply
localized dialect bug.

## Scope (start small, ladder up)
- Vendor a **curated subset** first (installer fetcher, pinned FPC release tag,
  gitignored) — not all thousands at once. Begin with the categories the compiler
  self-host never exercises: **generics** (`tgeneric*`), **classes/properties/
  visibility** (`tobject*`, `class*`), **exceptions** (`texcept*`), **RTL/string/
  math** units, **operator overloading**, **variants**.
- Runner (mirror `install_lib_candidates.sh` + the c-testsuite harness): compile
  each, run, diff stdout; honor the suite's `%FAIL`/`%NORUN`/expected-error
  markers so `terror*` negatives count as pass when they correctly reject.
- **Skip list, burned ticket by ticket** — same discipline as c-testsuite: a
  failing program → one narrowed frontend bug (Track P for `lexer`/`parser`/
  dialect, Track A for IR/backend). Do NOT inline-fix during the audit; file, then
  resolve. Report the running pass count (like c-testsuite 220/220).

## Watch-outs
- FPC test suite assumes FPC RTL + modes; gate each program on **mode** and unit
  availability — a test needing a unit PXX lacks is a skip (→ RTL/library ticket),
  not a frontend bug. Separate "dialect gap" from "missing RTL."
- Expected-failure tests (`terror*`) must be run for *rejection*, not acceptance
  — a PXX that accepts an invalid program is a real bug the suite catches.
- Keep the vendored tree gitignored; commit only the fetcher + the skip-list +
  pass-count report.

## Gate
`make test` + self-host byte-identical for any frontend fix (shared
`lexer.inc`/`parser.inc`). Rung is "green" at an agreed pass threshold on the
curated subset; expand the subset as rungs clear.

## Links
Rung of [[feature-pascal-corpus-expansion]] · method mirror
[[feature-c-corpus-expansion]] · dialect policy
[[project_fpc_compat_next_queue]] · [[project_mimic_fpc_done]].

## 2026-07-10 — infra landed + baseline audit

- Fetcher: `tools/install_lib_candidates.sh fpc-testsuite` — sparse
  `tests/test` + `tests/tstunits` (erroru et al, symlinked next to the tests)
  at FPC `release_3_2_2` (0d122c49), gitignored, PROVENANCE.md.
- Runner: `tools/run_pascal_conformance.sh` — curated categories (generics,
  classes/props, exceptions, operators, strings/arrays/sets/case/enums/for-in,
  extended records, interfaces...), FPC dotest directives honored (`%FAIL` =
  must-reject, `%NORUN`, `%RESULT`, cpu/target/version/opt gates auto-skip),
  `--shard I/N`, `--all`, `--only GLOB`. Skip list
  `test/pascal-conformance/pxx.skip` (name + reason), same discipline as
  c-testsuite.
- **Baseline: 222 pass / 294 skip-listed / 34 auto-gated of 550 curated.**
- Cluster tickets filed: [[bug-pascal-headerless-program]] (111!),
  [[feature-pascal-delphi-generics-syntax]] (93),
  [[feature-pascal-generic-nonclass-templates]] (10),
  [[feature-pascal-class-management-operators]] (8),
  [[bug-pascal-missing-diagnostics-fail-tests]] (13),
  [[task-pascal-conformance-long-tail]] (rest).
- Note: the two big parser clusters touch shared `parser.inc` → sole-A
  confirmation needed before an E+B+P agent edits them.

## Parked 2026-07-10 — SUPERSEDED, DO NOT READ AS A LIVE BLOCK
> **This park was lifted on 2026-07-14 (see below) and the resume condition it
> states no longer exists**: the three tickets it names are all in `done/`, and
> "sole-A confirmation" is not a thing this repo has any more — CLAUDE.md's cold
> start says *"just take it — there is no sole-A guard and no grant to request."*
> Kept because it is the record of why the ticket sat, not an instruction.
> Flagged by `progress.sh check` as STALE-PARK-HELD, correctly: a held ticket is
> where a stale resume condition survives longest, because the holder has
> stopped re-reading the park they wrote. I am the holder and I had.

Infra + baseline + cluster tickets landed (see above). Burn-down of the two big
parser clusters edits shared `parser.inc` — needs the sole-A confirmation an
E+B+P agent doesn't have. Resume: grab a cluster ticket, confirm sole-A, burn
skip-list entries.

## Note 2026-07-11 — dialect-pass category + strict-case sweep
pxx.skip now distinguishes `dialect-pass` (PXX lax by design / FPC-impl-limit
tests — NOT bugs, do not burn: tgeneric14/20/30, tgenconstraint38/39, tenum2,
tover3) from `accepts-invalid` (real missing diagnostics, rainy-day). The
sweep runs the compiler with `--strict-case` (FPC-parity case-label
diagnostics; PXX's default keeps lax first-match labels). tclass13c
(TRootClass.Integer nested-type member) is PARKED by user call — needs a
per-class nested-type registry, near-zero value; revisit only if nested-type
lookups matter elsewhere. Triage details in
bug-pascal-missing-diagnostics-fail-tests.

## 2026-07-14 — UNPARKED, and the numbers in this ticket are stale.

The sole-A parking excuse is gone: both big parser clusters it was blocked on
(`bug-pascal-headerless-program`, `feature-pascal-delphi-generics-syntax`) plus
`feature-pascal-generic-nonclass-templates` are in `done/`.

**Current sweep at HEAD: 283 pass / 7 fail / 226 skip** (this ticket's text claims a 279/0
sweep, and the baseline it quotes is 222 — both stale). Today's session moved it 273 -> 283
by burning the whole advanced-record legality cluster (b347) plus tenum4 / the template
cluster / tsealed (b342-b344).

The 7 that remain, correctly classified (the diagnostics umbrella had these filed as "13 of
17 = one visibility bug", which was **wrong** — only ONE of them is visibility):

- `tclass12b` — `strict private` const reached from a DESCENDANT. The only real *visibility*
  test. Access control is still not enforced anywhere.
- `tclass14b` — a published class property.
- `toperator71 / 92 / 95` — operator declaration rules (a global `operator =` on a class
  type; two `Implicit` overloads differing only in RESULT type).
- `tdefault8` — **compile gap**: a nested type reference (`TTest.TRecord`) -> `unknown type`.
- `tset4` — **compile gap**: `TSysCharSet` is missing from the RTL.

The two compile gaps are the only ones that are not diagnostics, and they are the ones worth
taking first — a program that will not compile is a bigger hole than a program we fail to
reject.

Moved back to `backlog/`.

- 2026-07-19 (backlog sweep note) Stale numbers: sweep at HEAD is 323 pass / 0 fail (7b54288c) — the 283/7 and 279/0 figures above are outdated. Remaining scope = the ~200-entry skip-list burn-down (rainy-day per user).

## 2026-08-30 — RE-MEASURE (triage only, nothing applied): not a stale blocker; possibly mispriced

Checked in the parked-ticket pass, because this ticket names four now-resolved
slugs. It is **not** a stale resume condition: the 2026-07-10 park was blocked on
two parser clusters, and the ticket **already recorded its own unblocking** on
2026-07-14 ("UNPARKED... both big parser clusters it was blocked on ... are in
`done/`"). The scan hit is those same slugs, cited by the note that resolved
them. Working as intended.

What it is instead is a **pricing** question. The current park is a user call —
*"remaining burn-down is rainy-day per user call 2026-07-11"* — and the last
note (2026-07-19) puts the sweep at 323 pass / 0 fail with the remaining scope
being the ~200-entry skip-list burn-down. That work is `compat`-tagged
conformance-diagnostic parity, which CLAUDE.md's compat table places at the
*defer* end ("our diagnostic/message/error number differs → defer"), and it is
explicitly rainy-day by the owner's own call.

**It sits at `prio: 65`.** That is high enough to keep it in every ranker scan
ahead of work the same table ranks above it, which is the exact cost CLAUDE.md
warns about for parked-but-ranked tickets. **Recommend re-pricing down to the
15-25 band** the compat table implies for diagnostic parity — a Track P/owner
call, not mine, so it is flagged here rather than changed.

Also dated: the numbers in this file have now been superseded three times
(279/0 → 283/7 → 323/0). Anyone resuming should re-run the sweep before quoting
any of them.

Nothing applied.


---

## 2026-09-05 (frankA) — 347 -> 368 by burning 21 stale skip entries, and the skip list is not what the pricing note says it is

Re-claimed after the corpus install unblocked it. Working the **compile-gap**
half deliberately: the 2026-07-11 owner call parks the burn-down as rainy-day,
that call is about diagnostic parity, and a program that will not compile is not
that.

### The remaining scope is NOT mostly diagnostic parity

The 2026-08-30 note recommends re-pricing 65 -> 15-25 on the ground that the
remaining ~200-entry burn-down *"is compat-tagged conformance-diagnostic
parity"*. **By the skip file's own taxonomy it is not.** Censused before
touching anything, 167 rows:

| tag | rows |
| --- | --- |
| `gap:` — a real unimplemented pxx feature | 150 |
| `wontfix:` — probes FPC internals / deliberate divergence | 15 |
| `accepts-invalid:` — a diagnostic we do not emit | 2 |

**Two rows are the diagnostic kind.** The 150 are language features: generics
and specialize forms, operator overloading, record management operators,
old-style `object` types, subrange-of-enum, modeswitches. Re-pricing is a Track
P/owner call and is not made here -- but it should be made against 150/15/2
rather than against "diagnostic parity", which is what the recommendation
currently rests on.

### A skip reason is a dated claim, and 21 of them had expired

The harness had no way to re-test an entry, so nothing ever did. Added
`--retry-skips` (`1984e6ba9`) and ran it over all 167.

**24 rows came back exit-clean** (excluding `tgenconstraint37`, which is
frankB's and is left alone). Each was then diffed against fpc 3.2.2 rather than
trusted:

| | rows | disposition |
| --- | --- | --- |
| stdout AND exit code match fpc exactly | 17 | burned |
| unit-shaped; both compilers compile clean | 3 | burned |
| `tenum2` — a `%fail` row; both compilers reject at the SAME line | 1 | burned |
| exit 0 with WRONG OUTPUT | 3 | kept |

**Measured: 347 -> 368 pass, 167 -> 146 skip, 2 fail unchanged** (still
`tgenfunc17`/`tgenfunc18`, the accidental-pass pair, unrelated). 368+2+146+34 =
550 reconciles, and no new failure appeared.

### The instrument has a false-positive mode, measured at 3 of 24

This is the part worth carrying forward. **The harness compares the EXIT CODE,
not the output**, so a row that runs to completion printing wrong values is
"exit-clean". Three did:

- `tarray2` — a `PChar` in a `TVarRec` printed as its POINTER (`4366520`)
  instead of the string.
- `tforin24` — an enum name printed as garbage bytes where FPC prints `Monday`.
- `tclass12a` — double-width float where FPC prints 80-bit Extended.

**All three already said so in their own skip reasons** -- `tforin24`'s reads
*"exit 0 with wrong output -- keep skipped; re-confirmed 2026-07-15"*. So this
is not three new findings; it is a differential CONFIRMING that three reasons
are accurate and current, and catching that the new flag would have burned them.
The flag's summary now says this in its own output, with the rate, so the next
session does not have to rediscover it.

### Two things a burn-down must not skip

**Check `%FAIL` with the runner's own extractor, not a grep.** Mine said 0 of 25
were must-reject rows; the runner said 1. The runner was right: `tenum2` spells
it `{ %fail }` in lower case and the runner uppercases. Trusting my grep would
have burned a must-reject row. It turned out safe anyway -- pxx refuses it at
`e := tone`, exactly where fpc 3.2.2 refuses it with `Identifier not found
"tone"` -- but that was luck, established afterwards.

**A refuted lead is worth the two minutes.** `tenum2`'s refusal looked like a
real gap (an enum member invisible through a two-unit type alias). Built the
three-unit repro: **fpc refuses it identically**, so a type alias correctly does
not re-export enum members. Nothing filed. Its skip reason (*"inc(enum) past
range -- PXX's lax enum-as-ordinal model"*) misdescribes the row twice over --
neither compiler reaches the `inc`.

### Where the remaining 146 actually are — the priority list

Clustered from the surviving `gap:` reasons (130 of the 146; the rest are
`wontfix:`/`accepts-invalid:`). This is what "grow the umbrella by attempting the
target" produced, in the order the corpus itself puts them:

| rows | cluster |
| --- | --- |
| 42 | generics / `specialize` forms and constraints |
| 23 | operator overloading (global, cross-unit, `in`, implicit `:=`) |
| 13 | strings — shortstring / ansistring / pchar / widestring overload resolution |
| 8 | old-style `object` types (virtual methods, ctor/dtor) |
| 8 | enums and subranges-of-enum |
| 4 | an RTL unit or symbol we do not have |
| 2 each | typed-const initializers · for-in enumerators · variants / array of const |
| 25 | uncategorised by this pass — read them individually |

**Generics is a third of the remaining surface on its own**, and operator
overloading is another sixth. Those two clusters are 65 of 130. Anyone
continuing should take one cluster, not one row -- CLAUDE.md's group rule, and
the corpus is already sorted for it.

Counts reconcile: the file held 150 `gap:` rows, 20 of the 21 burned were `gap:`
(the 21st, `tenum2`, was `wontfix:`), leaving 130.

### What is left

146 skips, 142 of which the retry run confirms still fail. That is the real
burn-down surface and it is feature work, not diagnostics. `tgenconstraint37` is
frankB's and is untouched.

---

## 2026-09-05 (frankA) — the generics cluster, attempted as a cluster: 42 rows, and the first mechanism is ONE token

Took the cluster whole rather than row by row. **The interesting number is
mechanisms, not rows**, and the first one is a single lexing detail standing in
front of 8 rows.

### Mechanism 1 — a missing SPACE decided whether the program compiled

The suite writes generic headers tight:

```pascal
generic TList<_T>=class(TObject)
```

Maximal munch makes `>=` ONE `tkGe` token; the header grammar wants `>` then
`=`. Proven by varying exactly one axis — the identical program with a space
before the `=` compiles and runs, without it is refused `expected '>' before
'>='`. fpc 3.2.2 accepts both. A space cannot change what a program means.

**Fixed at the CONSUMER, deliberately not in the lexer.** The header collector's
own comment uses "`>=` lexes as tkGe" as the discriminator that tells a template
header from a comparison `a < b >= c`; splitting tkGe globally would destroy
that. At `ParseGenericTemplateNamed`'s `Expect(tkGt) / Expect(tkEq)` the parser
is already committed to a header, so a `>=` there can only be the tight
spelling. The two token-SCANNING detectors that share the blind spot
(`Tokens[j]=tkGt and Tokens[j+1]=tkEq`) were left alone: the diagnostic proves
detection had already succeeded, so widening them would be a guard whose
necessity was never shown.

### What the 8 rows did, which is the argument for attempting a cluster

| | |
| --- | --- |
| built AND matched fpc 3.2.2 | tgeneric1, tgeneric3, tgeneric5 |
| built, compile-only agreement (0 write-sites by design) | tgeneric92 |
| advanced PAST the header into a DIFFERENT diagnostic | tgeneric6, tgeneric8, tgeneric10, tgeneric11 |

**The header refusal was masking four more defects**, and they cluster again:
`cannot assign AnsiString to Integer` on both tgeneric6 and tgeneric8 (two rows,
one shape — smells like a type parameter not being substituted), plus
`"TCompareFunc": no such member` (tgeneric10) and `no overload of assign`
(tgeneric11). So 8 rows were at least three mechanisms deep, and only the
outermost is now gone.

**The four skip reasons were all over-attributed.** They said "objfpc generic
syntax not parsed" and, for tgeneric5, "+ `typeinfo(_T)` intrinsic and typinfo
unit". The real blocker was the one token; tgeneric5 needs no typeinfo work at
all. A reason written at triage names the first plausible cause and is never
re-read — which is the same finding as the burn-down above, from the other side.

### The count moved to 371/3, and the third failure is an ACCIDENTAL PASS REMOVED

```
test-pascal-conformance: 371 pass, 3 fail, 142 skip, 34 auto-gated (of 550)
  FAILURES: tgeneric4.pp tgenfunc17.pp tgenfunc18.pp   (all accepted-invalid)
```

368 + 4 unskipped = 372, minus tgeneric4 moving pass -> fail = 371; skip 146 ->
142; fail 2 -> 3. Reconciles exactly.

**tgeneric4 is not damage this change did.** It is `{ %fail }`, and pin v403
refuses it with `expected '>' before '>='` **in ugeneric4.pp** — it was green
because the parser could not read the unit. What it actually tests is a
diagnostic pxx has never had (`Global Generic template references static
symtable`). Filed as
[[bug-p-a-generic-template-body-resolves-its-symbols-at-the-specialization-site]], the
THIRD instance of this shape after tgenfunc17/18.

**Expect more of these.** A `%FAIL` row is a pass-by-refusal, so every parser
capability added here can turn one red, and each is a missing diagnostic that
was always missing. That is a property of the suite, not a regression signal —
but it means the pass count alone cannot be read as progress, and the fail list
has to be read by NAME every time.

Gate: quick GREEN, fgl 7/7, self-host converged. Every row moved from gap to
pass was diffed against fpc 3.2.2 output, not scored on its exit code.

### Mechanism 2 — a pointer to a nested type keeps the FIRST specialization's pointee

The two-row shape behind mechanism 1 (`tgeneric6`, `tgeneric8`, both saying
`cannot assign AnsiString to Integer`) reduced to a 15-line repro and is filed as
[[bug-p-a-pointer-to-a-generic-nested-type-is-shared-across-specializations]].

**Order-dependent**, which is what named it: swap the two `specialize` lines and
the message swaps direction. The pointee is whatever the first specialization
made it — a value read from a shared slot, not from the type.

**Three-way control, because the trigger is a CONJUNCTION and either half alone
passes:**

| probe | shape | result |
| --- | --- | --- |
| pointer to nested type, TWO specializations | | refused |
| pointer to nested type, ONE specialization | | correct |
| nested record used DIRECTLY, two specializations | | correct |

So the nested record IS specialized per instantiation; only the pointer's
pointee is shared. My first probe used the record directly and PASSED — the
minimal case is not the defect, and stopping there would have recorded "cannot
reproduce".

Not fixed here. The nested-type hoisting machinery in `pasparser_generic.inc` is
a different path and its own comment says it fires only when a nested type is
used as a GENERIC ARGUMENT, which a pointee is not. That is deeper than a
cluster pass should microfix, so the diagnosis is banked with the controls
rather than half-applied.

### The mechanism count — 41 rows are ~10 mechanisms, and the 7 that COMPILE are all defects

The cluster collapses, as predicted. Re-censused against the compiler AFTER
mechanism 1 landed, so this is the current picture and not the entry one.

| rows | mechanism | state |
| --- | --- | --- |
| 8 | tight `>=` in a generic header | **FIXED** `9a3b8f38c` — 4 rows pass, 4 advanced into the mechanisms below |
| 4 | `generic function F<T>` as a CLASS METHOD | filed [[feature-p-generic-routines-in-a-class-body-and-in-delphi-spelling]] |
| 4 | Delphi `function F<T>` — free routine and method | same ticket (one fix likely serves both) |
| 3 | missing diagnostic: a generic without specialization used as a variable type | tgeneric83/84/85 — pxx ACCEPTS |
| 2 | pointer to a nested type shared across specializations | filed [[bug-p-a-pointer-to-a-generic-nested-type-is-shared-across-specializations]] |
| 2 | `expected ':' before '.'` | unexamined |
| 1 | missing diagnostic: generic declared inside a generic | tgeneric21 — pxx ACCEPTS |
| 1 | `{ %result=201 }` range check never raised | tgeneric7 — pxx exits 0 |
| 2 | compiles, fails its own self-check | tgeneric15, tgeneric16 |
| ~11 | singleton diagnostics | unexamined |

**Seven rows already COMPILE, and not one of them is burnable.** Four are `%FAIL`
rows pxx wrongly accepts, one expects a runtime range check pxx never raises,
two run and fail their own assertions. Every one is the "compiles fine, behaves
wrong" class — the class an exit-code harness cannot see and the burn-down above
is most at risk from.

**I nearly burned four of them.** `fpc built no binary` was read as "unit-shaped,
so compile-only agreement". It was not: fpc produced no binary because fpc
REJECTS them. Two causes, one observation, and the discriminator is the
directive block — read with the runner's own `directives()`, three of the four
turned out to share ONE missing diagnostic ("Generics without specialization
cannot be used as a type for a variable"). Second time in one session that
`%FAIL` nearly turned a defect into a green row, in a new disguise.

**So the cluster is roughly 10 mechanisms behind 41 rows**, and the top three
account for 16 of them. Generics is not 42 problems.


## 2026-09-05 (frankA) — the generic-routine lever, and what it did to the census

`feature-p-generic-routines-in-a-class-body-and-in-delphi-spelling` is resolved
(`63b699013`, `0ee1e272f`). Against the mechanism table above:

| was | now |
| --- | --- |
| 4 rows — `generic function F<T>` as a CLASS METHOD | **mechanism closed.** tgenfunc4 passes; tgenfunc5/6 parse and compute; tgenfunc12 partial; tgenfunc7/9 split out |
| 4 rows — Delphi `function F<T>`, free and method | **mechanism closed.** Same commit, same expansion — it was one job |

**Two mechanisms closed, two conformance rows moved.** That gap between the two
numbers is the whole point of reporting mechanisms: the remaining rows are held
by things that have nothing to do with generic routines —

- `tgenfunc5`, `tgenfunc6`: the ROWS call an instance method on a
  never-`Create`d object. pxx raises nil-reference 216 where fpc runs it, and
  that is **pre-existing, non-generic and chosen** (an ordinary method on a nil
  receiver does the same on pin v403). One added `Create` and both exit 0.
- `tarray16`: dynamic-array const initializers, verified still missing.
- `tgenfunc7`, `tgenfunc9`: cross-unit, now
  [[feature-p-a-generic-method-cannot-be-used-from-across-a-uses-clause]].
- `tgenfunc12`: `.Free` on a method RESULT, and `specialize F<C>;` with no
  argument list.

**And the pass count is again the wrong instrument.** Both commits moved it by
+1 and 0 respectively while turning two `%FAIL` rows red (`tgeneric31`, caught
and fixed — it was a real diagnostic the change had removed; `tgenfunc14`, kept,
because accepting a redundant constraint is not a defect). Read by NAME or you
see nothing.

---

## 2026-09-05 (frankA) — the skip list re-clustered by MEASURED first error, not by reason text

The 2026-09-05 cluster table above was built from the skip file's REASON TEXT.
Three clusters taken from it since have each turned out to be mislabelled —
generics was ten mechanisms, strings/pchar seven, "enums" was really "a subrange
bound must be a literal token", "object" conflated three unrelated constructs.
**A reason line is a symptom label written by whoever last looked**, so this pass
did not read any of them: every skip row was re-attempted with
`--retry-skips` and clustered on the compiler's own first error.

Measured at `36d7e5fd4`, compiler `e6af001d6c0e3bf2`, 133 rows re-attempted:
**5 now exit-clean, 128 still failing**, 132 with a captured first error.

| rows | measured first error |
| --- | --- |
| 25 | `expected '…' before '…'` |
| 17 | `%FAIL test compiled (…)` |
| 16 | `undefined variable (…)` |
| 5 | `class var is not allowed in a record type` |
| 5 | `an object type cannot have a constructor -- pxx lowers `object` as a value type ` |
| 4 | `exit code 1 (…)` |
| 3 | `expected name` |
| 2 | `dynamic array initializer not supported` |
| 2 | `duplicate definition of '…' with the same parameter types; the later body wins, ` |
| 2 | `not a constant` |
| 2 | `exit code 216 (…)` |
| 2 | `incompatible types: cannot assign AnsiString to Integer` |
| 2 | `no operator overload found for record operands (…) — PXXDBG=a.opovl prints the l` |
| 2 | `duplicate conversion operator: this source type already converts to this result ` |
43 further rows are singletons — 57 distinct errors over 132 rows.

### What the labels were hiding: five rows are ONE helper unit

`tobject1`, `tstring2`, `tstring4`, `tstring5` and `texception3` all fail inside
**`erroru.pp`**, a suite helper they all `uses`, on exactly three System symbols
we do not have: **`erroraddr`, `TFPCHeapStatus`, `GetFPCHeapStatus`**. Their
skip reasons say "object", "strings" and "exception" — three different clusters,
none of them the cause, and nothing in the reason text could ever have shown
that they are one unit. `TFPCHeapStatus` is also the wall four FPC units hit in
`goal-compile-fpc-compiler`, so **that symbol pays twice**; frankB has taken it
(`feature-b-getfpcheapstatus-needs-always-on-heap-accounting` covers the heap
half, and `erroraddr` is new work).

### The 25 uncategorised: measured, and they really are singletons

`ready`-style triage kept deferring these as "read them individually". They were
run instead: **24 rows produce 17 distinct first errors**, the largest sharing
four (`%FAIL` accepted-invalid rows). There is no cluster hiding in them — the
absence of a label was accurate. That is a finding, not a null: it means the
remaining cheap wins are NOT here, and the burn-down should take the three
measured walls above instead.

### Two caveats on the exit-clean five

`tarray2 tclass12a tforin24 tgenfunc3 tstring1` now exit 0. The runner already
says loudly that **exit-clean is not correct** — it compares exit codes, not
output — and three of these five are known to print wrong values. `tgenfunc3`
and `tstring1` are the two not yet explained and are the only burn candidates;
neither was diffed against fpc here, so neither was burned.

**Numbers carry their tree:** everything above is at `36d7e5fd4` with compiler
`e6af001d6c0e3bf2`, taken after frankB's `{$PACKENUM}`, `{$H-}` and named-set
work landed. A row measured before those is measuring a different compiler.

## 2026-09-06 (frankD, Track P) — THE `erroru` WALL IS DOWN, and this row's two blockers are stale as blockers

Measured at `855356445cd7`, ordinary build. frank-coordinator flagged that the two
`blocked-by:` rows looked implemented-and-unresolved from a declaration grep and
declined to close on that; this is the behavioural half.

All three symbols the previous section named as the single cause behind five
differently-labelled skip rows now resolve from user code:

```
ErrorAddr := nil                                   compiles, runs
GetFPCHeapStatus                                   compiles, counters LIVE
  s1 := GetFPCHeapStatus; GetMem(p,1MB); s2 := ...
  pxx  CurrHeapUsed 0 -> 1048576   |  fpc  0 -> 1048608
program eu; uses erroru; begin ... end.            compiles, runs
```

**The always-on heap accounting that the blocking ticket called "the whole
ticket" exists.** It was built by someone and never written back to the ticket —
so this row has read as gated on unbuilt work for an unknown period.

**A single `GetFPCHeapStatus` call cannot establish that** and nearly cost this
measurement: one call answers 0, and 0 is equally "nothing allocated yet" and
"not implemented". Only the delta around a known allocation separates them.

### The five rows, re-run

| row | result |
| --- | --- |
| `tstring2` | compiles, runs, exit 0 |
| `tstring4` | compiles, runs, exit 0 |
| `tstring5` | compiles, runs, exit 0 |
| `texception3` | compiles, runs, **exit 1** — a runtime failure, not a frontend gap |
| `tobject1` | **REFUSED**, and not on `erroru`: `an object type cannot have a constructor` → `bug-p-object-value-types-standard-meaning` |

Two different shapes behind one old label, and only one of them is a frontend
gap. Neither is burned here — `texception3` needs its output diffed against fpc
before anyone calls it anything.

### One disposition question for whoever owns this row

`tstring4` prints `[HEAP] Size: 262144 Kb, Used: 128 bytes` where fpc 3.2.2
prints `0 bytes / 0 bytes` on the same line. **pxx is reporting real accounting
where fpc reports none.** Under CLAUDE.md's own rule — the test is the value in
its declared type, and a truthful instrument returning an unexpected answer is
not a defect — pxx is arguably the better of the two, and this is
`known-incompat`-shaped rather than `rejected/`. It is a feature landing and
turning a comparison row into a divergence. Not ruled on here.

### Corpus availability, which was the reason nobody re-ran this

This checkout had **zero** corpus files until tonight; the fetch took under a
minute for 1447. Across the box it was **13 of 17 checkouts with no corpus, now
12** — and a missing corpus does not fail, it **passes by absence**: the
conformance target's presence check succeeds on the parent directory while the
suite is missing. That is filed as
`bug-t-the-conformance-runner-reports-an-empty-corpus-as-a-normal-green`.

**Not claimed.** The body above records `Owner: frankA` and the four most recent
sections are frankA's; frontmatter `owner:` deliberately left unset rather than
assigned by a passing seat.


## 2026-09-06 (frankS) — new census, and the RUNNER MOVED under it

**`377 pass, 0 fail, 123 skip, 50 auto-gated (of 550)`** at `e929e720f`,
compiler `d1d15deee084`.

**Read the pass count against a changed instrument, not against 368.**
`109fbebb1` added a **unit-source auto-gate**: pxx cannot compile a unit
standalone, so it answers "this file is a unit, not a program" for every one —
a REFUSAL, which under the `%FAIL` contract meant **every unit-source `%FAIL`
row passed vacuously, whatever it contained**. Those rows are now auto-gated
instead of counted. **17 rows are gated as `unit-source` in this census**, and
some fraction of them were previously in the 368.

So the two numbers are not directly comparable in either direction, and I am
NOT claiming a decomposition I did not measure — running the old runner at the
old commit is what that would take. What is safe to say:

- **it went UP, not down.** frank-coordinator flagged the opposite risk (a
  smaller number after a runner change reads as a regression); the generic-method
  work landed more rows than the gate removed.
- **`0 fail` across all 550.** `tgeneric4` and `tgenfunc13` were the last two and
  both are dispositioned with measured values.

If you re-run this and want a clean delta, the runner change is `109fbebb1` and
`--report` writes a per-row TSV; diffing two reports separates "newly gated"
from "newly passing" without re-deriving anything.

### Re-run at `b19b2f3b9` — identical, per row

`377 pass, 0 fail, 123 skip, 50 auto-gated (of 550)`, compiler `5e31fa11a35f`.

Re-run because two Track P changes landed downstream of the `e929e720f`
census — `refactor-p-one-lvalue-path-for-statements-and-expressions` and
`61932d0ec` (an implicit deref over an explicit caret on a pointer-to-pointer).
A refactor of the lvalue path is exactly the kind of change 550 corpus rows are
worth spending eight minutes on.

**Diffed per row, not by total.** Equal totals can hide offsetting moves, which
is the reason to keep the `--report` TSV at all:

```
diff <(awk -F'\t' '!/^#/{print $2"\t"$1}' census-e929e720f.tsv | sort) \
     <(awk -F'\t' '!/^#/{print $2"\t"$1}' census-b19b2f3b9.tsv | sort)
-> no differences
```

**Not one of the 550 rows changed status.** That is a clean corpus-wide
statement about those two changes, and it is the delta-by-diff this ticket's
previous entry said the TSV would make possible — first use of it.

## Parked 2026-09-06

Nobody holds it: the body says in as many words 'Not claimed -- frontmatter owner: deliberately left unset rather than assigned by a passing seat.' That was the right instinct and it produced the wrong board state, because working/ + empty owner is out of ready AND attributed to nobody, so a p65 row four sessions contributed to tonight was invisible to the campaign count. Parked so it ranks again; RESUME by re-claiming. Live and current: census 377 pass / 0 fail / 123 skip / 50 auto-gated of 550 at b19b2f3b9, identical PER ROW across the lvalue refactor; both blocked-by edges measured stale (the B features are implemented, their own criterion is the unfetched FPC compiler-source corpus).

**Before resuming:** read the reason above, then the ticket body. If the reason does not tell you what would make this worth picking up again, establishing that is the first step -- a park is a handoff to a stranger who may be you.

## 2026-09-06 (frankS) — 380 / 0 / 120 / 50, and three rows burned off the skip list

**Verdict census at compiler `faa41e4b920f`: 380 pass, 0 fail, 120 skip, 50
auto-gated of 550.** Previous: 377 / 0 / 123 / 50. The delta is exactly the three
rows removed below and nothing else — **predicted before the run and confirmed**,
which is what says no row moved for a reason nobody looked at.

### The method, because the headline number is the least interesting part

`--retry-skips` re-attempts every skip-listed row. 8 of 123 passed. **Three of
those eight were vacuous and the runner's own summary names them** — `tarray2`,
`tclass12a`, `tforin24` run to completion printing WRONG VALUES, and all three
already said so in their own skip reasons. So a pass under `--retry-skips` is a
CANDIDATE, and the only thing that settles it is a diff against fpc 3.2.2.

Diffed all eight, output and exit code:

| row | verdict |
| --- | --- |
| `tclass9` `tgeneric6` `tstring1` | **match fpc byte for byte** — un-skipped |
| `tforin12` | exits 0, prints `a`/`s`/`d` where fpc prints `asd` — **stays** |
| `tarray2` `tclass12a` `tforin24` | differ, as their reasons already said — **stay** |
| `tstring4` | differs; `wontfix:` stands, its REASON did not — see below |

`tforin12`'s reason now records that it compiles and runs, so the next reader
does not mistake the retry pass for progress.

### A false reason on a skip row, and the bug hiding behind it

`tstring4`'s reason claimed it *"diverges only on GetFPCHeapStatus numbers"*.
It does not. It also diverges on the ansistring `Len` header words — which IS
what its `wontfix:` is about, so that half is fine — **and on `Str` of
Comp/Extended/Single, which neither clause covers.** Extended and Single are the
decided `Extended = Double` architecture. Comp is a real defect:

```
D := 4.7;  Co := D    { pxx 4616977747989548237   fpc 5 }
```

The IEEE-754 bits of 4.7, moved rather than converted. Filed as
[[bug-a-a-float-assigned-to-an-integer-lvalue-moves-the-bits-instead-of-converting]] —
one direction only (int-to-float is correct and was measured), and two faces
needing opposite answers because `comp` maps to `tyInt64` and the compiler cannot
tell `Comp := <real>` (fpc ACCEPTS) from `Int64 := <real>` (fpc REFUSES).

**A wontfix row is not inert.** This one was hiding a Track A defect behind a
reason that was wrong in a direction nobody would re-check, because the verdict
it justified was correct.

### Instrument note for whoever runs this next

**`--all` is a DIFFERENT POPULATION from the census and its headline is not
comparable.** `--all` lists every `*.pp` in the suite (~1362 rows here: 598 pass,
494 fail, 270 auto); the census population is the `$CATEGORIES` subset, which is
the "of 550" every figure in this ticket quotes. Running `--all` and comparing to
550 reads as a collapse that did not happen. The verdict run is the one with
neither `--all` nor `--retry-skips`, and the runner says so itself in its
summary.

## 2026-09-06 (frankS) — 391 / 0 / 109, and the tmoperator cluster is triaged

Census **391 pass, 0 fail, 109 skip, 50 auto-gated of 550**, up from 377,
measured with compiler `5dec56ae8b3f` — the binary that run actually used, not
the one at the end of the session. Re-run and confirmed at `88a0b3d93835` after
the two later fixes, which touch nothing the corpus population reaches
differently; the number is quoted with the sha it was produced by either way,
because "it cannot have changed" is a prediction and this file has been wrong
about a census figure before. The intermediate numbers this session passed through were
387/2/111 and 391/0/109; the two FAILs were `tgenfunc3`/`tgenfunc4` and were
**not** this ticket's work — frankD's `7d263221f` fixed them, proven by
stash-and-rebuild before they were routed.

Burned here: `tforin26`, `tforin27` (a user routine named `Write`, `1ead40679`)
and `tgeneric83/84/85` earlier in the session.

**The `tmoperator` cluster is triaged rather than burned, and that is the
result.** Six live rows, measured one by one at `88a0b3d93835`, resolving to
exactly THREE causes and one defect I could fix:

| rows | cause |
| --- | --- |
| 4, 7 | [[feature-pascal-management-operators-nested-and-array]] — the nested-field and array arms |
| 8 | [[feature-pascal-management-operators-copy-and-addref]] |
| 2, 3, 9 | [[feature-a-record-rtti-descriptors-for-initializearray-and-finalizearray]] — filed today |

**Five of the six skip reasons were wrong about what their row stops on**, all
in the same direction: they named the FEATURE the file is about rather than the
LINE the compiler refuses. `tmoperator7`'s said "the management-operator
cluster" and it was stopping at line 29 on a `class var` named unqualified from
inside a `class operator` body — name resolution, no relation, fixed in the same
commit, and the row then advanced 72 lines to a real management-operator wall.
`tmoperator8`'s named Initialize/Finalize, which work. **A skip reason is a
claim about one line, and everything past that line is unverified** — which is
now written into each of the six.

The two existing tickets had **no frontmatter beyond `track` and `prio`**: no
slug, no status, no summary, and no edge to
[[umbrella-managed-memory-is-correct]] (p75) that they plainly belong under.
Wired, and both moved from p30/p35 to effective **p75** — the top two of the
Track P queue. The membership was stated in prose and absent from frontmatter,
which is the one place the ranker cannot look.

## 2026-09-06 (frankS) — tarray2, and what a skip reason costs when it names the file

`tarray2.pp` has been on the skip list as *"array of const / TVarRec (vtype
fields, `VExtended^`, `VPointer`)"*. It **compiles and exits 0**, so the runner
— which compares EXIT CODES — has always called it clean; the row is on the list
because its OUTPUT diverged. Diffed against fpc 3.2.2 line by line, the
divergence was five rows, and the reason named **none** of the four that were
defects:

| row | fpc | pxx (before) | what it was |
| --- | --- | --- | --- |
| `type PChar` | `Eerste Pchar` | `4357640` | `TVarRec.VPChar` was a bare `Pointer`, so `writeln` printed the address |
| `type Object` | `TObject` | *(empty)* | `VObject` was a bare `Pointer`; a `Pointer` has no `.ClassName` |
| `type Class` | `vtClass` | `vtPointer` | a class REFERENCE is `tyPointer`, so `AN_VARREC_ARRAY`'s tag arm gave it 5 |
| `QWord(1234)` | `QWord` | `Int64` | `tyUInt64` shared the `vtInt64` arm — read back through a `PInt64` |
| `type Pointer` | `4198656` | `4351789` | an ADDRESS. Not a defect and never will be. |
| `1.234` ×2 | 20 digits, `E+0000` | 17 digits, `E+000` | this RTL models `Extended` as `Double` — CLAUDE.md records that as the architecture |

Four fixed, two remaining and neither is ours to fix, so the row is now
`wontfix:` rather than `gap:` — it can never match by design, and leaving it
tagged `gap:` kept it in a burn-down population it does not belong to.

**The tag arm and the field types are ONE claim, not two.** `VClass: TClass`
without the `vtClass` arm is a field nothing ever tags; the `vtClass` arm
without `VClass: TClass` is a tag whose reader has no members. They landed
together for that reason.

**`vtQWord` needed a third edit nobody would predict from the first two.** The
boxing decision is `if (vrTag = 16) or (vrTag = 3)` — an ENUMERATION of tags,
not a property of the value — so tagging 17 without adding it there put the
QWord's *value* in a slot the reader dereferenced as a pointer. It segfaulted,
which is the lucky outcome: the same omission on a value that happens to look
like an address reads memory instead. A tag introduced next to an existing one
inherits none of its handling.

**And the QWord test row carries a value above `High(Int64)` on purpose.**
tarray2's own probe is `QWord(1234)`, which reads back as 1234 through a
`PInt64` just as happily as through a `PQWord` — **the file that reports the
bug cannot detect the fix.** `High(QWord) - 1` prints `18446744073709551614`
correctly and `-2` incorrectly, which is the discriminator the suite lacked.

The general shape, and it is the second time today in this ticket: **a skip
reason describes the FILE and gets read as describing the WALL.** Five of six
tmoperator rows were wrong the same way this morning. Any reason that names a
FEATURE rather than a LINE has not been measured since it was written.
