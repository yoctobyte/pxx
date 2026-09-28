---
track: A
prio: 20
type: bug
blocked-by: []
status: done
found-by: frankD (2026-09-28, Nil Python corpus differential; test_nilpy_the_sys_streams.npy differed on hosted xtensa and riscv32)
tags: [pascal, nilpy, stderr, cross-target, silently-wrong]
summary: "`WriteLn(StdErr, ...)` and Nil Python `print(..., file=sys.stderr)` wrote to STDOUT on i386, arm32, aarch64, riscv32, xtensa and wasm32. Only x86-64 read the fd the frontend puts on IR_WRITE/IR_WRITELN, and even x86-64 sent formatted floats to stdout, because the runtime writers hard-coded fd 1. Every CLI program that separates diagnostics from output was silently wrong off x86-64. Fixed in every backend. Also fixed: `WriteLn(StdErr)` with no other argument (refused before; FPC accepts it), and `sys.stderr.write` on wasm32 (Runtime error 9)."
owner: ""
---

# StdErr writes reach stdout on every target but x86-64

```
$ printf "program e; begin WriteLn(StdErr,'to-err'); WriteLn('to-out'); end.\n" > e.pas
$ pascal26 --target=i386 e.pas e && qemu-i386 ./e 2>/dev/null
to-err
to-out
```

FPC and pxx x86-64 print only `to-out`.

## Three layers, one rule

1. **Codegen.** The frontend already put the target fd in IRIVal of every
   IR_WRITE and IR_WRITELN. Only `ir_codegen.inc` (x86-64) read it, into
   CurWriteFd. The other backends' inline write syscalls hard-coded fd 1: i386
   used `EmitI32(STDOUT)`, arm32 `mov r0,#1`, aarch64 `movz x0,#1`, and riscv32
   and xtensa a literal 1. They now all take CurWriteFd.
2. **Runtime.** The builtinheap writers (pad, char, newline, decimal, bool,
   string forms and C string) called `PXXSysWrite(1, ...)`. The float and
   variant writers printed their digits with `write(...)` statements, which
   compile once, with fd 1. So even x86-64, which shims its floats onto them,
   sent `WriteLn(StdErr, 1.5:0:1)` to stdout. The writers now use `PXXOutFd`
   (0 = stdout, so the zeroed BSS is right everywhere), through
   `PXXPutC`/`PXXPutLit` where they used `write`.
3. **The wrap.** Each backend's node emitter asks `IRWriteNodeToStdErr(node)`
   (ir.inc) first. For a StdErr node it calls `PXXOutToStdErr`, sets
   CurWriteFd = 2, emits the node as before, then restores both. wasm32 does
   the same in WasmEmitWrite. A stdout write never reaches the wrap, so the
   code at a stdout write site is unchanged (the runtime writers it calls did
   change, as above). Under --threadsafe the statement is already inside the
   I/O lock, which ir.inc emits on x86-64, i386, aarch64 and arm32, so no
   other thread can see the swapped fd there.

Also fixed:

- `WriteLn(StdErr)` alone (the newline to stderr) was refused with "expected
  expression". FPC accepts it.
- Nil Python `sys.stderr.write` went through `write(StdErr, s)` in pylib, which
  there names the Text-file RTL's StdErr. On wasm32 that died with "Runtime
  error 9 (I/O error)". It now writes fd 2 directly, the same fd as
  `print(file=sys.stderr)`, so the two stay in order.

## Measured (2026-09-28, fixedpoint 274fa145eca6)

Two tests, with each stream checked alone (`2>/dev/null`, then `1>/dev/null`):

- `test/test_stderr_separation.pas` covers const, int with width, Int64,
  Boolean, Char, fixed and scientific Double, AnsiString and ShortString with
  width, `Write` pieces, and bare `WriteLn(StdErr)`. The .expected and
  .err.expected files are FPC 3.2.2's.
- `test/test_nilpy_print_to_stderr.py` covers str, int, float, bool/None,
  list/tuple, dict, an object with `__str__`, an f-string, `sep=`, `end=`,
  empty `print(file=...)` and `sys.stderr.write`. Its expectations are
  CPython's.

Both match on x86-64, i386, arm32, aarch64, riscv32, xtensa windowed, xtensa
call0 and wasm32.

Controls on the pinned v450:

- It refuses the Pascal file on `WriteLn(StdErr)`.
- The Nil Python file differs on i386 and riscv32.
- It passes the Nil Python file on x86-64, which had only the float leak.

ESP: both tests build for the C3 and S3 on the IDF profile, and the Pascal test
also builds on the bare profiles. On IDF, PXXSysWrite sends fd 1 and fd 2 both
to the console. On bare, writes emit nothing, as before. They have not been run
on a board.

## Not in this fix

The test deliberately declares no PChar variable and never names `Output`.
Either one pulls the Text-file unit, whose `StdErr` is a Text variable that
shadows the constant, and those writes go through the Text RTL. That path
already reaches the right fd. But on every target, x86-64 included, it prints a
bare Double in natural form (`2.25`, FPC prints ` 2.2500000000000000E+000`)
and a PChar as its address. That is a formatting defect of Text writes, not an
fd defect, and it is the next fix.
