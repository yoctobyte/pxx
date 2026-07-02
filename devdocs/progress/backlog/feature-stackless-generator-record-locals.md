# Stackless generator: record locals / record yield element (chess GenMoves wall #2)

- **Type:** feature (compiler restriction lift)
- **Track:** A — `compiler/parser.inc` (stackless generator transform)
- **Status:** backlog
- **Opened:** 2026-07-02

## Problem

With yield-in-case lifted (feature-stackless-generator-yield-in-case, done
2026-07-02), the NEXT wall between `examples/chess/chess.pas` and cross-target
builds is:

```
pascal26:634: error: stackless generator: only ordinal/pointer locals are supported (v1) ()
```

`GenMoves(const pos: TPosition): TMove; generator; stackless;` yields a RECORD
(TMove) and keeps record locals across yields. The v1 stackless instance layout
persists locals as single 8-byte words (SL_OFF_SLOTS + 8*slot), so records
(multi-word) can't be checkpointed, and the yielded CURRENT slot is one word too.

## Scope

- Persist record locals across yields: byte-copy the record into/out of a
  correctly-sized instance region (slot allocation by size, not word count).
- Support a record element type for the generator (CURRENT becomes a
  record-sized region; for-in copies it out).
- `const` record params (pos: TPosition) may already work via pointer-word
  persistence — verify.

## Acceptance

- A stackless generator with a record local + record element compiles and runs
  correctly on x86-64 + i386.
- `examples/chess/chess.pas` (with `stackless` added to GenMoves) builds and
  passes perft on the cross targets — the remaining chess acceptance from the
  yield-in-case ticket.
- Existing test/test_stackless_gen.pas stays green; self-host byte-identical.

## Log
- 2026-07-02 — Filed by Track A while resolving
  feature-stackless-generator-yield-in-case: case restriction lifted, chess's
  GenMoves now stops at this wall instead (also note chess.pas declares plain
  stackful `generator;` — cross builds additionally need the `stackless`
  keyword on GenMoves, i.e. a one-word source tweak, Track B's call).
