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

  x86-64 only for now; CoSwitch + the initial-frame builder are ported per
  target in later phases. }

interface

type
  TCoroEntry = procedure(arg: Pointer);

procedure Spawn(entry: TCoroEntry; arg: Pointer);
procedure CoYield;
procedure RunUntilDone;

implementation

const
  MAX_CO = 64;
  CO_STK = 65536;   { per-coroutine heap stack }

type
  PW = ^NativeInt;  { pointer-sized machine-word access at an address }

var
  coSp    : array[0..MAX_CO-1] of Int64;       { saved stack pointer }
  coStk   : array[0..MAX_CO-1] of Int64;       { heap stack base (for FreeMem) }
  coState : array[0..MAX_CO-1] of Integer;     { 0=free 1=runnable 2=done }
  coEntry : array[0..MAX_CO-1] of TCoroEntry;  { body to run on first switch-in }
  coArg   : array[0..MAX_CO-1] of Pointer;
  coCount : Integer;
  curCo   : Integer;                           { running coroutine, -1 = scheduler }
  schedSp : Int64;                             { scheduler's own saved sp }
  gEntry  : TCoroEntry;                        { handoff to CoStart }
  gArg    : Pointer;

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
{$ifdef PXX_TARGET_I386}
  { i386 pops: exc, edi, esi, ebx, ebp, ret — 6 dwords. }
  top := top - 24;
  PW(top + 0)^  := 0;                { exc_top }
  PW(top + 4)^  := 0;                { edi }
  PW(top + 8)^  := 0;                { esi }
  PW(top + 12)^ := 0;                { ebx }
  PW(top + 16)^ := 0;                { ebp }
  PW(top + 20)^ := Int64(@CoStart);  { return address -> CoStart }
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

{ Round-robin every runnable coroutine until all have finished. }
procedure RunUntilDone;
var i, any: Integer;
begin
  repeat
    any := 0;
    for i := 0 to coCount - 1 do
      if coState[i] = 1 then
      begin
        any := 1;
        curCo := i;
        gEntry := coEntry[i];
        gArg := coArg[i];
        __pxxcoswitch(@schedSp, @coSp[i]);   { run i until it yields or finishes }
        if coState[i] = 2 then
          FreeMem(Pointer(coStk[i]));
      end;
  until any = 0;
  curCo := -1;
end;

end.
