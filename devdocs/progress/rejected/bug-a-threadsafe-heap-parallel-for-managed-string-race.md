---
prio: 70
track: A
status: rejected
---

# REJECTED — not a heap bug: was a shared captured-variable data race

- **Type:** bug (filed) → **rejected** (wrong premise, corrected same day).
- **Filed / rejected:** 2026-07-17.

## What was filed

A `parallel for` whose body did `s := s + s` on an `AnsiString` SIGSEGV'd ~40%
of runs on x86-64 native and corrupted string lengths otherwise. It was filed as
a threadsafe-heap concurrency bug.

## Why it is NOT a bug

`s` was declared in the ENCLOSING procedure's `var` block, so `parallel for`
captures it **by-ref via the frame pointer** — it is ONE shared variable, and
every worker was writing it concurrently. That is a user data race, not a heap
fault. The exact hazard `test_parallel_for_capture.pas`'s `WriteCap` avoids by
calling `PXXSetParForWorkers(1)` before a captured-scalar write ("deterministic:
one worker, no reduction race"). A racing managed handle segfaults (double-free /
use-after-free on the refcount) — expected UB for a shared-write race, the same
as FPC/OpenMP.

## Proof the heap is actually thread-safe

Move the per-worker string work into a FUNCTION — its locals live on each
worker's OWN stack (private per call), disjoint result slots — and it is clean:

```pascal
function Work(i: Integer): Integer;
var s: AnsiString;
begin s := 'abcdefghij'; s := s + s + s + s; s := s + s; Work := Length(s); end;
...
parallel for i := 0 to 399 do if Work(i) <> 80 then bad[i] := 1;
```
x86-64 native 10/10 clean; aarch64/i386/arm32 5/5 clean. Concurrent
alloc/concat/free from workers is safe as long as each worker uses PRIVATE
storage (function locals or disjoint pre-allocated slots).

## Real (much smaller) takeaway

The footgun is silent: writing a captured MANAGED var from multiple workers
compiles with no diagnostic and crashes at runtime. A compile-time warning when a
captured managed variable is WRITTEN inside a multi-worker `parallel for` body
(or a first-class per-worker/private + reduction facility) would help. Tracked as
a DX/feature idea under [[meta-multithreading]], not a bug. See also
[[project_com_interface_default_and_lifetime]] (refcount lifetime).
