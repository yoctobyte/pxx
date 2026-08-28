---
prio: 75
---

# Pascal real-world corpus expansion — the ladder Track P never had

- **Type:** feature — umbrella (frontend stress corpus)
- **Track:** P (Pascal frontend; shares `lexer.inc`/`parser.inc` with A, so bugs
  found land as Track P — A-gated — or Track A core)
- **Status:** working
  neglected by comparison — user call).
- **Owner:** frankA

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
| 4. fpjson (fcl-json's own 203-case suite) | `make test-fpjson` | **wired, RED** — recorded 203/203, re-measured 2026-08-25 at dev HEAD `20c989a5e`: does not compile, `data ptr fixup overflow`. [[bug-a-the-fpjson-suite-overflows-the-fixed-4096-entry-data-ptr-fixup-table]]. In **no testmgr tier**, which is why nobody noticed. |
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

Fetcher entry landed as `4f380892c` (`fetch_rtl_generics`, same pinned
`$FPC_COMMIT` as the other FPC-sourced corpora). **`CORPUS_EXPECTED` in
`twatch.py` is deliberately untouched** — this rung is a one-shot diagnostic,
not a gated job. Gate what can be green; diagnose what cannot.

**Binary:** `2c4e727d4b63`, verified self-host fixedpoint at `4f380892c`. Every
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

| # | wall | owner | sites | ticket |
| --- | --- | --- | --- | --- |
| 1 | typinfo: `PTypeData` fields, `PTypeInfo`, `GetTypeData`, `TTypeKind`, `TOrdType`, `TFloatType` | **B** | see list below | `feature-typinfo-facade-unit` (p72) |
| 2 | generic method header binds to same-named non-generic class | **P** | ~700 lines gated | `bug-p-a-generic-methods-out-of-line-header-binds-to-a-same-named-non-generic-class` |
| 3 | `TGeneric<T>.ClassMethod` inside another generic's body | **P** | 13 in `defaults`, ~357-ish shape count in `collections` | `bug-p-a-generic-class-method-call-is-undefined-inside-another-generics-body` |
| 4 | SysUtils gaps: `EArgumentOutOfRangeException`, `Exception.CreateRes`, `System.Error`/`TRuntimeError` | **B** | 3 + 3 + 7 | (to file / relay to frankB) |

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
