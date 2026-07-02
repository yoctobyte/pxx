# riscv32 hosted: exception machinery (raise/try) — last wall before chess

- **Type:** feature (target bring-up)
- **Track:** A — `compiler/exception_emit.inc`, `compiler/ir_codegen_riscv32.inc`
- **Status:** backlog
- **Opened:** 2026-07-02

## Problem

With the riscv32 hosted leg brought up (writeln/read/eof/exit, syscalls,
set ops, in-operator, Int64 neg/l2d, stack args — 2026-07-02), the ONLY
remaining compile error for the stackless chess demo on hosted riscv32 is:

```
error: target riscv32: unsupported node in IR codegen: raise
```

exception_emit.inc's riscv32/xtensa branch is a stub (ExcRaise = EmitExit(1)),
and the backend lowers none of IR_EXC_ENTER/LEAVE/RAISE/EXC_STORE/EXC_MATCH/
EXC_CLEAR. sysutils raises (EConvertError etc.), so anything pulling sysutils
is walled.

## Scope

- Mirror the i386/arm32 setjmp/longjmp-frame design (32-byte per-frame,
  BSS_EXC_* chain) for riscv32: ExcSetJmp/ExcLongJmp/ExcRaise stubs saving
  callee-saved regs + sp + ra, and the 7 IR_EXC_* cases in the backend.
- Acceptance: test/test_exception.pas (whichever the i386 gate runs)
  output-identical on riscv32; stackless chess --selftest byte-identical on
  hosted riscv32.

## Log
- 2026-07-02 — Filed by Track A during riscv32 hosted bring-up.
