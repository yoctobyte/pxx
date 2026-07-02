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
