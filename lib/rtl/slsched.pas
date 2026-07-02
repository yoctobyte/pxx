{ SPDX-License-Identifier: Zlib }
unit slsched;
{ Stackless-coroutine scheduler (PXX-only; never used in compiler.pas, per the
  FPC/PXX boundary).

  A `; async; stackless;` routine is compiled — by the same state-machine
  transform that drives stackless generators — into a step function with the ABI
  `function(self: Pointer): Boolean`: each call advances the coroutine to its next
  `await` (returns True = "resume me later") or runs it off the end (returns False
  = done). Unlike the stackful scheduler (scheduler.pas) there is NO context
  switch and NO per-coroutine heap stack — each coroutine is just a small heap
  instance + a step-function pointer — so it runs on every target with zero asm,
  the RAM-cheap path for constrained devices.

  The compiler spawns one via `AsyncGo(@Body)`, which desugars to
  `SLSpawn(@Body, SlAlloc(instSize, ...))` (instance allocation in slgen).
  SLRunUntilDone round-robins the live set, resuming each coroutine one await-step
  per pass, until all finish. Resumption is an indirect call through the stored
  proc-typed step pointer (procedural types). }

interface

uses slgen;

type
  TSLStep = function(self: Pointer): Boolean;

procedure SLSpawn(step: TSLStep; inst: Pointer);
procedure SLRunUntilDone;

implementation

const
  MAX_SL = 64;

var
  slStep  : array[0..63] of TSLStep;   { step function per coroutine }
  slInst  : array[0..63] of Pointer;   { heap instance per coroutine }
  slLive  : array[0..63] of Boolean;   { still runnable? }
  slCount : Integer;

procedure SLSpawn(step: TSLStep; inst: Pointer);
begin
  slStep[slCount] := step;
  slInst[slCount] := inst;
  slLive[slCount] := True;
  Inc(slCount);
end;

{ Round-robin: each pass resumes every live coroutine for one await-step; a
  coroutine whose step returns False has run to completion — mark it dead and
  free its instance. Ends when nothing is live. }
procedure SLRunUntilDone;
var i, anyLive: Integer; more: Boolean; fn: TSLStep;
begin
  repeat
    anyLive := 0;
    for i := 0 to slCount - 1 do
      if slLive[i] then
      begin
        anyLive := 1;
        fn := slStep[i];
        more := fn(slInst[i]);          { indirect call through the proc-typed step }
        if not more then
        begin
          slLive[i] := False;
          SlFree(slInst[i]);
        end;
      end;
  until anyLive = 0;
  slCount := 0;
end;

end.
