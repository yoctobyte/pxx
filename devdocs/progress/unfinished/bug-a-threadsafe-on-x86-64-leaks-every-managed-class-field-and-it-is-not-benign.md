---
track: A
prio: 55
type: bug
blocked-by: []
summary: "`--threadsafe` on x86-64 gates PXXClassFinalize's string/dynarray pass off (PXX_TS_HARDLOCK), so EVERY managed field of EVERY destroyed class instance leaks: 392 kB -> 398336 kB on 200k instances, in plain Pascal. MEASURED 2026-08-31: the guard is LOAD-BEARING — deleting it segfaults 3/3 at NT=4 and runs clean 3/3 at NT=1, so it is a real allocator race, not a double free. test_threadsafe_class_finalize_race.pas is the positive control, green today. Parked with the fix shape and the kind-6 recursion constraint that kills the one-line version."
status: unfinished
owner: frankS
---

# --threadsafe leaks every managed class field on x86-64, and "benign" was never measured

- **Track A** (heap lock discipline + `compiler/builtin/builtinheap.pas`).
  Measured 2026-08-31 by frankS while verifying that two NilPy leak fixes held
  under `--threadsafe`; they do, and this was underneath them.
- Not a regression and not new. It is the RESIDUAL that
  `bug-a-class-managed-fields-not-finalized-on-destroy` (done) recorded as kept
  out on purpose — *"the hardlock string case keeps the pre-existing benign
  leak instead of racing the allocator"*. That was the right call at the time.
  What was never done is put a number on it.

## The repro — plain Pascal, no NilPy

```pascal
program tsleak;
type THolder = class S: AnsiString; constructor Create(base: AnsiString); end;
constructor THolder.Create(base: AnsiString); begin S := base + '!'; end;
var h: THolder; k, i: Integer; b: AnsiString;
begin
  b := ''; for i := 1 to 2000 do b := b + 'x';
  k := 0;
  for i := 1 to 200000 do begin h := THolder.Create(b); k := k + Length(h.S); h.Free; end;
  WriteLn(k);
end.
```

| build | max RSS |
| --- | --- |
| `pascal26 -Fulib/rtl tsleak.pas` | **392 kB** |
| `pascal26 -Fulib/rtl --threadsafe tsleak.pas` | **398336 kB** |

Same source, same printed answer (`400200000`), 1016x the memory. It is the
whole field payload, every instance, forever.

## Mechanism, and it is one `{$ifndef}`

`PXXClassFinalize` (builtinheap.pas) ends with

```pascal
{$ifndef PXX_TS_HARDLOCK}
  PXXRecordRelease(inst, desc);
{$endif}
```

`PXX_TS_HARDLOCK` is defined by `--threadsafe` on x86-64 only (lexer.inc:1168).
The stated reason is real: on that target the heap lock is the **codegen-emitted
BSS spinlock**, which Pascal-level runtime code cannot take, so releasing from
Pascal would race the allocator. The kind-4 (COM interface) pass above it is
NOT gated and does run.

## MEASURED 2026-08-31 (frankS) — the guard is LOAD-BEARING. Do not delete it.

I set out to show the guard was over-broad, on the reasoning that
`PXXStrDecRef`, `PXXObjRelease` and `PXXDynArrayRelease` all reach `PXXFree`
from Pascal with no `PXX_TS_HARDLOCK` gate, so one more caller could not be a
new hazard class. **That reasoning was wrong and the experiment says so.**

`test/test_threadsafe_class_finalize_race.pas` (added with this note, wired into
`test-threads`): NT threads each build a `THolder` whose AnsiString field is
filled with a thread-unique char, read it back, and `Free` it. Three runs each:

| build | NT | result |
| --- | --- | --- |
| guard ON (HEAD) | 4 | `errors=0 RACE OK` — 3/3 |
| guard removed | 4 | **SIGSEGV** — 3/3 |
| guard removed | 1 | `errors=0 RACE OK` — 3/3 |

The NT=1 row is the one that matters: unguarded, the pass is CORRECT
single-threaded, so this is a genuine allocator race and not a double free.
Removing the guard also does fix the leak exactly — the 200k-instance probe goes
398336 kB -> **392 kB**, identical to a non-threadsafe build. So both halves are
confirmed: the guard costs the whole leak, and it buys real safety.

## What is now known about the fix, and the constraint that kills the easy one

- **No caller of `PXXClassFinalize` holds the lock.** Stated at
  `ir.inc:11191` — *"The call is NOT under the heap lock — the codegen's lock
  wrap covers only the FreeMem emission itself"* — and true for the NilPy route
  too (`PXXObjRelease` frees unlocked). So a fix MAY take the lock; it will not
  self-deadlock on entry.
- **But it cannot hold it across the whole walk in a NilPy compilation.**
  `PXXRecordRelease`'s kind-6 arm calls `PXXObjRelease` -> the finalize hook ->
  `PyObjFinalize` -> `PXXClassFinalize` again. A non-reentrant spinlock held
  across that self-deadlocks. In PASCAL mode there is no kind 6 and kinds 1-3
  call no user code, so a held lock is safe there — which makes a Pascal-mode-
  only fix strictly easier than the general one.
- **Precedent for the shape exists**: `IR_DEFAULT_MEM` (ir_codegen.inc:2660)
  already does `EmitAcquireHeapLock; EmitManagedRecordReleaseLocked(recId);
  EmitReleaseHeapLock` — a codegen-emitted, lock-wrapped managed-field release.
  It is static-typed, so it cannot serve a polymorphic `Free` directly, but it
  proves the wrap is expressible where the lock lives.
- **The blocker for the obvious version** is that the finalize is injected as an
  IR call in `ir.inc`, and there is no IR op for "acquire the heap lock", so the
  wrap has to be emitted by codegen — which at `procIdx = -Ord(tkFreeMem)`
  (ir_codegen.inc:8541) does not know the operand is a class instance.

## The shape a fix would take

Split `PXXClassFinalize` into `...Intf` (kind 4, called unlocked exactly as
today — its destructor chain reaches a codegen-wrapped `FreeMem` and MUST NOT be
under the lock) and `...Managed` (kinds 1-3, requiring the caller to hold the
lock), then emit the second from codegen inside the existing `tkFreeMem` wrap,
with the class-ness plumbed through so codegen can tell. NilPy stays on the
leaking path until the kind-6 recursion has a reentrant lock or a depth
counter — which needs per-thread state, i.e. `feature-threadsafe-heap-optimize`'s
TLS work.

**Parked here rather than microfixed.** Every remaining step is real design in
the heap contract, and the one-line version is now measured to segfault.

## Two directions, neither verified — do not pick one from this ticket

1. **Give Pascal a way to take the lock.** The blob route already exists in the
   opposite direction: `AnsiStrReleaseAddr` is a codegen-emitted blob that
   acquires and releases the spinlock around exactly this kind of work, and
   scope-exit epilogues call it under `--threadsafe` today. If a Pascal-callable
   acquire/release pair is expressible, the `{$ifndef}` goes away. **First
   question to measure: what else already frees from Pascal under
   `--threadsafe`, and why is that safe?** If the answer is "quite a lot", the
   guard is over-broad rather than load-bearing.
2. **Emit the field walk as codegen** at the `Free` desugar, where the lock is
   reachable. Correct by construction, and a much larger change — it duplicates
   a walker that exists once today.

## Also in scope, same constraint, named in the done ticket

RECORD COM-interface fields are the same benign-by-assertion leak under the
same lock. Whoever measures one should measure the other.

## Why this is filed rather than fixed

The `{$ifndef}` is one line and deleting it is a data race, not a fix. The
work is establishing which of the two directions is sound, and that is
measurement plus a lock-discipline judgement — not a microfix.
