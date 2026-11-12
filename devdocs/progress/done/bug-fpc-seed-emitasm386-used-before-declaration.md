---
track: core
prio: 40
type: bug
blocked-by: []
summary: "Converting raw i386 bytes in emit.inc, symtab.inc and the runtime stub emitters to EmitAsm386 broke the FPC-seeded cold-start bootstrap (full tier, advisory fpc-bootstrap: `thread_emit.inc(375,5) Error: Identifier not found \"EmitAsm386\"`). Those files are included before asmtext_386.inc; PXX's prescan is order-agnostic, FPC's is not. Fixed with forward declarations next to EmitAsmX64's, plus refusing stubs for -dPXX_NO_I386 builds."
status: done
owner: unassigned
---

# FPC seed: EmitAsm386 used before its declaration

## Found

The 2026-11-12 full tier ran on the i386 raw-byte conversion (batches i1+i2).
It was GREEN apart from the advisory fpc-bootstrap job, which failed with
`thread_emit.inc(375,5) Error: Identifier not found "EmitAsm386"`.

## Cause

compiler.pas includes emit.inc, symtab.inc and exception/coroutine/
thread_emit.inc before asmtext_386.inc. PXX resolves the call anyway. FPC
needs a declaration first. This is the same trap as
bug-a-fpc-seed-drift-emitasmx64-forward, now for the i386 assembler.

There is a second problem. A `-dPXX_NO_I386` build leaves asmtext_386.inc
out, so the i386 regions of those files would call an undefined routine.

## Fix

compiler.pas declares both EmitAsm386 overloads `forward`, next to the
EmitAsmX64 forward. Under PXX_NO_I386 it defines them as stubs that raise
Error instead. Those regions cannot run in such a build, because
`--target=i386` is refused.

## Checked

- An FPC build of compiler.pas links. The FPC-built compiler builds a PXX
  compiler that rebuilds itself to the same binary as the normal PXX build.
- The forwards change no output: the compiler is byte-identical to the one
  the full tier ran.
- A `-dPXX_NO_I386` build compiles and refuses `--target=i386` as before.
