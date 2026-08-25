---
prio: 75
---

# Pascal real-world corpus expansion — the ladder Track P never had

- **Type:** feature — umbrella (frontend stress corpus)
- **Track:** P (Pascal frontend; shares `lexer.inc`/`parser.inc` with A, so bugs
  found land as Track P — A-gated — or Track A core)
- **Status:** backlog — filed 2026-07-10 (C wound down to 2 open bugs; Pascal
  neglected by comparison — user call).
- **Owner:** —

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
| 4. fpjson (fcl-json's own 203-case suite) | `make test-fpjson` | **wired, green (203/203)** — but in **no testmgr tier** |
| 5. Synapse | `make lib-test` (Track B), 3 drivers incl. TLS | **wired, green** |
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
2. **Enrolment gaps.** `test-fgl` and `test-fpjson` are in no testmgr tier —
   [[task-t-enrol-the-fgl-corpus-rung]].
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
work:** (a) burn the three fgl walls — cheapest, and each turns on more than
its own driver; (b) enrol what exists; (c) then rung 6 (rtl-generics), which is
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
