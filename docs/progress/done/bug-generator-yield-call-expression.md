# Generator `yield` of a call expression lowers to unsupported IR

- **Type:** bug (compiler / IR lowering)
- **Status:** done
- **Owner:** Track A
- **Opened:** 2026-06-21
- **Relation:** current `examples/chess` blocker; belongs to the generator /
  record-yield family but is narrower than the old demo-gap ticket.

## Symptom

`examples/chess/chess.pas` fails in the move generator:

```text
Unsupported linear node in IR codegen! Kind=10 node=120 IRA=8 IRB=107 IRC=-1 IRIVal=90
pascal26:629: error: Unsupported linear node in IR codegen ()
```

The source reported at line 629 is the closing `end` of `GenMoves`, but the IR
dump shows unsupported nodes immediately under `IR_YIELD`. The first offending
source construct is:

```pascal
if RankOf(dest) = promoRank then
begin
  yield MkMove(from, dest, pkQueen,  [mfPromo]);
  yield MkMove(from, dest, pkRook,   [mfPromo]);
  yield MkMove(from, dest, pkBishop, [mfPromo]);
  yield MkMove(from, dest, pkKnight, [mfPromo]);
end
```

`MkMove(...)` returns a `TMove` record. The same shape appears throughout
`GenMoves`:

```pascal
yield MkMove(from, dest, pkNone, [mfCapture]);
yield MkMove(4, 6, pkNone, [mfCastleK]);
```

`--dump-ir` shows:

```text
unsupported a=8 ... ival=90 ...
yield a=<unsupported-node> ...
```

where `IR_UNSUPPORTED` carries `a=8`, i.e. `AN_CALL`.

## Root Cause

IR lowering for stackful generator `yield` can handle record-yield storage once
it has a lowered value/address, but `AN_YIELD` does not lower a record-returning
call expression used directly as the yielded value. The call expression falls
through to `IR_UNSUPPORTED`, then x86-64 codegen reports the generic unsupported
linear node.

Using a local temporary is expected to sidestep the issue:

```pascal
tmp := MkMove(from, dest, pkQueen, [mfPromo]);
yield tmp;
```

but the direct expression is legal source and should compile.

## Direction

- Fix `AN_YIELD` / record-yield lowering so a call expression can be materialized
  before yielding.
- Prefer a general solution: any yield expression that returns an aggregate
  should lower through the same temporary/address path as assignment of a
  record-returning call.
- Add a small regression test with a generator yielding a record returned by a
  helper function.
- Keep the chess source as-is; do not require manual temporaries in the demo.

## Acceptance

- Minimal `yield MakeRecord(...)` generator test compiles and runs.
- `examples/chess/chess.pas` gets past the current `IR_UNSUPPORTED` failure.
- Existing generator record-yield tests remain green.

## Log

- 2026-06-21 - Opened from pinned v26 chess discovery failure. The failing source
  is direct `yield MkMove(...)` in `GenMoves`; the diagnostic lands on the
  generator's closing `end` because the unsupported call expression is discovered
  during IR codegen.
- 2026-06-21 - DONE (Track A). Fixed at parse time in the `yield` builtin
  dispatch (`ParseStatementAST`): when the yielded value is a `tyRecord` that is
  not an addressable lvalue (not `AN_IDENT/AN_FIELD/AN_INDEX/AN_DEREF`, i.e. a
  record-returning call), materialise it into a generator-frame local
  (`AllocVar` + `InferSymTypeFromNode` to carry `RecName` from `ProcRetRecId` +
  `AllocateSymOffset`), emit `tmp := <call>` before the yield, and yield the
  temp. The stackful frame keeps the temp alive until the next resume, so the
  existing `AN_YIELD`→`IRLowerAddress` record path (which previously fell through
  to `IR_UNSUPPORTED` on `AN_CALL`) now sees an `AN_IDENT`. Source stays
  manual-temp-free. Regression test `test/test_generator_yield_call.pas`. `make
  test` green; self-host + threadsafe fixedpoint byte-identical.

**Resolved-in:** 085be11 (finalizing commit)
