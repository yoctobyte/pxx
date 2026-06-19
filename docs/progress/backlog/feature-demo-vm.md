# Demo — bytecode VM + assembler (small ISA)

- **Type:** feature
- **Status:** backlog
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
