unit scheduler;
{ Cooperative single-thread coroutine scheduler (PXX-only; never used in
  compiler.pas, per the FPC/PXX boundary).

  Built on two pieces: the low-level __pxxcoswitch context-switch intrinsic and
  procedural types. Each coroutine owns a heap stack and a saved stack pointer.
  Spawn plants @CoStart as a fresh stack's first return address; the scheduler
  hands the entry proc + arg off through gEntry/gArg right before the first
  switch-in, and CoStart calls entry(arg) through a proc-typed variable. No
  per-target entry shim is needed — the call goes through the normal procedural
  call path.

  Single OS thread, cooperative: a coroutine runs until it calls CoYield (back to
  the scheduler) or its entry returns (marked done, stack freed). RunUntilDone
  round-robins the runnable set until all finish.

  Works on x86-64, i386, aarch64 and arm32 — the only per-target piece is the
  initial-frame layout below (CoSwitch itself lives in the compiler). }

interface

type
  TCoroEntry = procedure(arg: Pointer);

procedure Spawn(entry: TCoroEntry; arg: Pointer);
procedure CoYield;
procedure RunUntilDone;

{ Async-I/O reactor (x86-64 only for now). The fd must be non-blocking; on an
  EAGAIN, the coroutine calls WaitReadable/WaitWritable, which parks it on the
  scheduler's epoll instance and yields. RunUntilDone's idle path epoll_waits
  and wakes the coroutines whose fds became ready. On other targets these
  degrade to a plain CoYield (busy-poll). }
procedure WaitReadable(fd: Integer);
procedure WaitWritable(fd: Integer);
procedure SetNonBlocking(fd: Integer);

implementation

const
  MAX_CO = 64;
  CO_STK = 65536;   { per-coroutine heap stack }

{$ifdef CPUX86_64}
const
  SYS_fcntl         = 72;
  SYS_epoll_create1 = 291;
  SYS_epoll_ctl     = 233;
  SYS_epoll_wait    = 232;
  O_NONBLOCK    = $800;
  F_SETFL       = 4;
  EPOLL_CTL_ADD = 1;
  EPOLL_CTL_DEL = 2;
  EPOLLIN       = $001;
  EPOLLOUT      = $004;

type
  { Linux epoll_event is packed: u32 events then u64 data = 12 bytes. The data
    word carries the waiting coroutine's id straight back from epoll_wait. }
  TEpollEvent = packed record
    events : LongWord;
    data   : Int64;
  end;
{$endif}

type
  PW = ^NativeInt;  { pointer-sized machine-word access at an address }

var
  coSp    : array[0..MAX_CO-1] of Int64;       { saved stack pointer }
  coStk   : array[0..MAX_CO-1] of Int64;       { heap stack base (for FreeMem) }
  coState : array[0..MAX_CO-1] of Integer;     { 0=free 1=runnable 2=done 3=io-blocked }
  coEntry : array[0..MAX_CO-1] of TCoroEntry;  { body to run on first switch-in }
  coArg   : array[0..MAX_CO-1] of Pointer;
  coCount : Integer;
  curCo   : Integer;                           { running coroutine, -1 = scheduler }
  schedSp : Int64;                             { scheduler's own saved sp }
  gEntry  : TCoroEntry;                        { handoff to CoStart }
  gArg    : Pointer;
  epfd    : Integer;                           { epoll instance, -1 = not created }

{ First-entry trampoline. Runs on the coroutine's own stack the first time the
  scheduler switches into it; the scheduler set gEntry/gArg just before. After
  the body returns, mark done and switch back — this never returns. }
procedure CoStart;
var e: TCoroEntry; a: Pointer;
begin
  e := gEntry;
  a := gArg;
  e(a);
  coState[curCo] := 2;
  __pxxcoswitch(@coSp[curCo], @schedSp);
end;

{ Build the initial saved-state frame the first CoSwitch-in pops. The slot order
  must mirror the per-target CoSwitch's pop sequence (see coroutine_emit.inc):
  exc_top first (lowest address, popped first), then the callee-saved registers,
  then the return address (= CoStart). PW = ^NativeInt writes one machine word,
  so the slot stride is the target pointer size automatically. }
procedure Spawn(entry: TCoroEntry; arg: Pointer);
var id: Integer; stk, top: Int64;
begin
  id := coCount; Inc(coCount);
  stk := Int64(GetMem(CO_STK));
  top := stk + CO_STK;
  top := top - (top mod 16);   { 16-align down }
{$ifdef CPU_I386}
  { i386 pops: exc, edi, esi, ebx, ebp, ret — 6 dwords. }
  top := top - 24;
  PW(top + 0)^  := 0;                { exc_top }
  PW(top + 4)^  := 0;                { edi }
  PW(top + 8)^  := 0;                { esi }
  PW(top + 12)^ := 0;                { ebx }
  PW(top + 16)^ := 0;                { ebp }
  PW(top + 20)^ := Int64(@CoStart);  { return address -> CoStart }
{$else}
{$ifdef CPU_AARCH64}
  { aarch64 restores: exc(16B slot), then x29/x30, x27/x28 ... x19/x20 — 112
    bytes. Only exc_top (0) and the x30 slot (= CoStart) must be set; the other
    callee-saved slots are dead on first entry. CoSwitch ret jumps to x30. }
  top := top - 112;
  PW(top + 0)^  := 0;                { exc_top }
  PW(top + 24)^ := Int64(@CoStart);  { x30 -> CoStart }
{$else}
{$ifdef CPU_ARM32}
  { arm32 restores: exc, then r4..r11, lr — 40 bytes. Only exc_top (0) and the
    lr slot (= CoStart) matter; the rest are dead on first entry. CoSwitch
    bx lr jumps to lr. }
  top := top - 40;
  PW(top + 0)^  := 0;                { exc_top }
  PW(top + 36)^ := Int64(@CoStart);  { lr -> CoStart }
{$else}
  { x86-64 pops: exc, r15, r14, r13, r12, rbx, rbp, ret — 8 qwords; rsp at
    CoStart entry must be == 8 (mod 16). }
  top := top - 8;
  top := top - 64;
  PW(top + 0)^  := 0;                { exc_top -> fresh chain on this stack }
  PW(top + 8)^  := 0;                { r15 }
  PW(top + 16)^ := 0;                { r14 }
  PW(top + 24)^ := 0;                { r13 }
  PW(top + 32)^ := 0;                { r12 }
  PW(top + 40)^ := 0;                { rbx }
  PW(top + 48)^ := 0;                { rbp }
  PW(top + 56)^ := Int64(@CoStart);  { return address -> CoStart }
{$endif}
{$endif}
{$endif}
  coSp[id]    := top;
  coStk[id]   := stk;
  coState[id] := 1;
  coEntry[id] := entry;
  coArg[id]   := arg;
end;

{ Suspend the current coroutine, returning control to the scheduler. }
procedure CoYield;
begin
  __pxxcoswitch(@coSp[curCo], @schedSp);
end;

{ Mark fd non-blocking so read/write return EAGAIN instead of blocking the whole
  scheduler thread. (v1 sets only O_NONBLOCK; it does not preserve other flags.) }
procedure SetNonBlocking(fd: Integer);
{$ifdef CPUX86_64}
var rc: Int64;
{$endif}
begin
{$ifdef CPUX86_64}
  rc := __pxxrawsyscall(SYS_fcntl, fd, F_SETFL, O_NONBLOCK, 0, 0, 0);
{$endif}
end;

{$ifdef CPUX86_64}
{ Park the current coroutine on epoll until fd is ready for the given event,
  then yield. On resume the fd is removed from the set (one-shot add/del). }
procedure WaitIO(fd, events: Integer);
var ev: TEpollEvent; rc: Int64;
begin
  if epfd = 0 then
    epfd := Integer(__pxxrawsyscall(SYS_epoll_create1, 0, 0, 0, 0, 0, 0));
  ev.events := events;
  ev.data := curCo;
  rc := __pxxrawsyscall(SYS_epoll_ctl, epfd, EPOLL_CTL_ADD, fd, Int64(@ev), 0, 0);
  coState[curCo] := 3;                         { io-blocked }
  __pxxcoswitch(@coSp[curCo], @schedSp);       { -> scheduler }
  rc := __pxxrawsyscall(SYS_epoll_ctl, epfd, EPOLL_CTL_DEL, fd, 0, 0, 0);
end;

procedure WaitReadable(fd: Integer); begin WaitIO(fd, EPOLLIN);  end;
procedure WaitWritable(fd: Integer); begin WaitIO(fd, EPOLLOUT); end;
{$else}
{ No reactor on this target yet: degrade to a cooperative yield (busy-poll). }
procedure WaitReadable(fd: Integer); begin CoYield; end;
procedure WaitWritable(fd: Integer); begin CoYield; end;
{$endif}

{ Round-robin every runnable coroutine; when none are runnable but some are
  blocked on I/O, epoll_wait for readiness and wake them. Ends when nothing is
  runnable and nothing is blocked. }
procedure RunUntilDone;
var i, anyRunnable, anyBlocked: Integer;
{$ifdef CPUX86_64}
    n, k, cid: Integer;
    evs: array[0..MAX_CO-1] of TEpollEvent;
{$endif}
begin
  repeat
    anyRunnable := 0;
    for i := 0 to coCount - 1 do
      if coState[i] = 1 then
      begin
        anyRunnable := 1;
        curCo := i;
        gEntry := coEntry[i];
        gArg := coArg[i];
        __pxxcoswitch(@schedSp, @coSp[i]);   { run i until it yields or finishes }
        if coState[i] = 2 then
          FreeMem(Pointer(coStk[i]));
      end;
    anyBlocked := 0;
    for i := 0 to coCount - 1 do
      if coState[i] = 3 then anyBlocked := 1;
{$ifdef CPUX86_64}
    if (anyRunnable = 0) and (anyBlocked = 1) then
    begin
      { Nothing to run but coroutines wait on I/O: block here until an fd is
        ready, then mark the parked coroutines runnable (data = their id). }
      n := Integer(__pxxrawsyscall(SYS_epoll_wait, epfd, Int64(@evs[0]), MAX_CO, -1, 0, 0));
      for k := 0 to n - 1 do
      begin
        cid := Integer(evs[k].data);
        coState[cid] := 1;
      end;
    end;
{$endif}
  until (anyRunnable = 0) and (anyBlocked = 0);
  curCo := -1;
end;

end.
