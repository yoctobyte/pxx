---
prio: 62  # auto — un-neglect Pascal; the full dialect (Track P) is only stressed by real programs
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
