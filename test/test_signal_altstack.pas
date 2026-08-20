program test_signal_altstack;
{ sigaltstack + SA_ONSTACK (feature-signal-siginfo-ucontext item 3).

  A stack-overflow SIGSEGV is the one fault a handler cannot take on the
  faulting stack: the fault happens BECAUSE there is no stack left, so pushing
  a signal frame onto it faults again and the kernel kills the process. Before
  this, the program below died with exit 139 and the hook was never entered.

  The interesting assertion is the third line, not the fact that we survived.
  Surviving only shows the handler ran; it does not show WHERE. So the handler
  compares its own frame against the faulting address: on the alt stack (a BSS
  buffer, low addresses) they are hundreds of megabytes apart, while a handler
  running on the faulting stack would sit within a few KB of it. That distance
  is what proves sigaltstack took effect rather than the overflow having
  happened to leave a usable slack page.

  Depth is deliberately NOT printed — it depends on RLIMIT_STACK and on frame
  layout, so it is exactly the kind of environment-dependent number that makes
  a test flap.

  Oracle: the same program in C (sigaltstack + SA_ONSTACK + SA_SIGINFO under
  gcc) prints SEGV_MAPERR and exits 0 too. }

var
  depth: Integer;

procedure OnSegv;
var
  hLocal: Integer;
  gap: PtrUInt;
begin
  hLocal := 1;
  if PtrUInt(@hLocal) > PtrUInt(__pxxSigAddr) then
    gap := PtrUInt(@hLocal) - PtrUInt(__pxxSigAddr)
  else
    gap := PtrUInt(__pxxSigAddr) - PtrUInt(@hLocal);
  WriteLn('code=', __pxxSigCode);                        { SEGV_MAPERR }
  WriteLn('handler-off-faulting-stack=', gap > $10000000);
  Halt(0);
end;

procedure Recurse;
var
  pad: array[0..255] of Integer;
begin
  Inc(depth);
  pad[0] := depth;
  pad[255] := depth;
  Recurse;
  { keeps `pad` live so the frame cannot be optimised away into a tail call }
  if pad[0] <> pad[255] then WriteLn('never');
end;

begin
  depth := 0;
  SetSignalHandler(11, @OnSegv);
  WriteLn('recursing');
  Recurse;
  WriteLn('unreachable');
  Halt(1);
end.
