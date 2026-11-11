---
track: A
prio: 50
type: perf
blocked-by: []
summary: "x86-64 scope-exit cleanup took the heap lock and called PXXDynArrayRelease for EVERY dynamic-array local on every return, including slots that were nil because that path never filled them. Every `[...]` argument site owns a hidden dyn-array temp, so a big routine paid one full release call per constructor site per invocation: IREmitNode made 18.8 M release calls in one compile of lib_charset.pas. A nil slot now skips the sequence (`test rax, rax / jz`). The compiler's instruction count on that compile fell 14% (2.676 G -> 2.294 G), with output byte-identical."
status: done
owner: unassigned
---

# Scope-exit cleanup released every nil dyn-array temp

## Found

This turned up while profiling the compile-time cost of the raw-asm conversion
(refactor-x86-64-raw-emitb-to-the-text-assembler.md, 2026-11-11). Converting
~110 more `EmitB` lines to `EmitAsmX64([...])` added +4.8% compiler
instructions. Almost all of it showed up as `PXXDynArrayRelease`, and almost
none as encoding work: the whole-call memo had removed that.

The compiler binary has no symbols. The callgrind addresses were symbolized
with the `.map` file written beside the binary. Callers of
PXXDynArrayRelease, from callgrind's call records:

| caller | calls |
|---|---|
| IREmitNode | 18,775,433 |
| EmitLoadVar | 243,575 |
| EmitStoreVar | 62,066 |
| (all others) | < 20,000 each |

## Cause

`AN_VARREC_ARRAY` and `AN_ARRAY_CTOR` lower each constructor site to a hidden
dyn-array temp that lives for the whole routine. That is the fix for
done/bug-a-an-array-constructor-in-argument-position-leaks-its-dynamic-array.md.
The SXR_DYNARR arm of EmitManagedLocalCleanup released each one on every exit:
load the slot, acquire the heap lock, call PXXDynArrayRelease, release the
lock. The callee returns at once for nil, but the call, the argument set-up
and the lock were paid regardless. IREmitNode has hundreds of constructor
sites and runs once per IR node, so the bill was hundreds of calls per node.

## Fix

symtab.inc, SXR_DYNARR arm: `mov rax, [rbp+off] / test rax, rax / jz` around
the lock and release. The jump is a forward rel32 scope label, so the length
of the lock sequence under --threadsafe does not matter.

## Measured

Callgrind, `pascal26 -O2 test/lib_charset.pas`, instruction totals:

| compiler | instructions |
|---|---|
| raw-asm batch 2 (before the conversions) | 2.494 G |
| batch 23 without this fix | 2.676 G |
| batch 23 with this fix (stage-2 build) | 2.294 G |

The compiled output is byte-identical with and without the fix. The fix
reaches the compiler only through a compiler built by a compiler that has it,
so the measurement is of the stage-2 binary.

The remaining per-call cost of building the constructor array on the heap is
in backlog-core/perf-an-open-array-constructor-argument-is-heap-built-per-call.md.
