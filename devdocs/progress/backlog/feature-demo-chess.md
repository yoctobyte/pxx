# Flagship demo — chess engine (real-world app + cross-target oracle + benchmark)

- **Type:** feature
- **Status:** backlog
- **Opened:** 2026-06-17
- **Relation:** consumes feature-for-in-iteration (move loops) and
  feature-generators-yield (move generation). Doubles as a living regression
  oracle and a cross-target performance benchmark.

## Purpose — three jobs in one program

1. **Flagship demo.** A *real* application, not a test: recognizable, non-toy,
   real algorithms (search / eval / hashing). Shows the language does serious
   work.
2. **Feature-coverage torture test.** Intentionally exercises as much of the
   language surface as practical (matrix below). When the demo compiles and
   `perft` matches known constants, a huge slice of the compiler is validated at
   once.
3. **Cross-target oracle + benchmark.** Same source on all 5 targets
   (x86-64 / i386 / aarch64 / arm32 / riscv32 / xtensa). Two deterministic
   outputs:
   - **Correctness:** `perft(N)` leaf-node counts are exact known integers →
     byte-identical across every target via the existing output-equality
     harness. Any codegen bug in move-gen / recursion / Int64 shifts the count.
   - **Performance:** same code → measure nodes/sec, and (where the target
     exposes a cycle counter) **cycles per node**. Lets us compare codegen
     quality per target / per clock tick. A real cross-ISA benchmark from one
     source.

## Why chess specifically

- **Integer-only core** — no float needed → fits ESP32 RAM, no float
  cross-target rounding nondeterminism (the risk that weakens ray-tracer /
  Mandelbrot as oracles). See [[project_cross_float_variant_done]] for why float
  determinism is the hard case we deliberately avoid in the oracle path.
- **Deterministic by construction** — `perft` has published exact constants
  (startpos perft(6) = 119,060,324). Self-validating, no reference renderer
  needed.
- **Compact** — mailbox engine ~1–2k LOC; bitboard variant adds 64-bit stress in
  modest extra code. Fits constrained RAM ([[project_esp32_stage1]]).
- **No OS deps** beyond UART / stdout. UCI over stdin is optional interactive
  surface.

## Feature-coverage matrix (criteria 2)

| Language feature | Where exercised |
| --- | --- |
| static arrays | mailbox board `array[0..63] of TPiece` |
| dynamic arrays | move lists, PV line |
| records | `TMove` (from/to/flags), `TUndo`, `TPair` in TT |
| enums | piece kind, color, castling-right, square |
| **sets** | castling rights, square / attack masks |
| recursion | alpha-beta / negamax search |
| **Int64 / UInt64** | bitboards + Zobrist 64-bit hash — stresses 64-bit math on the 32-bit targets (i386 / arm32 / riscv32 / xtensa); see [[project_i386_int64_codegen]] equivalents |
| **generators (`yield`)** | move generation as `generator of TMove` |
| **`for x in`** | `for m in GenMoves(pos) do` — directly consumes feature-for-in-iteration |
| procedural types | eval-term function table / search-callback |
| short-circuit `and`/`or` | legality + bounds guards ([[project_shortcircuit_landed]]) |
| managed strings + parsing | UCI protocol over stdin/UART; FEN parse/emit |
| collections / hashing | transposition table (open-addressed, Zobrist keyed) |
| classes / VMT (optional) | engine vs board object split |
| exceptions (optional) | illegal-input / abort-search path |

It **consumes the for-in + generator arcs**: demo and feature work reinforce
each other rather than duplicating effort.

## Known gaps + how to close them

Chess alone skips **floats** and **networking / GUI**. Deliberate — keep the
oracle path integer-deterministic. Optional closers:

- `--float-eval` flag: float-weighted eval term → exercises cross float without
  polluting the deterministic perft oracle.
- UCI over stdin: real protocol → strings / parse / interactive I/O breadth.
- (Leave GUI / networking to other demos — see appendix.)

## ESP32 fit (criteria 3)

- Mailbox board + small TT → tens of KB; tune TT size by target.
- Integer-only core → no FPU dependence.
- Output over UART; perft / bench numbers printed as plain integers.
- Build under the existing ESP harness ([[project_esp32_stage1]],
  feature-esp32-idf-xtensa / feature-esp32-idf-riscv32).

## Benchmark methodology (criteria: perf comparison)

- **Workload:** fixed `perft(N)` and a fixed-depth search from a fixed FEN, so
  every target runs identical work.
- **Metrics:** wall-time nodes/sec; where available, hardware cycle counter →
  **cycles/node** (CCOUNT on Xtensa, `rdcycle` on RV32, `rdtsc`/clock on x86,
  `PMCCNTR`/`cntvct` on ARM). Print as integers → diffable, archivable.
- **Use:** track codegen quality regressions over time; compare ISAs per clock;
  fun meta-metrics (e.g. regressions vs bytes-of-code-added). Numbers live in
  the repo so progress is publicly analyzable.

## Slices

1. **Board + movegen + perft (mailbox).** No search, no eval. Lands the oracle:
   `perft(1..6)` matches published constants on x86-64, then cross-bootstrap.
   Movegen written as a generator + driven by `for m in`.
2. **Search + eval.** Negamax + alpha-beta, integer material/PST eval. Fixed
   FEN / fixed depth reproducible best-move output.
3. **Transposition table + Zobrist.** 64-bit hashing → Int64 stress; TT as a
   collection. Re-validate perft (hash must not change counts).
4. **UCI + FEN I/O.** String parse/emit, interactive surface.
5. **Benchmark harness.** nodes/sec + cycles/node per target, integer output,
   wired into the cross harness.
6. **(optional) bitboard variant / `--float-eval`** — extra 64-bit + float
   coverage.

## Acceptance

- `perft(1..6)` from startpos (and a few standard test positions, e.g. Kiwipete)
  matches published constants on **every** target, byte-identical via the
  output-equality harness; `make cross-bootstrap`-style multi-target run green.
- Self-host compiler builds the demo on all targets.
- Benchmark prints deterministic integer perft counts + per-target
  nodes/sec & cycles/node.
- Demo exercises the matrix above; for-in + generator paths are real (not
  stubbed).

## Alternative demos

Chess is the chosen flagship. The ranked catalog of other demo/test-app
candidates — selection criteria, hard filters, and why each alternative was kept
or rejected — lives in its own ticket: **idea-demo-app-candidates**.

## Log
- 2026-06-28 — **slice 2 (search+eval) unblocked + verified** (Track B, v83).
  [[bug-proc-typed-call-const-record-arg]] fixed by Track A. `go 3` from startpos
  returns `bestmove e2e4 score 10 nodes 40793` — no longer INF. `--selftest` still
  `ALL OK` (CHECKSUM 5554659317958071639). Engine fully functional on x86-64:
  perft oracle + alpha-beta search + eval term table all green. **Remaining (Track A):**
  cross-target byte-identical perft, self-host build on all 5 targets, benchmark
  harness (nodes/sec, cycles/node).
- 2026-06-25 — **slice 2 (search+eval) blocked by codegen bug**
  [[bug-proc-typed-call-const-record-arg]]. `go N` returns `score 30000` (=INF)
  from any position because `Evaluate` calls its terms through the proc-typed
  table `EvalTerms[i](pos)` (`const TPosition` param), and indirect calls with a
  const-record arg are miscompiled (return the function pointer / segfault).
  Confirmed: direct `TermMaterial(pos)`=0, but `EvalTerms[0](pos)`=4318895 (a code
  address). The **perft oracle is unaffected** (no eval calls) and stays the
  lib-test gate; search/eval validation waits on the Track A fix. Engine left
  idiomatic (no workaround) per the platonic policy.
- 2026-06-25 — **x86-64 oracle validated + wired into `make lib-test`** (Track B,
  v66). The platonic engine compiles clean against `$(PXX_STABLE)` (no `-Fu`) and
  perft matches **every** published constant: startpos perft(1..6) =
  20/400/8902/197281/4865609/119060324; Kiwipete perft(1..3) = 48/2039/97862;
  Position 3 perft(1..3) = 14/191/2812. Added a `--selftest` mode (top-level
  `PerftCheck` + `SelfTest`, no nested-proc capture per the F3 gap) that checks
  10 perft values across those 3 positions, prints a folded integer `CHECKSUM
  5554659317958071639` and `ALL OK` in ~1.1s; wired as the `chess-perft` smoke
  oracle in lib-test (startpos perft>=5 deliberately excluded — ~19s, too slow for
  the gate). perft(6) confirmed manually (7m53s, x86-64). **Remaining (Track A):**
  cross-target byte-identical perft + self-host build on all 5 targets, and the
  benchmark harness (nodes/sec, cycles/node).
- 2026-06-19 — **Platonic engine source landed** (`examples/chess/chess.pas`).
  One coherent mailbox engine combining slices 1–4: FEN parse (exceptions),
  pseudo-legal **movegen as a `generator` driven by `for m in GenMoves(pos)`**,
  make/unmake, `perft` recursion (the oracle), negamax + alpha-beta with an
  open-addressed **transposition table** keyed by **UInt64 Zobrist** hashing,
  evaluation via a **procedural-typed term table** (`@TermMaterial` etc.), and a
  `TEngine` **class with a virtual `ScorePosition`** overridden by
  `TGreedyEngine` (VMT). Sets used for castling rights + move flags; a UCI-ish
  REPL (`perft`/`go`/`fen`/`print`) gives the interactive/serial surface.
  Written platonically, **not built or tested here** (per the demo policy).
  **Gaps surfaced** beyond feature-rtl-conversion-and-bitset-library
  (IntToStr/StrToInt): `UpCase`, `Eof` (stdin), `Copy` — assumed present, RTL to
  follow. Validation (perft constants byte-identical across targets, self-host
  build, benchmark numbers) remains; reopen scope unchanged.
- 2026-06-17 — opened. Chosen after design review: flagship demo doubling as
  cross-target correctness oracle (perft) + performance benchmark (nodes/sec,
  cycles/node). Intentionally consumes feature-for-in-iteration +
  feature-generators-yield. Integer-only core chosen to keep the oracle path
  deterministic (float deferred to optional `--float-eval`). Top-10 alternative
  demos recorded in appendix for future reference.
