# TThread Execute that writes (writeln) crashes nondeterministically

- **Type:** bug (thread runtime / M0) — Track A
- **Status:** backlog — **the** current M0 blocker for "threads just work"
- **Opened:** 2026-07-02, found while landing the --threadsafe I/O statement
  lock (feature-threadsafe-io-serialization): the threaded-interleave
  acceptance test crashed — and the crash reproduces on pinned v145 WITHOUT
  the lock, so it is pre-existing and unrelated to the new I/O lock.

## Repro (crashes on pinned v145 and on v146, --threadsafe)

```pascal
program tio2;
uses palthreadobj;
type TW = class(TThread) procedure Execute; override; end;
procedure TW.Execute;
var i: Integer;
begin
  for i := 1 to 100 do writeln('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
end;
var a, b: TW;
begin
  a := TW.Create; b := TW.Create;
  a.Start; b.Start;
  a.WaitFor; b.WaitFor;
  writeln('done');
end.
```
Two threads, writeln of a plain LITERAL only → SIGSEGV before any output,
nondeterministic faulting site. The existing make test-threads suite never
noticed because none of its Execute bodies perform I/O (they count/lock/join
and writeln only from the main thread after WaitFor).

## Evidence so far (gdb, one sample)

A SPAWNED thread (not main — main never reached its WaitFor breakpoint)
faults reading a byte field at `[rax]` with rax = a small integer (43), in
code shaped like a method prologue reading `Self+0x28` (FStarted-like
offset) — i.e. something in the thread path runs with a garbage
Self/pointer. Suspects, unverified:
- writeln machinery clobbering registers/scratch the thread context relies
  on (BSS INTBUF / write helpers are shared, but a literal write should be
  a bare syscall...);
- thread stack setup vs. the write path's stack expectations
  (__pxxclone trampoline, mmap stack alignment?);
- managed-literal materialization racing the heap despite the heap lock.

## Where to start

Reduce further: single thread (a only) with writeln in Execute; writeln
replaced by a raw __pxxrawsyscall write; literal vs int arg. Then rr the
2-thread case (rr serializes threads but preserves the bug class often).
The new I/O statement lock (v146) is in place and single-thread-verified;
once this crash is fixed, the interleave acceptance test
(scratchpad tio.pas shape: two threads x 200 lines, every line must match
^(A{60}|B{60}|done)$) becomes the gate for BOTH tickets.

## Resolution — 2026-07-02, hunted down same day (v147)

**writeln was a complete decoy.** Bisection: one thread with writeln crashed;
two threads with NO I/O crashed; the passing suite test differed in one
detail — it called `TWorker.Create(True)` while the crashing repros called
bare `TW.Create`, missing the required `CreateSuspended` argument. That
should be a compile error (FPC) — pxx's class-construction parse collected
whatever args were present with NO arity check.

**Actual mechanism** (ir_codegen.inc ctor marshalling): the push loop pushes
Self + the args ACTUALLY GIVEN; the pop loop pops exactly `ParamCount`
registers. One missing argument = one extra pop = the caller's stack
desynced by 8 bytes; every subsequent pop in the enclosing expression reads
shifted garbage — hence garbage Self, nondeterministic fault sites, and a
crash that moved when the program changed. Reproduced with a plain class,
no threads: `TC.Create` (1-param ctor, 0 args) = same silent compile, same
crash.

**Fix**: compile-time constructor arity check in the construction parse —
missing required args and extra args are now clean errors (FPC parity),
with trailing-default fill wired for when class methods gain default
params (declaring them is currently a separate parser gap). The codegen
marshalling is untouched — it is correct once the arg count is right.

Gates: test/test_ctor_arity_error.pas (must-not-compile, message grepped) in
make test; test/test_thread_writeln_interleave.pas in make test-threads —
the original crashing shape, now also the I/O-lock acceptance (401/401
atomic lines under --threadsafe; without the flag the same binary shows
~98% mixed lines, demonstrating the lock is what serializes). Suite +
threads green; self-host byte-identical; pinned v147.
