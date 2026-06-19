# Language gaps surfaced by the demo apps (sudoku / sieve / chess)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-19 (writing the platonic demo apps in `examples/`)
- **Relation:** companion to feature-rtl-conversion-and-bitset-library — that
  ticket tracks the *library* gaps (IntToStr / Val / StrToInt / UpCase / Eof /
  Copy / a bit-set type); **this** ticket tracks *language / codegen* gaps the
  same demos hit. Touches feature-generators-yield (done) and the set lane noted
  in feature-demo-sudoku.

## Why

The demos are written platonically (idiomatic code, no workarounds). Library
holes go in the RTL ticket. A few gaps are in the language/compiler itself —
either confirmed or strongly suspected while writing — collected here.

## Gap 1 — `set of` built from runtime values  (CONFIRMED)

From feature-demo-sudoku: `s := s + [v]` with a *variable* `v` errors
("set item must be constant"), and `Include` / `Exclude` are unimplemented. So
the candidate-set lane (`set of 1..9` per row/col/box) cannot be built at
runtime; the sudoku solver, the sudoku game, and chess all fall back to integer
**bitmasks** where the value is dynamic. Chess uses sets only with *constant*
elements (`[mfCapture, mfPromo]`, `pos.castling - [crWK]`), which works.

To close:
- variable element in a set constructor: `[v]`, `[a..b]` with runtime bounds
- `Include(s, v)` / `Exclude(s, v)` builtins
- runtime `in` already works; this is about *construction* / mutation

This is the poster-child set feature; closing it lets the sudoku demos use the
real set lane instead of a bitmask, and is likely the pragmatic substrate for
the bit-set type in the RTL ticket.

## Gap 2 — `yield` from a nested routine inside a generator  (SUSPECTED)

Chess movegen wanted a nested helper `EmitPawnTo(...)` that does the four
promotion `yield`s, called from the generator body. The stackful-coroutine model
appears to only allow `yield` lexically in the generator's own body, so the
helper was **inlined** (promotion expansion duplicated for push and capture).
Verify whether `yield` inside a nested proc of a `generator` routine is
supported; if not, either support it or document the restriction.

## Gap 3 — generator yielding a record / aggregate  (TO VERIFY)

`test/test_generator.pas` only yields `Integer`. Chess declares
`function GenMoves(const pos): TMove; generator;` and `for m in GenMoves(pos)`
over a **record** element. If aggregate yield / aggregate for-in-over-generator
is not yet wired, the chess demo will not compile — confirm against the for-in
aggregate path (`test/test_forin_aggr_elems.pas` proves *array*-of-record
for-in; the *generator* element path is the unverified one).

## Acceptance

- Sudoku demos can use `set of 1..9` + `Include`/`Exclude` for candidates
  (bitmask becomes an optional alternative, not a necessity).
- A generator may `yield` from a nested routine, or the limitation is documented
  and the chess source matches it.
- A `generator of <record>` consumed by `for x in` compiles and runs; chess
  movegen validated against perft constants (in feature-demo-chess).

## Log
- 2026-06-19 — Opened from the demo apps. Gap 1 confirmed (carried over from
  feature-demo-sudoku, no prior dedicated ticket). Gaps 2 + 3 are suspicions
  from writing `examples/chess/chess.pas`; not built/tested here, so flagged for
  verification rather than asserted.
