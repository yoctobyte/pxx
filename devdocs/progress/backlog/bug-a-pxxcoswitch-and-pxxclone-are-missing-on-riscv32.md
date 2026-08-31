---
slug: bug-a-pxxcoswitch-and-pxxclone-are-missing-on-riscv32
track: A
type: bug
prio: 25
status: backlog
found: 2026-08-31
found-by: frank-rust
owner: unassigned
blocked-by: []
summary: "`__pxxcoswitch(@a, @b)` compiles for x86-64 and arm32 and gives `pascal26: error: target riscv32: unsupported node in IR codegen: coswitch` on riscv32; `__pxxclone` has the same missing arm. Compile-time error, not a wrong answer. Found while auditing what else riscv32 lacked after adding IR_RTTI_REG/IR_RESOURCES — the other four absent node kinds are all unreachable on riscv32, these two are not."
---

# `__pxxcoswitch` and `__pxxclone` have no riscv32 arm

`compiler/ir_codegen_riscv32.inc` handles 58 IR node kinds; aarch64 handles 65.
Six of the seven-way difference are `IR_CLONE`, `IR_COSWITCH`, `IR_IMTADDR`,
`IR_IO_LOCK`, `IR_IO_UNLOCK`, `IR_MULHI`. (The seventh, `IR_WRITELN`, was a
false positive — it is the trailing label of `IR_WRITE, IR_WRITELN:`.)

**Four of the six cannot be reached on riscv32**, so they are not bugs:

- `IR_MULHI` — `ir.inc:7781` errors at the emission site for any non-64-bit
  target and points at `MulHiU64` in lib/rtl.
- `IR_IO_LOCK` / `IR_IO_UNLOCK` — `ir.inc:13213` gates them to
  x86-64/i386/aarch64/arm32 under `--threadsafe`.
- `IR_IMTADDR` — no emitter anywhere in the frontend, and interface dispatch
  through a `TInterfacedObject` runs correctly on riscv32 today (verified).

**Two are reachable.** `AN_COSWITCH` (`pasparser_expr.inc:4132`,
`pasparser_stmt.inc:5056`, `pyparser.inc:46140`) and `AN_CLONE`
(`pasparser_expr.inc:4170`, `pyparser.inc:46178`) are ungated builtins.

## Repro

```pascal
program cosw;
var a, b: Pointer;
begin
  a := nil; b := nil;
  __pxxcoswitch(@a, @b);
  WriteLn('back');
end.
```

```
$ pascal26 cosw.pas cn                     # ok
$ pascal26 --target=arm32 cosw.pas ca      # ok
$ pascal26 --target=riscv32 cosw.pas cr
pascal26:7: error: target riscv32: unsupported node in IR codegen: coswitch
```

## Suspected site

`compiler/ir_codegen_riscv32.inc`. Donor arms: `ir_codegen_arm32.inc` handles
both, and it is the closer model than aarch64 — same 32-bit pointer width, same
`IR_ARG` chain shape (`ir.inc:7692` for coswitch, `ir.inc:7711` for clone).
`IR_CLONE`'s comment names the SysV arg regs, so the register mapping is the
part that has to be re-derived for the RISC-V calling convention rather than
copied.

Low priority: both are low-level builtins with no in-tree riscv32 caller. The
failure is loud and at compile time.
