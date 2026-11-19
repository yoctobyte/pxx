---
track: C
tags: [C, abi, emit-obj, x86-64]
prio: 50
type: bug
blocked-by: []
summary: "A C function returning a struct BY VALUE, called across a pxx/gcc object boundary, crashes in both directions. pxx returns aggregates through a hidden destination in r10 (RetViaHiddenDest) for every C function, external ones included; SysV returns a <=16-byte struct in rax:rdx (or xmm) and a larger one through a hidden pointer in rdi, returned in rax. pxx calling gcc's `struct pt mkpt(int,int)` copies 8 bytes from the address it expects in rax and gets the struct's VALUE: SIGSEGV. gcc calling pxx's mkpt gets the same crash the other way. A 24-byte struct crashes too. libc's div()/ldiv() work, through the dynamic-import classifier. The codegen comments say it outright: 'true SysV sret (rdi, and rax:rdx for 16 bytes or less) is still not modelled'."
status: done
owner: claude-dupwt
---

# A struct returned by value across a gcc object boundary crashes

Found 2026-11-14 while writing the block-scope prototype test. Measured on
x86-64 with `--emit-obj` objects linked by gcc:

```c
/* cal.c */
struct pt { int x, y; };
struct big { long a, b, c; };
struct pt mkpt(int a, int b) { struct pt p = {a, b}; return p; }
struct big mkbig(long a) { struct big r = {a, a + 1, a + 2}; return r; }
```

| caller | callee | struct | result |
| --- | --- | --- | --- |
| pxx object | gcc object | 8 bytes | SIGSEGV |
| gcc | pxx `--freestanding` object | 8 bytes | SIGSEGV |
| pxx object | gcc object | 24 bytes | SIGSEGV |
| gcc | pxx object | 24 bytes | SIGSEGV |
| pxx program | libc `div`, `ldiv` | 8/16 bytes | correct |

The crash site in the pxx caller: after `call`, it copies 8 bytes with
`rep movsb` from the address in rax, which holds the struct's value.

## Where

- Caller: ir_codegen.inc, the direct C-call arm (`ABIRetViaHiddenDestProc`
  passes the destination in r10, also for ProcExternal), and the cdecl
  indirect arm (IRCallDest -> r10).
- Callee: EmitAggregateDestStash in the prologue, and the epilogue fill.
- Done tickets nearby: bug-c-a-struct-return-across-objects-passes-no-hidden-destination
  (pxx-to-pxx across objects, which is why r10 is used for externals too).

## The fix, in outline

A C-ABI function (CProcUsesCAbi) returning a record classifies it as SysV
does, on both sides: INTEGER/SSE eightbytes come back in rax/rdx/xmm0/xmm1
and the caller stores them into its destination; MEMORY class passes the
destination in rdi (shifting the integer arguments by one) and gets it back in
rax. pxx-to-pxx calls between objects then use the same rule, so both
directions agree. aarch64 needs the same (x8 for MEMORY, x0/x1 or v0-v3 for
small/HFA); i386 and arm32 have their own rules. Nilix builds every object
with pxx, so it is not hit there today.

Nilix was named Gibux until 2026-11-17 (githome:gibux is frozen; the ticket slug keeps the old name).


# Fixed 2026-11-19 (claude-dupwt): x86-64; aarch64, i386 and arm32 still open

One oracle, asked by both sides: `ABIX64SysVRet(proc)` in abi.inc. It reuses
the existing argument classifier (ABISysVRecordEightbytes). It answers for a
ProcCdecl routine (every C function, and Pascal `cdecl`) returning a record,
on x86-64 other than --os=nt, when the record has no managed fields:

- **-1**: pxx's r10 convention, unchanged (everything else).
- **0, MEMORY** (> 16 bytes): the destination is rdi and the integer
  arguments start at rsi. Changed in the caller's direct C arm and IR_CALL_IND
  cdecl arm, the callee's EmitParamSpillsForTarget cdecl arm and
  EmitAggregateDestStash, and the variadic named-GP count, so va_start skips
  rdi. The callee already answered the destination in rax.
- **1/2 eightbytes**: the callee's EmitProcEpilog loads Result into
  rax/rdx/xmm0/xmm1 by class, and the destination copy is skipped. The caller
  stores them at its destination (IREmitSysVRetStore) and answers its address
  in rax, so every consumer downstream is unchanged. The entry copy-in of the
  destination is skipped for this class, because there is no destination.

SYSV_CLS_* moved to defs.inc: the FPC seed build is single-pass, and
symtab.inc reads them.

## Measured

test/c_struct_return_sysv_{callee,caller}.c covers 8-byte INTEGER, 3-byte,
(SSE,INTEGER), (SSE,SSE), 24-byte MEMORY, MEMORY with seven integer arguments,
a variadic MEMORY return, and calls through a function pointer:

| link | before (published a86c2819d9) | after |
| --- | --- | --- |
| pxx caller, gcc callee | SIGSEGV | = gcc |
| gcc caller, pxx callee | SIGSEGV | = gcc |
| pxx, pxx | = gcc | = gcc |

The old row csret_x also passes now with a gcc-built definition. Other checks:
c_fn_typedef_struct_ret on x86-64, i386 and aarch64; test-c-conformance,
test-lua and test-quickjs pass; gate quick passes. The self-host is unchanged
in behaviour (the compiler is Pascal with no cdecl record results). test-core
stops at freebsd_kernel_entries (5 vs 2), which the published compiler gives
too, so it predates this change.

## Still open

aarch64 (x8 for MEMORY; x0/x1 or v0-v3 for small and HFA), i386 and arm32
keep pxx's own convention, so the same crash exists there across a gcc
boundary. Pascal `{$L obj}` does not link an object into a pxx program (the
symbol became a dynamic import), so Pascal-to-gcc was checked only by reading
the predicate, which covers cdecl.
