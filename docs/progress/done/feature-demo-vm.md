# Demo — bytecode VM + assembler (small ISA)

- **Type:** feature
- **Status:** done — unblocked + green on v35
- **Owner:** —
- **Opened:** 2026-06-19
- **Relation:** demo-class survivor from idea-demo-app-candidates. Interpreter
  family (kept demo, not library). Little-brother to the parked
  **Lua-as-compile-target** arc — same shape, bounded scope. Platonic source
  like the chess/sudoku demos.

## Goal

Define a small (~20-opcode) stack bytecode ISA, a text **assembler** (mnemonics
→ bytes), and a **VM** that executes it. Not a real language frontend — a
self-contained machine.

## Surface / shape

- opcode `enum`; instruction `record` (op + operand)
- assembler: parse mnemonic lines → byte program (managed strings)
- VM: program counter, operand stack, memory `array`, dispatch via a
  **procedural-type table** indexed by opcode (or a `case`)
- ops: push/pop/add/sub/mul/div/load/store/jmp/jz/call/ret/print/halt

## Coverage

enums (opcodes) · records · static + dynamic arrays (stack / memory / program) ·
**procedural types** (dispatch table) · Int64 · managed strings (assembler) ·
recursion (call/ret). Self-hosting flavor — mirrors the real compiler's spirit.

## Acceptance / oracle

- Fixed assembled programs (e.g. iterative fib, factorial, a loop sum) produce
  deterministic integer output, byte-identical across all targets.
- Demo: `examples/vm/` assembles + runs a bundled program set.

## Constraints

Platonic source, assumes idiomatic RTL; no compiler changes; ESP32-fit
(integer-only). No self-host / cross regression once wired into the harness.

## Log
- 2026-06-19 — Opened in the demo-ticket organization pass.
- 2026-06-22 — **Implemented** (track B): `lib/rtl/vm.pas` — 22-opcode stack ISA
  (push/pop/dup/swap, arith, lt/gt/eq, load/store, jmp/jz/jnz, call/ret, print,
  halt), a label-resolving two-pass text assembler, and a `case`-dispatch
  executor returning PRINT output as a string. Flat parallel Integer arrays for
  the program (no records-with-dynarrays). Oracle `examples/vm/vmdemo.pas`: loop
  sum (55), iterative + recursive factorial (120, recursion via call/ret), a
  twice-called subroutine (36/81), and assembler-error rejection.
  **FPC runs it `ALL OK`.**
  **Blocked:** PXX rejects the clean source with `SetLength expects a string
  variable in IR codegen` — a layout-sensitive codegen bug
  (bug-setlength-ir-string-in-complex-method). Left as clean Platonic code (no
  workaround) and NOT wired into `make lib-test`. Unblocks + closes when the
  codegen bug is fixed.
- 2026-06-22 (later) — **DONE.** Track A's named-dynamic-array-field SetLength
  fix (bug-named-dynarray-field-setlength, pinned v35) cleared the
  `SetLength expects a string variable in IR codegen` error. `examples/vm/vmdemo.pas`
  runs `ALL OK` on v35 (loopsum 55, iter+recursive factorial 120, subroutine
  36/81, assembler-error rejection). Wired into `make lib-test` + `make demos`.
  The clean Platonic source compiled unchanged once the compiler was fixed.
  Source committed in 56678e2; lib-test wiring + close in the math/vm batch.
