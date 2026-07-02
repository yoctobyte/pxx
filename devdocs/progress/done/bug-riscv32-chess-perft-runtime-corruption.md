# riscv32 hosted: chess perft miscounts (164 vs 20) then segfaults — post-InitZobrist corruption

- **Type:** bug (riscv32 backend runtime)
- **Track:** A — `compiler/ir_codegen_riscv32.inc`
- **Status:** backlog
- **Opened:** 2026-07-03

## State of the bring-up

Stackless chess now COMPILES and STARTS on hosted riscv32 (exceptions, class
instantiation, virtual calls, ParamStr/ParamCount, frozen-string write/EQ all
landed 2026-07-03). `--selftest` runs but perft(1) counts 164 (want 20), later
depths 0, then segfault.

## Narrowed so far (all standalone-verified IDENTICAL to x86-64 on riscv32)

- GenMoves alone on the start position: exactly 20 moves, identical list.
- Make/Unmake roundtrip WITHOUT InitZobrist: 20 moves, 0 desyncs... on x86-64;
  the riscv32 leg of that same repro (mg2/mg3 in the session scratchpad)
  CRASHES in SetFEN — but only when InitZobrist ran first. InitZobrist itself
  completes. Suspicion: some 64-bit store path in InitZobrist (NextKey RHS
  call + 3-D UInt64 global array dest) tramples adjacent BSS (heap arena?),
  and later heap/string ops crash.
- NOT the cause (each byte-identical on riscv32): 3-D UInt64 arrays incl.
  enum subrange lower bounds (zb/zb2), 1-D/3-D const array params (ap/ap3),
  typed-const/global-init/multidim after the IR_LOAD_MEM/IR_STORE_MEM 64-bit
  fixes.

## Repro

`mg3.pas`: chess.pas lines 26..632 as an include + `InitZobrist; SetFEN(...)`
— prints A, B, then segfaults inside SetFEN on riscv32; fine on x86-64.

## Acceptance

- mg3 repro runs identically to x86-64.
- Stackless chess `--selftest` CHECKSUM identical on hosted riscv32.

## Log
- 2026-07-03 — Filed by Track A after the hosted bring-up session; bisection
  state recorded above so the next session doesn't redo it.
- 2026-07-03 — Track A: FIXED — chess perft --selftest is now BYTE-IDENTICAL
  to the x86-64 oracle on hosted riscv32 (CHECKSUM 5554659317958071639,
  ALL OK). Three distinct riscv32 bugs stacked:
  1. Missing hidden-temp nil-init pass in the riscv32 (and xtensa) walkers:
     managed temps materialised during IR lowering (e.g. the concat temp in
     `raise EChess.Create('bad piece in FEN: ' + c)`) held stale stack bytes,
     and the epilogue's scope-exit DecRef released garbage whenever the
     temp's path never ran — the "post-InitZobrist SetFEN segfault" (the
     zobrist fill just made the stale bytes non-nil). Ported the x86-64
     walker's nil-init pass to both.
  2. IR_JUMP_IF_FALSE emitted a lone `beq` (B-type, +-4KB): big routines
     silently truncated the offset. Now bne-skip + jal (+-1MB).
  3. By-value 32-byte SET parameters marshalled as ONE word (the set's
     address) while the callee read its own 32-byte slot as set bytes —
     MakeMove/UnmakeMove saw phantom move flags (perft(1)=164, every
     make/unmake desynced). Now 8 words inline (mirrors i386), callee
     rebuilds the slot from a-regs + the caller-kept stack block.
  New all-target regression test/test_cross_set_param.pas (riscv32 gate +
  verified i386/aarch64/arm32/x86-64). Full suite + all cross + ESP gates
  green, self-host byte-identical.
