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
- 2026-07-02 — Track A: DONE.
  - Record LOCALS persist across yields: multi-word slot regions
    (RecSize-rounded), SlBlob/SlUnblob byte-copy save/restore (new slgen
    helpers). Managed-field records rejected cleanly.
  - Record ELEMENT type: record-sized CURRENT region reserved at the instance
    tail; yield blob-copies the (always-lvalue, parse-site-materialised)
    record and publishes the region address in the CURRENT word; for-in
    derefs it into the loop var (mirrors the stackful CoCurrent shape).
  - By-ref (var/const-record) params persist their POINTER WORD via new
    AN_SLOTADDR (=77, lowers to existing IR_SLOTADDR) — a plain assign to an
    IsRef sym stores THROUGH the caller address. Pointer-typed deref (native
    width — Int64 clobbered the neighbour slot on 32-bit targets).
  - Step-call pad args for by-ref params use an addressable ident (a zero
    literal has no address for the by-ref marshalling path).
  - continue/break inside a FLATTENED loop rewritten to gotos
    (SLRewriteLoopJumps; for-loop continue targets a new inc label).
  - SlAlloc (6×Int64 = 12 arg words, over riscv32's 8-word limit) replaced by
    SlNew + per-arg SlSet; AsyncGo switched too.
  - aarch64 IR_SLOTADDR fixed to the raw-slot contract (was auto-dereffing
    by-ref params via EmitLoadVarAddrA64 — x64/i386/arm32 were already raw).
  - MAX_GOTO_LABELS 64 -> 2048 (chess GenMoves needs hundreds);
    BlockParent 8192 -> 32768 (FPC cold bootstrap, cap was baked into the
    compiling binary).
  - Validated: test_stackless_gen.pas extended (RecGen: record local mutated
    across resume, call-result yield, const-record param, continue, case) —
    output-identical on x86-64/i386/aarch64/arm32. Stackless chess variant:
    perft selftest CHECKSUM identical to stackful on x86-64.
  - Chess CROSS builds still walled — but no longer by generators: `readln`
    unsupported on cross backends (filed feature-cross-readln-console-input);
    riscv32 hosted writeln hangs even on pinned v154 (pre-existing, filed
    bug-riscv32-hosted-writeln-hello-hangs).
