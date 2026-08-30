---
prio: 75
track: P
status: unfinished
owner:
---

# Pascal real-world corpus expansion — the ladder Track P never had

- **Type:** feature — umbrella (frontend stress corpus)
- **Track:** P (Pascal frontend; shares `lexer.inc`/`parser.inc` with A, so bugs
  found land as Track P — A-gated — or Track A core)
- **Status:** unfinished — **parked 2026-08-30 (frankB) with the wall measured.**
  The object blocker IS discharged: `decide-revisit-object-types-rtl-generics-fired-the-trigger`
  is in `decided/` as **option C** (`object` = a value type with a hard error on
  inheritance; **option B, "`object` becomes `TObject`", was explicitly
  REJECTED**), and it is already built — `done/bug-p-object-value-types-standard-meaning`,
  `pasparser_decl.inc:5745`. Verified by compiling, not by reading.
  **Rung 6 is nevertheless still RED**, on a wall that is none of walls 1-7 and
  unrelated to `object`: four unbound identifiers in the dictionary includes.
  Full measurement, provenance, and seven ruled-out shapes in the re-compile
  note inside THE ONE CANONICAL TABLE below. **Re-measure after
  `regression-p-generic-constraint-check-rejects-a-class-declared-in-the-same-type-section`
  lands — independence is unproven.**
- **Owner:** frankB

---

## 2026-08-29 (frankP) — the "two ordering defects, one restructuring" note is STALE

The park note below lists **wall 6's Delphi ordering defect as open**, and the
rung-9 note near the bottom of this file tells whoever takes
[[bug-p-a-delphi-mode-generic-from-a-used-unit-cannot-be-specialized]] to *"read
wall 6's ticket alongside this one and ask whether a single restructuring closes
both."* Both are out of date, and the second is the expensive one — it sends the
next holder looking for a shared fix that does not exist.

**Wall 6 is closed** ([[bug-p-a-generic-class-method-call-is-undefined-inside-another-generics-body]],
now in `done/`, commit `35f485537`, 2026-08-28). It was closed by giving the
prerequisite scan a THIRD source — this template's not-yet-buffered method impls
read straight out of `Tokens[]`, bounded by the `GenMethImplSOff` header offsets
the rewrite recorded — **not** by changing when or where
`DelphiRewriteGenericUses` emits. So the two defects shared a symptom
("something ran before the thing it needed existed") and nothing else. The
rung-9 arm was fixed on its own, from its own end.

The durable fact the two DO share is worth keeping, because it is about the
mechanism rather than either bug: **`Tokens[]` is one array shared by every unit,
the main program is lexed first, and units are appended after it.** Everything
that reads a token INDEX across a unit boundary has to survive that.

## PARKED 2026-08-28 (frankA) — what the next holder needs

Moved out of `working/` because `working/` is a **live lock**, and a lock held by
a parked session reads as "someone is on it" while nothing is happening.
Everything is pushed; HEAD at park was `bc0100404`. Nothing is reverted or
half-applied.

**Two open items, both Track P, both unclaimed:**

1. **Wall 6, Delphi half — an ORDERING defect**, in
   [[bug-p-a-generic-class-method-call-is-undefined-inside-another-generics-body]]
   (`unfinished/`). `GenericMethodCount=0` when the Delphi specialization runs.
   The enabling fact is banked there: `LexAll` fills `Tokens[]` before the parser
   starts, so the method bodies are **unindexed, not unavailable** — a bounding
   job, not a reordering one. **Read the "do not weaken the prerequisite scan"
   note before touching it**; the obvious sweep over-approximates on `T`/`U` and
   would produce a silently wrong specialization instead of an absent one.
2. **[[bug-p-two-different-nested-specializations-of-one-template-collide]]**
   (p65, new). Newly reachable, not a regression. Its "where to start" is
   explicitly a hypothesis from the error's shape, **not** a measurement.

Wall 7 is a third, independent, and smaller: [[bug-p-a-resourcestring-is-not-addressable]]
(p55) — it moves the corpus without touching either of the above.

**A correction worth keeping, because it was wrong in a way that looked right:**
wall 7 was first recorded here as Track B, "the constant exists at
`lib/rtl/rtlconsts.pas:13`, so it is a visibility/export gap". The constant does
exist and it *is* exported — and neither fact is the defect. The corpus writes
`CreateRes(@SArgumentOutOfRange)`, which takes an **address**, and a plain
`const` has none. Worse, our copy is not even the symbol in play: the corpus
declares its own under a `resourcestring` section in `generics.strings.pas:25-26`
(`resourcestring` at :25, `SArgumentOutOfRange` at :26 — I cited `:24` here and
to the coordinator, off by one, in the middle of an exchange about how a
`file:line` is exactly what makes a wrong answer persuasive). Conclusive:
`generics.defaults.pas:42` does not use `RtlConsts` at all, so our copy is not
merely the wrong candidate, it is out of scope in the unit where the failures
were measured.
*"The symbol is there"* and *"its address can be taken"* both fail with the
symbol present, and only the second one is the bug.

## 2026-08-28 (frankA, park) — the third ordering defect is DIAGNOSED, not fixed

Parked deliberately with **no code changed**, per the stopping boundary agreed
with the coordinator. `generics.defaults.pas` stands at `:3250`.

The ticket's own direction — "emit the prerequisite at the end of the type
section" — was **refuted by measurement before being acted on**: in the failing
order the scan finds nothing at all (`nested=0`), so there is no emission to
move. Discovery is not merely mis-placed, it is impossible at that time: the
referenced template is not yet declared, so its use has not been rewritten, and
marking it would require knowing it is a template.

The replacement direction (discover at *materialisation* time, where all
templates are known) is sound but not small: `NestedSpecKnown` consults
REGISTERED specializations, not inserted tokens, so emitting a declaration
around the stream cannot work in either order — the method's streaming has to be
deferred and retried once the declaration is parsed, without breaking
`BufferGenericMethod`'s "materialised exactly once" invariant. Both dead
variants are written into the ticket so they are not re-attempted.

**Three ordering defects fell today and the remaining count is unknown, not
small.** Each was invisible until its predecessor fell. Whoever picks this up
should decide whether rung 6 deserves a fourth on its own merits — the test the
coordinator set is the right one: *stop when a defect is only worth fixing
because it advances the corpus.* None of today's three was that; all three are
plain-Pascal bugs with short repros that FPC compiles, and they would bite anyone
writing that code with no corpus in sight.

## 2026-08-28 (frankA, later still) — the false cycle is gone; rung 6's wall is a THIRD ordering defect

`bug-p-mutually-referencing-generics-are-rejected-as-circular` resolved. A
prerequisite found in a METHOD BODY is materialisation-time and is now emitted
without deferring; only class-body (declaration-time) edges defer. The
distinction needed no new state — the scans already run class body first, so the
boundary is one index — which is also what kept it inside Track P, since the
`NSpec*` arrays live in `defs.inc` and a per-edge flag would have crossed into A.

`generics.defaults.pas` **`:994` → `:3250`** (2256 lines).

The new stop is the same ordering family a third time, and it is filed:
[[bug-p-a-generic-prerequisite-is-emitted-before-the-referenced-template-exists]]
(p60). The rewrite emits a template's alias right behind *that template's own*
declaration, so a prerequisite naming a template declared LATER in the same type
section lands before it exists:

| | line |
| --- | --- |
| `TGStringComparer<T, THashFactory>` declared | ~985 |
| `TGOrdinalStringComparer<T, THashFactory>` declared | **1002** |
| `TGStringComparer.Ordinal`'s body names it | 3250 |

**Rung 6 has now yielded three ordering defects in a row** (wall 6, the false
cycle, this), each revealed only by fixing the one in front of it. That is worth
saying plainly to whoever sizes the rung next: the wall count is not a work
estimate, and each of these was invisible until its predecessor fell.

`generics.collections.pas` still dies at the same `defaults` line without
reaching one of its own.

## 2026-08-28 (frankA, later) — wall 6 is DOWN; rung 6's wall is now ONE defect, in both units

`bug-p-a-generic-class-method-call-is-undefined-inside-another-generics-body` is
resolved — the mode-Delphi ordering defect. The prerequisite scan now also reads
this template's not-yet-buffered method impls, bounded by the header offsets the
rewrite recorded (`GenMethImplSOff`), never by argument shape. The banked warning
held: the tempting raw-token sweep over-approximates on `T`/`U` and would have
registered a silently wrong specialization.

| | `generics.defaults.pas` stops at |
| --- | --- |
| before | `:3231` — `undefined variable (specialize)` |
| after | `:994` — `circular generic specialization` |

**Earlier in the file, and better.** The old error meant a prerequisite was never
discovered; the new one means it *is* discovered and our machinery cannot order
it. The circularity is **pre-existing** — the same objfpc repro gives the
identical error on this tree with the fix stashed — and is filed as
[[bug-p-mutually-referencing-generics-are-rejected-as-circular]] (p60).

`generics.collections.pas` dies at the same `defaults:994`, still without
reaching a line of its own. So rung 6 is now behind **one** defect in both units,
and it is a real one: `TDel<T> = class(TEq<T>)` is a declaration-time dependency
while `TEq<T>`'s method body constructing a `TDel<T>` is materialisation-time,
and we treat both as blocking. FPC compiles it and prints 7.

## 2026-08-28 (frankA) — wall 7 is DOWN; rung 6 is behind wall 6 alone, measured

`bug-p-a-resourcestring-is-not-addressable` is resolved: a `resourcestring`
section now declares initialised string storage, so `@SArgumentOutOfRange`
compiles. Attribution is clean — `pinned` is the WRONG baseline here (it predates
other landed-but-unpinned fixes and dies at `:2205` on an unrelated wall), so the
before-measurement was taken by rebuilding this same tree with the change
stashed:

| | `generics.defaults.pas` stops at |
| --- | --- |
| before (same tree, change stashed) | `:2960` — `undefined variable (SArgumentOutOfRange)`, the first of the 7 `CreateRes` sites |
| after | `:3231` — `undefined variable (specialize)`, the Delphi-mode ordering defect |

~271 lines, past all seven sites. **The new stop is wall 6**, already diagnosed
and parked in
`unfinished/bug-p-a-generic-class-method-call-is-undefined-inside-another-generics-body`
— not a new wall, and its ticket already carries the warning not to weaken the
prerequisite scan to make the corpus advance.

`generics.collections.pas` still holds **18** of the 25 `CreateRes(@…)` sites.
Probed directly after this fix (2026-08-28): it still cannot be assessed, and now
for a precisely known reason — it `uses Generics.Defaults`, so it dies at
`generics.defaults.pas:3231`, **wall 6**, without reaching a line of its own.

So this fix's value in collections is real but **unrealisable until wall 6
falls**, and those 18 sites are not evidence collections is close — nothing about
that unit has been measured. Wall 6 now gates both units, which raises what
finishing it is worth without changing anything about how it should be done: its
ticket's warning stands, and *do not weaken the prerequisite scan to make the
corpus advance*.

## LIVE STATUS — rung 6 (`rtl-generics`). THE ONE CANONICAL TABLE.

**Every other wall table in this file is a dated snapshot of what was true when it
was written, and they disagree with each other by design.** Three of them
accumulated because each session appended its measurement rather than editing the
last — right for the record, wrong for anyone asking "where is this now", who
then reads whichever table they scroll to first. Wall 4 sat `filed` in one table
and `(to file / relay to frankB)` in another while it was actually **done**.
**Update THIS table. Leave the snapshots alone.**

Last measured 2026-08-28 against binary `c3cd377d5`, on the **pristine**
corpus (no stubs). **Wall states re-checked against HEAD 2026-08-30 by frankD**
(folder plus resolution commit, not folder alone); the compile itself was not
re-run, so the *line numbers* below are still the 08-28 measurement.

> **RE-COMPILED 2026-08-30 (frankB) — the first actual compile since 08-28, and
> the table's condition is met while the rung is still RED.** Binary: HEAD
> `4f42b78b9`, self-host fixedpoint `faf762981c3c`, byte-identical to pin
> **v397** (`0d9341089`) — provenance checked, not assumed. Result:
>
> | rung | probe | result |
> | --- | --- | --- |
> | 6a | `uses Generics.Defaults` | **ok** — 671512B code, 1661 procs, 25s |
> | 6a | *control:* same + `TComparer<Integer>.Default` actually instantiated | **ok** — 1672 procs, 31s |
> | 6b | `uses Generics.Collections` | **ERROR** — `unknown type: TKey` +13 more |
>
> The 6a control is the load-bearing half. "Compiles standalone" and "is
> correct" are different claims if an uninstantiated generic body is never
> type-checked, and the **+11 procs** (1661 → 1672) is what proves the
> instantiation generated code rather than being skipped. Without it the green
> is vacuous. **6a is genuinely clean.**
>
> **6b's wall is none of walls 1-7, has nothing to do with the object decision,
> and is ALREADY FILED** —
> [[bug-p-the-rtl-generics-corpus-stops-on-tkey-in-a-tlist-body]] [P p55,
> frank-rust]. My first two errors are byte-identical to that ticket's,
> `near:` context included. **Do not open a new ticket for this wall.**
>
> **Corrected 2026-08-30, same day:** I first attached this to
> [[bug-p-generic-type-param-unresolved-in-class-abstract-template]] [P p70] on
> the strength of a `:120`/`:123` line-number overlap — while simultaneously
> arguing those coordinates are garbage. The symbol is the discriminator and it
> is decisive: p70's headline is `unknown type: PT`, and **`PT` appears zero
> times in my run** (mine: `TKey` 6, `TValue` 4, `TDictionaryPair` 3,
> `PDictionaryPair` 1). Retraction recorded on p70. **Match a wall by `near:`
> context and by SYMBOL, never by line number** — the line is paired with the
> wrong file by [[bug-p-a-specialized-body-reports-errors-in-the-wrong-file]],
> so it identifies nothing. Four identifiers come back unbound — `TKey`, `TValue`,
> `TDictionaryPair`, `PDictionaryPair` — all of them `TCustomDictionary`'s
> parameters and nested types. `TDictionaryPair` is declared **only** in
> `inc/generics.dictionariesh.inc`, so the parser IS reaching the include; the
> failure is that the parameters do not bind inside it.
>
> **The object arm IS discharged — measured, not inferred.** `= object`
> compiles as a VMT-less value type (`SizeOf` 8), a **generic** `= object`
> works too (`SizeOf` 4), and `TB = object(TA)` gives the decision's hard error.
> The compile advances well past the corpus's single `= object`
> (`collections.pas:146`) to the dictionary declarations.
>
> **Seven shapes were ruled out by construction, each with a control — do not
> re-run these:** cross-unit generics; `{$MACRO ON}` value macros; a macro used
> across an `{$I}` boundary; a 3-param macro with nested `TDictionaryPair`/
> `PDictionaryPair` referenced in bodies; the macro as the **declaration's**
> parameter list (the corpus's exact shape); backslash include paths
> (`{$I inc\file.inc}` resolves on Linux — verified non-vacuously by
> referencing the included type); and a constrained generic `TObjectList<T:
> class> = class(TList<T>)` specialized from another unit with a class declared
> after it. All seven compile and run. The trigger needs the real file's
> combination, not any one of these.
>
> **Do NOT assume this is independent of the constraint regression.**
> `f4fb9d31b` (constraint recording/checking) IS live in this binary, and
> `regression-p-generic-constraint-check-rejects-a-class-declared-in-the-same-type-section`
> is open. The corpus does use constrained generics (`collections.pas:423`,
> `defaults.pas:525`), and 423 precedes the includes at 470/2333. My errors are
> unbound-identifier errors rather than constraint violations, which is *weak*
> evidence for independence and not proof. **Re-measure 6b against a post-fix
> binary before concluding anything about `TKey`.**
>
> **RETRACTED 2026-08-30, same day (frankB): the corpus diagnostic was CORRECT
> and my "wrong file" evidence was backwards.** frank-rust's source-map
> instrument (`PXXDBG=a.srcmap:*`) shows the error token sits inside a body
> spliced *from* `generics.defaults.pas`, and the file and line were right all
> along. Confirmed independently here: `generics.defaults.pas:78` is
> `function Equals(constref ALeft, ARight: T): Boolean;` inside
> `IEqualityComparer<T>`, and `inc/generics.dictionariesh.inc:56` specializes it
> as `IEqualityComparer<TKey>`. So `unknown type: TKey` reported at that line is
> exactly right — the template's own line, with `T` substituted by `TKey`.
>
> **`TKey` occurring 0 times in that file is what a CORRECT specialization looks
> like from a grep**, because the argument comes from the instantiation site and
> is not in the template's text. I had printed line 78 myself, observed it
> "contains neither `TKey` nor `SizeOf`", and read that as proof of
> mis-attribution when it was proof of correctness. The disconfirming evidence
> was in my hand and I read it backwards.
>
> **What IS wrong in the corpus is `near:`**, which printed stale pre-splice
> spellings that really do occur at `collections.pas:1631`/`:1687` — a real
> place, in a file that really does contain `TKey` 65 times, so everything
> corroborated everything. That is
> [[bug-a-the-near-context-window-is-stale-after-a-token-splice]] [A p45].
>
> **The transferable lesson is the third failure mode:** a symbol grep rides on
> no token index and so survives both broken instruments — and still answered a
> question nobody wanted asked. Coordinate-free bought soundness, not relevance.
>
> The wrong-file defect below is REAL and is fixed (`dc7757a11`) — but on
> frank-rust's own reduction, not on this corpus instance, which was never one:
> [[bug-p-a-deferred-generic-body-s-diagnostic-names-the-wrong-file-and-line]]
> [P p60] — the errors name `generics.defaults.pas:78`, which contains neither
> `TKey` nor `SizeOf`, while the `near:` context is `collections.pas:1309-1310`.
> **CORRECTED 2026-08-30 (frank-rust): `near:` is NOT trustworthy either.**
> I wrote that it was the only reliable field; the `in:` half is now fixed
> (`dc7757a11`), but `near:` is stale after a token splice — `InsertTokens`
> shifts `Tokens[]` and the range tables but not the parallel
> `TokSrcOff[]`/`TokSrcLen[]` that the context window reads, so it prints the
> spelling that lived at those indices BEFORE the splice. A
> specialization-heavy corpus is nothing but splices. Filed as
> [[bug-a-the-near-context-window-is-stale-after-a-token-splice]] [A p45].
> **Identify a wall by SYMBOL NAME — symbol counts do not ride on token
> indices, and no coordinate field currently does.**

| # | wall | owner | status |
| --- | --- | --- | --- |
| 1 | typinfo surface | B | **DONE** — facade `cfa72767f` |
| 2 | generic method header binds to same-named non-generic class | P | **DONE** — `042bcbb32` |
| 3 | nested `specialize X<T>` in expression position | P | open, diagnosis banked, not reached by the probe yet |
| 4 | SysUtils: `EArgumentOutOfRangeException`, `CreateRes`, `Error`/`TRuntimeError` | B | **DONE** — all three declared in `lib/rtl/sysutils.pas` (191, 154/155, 208/268); verified by compiling a `raise EArgumentOutOfRangeException` program, not by grep |
| 5 | method pointers | P | **DONE** — defect A `9ab19fb21`, defect B `6d2a841a1` (parse) + `2c155cce2` (lowering). All 7 shapes match FPC |
| 6 | generic class specialized by the ENCLOSING generic's type parameter | P | **DONE** — objfpc `c3cd377d5`; the Delphi half closed 2026-08-28, `35f485537` |
| 7 | `@SArgumentOutOfRange` — a `resourcestring` is not addressable | **P** | **DONE** — [[bug-p-a-resourcestring-is-not-addressable]] is resolved and in `done/` |

> **Every wall in this table is now DONE (checked 2026-08-30, frankD).** The
> paragraph below is kept because it is the reasoning that made wall 6 the last
> one, and it was correct — but its conclusion has been overtaken: wall 6 fell
> the same day it was written. **Rung 6 is no longer behind any wall in this
> table.** It is behind something else that did not exist when the table was
> made — see "Is the park's condition met?" at the end of this file.

**Rung 6 is now behind wall 6 alone.** Wall 5 fell on 2026-08-28 and the compile
advanced roughly 900 lines, from `generics.defaults.pas:2381` to `:3250`, where
it meets an ALREADY-DIAGNOSED ticket:
[[bug-p-a-generic-class-method-call-is-undefined-inside-another-generics-body]],
parked in `unfinished/` with its repro and diagnosis banked. So the next step is
to un-park that ticket, not to diagnose anything new.

**Wall 3 IS wall 6 — resolved, not merely suspected.** The question was asked of
the two DEFECTS rather than the two row numbers (the snapshot tables below number
them inconsistently, and one snapshot already had them as a single row): wall 6's
ticket concludes its real defect is *"a nested `specialize X<T>` group is not
supported in EXPRESSION position"*, which is verbatim wall 3's subject. One
defect, one ticket, no separate wall-3 ticket needed.

**What is left on wall 6 is an ORDERING defect, not the scan.** `generics.defaults.pas`
is `{$MODE DELPHI}`, and `--debug` shows `GenericMethodCount=0` at the moment the
Delphi specialization runs: the rewrite emits its aliases near the top of the
token stream, so `ParseSpecialization` executes before any method body has been
buffered — even though those methods appear EARLIER in the source. Scanning more
cannot help; there is nothing to scan yet. Full measurement in the ticket.

Three defects fell on the way (`c3cd377d5`): the header test that read what
FOLLOWS a group instead of what precedes it, the prerequisite scan that never
looked in method bodies, and — with nothing to do with generics at all — **a
method could not be named `Default`**, which is the name `TComparer<T>.Default`
needs. Also newly exposed and filed:
[[bug-p-two-different-nested-specializations-of-one-template-collide]].

Under wall 5, the root cause is now
[[bug-p-a-method-call-with-missing-arguments-is-accepted-and-reads-garbage]]
(p80): a method mentioned without its arguments is compiled as a zero-arg call
reading garbage, which is why a cast to a method-pointer type takes the call
reading. Fix that first; defect B may fall out of it.

## Why (the gap)
The C frontend got a driven ladder (c-testsuite → zlib → cjson → lua → sqlite →
tcc, all green). **Pascal never got one.** What exercises the Pascal frontend
today:
- **self-host** — maximal, but only the *thin subset* the compiler writes itself
  in (careful classes, no generics, hand-picked RTL). It proves the subset, not
  the dialect.
- **629 `test/*.pas`** — hand-written feature tests. Valuable, but not a *real
  program's worth* of features interacting.

Track P *owns the full dialect* — classes, generics, properties, exceptions,
mode-Delphi, real RTL semantics, "far past what self-host needs." **Only
real-world Pascal stresses that**, and it's currently scattered across a few
prio-45 tickets + two rainy-day probes. This umbrella gives Pascal a ranked
`next --track P` queue, same as C had.

## The underused asset
PXX is **FPC-seeded and FPC-faithful**, so FPC-compatible code should compile at
high fidelity — and **FPC ships its own test suite: thousands of
`tests/test/*.pp` conformance programs.** That is the c-testsuite analog, but
authoritative and far larger, and today only a rainy-day probe touches it.

## The ladder ("variation is good" — interleave conformance + real apps)
1. **FPC test-suite subset** — conformance corpus, the c-testsuite analog.
   Systematic full-dialect coverage, ready-made. **Do first** —
   [[feature-pascal-corpus-fpc-testsuite]].
2. **Synapse** — real networking lib, already vendored in `external/synapse/`.
   I/O + classes + RTL. [[feature-synapse-compile-check]].
3. **A real self-contained tool** — e.g. **PasDoc** (doc generator: OO, RTL-heavy,
   standalone). The "real app compiles" flex. (candidate — file when reached.)
4. **PascalScript / DWScript** — embeddable script engines, heavy
   RTTI/OO/generics = the hard rung (tcc-equivalent).
   [[feature-embed-pascal-script]] · [[feature-embed-dwscript-rtti]].
5. **Pascal chess engine** — perft oracle already cross-validates the C and Rust
   chess ([[feature-c-corpus-chess]]); a Pascal one = three frontends, one oracle.
   Cheap, high-signal cross-language check. (candidate.)
6. **Lighthouse (stretch):** compile FPC's own compiler `pp.pas` — the
   "tcc self-compiles" analog. [[goal-compile-fpc-compiler]] ·
   [[experiment-compile-fpc-as-stress-probe]] (stay rainy-day until the lower
   rungs are green).

## Method (mirror the C corpus)
Per rung: vendor the source (installer fetcher, pinned commit, gitignored) →
compile with the current pxx → each failure = one narrowed frontend bug ticket
(Track P if `lexer`/`parser`/dialect; Track A if IR/backend/core) → burn the
skip list ticket by ticket → rung green → next rung. Land bugs green; dialect
policy = FPC-faithful default, extensions behind a switch.

## Gate
Frontend/dialect fixes carry Track P's gate = `make test` + self-host
byte-identical (shared `lexer.inc`/`parser.inc`), plus cross where a backend is
touched. Corpus programs run to correct output (compare against FPC where an
oracle helps).

## Links
Mirror of [[feature-c-corpus-expansion]] · dialect policy
[[project_fpc_compat_next_queue]] · [[project_synapse_progress]].

## 2026-08-25 — re-survey: the ladder mostly EXISTS; what it lacked was visibility, one rung, and enrolment

Filed under a re-triage that read this ticket's prio-15 and concluded "Pascal
never got a ladder". That framing is **wrong as of today** and the correction
matters, because it changes what is worth doing next. What is actually wired:

| rung | mechanism | state |
| --- | --- | --- |
| 1. FPC test-suite conformance | `tools/run_pascal_conformance.sh` + `test/pascal-conformance/pxx.skip` (206 entries), 6-way sharded, testmgr `full` tier, twatch dashboard (`conformance.tsv`) | **wired, green** (323 pass / 0 fail at last recorded sweep) |
| 2. **fgl — real FPC generic containers** | `tools/run_fgl_corpus.sh` + `test/fgl/` + `make test-fgl` | **wired 2026-08-25** — 3 pass / 4 known-fail. [[feature-pascal-corpus-fgl]] |
| 3. fpcunit | folded into the fpjson runner | done |
| 4. fpjson (fcl-json's own 203-case suite) | `make test-fpjson` | **both halves of this row are STALE** (frankD, 2026-08-30). The overflow blocker resolved 2026-08-25 in `042e13b5c`, and `test-fpjson` is no longer in no tier — it is in **full**, deliberately full-only (`tools/testmgr.py:236`), with the note there citing this exact rung as why. Recorded RED and unswept is no longer true; **what is true is that nobody has re-measured it since the blocker closed.** |
| 5. Synapse | `make lib-test` (Track B), 3 drivers incl. TLS | **wired, green** — re-measured 2026-08-25 at dev HEAD, all three pass |
| 6. rtl-generics (Generics.Collections) | — | blocked: [[feature-pascal-corpus-generics]] |
| 7. fcl-passrc (60k LOC) | — | endgame: [[feature-pascal-corpus-passrc]] |
| 8. FPC's own `pp.pas` | — | rainy-day lighthouse |

So the ladder was **six rungs deep and largely green**. The three real defects
were:

1. **fgl — the named compat target — was not actually wired.** Its check was
   guarded on `/usr/share/fpcsrc/3.2.2`, a distro source package absent from
   this box, the watcher box and any fresh clone, so it printed
   `SKIP (no fpcsrc)` and passed while asserting nothing. Fixed: the FPC RTL
   sources are now fetched from the same pinned commit the testsuite already
   used (`tools/install_lib_candidates.sh fpc-rtl`), and the rung is a real
   target with a skip list.
2. **Enrolment gaps, and the rot they hide.** `test-fgl` and `test-fpjson` are
   in no testmgr tier. Re-running fpjson by hand for the first time since it
   landed found it **red** — `data ptr fixup overflow`, a fixed 4096-entry table
   in the ELF writer that a real class-dense program has outgrown
   ([[bug-a-the-fpjson-suite-overflows-the-fixed-4096-entry-data-ptr-fixup-table]]).
   The corpus is pinned, so the change is on our side. The rung that was not
   enrolled is the rung that rotted — [[task-t-enrol-the-fgl-corpus-rung]] is
   the fix and should be read as urgent, not tidy-up.
3. **No single place said what the ladder was**, which is how a re-triage
   concluded it did not exist. This table is that place.

### What the fgl rung immediately bought

Three narrow frontend walls, each a double-case where the sibling path already
works, and between them they block four of seven fgl containers:

- [[bug-p-a-string-typecast-is-a-conversion-and-not-a-cast]] — `String(x)`
  resolves to the conversion intrinsic, not a cast, so every *string-keyed*
  container is out.
- [[bug-p-inherited-ignores-the-parents-default-parameter-values]] — the
  standard owning-container constructor idiom.
- [[bug-p-a-cast-as-lvalue-does-not-accept-a-builtin-type-name]].

Plus two found in passing:
[[bug-p-stray-tokens-in-a-unit-declaration-section-are-silently-skipped]] (a
typo'd section header discards declarations with no diagnostic) and
[[bug-p-a-diagnostic-in-a-used-unit-names-the-wrong-source-file]].

That is a good yield for one rung, and it argues for the ladder rather than
against it. **Recommended next rungs, by real-language-surface per unit of
work:** (a) the fpjson `data ptr fixup overflow` — a real program the compiler
cannot build at all, which outranks everything else here; (b) enrol what exists,
so the next one does not rot unseen; (c) burn the three fgl walls — cheap, and
each turns on more than its own driver; (d) then rung 6 (rtl-generics), which is
already scoped and only blocked on one Track B typinfo gap.

### Two facts about unit resolution, measured, worth not re-deriving

- pxx **ships** `math`, `types`, `typinfo`, `sysutils`, `classes`, `rtlconsts`,
  and a **shipped unit beats an `-Fu` path of the same name**. So the corpus
  cannot exercise FPC's real `sysutils`/`classes` sources by putting them on the
  search path; only units pxx does not ship (`fgl`, `character`, …) actually
  compile from vendored source. Whether that precedence is intended is a
  question for Track U if it ever blocks a rung.
- Of the FPC `rtl/objpas` units pxx does *not* ship, `fgl` compiles;
  `character.pas` is rejected at line 1 (`unexpected character`) and
  `fpwidestring` needs `rtl/inc` on the include path. Neither was pursued —
  low value next to the fgl walls.

## 2026-08-27 (frankA) — re-survey #2: the recommendations were all stale, and rung 6's real wall is three defects deep

The 2026-08-25 entry above corrected a re-triage that said the ladder did not
exist. **Its own "recommended next rungs" list has since gone stale in exactly
the same way** — every one of (a), (b) and (c) is now `done/`:

| 2026-08-25 recommendation | state today |
| --- | --- |
| (a) the fpjson `data ptr fixup overflow` — "outranks everything else here" | **done** — `bug-a-…-4096-entry-data-ptr-fixup-table` is in `done/` |
| (b) enrol what exists | **done** — `test-fgl` is in testmgr's `limited` + `full`, `fpc-rtl` is in twatch's `CORPUS_EXPECTED` |
| (c) burn the three fgl walls | **done** — all three `bug-p-*` are in `done/` |
| (d) then rung 6 (rtl-generics) | still the next rung, and now measured — see below |

That is twice this table has aged into being actively misleading, which is the
recurring defect rather than an accident. **The state belongs where it cannot
rot: in the runner's own output.** Ticket prose is a snapshot; a rung either
passes today or it does not.

### Measured, not inferred — rung 2 is genuinely green

`tools/run_fgl_corpus.sh` against the compiler at this commit: **7 pass / 0 fail
/ 0 skip**, real FPC 3.2.2 `fgl.pp`, `pxx.skip` empty. The corpus tree was absent
on this box and was fetched with `tools/install_lib_candidates.sh fpc-rtl`.

**One caveat found and NOT filed, deliberately.** With the tree absent the runner
prints `SKIP` and **exits 0** — the vacuous pass this ticket already records as
defect #1. The 2026-08-25 fix moved which path it checks, not whether absence is
silent, so a fresh clone still gets a green that asserts nothing. It is not filed
because the enrolment work closed it one level up: twatch's `CORPUS_EXPECTED`
warns when the tree is missing, which is the layer that can tell "absent because
unprovisioned" from "absent because broken". Recorded here so the next reader who
notices the exit 0 does not re-file it.

### Rung 6 (rtl-generics) — most of the predicted walls are already gone

The generics ticket predicts walls at "generic class header syntax, specialize,
nested generic types, interface constraints, TArray<T>", and its own
next-wall inventory names type-keyword method names and untyped `constref`.
Probed individually against this compiler:

| predicted wall | actual |
| --- | --- |
| methods named after type keywords (`class function Integer(...)`) | **works** |
| untyped `constref` params | **works** |
| generic class across UNITS, two specializations | **works**, matches FPC |
| interface constraint `generic THolder<T: IThing>` | **works** |
| class constraint `generic TWrap<T: TBase>` | **works** |
| `generic TArr<T> = array of T` | **works** |
| **nested type inside a generic (`TPair`)** | **three separate defects** |

So the rung's remaining cost is not spread across the feature surface — it is
concentrated in **nested types**, which is precisely what
`TDictionary<K,V>.TPair` is:

1. A nested type's field named after an enclosing type parameter — **fixed this
   session** (`83468c546`), test + FPC oracle.
2. [[bug-p-two-generic-templates-cannot-share-a-nested-type-name]] — the second
   template's `TPair` resolves to the first's.
3. [[bug-p-a-second-specialization-of-a-generic-with-a-nested-type-segfaults]] —
   compiles clean, first specialization runs, second SIGSEGVs.

2 and 3 are pre-existing (both reproduce on the pinned binary) and both look like
one cause: **a nested type's identity is not per-specialization**. They should be
taken together, and taking them is what unblocks rung 6 — more than any of the
walls the ticket currently predicts.

### Method note

Every row above is a compile-and-run against `fpc -Mobjfpc` as oracle, one file
at a time — the rung suites themselves (`make test-fgl`, `test-fpjson`) are
hook-refused per CLAUDE.md and are Track T's to sweep. One file at a time is
enough to survey a rung and is what found all three defects.

### 2026-08-27, later — all three nested-type defects are closed; rung 6's named blocker is gone

The three defects the re-survey above concentrated the rung's cost into are now
fixed, and the second and third turned out to be **one cause, one change**
(`7ee75329e`), as predicted:

| defect | outcome |
| --- | --- |
| nested type's field named after an enclosing type parameter | fixed `83468c546` |
| two templates cannot share a nested type name | fixed `7ee75329e` |
| second specialization of a generic with a nested type segfaults | fixed `7ee75329e` |

The shared cause is worth keeping because it is this repo's documented
double-case shape: `AddClassLikeType` registers a nested type under its
QUALIFIED name once the bare name is taken, and its own comment says the
qualified spelling and a bare one inside the owner's body should "find the same
entry" — but **only the qualified path was ever wired**, because every
`FindNestedType` call site keys on a `.`. The bare reference fell through to the
flat unit table and found whichever was registered first, so a generic's nested
type — re-materialised per instantiation on purpose — was shared by every
instantiation after the first.

What identified it was ordering, not reading: whichever template was specialized
**second** broke, and swapping the order moved the error to the other one.

**Status of rung 6 (rtl-generics) after this:** every wall its ticket names or
predicts is now cleared locally — type-keyword method names, untyped `constref`,
generics across units, interface and class constraints, `TArray<T>`, and nested
types. Its `blocked-by` is still the Track B typinfo/PTypeData gap, and the
actual corpus (`packages/rtl-generics`) is not among the trees
`tools/install_lib_candidates.sh` fetches, so **the next step for that rung is
vendoring it and compiling — not another wall hunt.** Nothing local predicts a
further blocker, which is exactly the point at which the real corpus is the only
thing that will tell the truth.

---

## Rung 6 — `rtl-generics`: the one-shot diagnostic (2026-08-28)

Fetcher entry landed as `4bb5fd66f` (`fetch_rtl_generics`, same pinned
`$FPC_COMMIT` as the other FPC-sourced corpora). **`CORPUS_EXPECTED` in
`twatch.py` is deliberately untouched** — this rung is a one-shot diagnostic,
not a gated job. Gate what can be green; diagnose what cannot.

**Binary:** `2c4e727d4b63`, verified self-host fixedpoint at `4bb5fd66f`. Every
number below came from that binary; both new defects reproduce on **pinned**
too, so none of them is fallout from the nested-type fixes.

### What compiles today

| unit | lines | status |
| --- | --- | --- |
| `generics.strings.pas` | 37 | clean |
| `generics.helpers.pas` | 146 | clean |
| `generics.memoryexpanders.pas` | 227 | clean |
| `generics.hashes.pas` | 1,617 | clean |
| `generics.defaults.pas` | 3,358 | **blocked** |
| `generics.collections.pas` | 4,165 | blocked *only* through `defaults` |

2,027 of 9,550 lines compile clean. All blockage is concentrated in
`generics.defaults.pas`; `collections` was never independently assessed because
it cannot get past its `uses`.

### The answer to the question that motivated this: it is NOT typinfo all the way down

The rung's dependency graph was wrong. Typinfo is the *largest* wall but not
the only one, and **two of the four walls are Track P defects in our own
generics implementation**. Method: stub each wall out in a throwaway copy
(`$SCRATCH/rgsrc`, never the vendored tree) and re-probe, so each subsequent
wall becomes visible. Stubs are labelled `{PROBE: ...}` in that copy and exist
only to see past a wall — nothing here is a claim that the unit compiles.

*(SNAPSHOT 2026-08-28, stubbed copy — superseded. Live table at the top.)*

| # | wall | owner | sites | ticket |
| --- | --- | --- | --- | --- |
| 1 | typinfo: `PTypeData` fields, `PTypeInfo`, `GetTypeData`, `TTypeKind`, `TOrdType`, `TFloatType` | **B** | see list below | `feature-typinfo-facade-unit` (p72) |
| 2 | generic method header binds to same-named non-generic class | **P** | ~700 lines gated | `bug-p-a-generic-methods-out-of-line-header-binds-to-a-same-named-non-generic-class` |
| 3 | `TGeneric<T>.ClassMethod` inside another generic's body | **P** | 13 in `defaults`, ~357-ish shape count in `collections` | `bug-p-a-generic-class-method-call-is-undefined-inside-another-generics-body` |
| 4 | SysUtils gaps: `EArgumentOutOfRangeException`, `Exception.CreateRes`, `System.Error`/`TRuntimeError` | **B** | ~~3 + 3~~ **7 + 7** + 7 (see note) | (to file / relay to frankB) |

> **The two `3`s in row 4 were one wrong measurement reported twice.** Re-measured
> 2026-08-28: `generics.defaults.pas` has **7** `EArgumentOutOfRangeException`
> sites and **7** `CreateRes(@SArgumentOutOfRange)` sites — and they are *the same
> seven lines* (2960, 3049, 3075, 3078, 3182, 3218, 3221), because each line
> spells both. So the two symbols never had independent counts to agree on; one
> figure was recorded under two headings, which is what made it look corroborated.
> A count that stops at 3 where the truth is 7 is the shape of an error-limited
> compile, not of a grep. Corpus-wide the real figure is **28** `CreateRes(@…)`
> sites — 18 in `generics.collections.pas`, 7 here, plus one each of
> `SDuplicatesNotAllowed` / `SDictionaryKeyDoesNotExist` / `SArgumentNilNode` —
> so this blocks **collections** harder than defaults, and collections has not
> been probed past its earlier walls.

After stubbing all four, `generics.defaults.pas` produced **no further distinct
errors** — the walls above are the complete set for that unit, not a prefix of
an unknown-length list.

### The named typinfo list frankB asked for

Not "generics.defaults needs typinfo" but exactly this surface:

- `PTypeData` — 39 references. Fields actually touched: `OrdType` (×3),
  `FloatType` (×3), `elSize` (×3), `MinInt64Value` (×1), `MaxInt64Value` (×1).
  **Five fields, nine sites** — a facade does not need the whole record.
- `PTypeInfo` — 14 references (passed through, rarely dereferenced).
- `TypeInfo(...)` — 6; `GetTypeData(...)` — 6.
- Enums needed whole: `TTypeKind`, `TOrdType` (`otSByte`/`otUByte`/`otSWord`/
  `otUWord`/`otSLong`/`otULong`), `TFloatType`.

`OrdType` and `FloatType` are used *only* as `case` selectors dispatching to a
comparer, and `MinInt64Value`/`MaxInt64Value` only in a single range test — so
the facade's hard requirement is a correct `OrdType`/`FloatType` for ordinal and
real types. That is a much smaller target than 39 references suggests.

### Caveat, stated plainly

Walls 2 and 3 gate the parts of `defaults` that walls 1 and 4 do not, but the
four sets are not proven disjoint: stubbing is not compiling, and code behind a
stub was type-checked against the stub, not against the real thing. The
partition above is sound as a list of *what must be built*; it is not a
prediction that fixing all four makes the unit compile on the first try. Re-run
this diagnostic — it is one `probe.sh` — after the typinfo facade lands.

---

## Rung 6 partition superseded — five walls, not four (2026-08-28, end of session)

The four-wall table above was correct **for that unit at that moment**, and both
halves of that qualifier have since moved. Recording it here rather than editing
the table, so the earlier measurement stays readable as what it was.

**What changed:** `042bcbb32` fixed wall 2, which moved `generics.defaults.pas`
from failing at line 2173 to 2351 and exposed a **fifth** wall the partition did
not predict — `AN_CLASS_VIRTUAL_CALL` failing to lower when a virtual class
method's *address* is taken as a value
([[bug-p-the-address-of-a-virtual-class-method-cannot-be-lowered]]). It is not
typinfo and **not generic-specific**: the repro has no generics in it at all,
which is worth knowing before anyone searches the generics code for it.

That is the concrete instance of the hedge the original partition carried: code
behind a stub is type-checked against the stub, so clearing one wall can reveal
another. **Do not treat the wall list as a work estimate.** Re-run the probe
(`$SCRATCH/rg/probe.sh`, one command) after each wall lands; it is cheap and it
is the only thing that keeps this section honest.

### Current state of the five walls

*(SNAPSHOT — superseded. Live table at the top.)*

| # | wall | owner | status |
| --- | --- | --- | --- |
| 1 | typinfo surface | B | facade landed `cfa72767f`; **type-level API only** — its instance-taking overloads are still unreachable, see below |
| 2 | generic method header binds to same-named non-generic class | P | **fixed**, `042bcbb32` |
| 3 | nested `specialize X<T>` in expression position | P | parked, diagnosis banked, **reclassified** — not a Delphi bug, fails in objfpc on `pinned` |
| 4 | SysUtils: `EArgumentOutOfRangeException`, `CreateRes`, `System.Error` | B | filed |
| 5 | address of a virtual class method | P | filed |

### A second chain now runs alongside this one

The typinfo facade shipped, but `GetPropInfo(AnObject, 'Caption')` — the spelling
every FPC consumer uses — still binds the wrong overload. Two defects were
stacked there: the implicit class-to-typed-pointer conversion (**fixed**,
`8b75fcabd`, which also closed a silent memory-safety hole) and, underneath it,
[[bug-p-a-parameters-pointer-element-type-is-lost-between-registration-and-overload-matching]],
which is what still gates the facade's consumer path.

That chain does **not** block this rung — rung 6 needs the *type-level* API
(`GetTypeData(PTypeInfo)`), not the instance overloads. Stated explicitly
because the two are easy to conflate now that they are open at the same time,
and a `blocked-by:` edge between them would rank correctly for the wrong reason.

### Standing warning for anyone verifying work on this chain

**A repro that passes on the fix and on `pinned` is not a verification.** Two
synthetic overload repros written during this session passed on both and were
never broken; they were a step away from being recorded as proof that the
overload half was fixed. Run the "before". It is the only thing that catches it.

---

## Rung 6 re-probed on the PRISTINE corpus (2026-08-28, later)

Re-ran the diagnostic as this section said to, now that the typinfo facade
(`cfa72767f`) has landed and wall 2 is fixed. **This time with no stubs at all** —
the earlier partition was measured through a stubbed copy, and stubs are what
made it a partition rather than a compile.

**Binary `ea689da902bb`. `generics.defaults.pas` now reaches line 2411.**

*(SNAPSHOT — superseded. Live table at the top.)*

| wall | status now |
| --- | --- |
| 1 — typinfo | **gone**: the facade covers it; no stub needed anywhere |
| 2 — generic method header binding | **gone**: fixed `042bcbb32` |
| 3 — nested `specialize` in expression position | not reached yet |
| 4 — SysUtils gaps | not reached yet |
| 5 — method pointers | **the current blocker**, 28 sites |

So two of the five walls are genuinely down, and rung 6 is now behind **one**
defect rather than a list. That is a materially better position than the
partition described, and it was worth re-measuring rather than assuming.

### Wall 5 turned out to be bigger than filed, and the first boundary was wrong

Filed as "the address of a virtual class method cannot be lowered". Measuring
eight shapes instead of four shows it is **two independent defects**, and
neither is really about `virtual`:

- **a CLASS method cannot become a method pointer at all** — `m := TSvc.CPick;
  m(5)` segfaults with no cast anywhere, while the instance twin works;
- **an inline cast of a method reference fails even for an instance method** —
  going through a variable works, casting in expression position does not.

Full table, repro and direction:
[[bug-p-a-class-method-cast-to-a-method-pointer-inline-segfaults]] (p70). The
`virtual` ticket is its honest-exit sibling — same shape, `IR_UNSUPPORTED`
instead of a bad pointer.

**Worth recording how the first table went wrong**, since this section is where
the method gets described: four shapes looked like a clean boundary
("everything adjacent works, only the inline cast is broken") and the two rows
that separate the defects — `class → var`, and `instance` with an inline cast —
had not been tried. The fix that boundary implied would have left half the bug
in place. Vary the shape until the table has no untested neighbours, not until
it looks tidy.

## Rung 6 progress, 2026-08-28 (frankA) — `:3250` → `:3341`, and the wall list keeps growing

Five defects landed today, four of them walls this unit was standing behind:
resourcestring addressability, wall 6 (a generic class method call inside
another generic's body), mutually-referencing generics rejected as circular, and
— in one fix closing two tickets — a generic specialized before its declaration
(`bug-p-a-generic-specialized-before-its-declaration-is-unresolvable` +
`bug-p-a-generic-prerequisite-is-emitted-before-the-referenced-template-exists`).

`generics.defaults.pas` moved `:2960 → :3231 → :994 → :3250 → :3341` across the
day. Note the `:994` — the third fix moved the failure *backwards*, because a
construct that had been rejected outright started compiling and reached a new
error earlier in the file. **A line number going down is not a regression here**,
and reading it as one would have wasted a session.

The new stop is a *different class* of error — `"LookupEqualityComparer": a
pointer has no members` — not another `specialize`. That is the first time today
the unit has failed on something other than generic prerequisite resolution, so
the next wall is probably not more of the same machinery.

**The rung-6 partition is still superseded, and today is more evidence for the
warning above, not less.** Four walls cleared, and the unit is still not through.
Re-run `$SCRATCH/rg/probe.sh` before estimating anything; do not read the wall
list as a work estimate.

`CORPUS_EXPECTED` untouched throughout, and the prerequisite scan was not
weakened to make the corpus advance — the fix adds a *second* run of the same
scan at a later time; both original scans stay, and `test_generic_cycle_fail`
still correctly refuses.

---

## 2026-08-29 (frankA) — rung 6 CLEARED: `generics.defaults.pas` compiles end to end

**First: the park note at the top of this ticket is STALE and should be read
with this section.** It lists three open items; two were already closed before
this session started:

| park note said | actual state on 2026-08-29 |
| --- | --- |
| wall 6 Delphi half, `bug-p-a-generic-class-method-call-is-undefined-inside-another-generics-body` — open in `unfinished/` | **done** |
| wall 7, `bug-p-a-resourcestring-is-not-addressable` (p55) | **done**, `c9cf8c457` |
| `bug-p-two-different-nested-specializations-of-one-template-collide` (p65) | still open, in `backlog/` |

A park note is a snapshot of the moment it was written and the tickets it names
keep moving without it. **Re-measure before reading it as a plan** — that is what
this session did, and the corpus had advanced past everything the note describes.

### The new wall, found and closed

Re-running the compile put `generics.defaults.pas` at a wall the note does not
mention:

```
error: @TEquals.Class: the address of a routine with no body was taken
```

That is [[bug-p-a-forward-declaration-does-not-bind-a-differently-cased-body]],
filed and **fixed** this session: Pascal is case-insensitive, so
`TEquals.&Class` (declared, `:186`) and `TEquals.&class` (implemented, `:1566`)
are one routine, and `FindProcOverloadRec` compared names exactly — so the body
registered a second proc and the declared one stayed bodiless.

**The `&` escape is a red herring** and was the first hypothesis: it is refuted
by the pair of controls — escaped-with-matching-case works, unescaped-with-
mismatched-case fails. A plain `function Bar; forward;` + `function bar;`
reproduces it with no class and no escape, and says `unresolved forward: Bar`,
which names the defect outright. The minimal repro was worth more than every
hypothesis formed from the corpus error.

### Rung 6 result

| unit | lines | before | after |
| --- | --- | --- | --- |
| `generics.defaults.pas` | 3,358 | blocked in the VMT const block | **compiles end to end** |
| `generics.collections.pas` | — | never independently assessed | reaches a NEW wall |

`generics.collections.pas`'s wall is **`unknown type: TKey`** at
`generics.defaults.pas:790` — a generic type parameter not in scope at the point
the specialization is materialised. Independent of everything above and of the
one remaining park item; it is the next rung's subject.

### Wall table, updated

| # | wall | owner | status |
| --- | --- | --- | --- |
| 6 | generic class specialized by the enclosing generic's type parameter | P | **DONE** |
| 7 | `@SArgumentOutOfRange` — resourcestring not addressable | P | **DONE** `c9cf8c457` |
| 8 | forward decl does not bind a differently-cased body | P | **DONE** (this session) |
| 9 | `unknown type: TKey` — generic type param out of scope in a materialised specialization | P | **open, new** |

Still open and untouched: [[bug-p-two-different-nested-specializations-of-one-template-collide]].

### PARKED again 2026-08-29 (frankA) — rung 6 done, rung 9 open and unclaimed

Out of `working/` because it is a live lock and nothing is happening on it.
Everything is pushed. Nothing is reverted or half-applied; no code is mid-edit.

**State:** `generics.defaults.pas` compiles end to end.
`generics.collections.pas` is the next unit and its wall is
[[bug-p-a-delphi-mode-generic-from-a-used-unit-cannot-be-specialized]]
(rung 9), which carries **two refuted hypotheses with the measurements that
refuted them** — the macros are fine, and it is not the forward-decl case bug.
Its first job is a two-unit reduction, which has not been built.

Also still open: [[bug-p-two-different-nested-specializations-of-one-template-collide]].

**Read the 2026-08-29 section above before the park note at the TOP of this
ticket** — that older note was stale on two of its three items by the time it
was read, which is the failure mode this one will have too. Re-measure the
corpus first; it takes one compile.

### Rung 9 RE-DIAGNOSED 2026-08-29 (frankA) — and the first framing was wrong

The wall behind `generics.defaults.pas` was filed as *"unknown type: TKey — a
generic type parameter is out of scope"*, marked **observed, not diagnosed**.
Good thing: reduced, it is not about type parameters, not about `TKey`, and not
about the macros. It is

> **in `{$MODE DELPHI}`, a generic declared in a USED UNIT cannot be
> specialized at all** — `var o: TOne<Integer>;` answers `unknown type: TOne`.

Same-unit works. The objfpc `specialize TOne<Integer>` spelling works
cross-unit. Only the Delphi angle-bracket surface fails, and a ONE-parameter
generic fails, so arity is irrelevant too. Eleven lines reproduce it.

Cause, measured: `DelphiRewriteGenericUses` sweeps the **shared** `Tokens[]`
starting at `insertAt` — just past the template's own declaration — and the main
program is lexed BEFORE the unit it uses, so the program's use sits below that
index and is never rewritten. Renamed to
[[bug-p-a-delphi-mode-generic-from-a-used-unit-cannot-be-specialized]] and
**banked, not microfixed**: the obvious "start at 0" is wrong on where the minted
alias must live and re-widens the surface of the already-recorded
`bug-a-the-delphi-generic-rewrite-is-not-idempotent`.

**Note for the ladder — and see the 2026-08-29 correction at the top of this
file.** This was recorded as the SECOND ordering defect in that one rewrite,
alongside wall 6's `GenericMethodCount=0`, with the suggestion that one
restructuring might close both. It does not: wall 6 was closed on 2026-08-28 by
extending the prerequisite SCAN, leaving this arm untouched, and this arm was
then closed by moving the SWEEP to the uses clause. The question was worth
asking; the answer is no.

---

## 2026-08-30 (frankA) — re-probed at HEAD `66b068019`. Rung 9 is CLEAR; the wall MOVED

Re-measured rather than read. Six `rtl-generics` src units, each through a
driver program, `-Fu`/`-Fi` at the src root:

| unit | at HEAD |
| --- | --- |
| `generics.defaults` | **OK** |
| `generics.hashes` | **OK** |
| `generics.helpers` | **OK** |
| `generics.memoryexpanders` | **OK** |
| `generics.strings` | **OK** |
| `generics.collections` | `unknown type: TKey` |

**Five of six now compile.** `generics.defaults` compiling standalone is rung 6
holding. Rung 9's blocker
([[bug-p-a-delphi-mode-generic-from-a-used-unit-cannot-be-specialized]]) closed
at `625991d20` and its own repro no longer fails.

### The remaining wall is NOT rung 9's, despite wearing its error text

`unknown type: TKey` is the string rung 9 was originally filed under and then
explicitly re-diagnosed away from. Reading it as "rung 9 is still open" would be
wrong. Two facts separate them:

- The error is raised **while parsing `generics.defaults.pas`**, at
  `IComparer<T>`'s `Compare(constref Left, Right: T)` — a unit that compiles
  perfectly on its own. It only fails when reached *through*
  `generics.collections`, which specializes `IComparer<TKey>` with a name that
  is itself still a type parameter.
- The **pinned** binary produces the identical message, so this is not a
  regression from anything that landed tonight.

### Narrowed by bisection to one include, and four hypotheses died first

Truncating the interface at declaration boundaries: `cut@438` **clean**,
`cut@474` **reproduces**. The only thing in between is

```
{$I inc\generics.dictionariesh.inc}
```

which declares `TPair<TKey, TValue>` and specializes `IEqualityComparer<TKey>`
across the unit boundary.

**Recorded because they cost the time and would otherwise be re-tried:** four
hand-built reductions did **not** reproduce — plain cross-unit
`IComparer<TKey>`; plus `constref`; plus a method implementation taking it;
plus a macro-supplied parameter list (`{$DEFINE MAP_CONSTRAINTS := TKey,
TValue}`); plus a nested `public type`/`private var` section. All five compile
clean. The obvious mechanism ("specializing a cross-unit generic with a
still-generic argument") is therefore **not** sufficient, and anyone starting
from it will burn the same hour.

### Moving those declarations into an `{$I}` include DOES break — differently

Eleven lines, and it separates the two binaries:

```
PINNED : pascal26:6: error: unknown type: TKey
HEAD   : pascal26:1: error: unexpected token
         near: interface uses u_tmpl type specialize >>> TPair TKey
```

`specialize` has been **injected before a generic DECLARATION**, which is the
Delphi rewrite treating `TPair<TKey, TValue> = record` as a *use*. That is the
sweep `625991d20` moved to the uses clause. Both binaries fail, so this is a
**changed failure mode on already-failing code, not a working case broken** —
but the wall was re-walled one layer down, exactly the shape this ladder keeps
producing. Filed as
[[bug-p-the-delphi-generic-rewrite-rewrites-a-shadowing-declaration-as-a-use]].

**Next holder:** the remaining corpus wall is the include, not the
specialization. Start from the bisection above, not from the error text.

### PARKED 2026-08-30 (frankA) — released from `working/`, probe complete

The re-probe above is finished and the ladder's next step is blocked on
[[bug-p-the-delphi-generic-rewrite-rewrites-a-shadowing-declaration-as-a-use]].
Released from `working/` rather than held, because a lock held by a session
that is not working the ticket reads as "someone is on it" while nothing
happens — which is the exact failure measured fleet-wide tonight and filed as
`decide-the-ticket-lock-is-too-heavy-for-a-per-minute-commit-loop`.

Everything is pushed. Nothing is half-applied. **Re-measure before trusting the
table above** — that is the rule this ladder keeps re-teaching, and this
section is now itself a snapshot.

### CORRECTION 2026-08-30 (frankA) — the include was NOT the trigger, and the repro was a DIFFERENT bug

The section above says the corpus wall was narrowed to
`{$I inc\generics.dictionariesh.inc}` and that an 11-line include repro
reproduces it. **Both halves are wrong**, and this correction is the reliable
part of that entry.

**The repro was a different defect.** Its error is `unexpected token`; the
corpus wall's is `unknown type: TKey`. I let "both fail near generics after the
same bisect" stand in for "same bug". The repro's real trigger was a name
reuse I had left in the support unit from an earlier experiment — the include
and the reuse varied together and I named the wrong one. Isolated four ways:
include without the reuse is **clean**; the reuse without any include
**fails**. That defect is real, is fixed, and is
[[bug-p-the-delphi-generic-rewrite-rewrites-a-shadowing-declaration-as-a-use]].

**The corpus wall is untouched by that fix** — re-probed after it landed,
`generics.collections` still stops at `unknown type: TKey` in
`generics.defaults.pas`, same line, same message.

**What survives:** the bisection itself. `cut@438` clean, `cut@474` reproduces,
and the include line sits between them. That is a measurement and it still
stands — but it locates the trigger's *neighbourhood*, not its mechanism, and I
wrote it up as though it were the mechanism.

**For the next holder: the corpus wall is UNREDUCED.** There is no repro for it.
Do not start from the include hypothesis and do not reuse the shadowing repro —
that is a different bug. Start by asking why `generics.defaults` parses cleanly
alone and fails when reached through `generics.collections`, and get a
reduction before believing any mechanism, including this paragraph's framing.

---

## 2026-08-30 (frankA) — the wall is REDUCED, and the reported line was never the defect

**Read this section instead of the "LIVE STATUS" table above.** That table's
wall (`unknown type: TKey` in `generics.defaults.pas`) is **gone**, and the
CORRECTION section above it — which says the wall is unreduced and warns against
the include hypothesis — is now itself stale. Third time this ticket has gone
stale on the same field. See the note at the end about recording the *recipe*
rather than the answer.

### Census, and the attribution is deliberately unlocated

| binary | first error | total |
| --- | --- | --- |
| `pinned` | `defaults:46 unknown type: TKey` | 20 |
| `a60f92ba830a` (HEAD minus the shard0-6-2 whitelist) | `collections:120 unknown type: PT` | 4 |
| `22c67e5ea61e` (HEAD, shard0-6-2 landed) | `collections:120 unknown type: PT` | 4 |
| `3309b9ba6609` (HEAD + the fix below) | `collections:146` (a new wall, see below) | **1** |

Rows two and three are identical, so **the `TKey` wall did not move because of
tonight's whitelist** — consistent with the bound-name harvest being unchanged
at `names=293 cap=512 overflow=0`. It moved for something already in HEAD that I
have not identified. Recorded as unattributed on purpose: a fix landing shortly
before an improvement is the cheapest wrong attribution available, and one extra
A/B run against the pre-fix binary was the whole cost of not making it. **There
is something in HEAD nobody has accounted for.**

### Root cause of the 4-error wall — and it is 24 lines away from where it is reported

`generics.collections.pas:144`:

```pascal
TCustomPointersEnumerator<T, PT> = class abstract(TEnumerator<PT>);
```

A **generic** class, declared **bodyless**, carrying a **modifier**.
`ParseGenericTemplateNamed` detects bodyless forms up front because there is no
`end` for its depth loop to count down to — but its test looked at the token
right after `class` for `(` or `;` and never skipped `abstract` / `sealed`. It
saw `abstract`, concluded the declaration had a body, and let the depth loop
swallow the following declarations until it found somebody else's `end`.

**The damage was reported at line 120**, on `function DoGetCurrent: T` — a line
with nothing wrong with it, in a class that compiles fine alone. That is why
every reduction aimed at line 120's text failed, including the four this ticket
already records and one more I wrote tonight. **The reported line was not the
defect and never had been.**

Confirmed by truncation at real declaration boundaries:

| cut | verdict |
| --- | --- |
| `cut@125` (TEnumerator only) | clean |
| `cut@141` (adds TEnumerable, `PT = ^T`, `TEnumerator<PT>`) | clean |
| `cut@144` (adds the bodyless generic) | **fails** |

Ruled out first, by measurement rather than argument: the Delphi rewrite (`p.dgen`
shows injections on the *uses* at 133/137/139/144/152 and **none** at 120 or
135), and harvest overflow (`names=293 cap=512 overflow=0`).

### Fix, and it is a sibling I should have found last commit

`compiler/pasparser_generic.inc` — skip `abstract`/`sealed` before the bodyless
test. **The identical omission was fixed in `CollectNestedTypeNames` earlier
tonight, in this same file, and I did not grep for the second copy.**
`devdocs/dev/normalise-dont-special-case.md` says in as many words: *if you fix a
bug on one arm of a double case, grep for the sibling before closing the
ticket.* One decision, two hand-rolled copies, one of them fixed.

Needs all three of generic + modifier + bodyless, which is why it survived: the
non-generic path consumes the modifiers itself (`pasparser_decl.inc` ~4449) and
was always right, and a real body ends at its own `end`.

Regression test `test/test_generic_bodiless_class_modifier.pas`, in `test-core`,
asserting `bodiless 7 3 1`. Per-form, one form per program, against
`22c67e5ea61e`:

| form | before | after |
| --- | --- | --- |
| `TAbs<T> = class abstract;` | FAIL | ok |
| `TDerived<T> = class abstract(TBase<T>);` | FAIL | ok |
| `TSealedB<T> = class sealed(TBase<T>);` | FAIL | ok |
| `TFwd<T> = class;` (no modifier — the control) | ok | ok |

The control is what isolates the modifier as the variable. It is **not** in the
test program: FPC rejects `TFwd<T> = class;` as *"Type TFwd$1 is not completely
defined"*, so including it would have cost the oracle — pxx accepting it is the
ordinary accept-more divergence, not a defect. I found that by running FPC on
the finished file, which is the only reason the header does not now carry a
false "FPC agrees" claim.

### The new wall, one error

```
generics.collections.pas:146: generic templates must be class, record,
interface, array or procedure declarations
  near: T PT >>> object strict private
```

`TCustomPointersCollection<T, PT> = object` — a generic **object** type, which
`ParseGenericTemplateNamed` does not accept. Distinct from everything above; not
started.

### For the next holder — and for this ticket's own health

This ticket has now gone stale three times on the same field, each time because
it recorded **what the wall was** rather than **how to re-derive it**. The wall
is a function of the whole compiler and moves faster than the ticket is read.
The re-derivation is four commands:

```sh
R=library_candidates/rtl-generics/packages/rtl-generics/src
printf 'program d;\nuses generics.collections;\nbegin\nend.\n' > /tmp/d.pas
./compiler/pascal26 -Fu$R -Fi$R /tmp/d.pas /tmp/d 2>&1 | grep -c 'error'
# then: truncate at declaration boundaries to find the FIRST bad line,
# because the reported line has twice now not been the defect.
```

**Do not trust any error line in this unit without a truncation bisect.**

### The last error is a DECIDED NON-GOAL, so rung 6 is finished as far as it goes

`generics.collections.pas:146`, `TCustomPointersCollection<T, PT> = object`,
is not a small gap in the generic path. **pxx has no `object` type at all** —
measured, not assumed: a plain non-generic

```pascal
type TObj = object F: Integer; end;
```

fails identically (`Expected: begin, but got: F`). So adding `tkObject` to
`ParseGenericTemplateNamed`'s accepted set would buy nothing; the type itself
does not exist.

That is already tracked and already answered:

- [[feature-p-legacy-value-object-types]] [P p15] — the feature, `gated-by` ↓
- [[decide-old-style-object-types]] — **DECIDED 2026-08-25, option A: we do
  not implement `object` types. Not now.** On the principle that *a corpus is a
  measuring instrument, not a dependency.*

**So rtl-generics will not compile fully, by design, and rung 6 should not be
read as blocked.** It went 20 errors → 1, and the 1 is a construct we have
decided not to support. Anyone who picks this up to "finish rtl-generics" would
be reversing a standing decision, at prio 15, to make a measuring instrument
read zero — which is the exact thing that decision refuses.

**Do not file the remaining error as a corpus bug.** If the `object` decision is
ever revisited, it is revisited on its own ticket, not because a corpus wants it.

### PARKED 2026-08-30 (frankA) — rung 6 done, lock released, nothing half-applied

Released from `working/` because rung 6 is finished as far as it goes and this
is a multi-rung ladder: holding it open on one completed rung blocks the file
for no gain. Everything is committed and pushed; there is no in-flight edit.

Rung 6 (rtl-generics) this session: **20 errors → 1**, and the 1 is the decided
non-goal recorded in the section above. Do not read that as blocked.

**Next holder: read the section above before the LIVE STATUS table.** That table
has now been stale three times on the same field, and the two corrections above
it are dated. The re-derivation recipe is four commands and is the reliable part.

## 2026-08-30 (frankA) — re-measured; rung 6's remaining wall is a Track U decision, not a bug

**Did what this ticket tells its next holder to do: re-measured before reading
any note as a plan.** Every prior park note was stale again, in the same
direction — the corpus had advanced past what they describe.

| the notes said | measured on HEAD today |
| --- | --- |
| rung 9 = `bug-p-a-delphi-mode-generic-from-a-used-unit-cannot-be-specialized`, open | **done** |
| wall 6 Delphi half, open | **done** |
| wall 7 resourcestring, open | **done** |
| `generics.collections` wall = `unknown type: TKey` | **not reproducible** — a different wall now |
| `bug-p-two-different-nested-specializations-of-one-template-collide` | still open, `backlog/` |

**Four of the five referenced defects are closed.** The one open item is
unchanged.

### How to re-measure (nobody had written this down)

pxx has no standalone-unit output, so a unit needs a driver:

```
S=library_candidates/rtl-generics/packages/rtl-generics/src
printf 'program d;\nuses Generics.Collections;\nbegin\nend.\n' > /tmp/d.pas
./compiler/pascal26 -Fu$S -Fi$S/inc /tmp/d.pas /tmp/d.bin
```

(`--check-only` does not exist; compiling the `.pas` directly gives *"this file
is a unit, not a program"*, which is easy to misread as a corpus failure. Two
minutes lost to each, recorded so the next holder loses none.)

### Current rung 6 state

| unit | result |
| --- | --- |
| `generics.strings` | **compiles** |
| `generics.defaults` | **compiles end to end** (confirms the 2026-08-29 note) |
| `generics.collections` | wall at `:146` |

```
pascal26:146: error: generic templates must be class, record, interface, array
                     or procedure declarations
```

### The wall is `object`, and it is NOT a whitelist omission

`TCustomPointersCollection<T, PT> = object` — the legacy value-`object`. The
whitelist in `pasparser_generic.inc:1130` omits it, but widening it would be
wrong: **there is no `tkObject` token, and `object` is already claimed by an
unrelated meaning** — the rooted object *reference* type
([[feature-object-reference-type]], `pasparser_decl.inc:492`), whose comment
states outright that value-`object` "was never supported here".

So this is a known absence with a standing decision behind it:
[[decide-old-style-object-types]] chose **option A, do not implement**, in
`decided/`.

### The decision's own revisit trigger has fired — filed, not decided

That decision named its trigger: *"Option B, in full, the moment actual source
someone wants to build needs it. Not an FPC test — a program."* rtl-generics is
that source, and this rung is prio 75.

Filed as [[decide-revisit-object-types-rtl-generics-fired-the-trigger]] rather
than acted on, because the cost case has changed and the call is the user's.
Measured, and this is the part worth carrying:

- the corpus contains **exactly one** `= object`, across all six units;
- it has **no fields, no inheritance, no virtual methods, no constructor** — none
  of the cost drivers the decision priced (storage, lifetime, assignment, VMT);
- the **equivalent generic record-with-methods compiles and runs on HEAD today**,
  including `strict private type` and pointer-to-specialization access.

The two deltas are the keyword and a `protected` that nothing inherits from.

**Rung 6 is therefore blocked on a decision, not on a bug**, and no amount of
frontend work moves it until that is answered. That is a different kind of stop
from every previous wall on this ticket, all of which were defects — so do not
go looking for the next ordering bug behind it.

### Still open, unchanged

[[bug-p-two-different-nested-specializations-of-one-template-collide]] (p65) —
independent of everything above, and its "where to start" remains a hypothesis
from the error's shape, not a measurement.

---

## Is the park's condition met? — judgement, 2026-08-30 (frankD, read-only pass)

Asked by the coordinator: *"do seven resolved blockers add up to a resume?"*
**Partly — and the count is answering a question this ticket stopped asking.**

### The seven are real, and the canonical table's condition IS met

Every wall in **LIVE STATUS — THE ONE CANONICAL TABLE** is now closed. Its own
conclusion was *"Rung 6 is now behind wall 6 alone"*, and wall 6
([[bug-p-a-generic-class-method-call-is-undefined-inside-another-generics-body]])
closed 2026-08-28 in `35f485537` — which the 2026-08-29 note at the top of this
file already says. Wall 7 is resolved too. Wall 3 was established to *be* wall 6.
So on the condition as written, the park is discharged.

### But the park was re-written mid-park, and the new condition is live

The Status line says *"parked **2026-08-30** — rung 6 blocked on
[[decide-revisit-object-types-rtl-generics-fired-the-trigger]]"*. That ticket is
open in `backlog/` at **U p70**. It post-dates all seven.

**This is the structural point, and it generalises past this ticket.** Counting
resolved blockers assumes a park condition is *static*. This one was replaced
while parked, so the seven and the current block are disjoint sets, and a
resolved-blocker tally answers a question the ticket had already stopped asking.
**A park's condition needs a date as much as a park does** — and only the Status
line here carries one, which is why it is the only line that was right.

### The resume is real, but it is not rung 6 — and both named alternatives moved

Rung 6 waits on a human decision and nothing an agent does changes that. What is
actually available has itself drifted since it was written down:

1. **Rung 4 (fpjson) is the live candidate, and its row above was wrong in both
   halves.** The blocker resolved 2026-08-25 (`042e13b5c`); the "in no testmgr
   tier" claim ended when `test-fpjson` was added to **full**. So the rung is not
   RED-and-unwatched — it is **unmeasured since its blocker closed**, which is a
   different and much cheaper problem. I did not run it: `make test-fpjson` is a
   full-tier target and the hook refuses it here; Track T sweeps it.
2. **The escape hatch named in the U ticket has closed.** That ticket argues —
   correctly at the time — that `blocked-by` should NOT go on this umbrella,
   because it would hide workable rungs, citing
   [[bug-p-two-different-nested-specializations-of-one-template-collide]] [P p65]
   as *"explicitly independent of this decision"*. **That resolved the same day,
   `4d5f86a0b`.** The reasoning stands; the example it rests on is gone, so the
   trade wants re-pricing rather than re-affirming.

### On the frontmatter edge — do NOT add `blocked-by` here

The coordinator's standing instruction is to promote a real blocker into
frontmatter, and I am declining for this one, on the coordinator's own earlier
reasoning: `blocked-by` on an **umbrella** removes the whole ladder from `ready`
when only one rung is blocked. Correct ranking bought by hiding several workable
rungs is a worse trade.

**The structural fix is that the edge has nowhere correct to go.** `blocked-by`
is a whole-ticket field and the block is per-rung, so no frontmatter on *this*
file can be right. **Rung 6 wants to be its own ticket**, carrying the edge; then
the ranker sees the real dependency, the ladder stays visible, and the prose stops
being the only register that knows. Until that split, this section is the
compensating control and it is the same class of thing it is compensating for.

### Sibling glance (asked for; read-only)

- **[[feature-pascal-corpus-fpc-testsuite]] [P p65] — strong resume candidate.**
  Of 10 wikilinks, four are not in `done/`: this umbrella (circular), two
  **dangling** (`project_fpc_compat_next_queue`, `project_mimic_fpc_done` resolve
  to no file at all), and one real — `task-pascal-conformance-long-tail`, in
  `backlog/`. Its own Status says the rung-1 harness is delivered and live. So
  its four-resolved count understates: it is effectively behind **one** item.
  (This umbrella cites two dangling links of its own — `project_fpc_compat_next_queue`,
  `project_synapse_progress`. A dangling wikilink reads as an open dependency to
  every tool that counts them, and as a typo to every human. Worth a sweep;
  not done here.)
- **[[feature-pascal-corpus-generics]] [P p65] — held by frankA, not touched.**
  Five open links, none of them dangling. Relayed to frankA rather than edited.

### What was and was not done here
Read-only judgement. Prose edits confined to this file: the canonical table
(which instructs *"Update THIS table. Leave the snapshots alone."*), the rung-4
ladder row, and this section. **No dated snapshot was altered**, no frontmatter
changed, no ticket moved, no compiler file opened. `pasparser_generic.inc` was
neither read for edit nor touched — frank-rust has held it uncommitted since
23:39.

## 2026-08-30 (coordinator) — RUNG 6's BLOCKER MOVED; retarget before anyone reads the park

The `Status:` line at the top of this file says rung 6 is *"blocked on
decide-revisit-object-types-rtl-generics-fired-the-trigger"*. **That is now stale
and points at settled work.** frank-user resolved
`bug-p-object-value-types-standard-meaning` in `d23f52948` (board move
`50d341cd9`): `object` in type-declaration position is the standard Pascal value
type with methods, lowered as an advanced record, and the rooted class-reference
meaning is retired.

**Rung 6 now waits on
[[bug-p-generic-type-param-unresolved-in-class-abstract-template]] [P p70]** —
`TCustomPointersEnumerator<T, PT> = class abstract(TEnumerator<PT>)` resolves `PT`
in the ancestor clause and not in its member signatures.

### The measurement is worth more than the retarget: AN EARLIER LINE NUMBER IS NOT AN EARLIER FAILURE

The corpus wall moved **backwards**, 146 → 120, and that is the *expected* shape
after this fix rather than a regression. frank-user measured both binaries against
the same file:

| binary | probe as RECORDED | stops at |
| --- | --- | --- |
| `pinned` | `$ pinned generics.collections.pas` (done ticket) — **this command cannot run, see below** | `:146` |
| HEAD, sha not recorded | *"a one-line program that only does `uses Generics.Collections`"* (new ticket, frank-user) | `:120` `unknown type: PT`, then `:123`, then `:135` |
| HEAD `ea5a8ef96`, binary `6319b892f517` | `{$mode delphi}` program, `uses Generics.Collections`, `-Fu<rtl-generics/src>` (frank-rust) | `:135` `unknown type: TArray` — **`:120` never appears** |

**Rows 2 and 3 are the SAME PROBE and disagree. The disagreement is unexplained —
do not quote either line number as "the wall" until someone reproduces one.**

**:146 is a SYNTAX error that aborts the parse. :120/:123/:135 are SEMANTIC
errors reported against the template's own line numbers, and they are only
reachable once a specialization is streamed** — which the abort prevented. So the
earlier number is *deeper* progress.

This also settles a retraction that was itself over-corrected. frank-rust reported
:120 earlier, could not reproduce it against either binary, and withdrew the
figure — correctly on the evidence it had, since the abort order made :120
genuinely unreachable at the time. **The number was not wrong, it was masked**, and
the honest form of that finding was "not reachable yet", not "not real". Its wider
conclusion — that the wall was long-standing rather than a regression from the
generics work — was right and remains right.

Carry this to anyone reading corpus tickets: **a corpus stop that moves to a lower
line number is the ordinary signature of a syntax fix**, and reading it as a
regression is the mistake this file is now proof against.

## 2026-08-30 (coordinator, same day) — I RELAYED A LINE NUMBER I HAD NOT MEASURED

The table above originally read *"HEAD: past 146; new wall at **:120**, `unknown
type: PT`"*, flat, as though one binary had one wall. **That was frank-user's
measurement written into a ticket on master by me, unverified**, twenty minutes
after I told another lane that a lead from this seat should arrive with the
measurement that would kill it. frank-rust supplied that measurement within the
hour: it pulled to `ea5a8ef96`, rebuilt to a fixedpoint (`6319b892f517`,
converged 1 round), re-ran **its own** probe and got **`:135`, `unknown type:
TArray`** — not `:120`, not `PT`.

It then declined to write my number into its ticket on my say-so, *"that is the
exact substitution that produced the original bad figure, one level up."* Correct,
and the table is amended rather than defended.

### THE RECONCILIATION: THE TWO PROBES ARE DIFFERENT PROGRAMS

Both measurements are true, and the difference is visible in the two tickets
without running anything. frank-user's ticket records its invocation as
`$ pinned generics.collections.pas` — **the unit compiled DIRECTLY**, which
reports `:120`, `:123` and `:135` as a list. frank-rust compiled a
`{$mode delphi}` program that reaches the unit through `uses`, with `-Fu` — and
there **`:120` does not appear at all**; the first stop is `:135`.

So the walls are not a sequence one behind the other; **the same file has
different walls depending on how it is entered.** `TCustomPointersEnumerator<T,
PT> = class abstract(TEnumerator<PT>)` resolves `PT` when the unit is reached
through a delphi-mode `uses` and does not when the file is compiled directly.

**HYPOTHESIS, MINE, UNMEASURED: the dialect mode differs between the two entries**
— a directly-compiled unit does not inherit the `{$mode delphi}` of a program that
`uses` it, and delphi-mode generic scoping is what makes `PT` resolve. **The
measurement that would settle it is one run**: compile `generics.collections.pas`
directly with `{$mode delphi}` forced. If `:120` disappears, the hypothesis holds
and `:120` is an artefact of the direct probe rather than a corpus wall at all. I
have not run it and it is not mine to run — **it is recorded here as a hypothesis
with its falsifier, not as a finding.**

**Consequence for `bug-p-generic-type-param-unresolved-in-class-abstract-template`
[P p70]:** its title and summary are built on `:120` / `unknown type: PT`, which is
reproducible **only under the direct probe**. Whoever takes it should run the
falsifier above first. If `:120` is a direct-compile artefact, the real corpus wall
is `:135` / `TArray` — a generic *array* template (`TArray<T> = array of T`,
declared at `:57` of the same file) failing to resolve where a generic *class*
template on `:133` succeeds — and the ticket wants retitling, not just re-probing.

### THE RULE THAT COMES OUT OF THIS, AND IT IS BETTER THAN THE ONE I WROTE

Mine was *"a corpus stop that moves to a lower line number is the ordinary
signature of a syntax fix"*. It held. frank-rust's corollary is the load-bearing
half:

> **While an abort stands, every figure behind it is UNFALSIFIABLE, not false.**
> A probe that cannot reach a line cannot report on it, and the honest verdict is
> **"masked"** — a third value that is neither *reproduces* nor *does not
> reproduce*. Its ticket collapsed three states into two, and that collapse is
> what turned a correct measurement into a wrong retraction.

**And the discipline every corpus figure in this file now owes: state the PROBE,
the SHA and the BINARY.** Two lanes measured the same file on the same day and got
different walls; neither was careless; and the only reason the discrepancy
surfaced is that one of them refused to accept a number from the other. A bare
line number in a corpus ticket is not a fact — it is a fact about a probe nobody
wrote down.

## 2026-08-30 (coordinator, third pass) — MY RECONCILIATION WAS WRONG, AND SO WAS THE CORRECTION TO IT

Two hours, three versions of this table, and the third one says *we do not know*.
That is the accurate state, and it took two lanes refusing each other's numbers to
reach it.

**What is now established, each verified rather than relayed:**

1. **pxx refuses a standalone unit.** Verified here on an unrelated file so the
   check shares no upstream with either claim: `pinned lib/rtl/aesgcm.pas` →
   `pascal26:2: error: this file is a unit, not a program — compile a program that
   uses it (pxx has no standalone-unit output)`. So the done ticket's
   `$ pinned generics.collections.pas` **cannot have produced any of its output**;
   it is shorthand written for a reader, standing where evidence appears to be.
2. **The mode hypothesis was dead in the source, not in a run.** `generics.collections.pas:29`
   is `{$MODE DELPHI}{$H+}` — the unit sets its own mode and inherits nothing from
   whoever compiles it. **I proposed a run to settle a question the file answers**,
   which is the playbook's own complaint about reasoning where measuring was
   cheaper, one level up: I reached for a probe instead of `sed -n 29p`.
3. **And the reconciliation I built on that is not merely unsupported, it is
   contradicted.** `bug-p-generic-type-param-unresolved-in-class-abstract-template`
   records its repro as *"a one-line program that only does `uses
   Generics.Collections`"* — **the same probe frank-rust ran.** So "the same file
   has different walls depending on how it is entered" has no second entry point in
   evidence. Both lanes ran a `uses` program and got different first errors.
4. **The two binaries were functionally identical.** `git log d23f52948..ea5a8ef96
   -- compiler/` is **empty**: only board and docs commits separate them. So a
   compiler change between the runs cannot explain the difference either.

**Every explanation on the table is therefore gone, and the difference is real and
unexplained.** The remaining candidates are all about the run nobody wrote down —
an unrecorded flag, or a binary that was not the sha its lane believed. **Only
frank-user can settle it**, because only frank-user has the shell history.

### THE FOURTH MISSING VALUE: A RECORDED INVOCATION THAT DOES NOT RUN

frank-rust's companion to "masked", and it is the sharper of the two:

> **A command nobody re-executes is not evidence, it is a claim with a `$` in
> front of it.**

Both tickets carry a shell block as their repro. One of them cannot run. **The
check is free — paste it and press enter — and neither of us did it for two
hours**, through three ticket edits and four messages, while both of us were
explicitly arguing about evidentiary standards. A fenced block beginning with `$`
reads as *executed*; nothing in the format distinguishes a transcript from a
paraphrase, and the paraphrase is what a careful person writes when tidying up.

Same family as face 222 (a test that exists, passes elsewhere and is unwired) and
face 212 (the reassuring answer must be inexpressible): **the artefact that looks
most like verification is the one least likely to be verified.**

### WHAT ANYONE TOUCHING THE CORPUS FIGURE MUST DO NOW

- **Do not retitle the p70 ticket.** frank-rust asked for that hold and is right —
  retitling on the strength of its `:135` would be the same move as its adopting
  my `:120`, in the other direction.
- **The only reproducible facts are frank-rust's**, on two binaries it can name:
  through a `uses` from a `{$mode delphi}` program with `-Fu`, `pinned` stops at
  `:146` and HEAD `ea5a8ef96` (binary `6319b892f517`) stops at `:135`.
- **Every corpus figure written here from now on states the probe, the sha, the
  binary — and is pasted from a run, not reconstructed.**

## UNBLOCKED — rung 6 is available (coordinator, 2026-08-30)

**The status line said "parked, rung 6 blocked" while its blocker sat in
`decided/`.** Corrected in place rather than only here, because a note at the
bottom of a long ticket does not reach the person who reads the status line and
moves on — the same failure frankB reported today about a frontmatter `summary`
outliving what it summarised, one field over.

`decide-revisit-object-types-rtl-generics-fired-the-trigger` [U p70] is decided:
**option C**. `generics.collections.pas`'s single `= object` — no fields, no
inheritance, no virtual methods, no constructor — becomes a `TObject`, and the
measurement backs it: identical output on every use (widening assignment from any
class, cast-back with virtual dispatch, `array of`, record field, parameter, `nil`
compare) at `code=63287B data=4276B bss=42532B`, unchanged. `TObject` is strictly
*better* here, permitting `Free`/`ClassName`/`Destroy` without the cast the bare
reference required. The decision's original cost driver — a second object model
with its own storage, lifetime, assignment and VMT — was never what this rung
needed.

**Residual risk, carried forward from the decision and accepted by the owner:**
Pascal source *outside* this checkout using `var x: object` would break. Four
uses in this repo, all in its own tests.

**Also from that decision's Consequences, not yet done:**
[[feature-p-legacy-value-object-types]] [P p15] is framed against option B's full
scope and should be rewritten to option C's scope or closed in favour of the new
P bug. Not urgent at p15, but it will mislead whoever reaches it.

**Ownership:** `owner: frankA` is stale — frankA has taken
`bug-c-a-c-function-s-calling-convention-depends-on-the-target`. Re-`claim`
before the first commit; resuming parked work is the one transition with no
prompt to re-claim.

## CORRECTION to the note above: I described option B, which the owner REJECTED

**Caught by frankB before it built anything, 2026-08-30.** The unblock stands.
The characterisation of the decision does not.

I wrote *"option C … its single `= object` becomes a `TObject`"*. That second
half **is option B, and the decision names it as rejected**, verbatim: *"Option B
is rejected for the reason the owner gave: `object` is not `TObject` and neither
FPC nor Delphi treats it as such. B prices inheritance, VMTs and a constructor
protocol that the corpus does not use and that nothing has asked for."*

**Option C, verbatim:** *"the rooted-reference `object` is RETIRED rather than
kept alongside it. `object` gets its standard Object Pascal meaning — a value
type, i.e. a record with callables — with a **hard error** on inheritance,
`virtual`, `constructor` and `destructor` rather than silent half-support."*

**How I got it wrong, since the mechanism is reusable:** I read the file's `tail`
and its `summary:`, found a measurement table comparing a `TObject` version
against an `object` version, and reported it as the ruling. It was evidence
*inside* the analysis, not the answer — and the answer was in a `# DECIDED`
section I never opened. Reading a fragment of a long ticket and stating its
conclusion is the exact failure this board has logged three times this week; the
fragment I chose was the one that looked like a result.

**And it is already implemented.** `= object` lands at `pasparser_decl.inc:5745`
as a VMT-less value type (`UClsIsRecord := True`, hard error on an ancestor),
closed as [[bug-p-object-value-types-standard-meaning]] in `done/`. Measured by
frankB at HEAD `4f42b78b9`, not read: a value-type `object` with methods
compiles, runs, prints `7 8`, `SizeOf` 8 — no VMT pointer; and `TB = object(TA)`
gives *"an object type cannot have an ancestor -- pxx lowers `object` as a value
type with no VMT …; use a class to inherit."* Both arms live.

**So there is no object work in this ticket.** Anyone building to my note would
have implemented the one thing the owner explicitly ruled out, against a decision
file that says so.

**Also corrected: no `lexer.inc` collision on this ticket.** `object` is not a
lexer keyword — it is handled in `pasparser_generic.inc` and
`pasparser_decl.inc`, both of P's own carved-out files. The generic A/P
shared-lexer caution does not bind here.

## The actual wall (frankB, HEAD `4f42b78b9` / pinned `faf762981c3c`)

```
rung 6a  generics.defaults.pas     ok    [671512B code, 1661 procs, 25s]
rung 6b  generics.collections.pas  ERR   "unknown type: TKey"  [75s]
```

**Rung 6a is NOT yet claimed clean, deliberately.** `generics.defaults` compiles
standalone and fails to survive being *used* from collections. The obvious
reading is "defaults is fixed, collections is the wall" — but an uninstantiated
generic body may never be type-checked at all, in which case the standalone green
is vacuous and says nothing about that file. frankB has a control running (same
unit with `TComparer<Integer>.Default` actually instantiated) to tell those apart,
and is withholding the wall until it reads. A clean table with no control is what
burned the ESP float arm.

The wrong-file diagnostic frankB hit on the way is filed separately as
[[bug-p-a-deferred-generic-body-s-diagnostic-names-the-wrong-file-and-line]].
