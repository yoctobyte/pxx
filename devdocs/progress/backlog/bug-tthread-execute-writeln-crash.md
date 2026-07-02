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
