---
track: C
tags: [C, abi, emit-obj, x86-64]
prio: 50
type: bug
blocked-by: []
summary: "A C function returning a struct BY VALUE, called across a pxx/gcc object boundary, crashes in both directions. pxx returns aggregates through a hidden destination in r10 (RetViaHiddenDest) for every C function, external ones included; SysV returns a <=16-byte struct in rax:rdx (or xmm) and a larger one through a hidden pointer in rdi, returned in rax. pxx calling gcc's `struct pt mkpt(int,int)` copies 8 bytes from the address it expects in rax and gets the struct's VALUE: SIGSEGV. gcc calling pxx's mkpt gets the same crash the other way. A 24-byte struct crashes too. libc's div()/ldiv() work, through the dynamic-import classifier. The codegen comments say it outright: 'true SysV sret (rdi, and rax:rdx for 16 bytes or less) is still not modelled'."
status: backlog
owner: unassigned
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
small/HFA); i386 and arm32 have their own rules. Gibux builds every object
with pxx, so it is not hit there today.
