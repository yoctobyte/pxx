# Demo / test application candidates — selection criteria + catalog

- **Type:** idea
- **Status:** backlog
- **Opened:** 2026-06-17
- **Relation:** parent discussion for flagship demos. The first chosen build is
  feature-demo-chess. This ticket holds the selection rationale and the ranked
  catalog of alternatives so future demo choices are documented, not re-argued.

## What a good demo/test app must be

A flagship demo is not a unit test. It is a *real* application that also stresses
the compiler. Selection criteria, in order:

1. **Real-world.** Recognizable, non-toy, real algorithms. Not contrived.
2. **Broad feature coverage.** Intentionally exercises as much language surface
   as practical (arrays / sets / records / enums / Int64 / generators / for-in /
   procedural types / short-circuit / strings / collections / classes).
3. **Compact + cross-platform.** Small enough to run on constrained targets
   (ESP32), no OS deps beyond UART/stdout.
4. **Deterministic oracle.** Produces an output that is exactly reproducible and
   byte-identical across all targets, so it doubles as a cross-target
   correctness check (and ideally a performance benchmark). Integer-deterministic
   beats float (float rounding risks cross-target byte-divergence —
   [[project_cross_float_variant_done]]).

## Hard filters (disqualifiers)

- **GUI / "please the user" output → rejected.** Target story is headless /
  ESP32. Anything whose point is visual or audio gratification (ray-tracer,
  Mandelbrot, chiptune synth) fails the headless-deterministic-integer lane.
- **No clean spec boundary → rejected.** Self-modifying / parser-is-the-language
  designs (Forth) are a wasps' nest: no clean separation, hard to bound scope.
- **Argues against using libraries → rejected as flagship.** Some problems are
  the *poster child* for "use an existing library, don't rewrite" (regex). A
  flagship that undermines the language's own ecosystem story is the wrong
  message. Fine as a small unit test, not as flagship.
- **Authoring overhead → rejected.** Demos that need hand-authored content
  beyond the engine itself (Z-machine needs a story file + a written game) cost
  more than they prove.

## Catalog — ranked

### Chosen / flagship

1. **Chess engine** — feature-demo-chess. Best coverage-per-LOC; built-in
   deterministic `perft` oracle (published exact node counts); integer-only core
   (clean oracle, no float nondeterminism); ESP32-fits; natural cross-ISA
   performance benchmark (nodes/sec, cycles/node). The only candidate that is
   simultaneously real-world, broad-coverage, integer-deterministic, ESP32-sized
   **and** benchmarkable.

### Strong survivors (pass all filters — good future demos)

2. **JSON parser + serializer** — headless; trivial deterministic roundtrip
   oracle (parse → emit → reparse == identity); real-world; heavy managed-string
   + dynarray + recursion stress. Unlike regex, JSON parsers *are* commonly
   hand-written, so it does not undermine the library story. → **library**:
   feature-json-library.
3. **Lisp / Scheme interpreter** — headless; eval-suite oracle; deep coverage
   (collections, recursion, GC pressure, strings, eval). Flagship-tier but
   larger; self-hosting flavor. → **demo ticket**: feature-demo-lisp.
4. **RPN / spreadsheet calculator** — headless; deterministic formula-result
   oracle; parser + expression eval + procedural-type op tables; compact. Solid
   mid-size demo. Float optional (keep out of oracle path). → **demo ticket**:
   feature-demo-calc.
5. **Bytecode VM + assembler** — small ISA, deterministic program output;
   enums/proc-type dispatch/arrays/Int64; self-hosting flavor; little-brother to
   the parked Lua-as-target arc. → **demo ticket**: feature-demo-vm.
6. **Maze generator + solver** — seeded deterministic; 2-D arrays / sets
   (visited) / queue / recursion; ASCII over serial. → **demo ticket**:
   feature-demo-maze.
7. **Conway's Game of Life** — tiny deterministic oracle + benchmark; 2-D arrays
   + bit packing; shallow coverage but cheap and classic. → **demo ticket**:
   feature-demo-life.

### Rejected (with reason — kept so we don't re-litigate)

- **Forth interpreter** — no clean spec boundary; self-modifying dictionary;
  wasps' nest. Out.
- **Regex engine (NFA/DFA)** — the canonical "just use a library" problem; wrong
  flagship message. Possible small unit test only. Out as flagship.
- **Ray tracer** — float-heavy (cross-target byte-divergence risk weakens the
  oracle) + visual "please-user" output + ESP32 framebuffer RAM pressure. Out.
- **Mandelbrot / fractal** — visual output, float-determinism caveat, shallow
  language coverage. Out (at best a secondary float toy, not flagship).
- **Chiptune / synth (integer DSP)** — audio output = "please-user" category;
  narrow coverage (mostly arrays + arithmetic). NOTE: classic chiptune = simple
  oscillators (square/tri/saw) + envelopes, NOT necessarily FM; FM (OPL/SID-style
  operator modulation) is a harder variant. Either way: out.
- **Z-machine-lite VM** — needs a hand-authored story file + game; authoring
  overhead exceeds what it proves. Out.

## Spawned library tickets (organization pass 2026-06-19)

Several survivors are really **reusable libraries** whose acceptance test *is*
the demo (build the lib, the test app is its oracle). Tracked as library tickets,
not just demos:

- feature-json-library — parser + serializer (roundtrip oracle)
- feature-hashing-library — CRC32 / MD5 / SHA-256 (known-vector oracle)
- feature-compression-library — Huffman / LZ77 (roundtrip + size; needs bit-set)
- feature-bignum-library — arbitrary-precision integers (factorial(1000) oracle)
- feature-sat-solver-library — DPLL over CNF (known SAT/UNSAT instances)

**Interpreters stay demo-class, not library:** VM / Lisp / Lua are *applications*
(or, for Lua, a whole frontend/target arc), not RTL units — keep them as
`feature-demo-*` if chosen, not library tickets. Lua-as-compile-target is a large
separate arc, deliberately parked.

## Use

When a new demo is wanted, pick from the survivors and open its own
`feature-demo-*` ticket; if it is library-shaped, open / use the matching
`feature-*-library` ticket above instead. Update this catalog if criteria change
or a new candidate appears.

## Log
- 2026-06-17 — opened. Split out of feature-demo-chess (appendix moved here).
  Captures selection criteria + hard filters (GUI/please-user out, Forth out,
  regex demoted as "use-a-library" poster child, Z-machine out for authoring
  overhead) + ranked catalog. Chess is the chosen flagship; JSON / Lisp / calc
  are the documented survivors.
