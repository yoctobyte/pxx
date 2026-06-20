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

## Gap 1 — `set of` built from runtime values  (DONE 2026-06-19)

**Resolved.** Runtime set construction + mutation landed:
- `[v]` and `[a..b]` with variable elements/bounds (any mix of constant and
  runtime items in one literal). All-constant literals keep the baked-blob fast
  path, so self-host stays byte-identical.
- `Include(s, v)` / `Exclude(s, v)` builtins.

Lowered entirely in the shared IR (`IRLowerSetBitMutate` / `IRLowerSetRangeMutate`
in `compiler/ir.inc`) from `IR_BINOP` / `IR_LOAD_MEM` / `IR_STORE_MEM` primitives
— no new IR ops, no per-backend asm, no builtinheap dependency. The value is
masked to 0..255 so the byte index always lands inside the 32-byte set
(out-of-range elements ignored, matching the constant path). Parser: a constant
element still folds to `AN_INT_LIT` (`ParseSetElementAST`), a non-constant one is
parsed as a full expression; `AN_SET_INCL` / `AN_SET_EXCL` carry Include/Exclude.

Validated on all 4 targets: `test/test_set_runtime.pas` in test-core +
i386/aarch64/arm32 cross suites (output identical to x86-64); self-host +
cross-bootstrap byte-identical. The sudoku/maze/chess candidate-set lanes can now
use real `set of 1..9` + `Include`/`Exclude` instead of integer bitmasks.

Original report below.

### (original) `set of` built from runtime values  (CONFIRMED)

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

## Gap 3 — generator yielding a record  (DONE 2026-06-19)

**Confirmed real (segfaulted) and fixed.** A `; generator;` routine can now yield
a record element consumed by `for x in`. A record does not fit the one-word
"current" slot, so `yield m` stores the record's ADDRESS (the stackful
generator's frame keeps it alive until the next resume) and the for-in desugar
derefs that address into the loop variable:
- ir.inc `AN_YIELD`: a `tyRecord` value lowers its address (`IRLowerAddress`).
- parser.inc `ParseForInGeneratorAST`: a record loop var assigns from an
  `AN_DEREF` of the `CoCurrent` address, with the record id carried on the deref
  node so the copy is sized.
- symtab.inc `ResolveNodeRec`: an `AN_DEREF` carrying a positive rec id on the
  node resolves to it (the base is an untyped Int64 call result).

Validated x86-64 (`test/test_generator_record.pas`, in test-core) for 16- and
24-byte records + accumulation; self-host + cross-bootstrap byte-identical.
Scope: the stackful (coroutine) path — stackful generators are x86-64-only
(CoSwitch). Stackless `; generator; stackless;` record-yield would need the same
deref in the SlCurrent path (separate, lower priority). Unblocks chess movegen
(`yield`ing a `TMove`).

## Gap 2 — yield from a nested routine  (documented limitation 2026-06-19)

**Confirmed:** `yield` inside a nested routine of a generator does not parse
(`yield` is only valid lexically in the generator's own body). Threading the
generator self-pointer into nested routines (stackful-only) is invasive and
deferred; the error now states the limitation clearly ("yield must appear
directly in a generator body, not in a nested routine — inline the helper for
now"). Chess already matches this (promotion expansion is inlined), so the
acceptance criterion ("the limitation is documented and the chess source matches
it") is met.

## Log
- 2026-06-19 — Opened from the demo apps. Gap 1 confirmed (carried over from
  feature-demo-sudoku, no prior dedicated ticket). Gaps 2 + 3 are suspicions
  from writing `examples/chess/chess.pas`; not built/tested here, so flagged for
  verification rather than asserted.
- 2026-06-19 — Gap 1 DONE (runtime sets + Include/Exclude, v11). Gap 3 verified
  (segfaulted) + DONE (record yield, stackful x86-64). Gap 2 verified (won't
  parse) + documented as a limitation with a clear error. This ticket is now
  effectively closed: Gap 1 + Gap 3 implemented, Gap 2 documented. Remaining
  follow-on (own ticket if pursued): nested yield, stackless record-yield.
- 2026-06-20 — commit reference (board checker): landed in 0e2a57a + 361163c (filed in f93f8ad)
