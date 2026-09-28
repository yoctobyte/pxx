---
slug: bug-a-an-unhandled-exception-prints-no-class-or-message-on-the-cross-backends
title: "An unhandled exception prints no class or message on i386/aarch64/arm32/riscv32"
summary: "x86-64 prints `Unhandled exception: Exception: frame chain is intact` on stderr; i386, aarch64, arm32 and riscv32 print only `Unhandled exception` (exit 217 on all). The detail line is emitted in exception_emit.inc's x86-64 arm (and wasm32's) only; the other backends' unhandled blocks were never taught it. Not a wrong value -- a diagnostic the cross targets lose, which is what makes a crash under qemu or on a board undebuggable."
track: A
type: bug
prio: 30
status: backlog
found: 2026-09-28
found-by: frankD (Pascal cross-target differential over the test corpus)
---

## The fact

`test/test_goto_within_exception_region.pas` (and the two
test_handler_early_exit_* tests), native vs `--target=i386` under qemu:

```
native:  Unhandled exception: Exception: frame chain is intact
i386:    Unhandled exception
```

Same on aarch64, arm32 and riscv32; stdout and the exit code (217) agree.

## Where

compiler/exception_emit.inc: the x86-64 arm prints the bare line, then a
detail line reading the class name from the RTTI blob and the message from the
object's first field, every read range-guarded (its comment gives the layout).
The i386 arm (~line 309), and the arm32/riscv32/aarch64 arms after it, print
the bare line and a newline only. wasm32 has its own detail printer
(ir_codegen_wasm32.inc ~8221).

## What a fix does

Port the guarded detail read to each backend, or better, call one RTL routine
(Pascal, in the runtime) that formats the line from the object, so the five
arms stop being five copies. Measure against the x86-64 text on each target.
