---
prio: 70
track: A
---

# `--threadsafe` heap races: concurrent managed-string alloc from parallel-for workers → SIGSEGV + silent corruption (ALL targets)

- **Type:** bug — runtime/heap concurrency. Track A (threadsafe heap/ARC).
- **Found:** 2026-07-17, while verifying the I/O lock for a parallel demo.
- **Severity:** HIGH. Crashes (SIGSEGV) on x86-64 **native** ~40% of runs;
  silently corrupts managed-string contents/lengths the rest. Not a qemu
  artifact — reproduces on the primary target with no emulation.

## Symptom

A `parallel for` whose body allocates/concats managed `AnsiString`s (per-worker,
each worker's own local string — NO shared handle) corrupts or crashes. Minimal
x86-64 native repro:

```pascal
program min; uses palparallel;
type TA = array[0..399] of Integer;
var bad: TA;
procedure Run;
var i: Integer; s: AnsiString;
begin
  for i:=0 to 399 do bad[i]:=0;
  parallel for i:=0 to 399 do
  begin
    s := 'abcdefghij';     { 10 }
    s := s + s + s + s;    { 40 }
    s := s + s;            { 80 }
    if Length(s) <> 80 then bad[i]:=1;
  end;
end;
var i, c: Integer;
begin
  Run; c:=0; for i:=0 to 399 do c:=c+bad[i];
  writeln('corrupt=', c, ' of 400');
end.
```
`pascal26 --threadsafe min.pas out; ./out` over ~8 runs:
```
exit=139 (SIGSEGV, no output)          <- ~40%
corrupt=209 of 400                     <- silent length corruption
corrupt=0 of 400                       <- occasionally clean
```
aarch64/arm32 (qemu): SIGSEGV / SIGBUS most runs. i386: silent length
corruption (`lenwrong` 12..53 of 200), no crash observed.

**Iteration distribution is CORRECT** (`miss=0 dup=0` — every index runs exactly
once); the fault is purely in the managed heap under concurrency, NOT the
parallel-for work split.

## Scope boundary (what IS safe)

- Statement-atomic console I/O works: writeln from parallel-for workers is
  atomic on all 4 arches (`test_parallel_writeln_atomic.pas`, gated).
- Data-parallel bodies writing PRE-ALLOCATED arrays/strings (no per-worker heap
  alloc) are fine — that is why `test_parallel_for_capture*` pass reliably.
- Only concurrent **allocation/free/refcount** of managed values from workers
  races.

## Likely root cause (needs pinning)

Every arch defines a heap lock — x86-64 `PXX_TS_HARDLOCK` (codegen-emitted BSS
spinlock at `BSS_HEAP_LOCK`), i386/aarch64/arm32 `PXX_TS_SOFTLOCK`
(`PXXHeapSpin` via `__pxxatomic_xchg` inside `PXXAlloc`/`PXXFree`), refcounts via
`__pxxatomic_*` (`lexer.inc` ~848). So a lock exists yet corruption persists —
suspects:
1. A managed-string helper path (`PXXStrConcat` / COW realloc / temp free /
   `PXXStrDecRef` free-on-zero) that touches `FreeBins`/`HeapPtr` WITHOUT taking
   the lock, or drops it too early.
2. The x86-64 hand-emitted spinlock not wrapping the alloc sites reached from
   inside string helpers (only the codegen top-level call site).
3. Refcount atomic vs the allocator lock not composing: decref-to-zero reads the
   count atomically then frees under the heap lock, but the check→free window
   races another worker's incref (classic refcount TOCTOU) — a shared interned
   empty/literal handle (`PXXEmptyChar`, literal blobs) would expose this even
   though each `s` is "local".

## Direction

Instrument `builtinheap.pas` alloc/free/refcount entry+exit with the lock state;
find the unlocked (or early-unlocked) path. Likely fix = ensure EVERY heap
mutation (incl. those reached transitively from string concat/COW/free) is under
the same lock, and close the decref→free TOCTOU. Gate = the minimal repro clean
1000× on x86-64 native + aarch64/arm32/i386 under qemu, self-host byte-identical,
cross. Then flip a stress version into the managed test tier.

See [[project_heap_size_class_allocator]], [[project_com_interface_default_and_lifetime]]
(refcount lifetime), [[meta-multithreading]].
