---
track: A
prio: 70
status: backlog
type: perf
blocked-by: []
summary: "MEASURED, two independent methods agreeing. `EmitManagedLocalCleanup` releases EVERY managed local at EVERY return, whether or not that path ever touched it, and the sweep is emitted INLINE at each return. Two separable costs, and conflating them will misdirect the fix: (1) RUNTIME — the full sweep EXECUTES on every call, measured linear at 3.87ns per local per call even when every slot is nil, which is ~4.5% of a compile for ParseFactorCore's 532 locals alone; (2) CODE SIZE — 308,112 release call sites binary-wide = ~36% of the compiler's 10.2MB .text. A shared epilogue fixes (2) and NOT (1): the sweep still runs in full. (1) needs per-path liveness. Found from the Track P ticket perf-p-parsefactorcore-walks-a-92-arm-name-chain-per-factor, whose premise this refutes for the third time."
---

# Every return releases every managed local, including untouched ones

`EmitManagedLocalCleanup` (`compiler/symtab.inc:12212`, the x86-64 arm;
`EmitManagedLocalCleanupForTarget` in `ir_codegen.inc:13643` for the other five)
loops `for i := Procs[CurProc].ScopeBase to SymCount - 1` and emits, per scalar
`tyAnsiString` local:

```
mov rax, [rbp+off]        ; symtab.inc:12316
call AnsiStrReleaseAddr   ; symtab.inc:12317
```

It is reached from `EmitProcScopeExitCleanupForTarget`, which
`EmitProcEpilog` calls, and `EmitProcEpilog` is emitted **inline at every
return** — its own comment says so: *"Reached by every return (early Exit and
fall-through both go through EmitProcEpilog)."*

## The measurement — `ParseFactorCore`, the worst case

Binary `p26-g-O2` built `-O2 -g` from `compiler/pascal26` at `a1536a832`
(`code=10178328B`, **identical to the plain default build**, so `-g` did not
change codegen and this is the shipping configuration). Workload: a zero-byte
`.npy`, i.e. parsing `pylib.pas` + `pyeval.pas`. `wall=1.87 user=1.81` — pure
user CPU, so the `<outside .text/vdso>` bucket is noise and every share below is
renormalised on in-`.text` samples, per `tools/pxxprof`'s own warning. It swung
17.0% / 23.2% / 47.3% across three identical runs; the renormalised numbers
moved 0.43pp.

`ParseFactorCore` is **9.92% / 9.94% / 10.35%** of in-`.text` samples over three
runs — i.e. **unchanged** from the 9.44% that opened the Track P ticket, so
`440c822e6` did not remove it.

Its extent is **1,146,385 bytes**, agreed by two independent symbol sources
(DWARF, and the compiler's own `.map`, 4143 entries, exactly one of which lands
in the range). Disassembled:

- **80,385** `call AnsiStrRelease` sites, in **exactly 150 runs of exactly 532**
  — mean = median = max. 532 string locals, 150 return points, every return
  releasing all 532.
- That chain is **84% of the function's bytes** and **36.1% of the samples that
  land in it**.

## The independent confirmation, which is what separates the two costs

A function with N `AnsiString` locals that assigns exactly one of them and
returns, 2M calls, min of 3 interleaved rounds:

| N locals | ms |
| --- | --- |
| 4 | 218 |
| 64 | 653 |
| 256 | 2192 |
| 532 | 4300 |

Linear: **3.87ns per local per call** (~11.6 cycles — `mov`/`call`/`test`/`je`/
`ret`), paid for slots that are **nil and were never touched**. The release
thunk's own fast path is `test rax,rax; je` — it is already as cheap as a call
can be, which is why the fix is not in the thunk.

Cross-check against the profile: 41,032 `ParseFactorCore` calls x 532 slots x
3.87ns = **84.5ms of 1870ms = 4.5%** of the compile. The sampling method said
~3.6% on the chain's own instructions plus a share of the release thunk's 8.1%.
**Two methods that fail differently, agreeing.**

### This is why a shared epilogue is only half a fix

The scaling table's teardown is ~6.4KB and contiguous — i-cache resident, no
150-fold duplication — and it still costs 3.87ns per slot. So the cost is the
**executed** releases, not the duplicated code. Emitting the sweep once and
jumping to it would cut ~36% of `.text` and change the runtime very little.
Cutting the runtime needs the sweep to skip slots that cannot be non-nil on the
path being taken.

## Scope, binary-wide

**308,112** `call AnsiStrRelease` sites in the whole compiler. At 12 bytes per
`mov`+`call` that is ~3.7MB of 10.18MB `.text` — **~36%**.

## What this does NOT say

Nothing here is a leak and nothing is wrong: releasing an untouched nil slot is
correct, just unnecessary. **Any fix must keep the sweep conservative** — the
guards in `EmitManagedLocalCleanup` are load-bearing and each was a real leak
(`not IsArray` on the AnsiString and Variant arms, both measured). A liveness
pass that is wrong in the *other* direction is a leak, not a slowdown, and
`test_open_array_no_leak.pas` shows an output assertion cannot see one:
use `tools/assert_no_leak.sh`.

## Gate

Track A's, plus the sharp oracle the Track P ticket named: `compiler.pas` in,
`cmp` the two emitted binaries. A cleanup change must not alter one emitted byte
for a program whose paths all touch every local.
