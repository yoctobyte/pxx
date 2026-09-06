---
prio: 65
blocked-by: [feature-b-getfpcheapstatus-needs-always-on-heap-accounting, feature-b-erroraddr-is-missing-from-system]
track: P
status: working
summary: "Rung 1 of the Pascal corpus ladder: FPC 3.2.2's own `tests/test` suite (1447 `.pp`, fetched by `tools/install_lib_candidates.sh fpc-testsuite`, gitignored) run as a conformance corpus, burning the skip list one narrowed frontend bug at a time. Last full census 368 pass at `36d7e5fd4` / compiler `e6af001d6c0e`. THE TWO `blocked-by:` EDGES ARE STALE AS BLOCKERS: `erroraddr`, `TFPCHeapStatus` and `GetFPCHeapStatus` all resolve from user code at `855356445cd7` and the heap counters are genuinely always-on (measured by delta, not by declaration), so `erroru.pp` — the suite helper whose absence gated `tobject1 tstring2 tstring4 tstring5 texception3` as three unrelated-looking clusters — now compiles. Four of those five compile; `tobject1` has a different wall behind it (`bug-p-object-value-types-standard-meaning`). The B rows stay open on their own criterion, which is a march over the separate FPC compiler-source corpus, so this row is gated by paperwork rather than by capability. Known trap on any burn: exit-clean is not correct — the runner compares exit codes, not output."
---

# Pascal corpus rung 1 — FPC test-suite subset (conformance)

- **Type:** feature (frontend conformance corpus)
- **Track:** P (Pascal frontend)
- **Status:** working
  [[feature-pascal-corpus-expansion]].
- **Owner:** frankA

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

## Parked 2026-07-10
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
