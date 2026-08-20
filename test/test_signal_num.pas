program test_signal_num;
{ __pxxSigNum — which signal is being dispatched, readable from inside the hook.

  The pxx hook ABI is deliberately PARAMETERLESS, and that is not changing: every
  existing SetSignalHandler user depends on it. The consequence is that ONE
  procedure registered for several signals had no way to tell them apart, which
  is precisely the shape an FPC-compatible `Signal(sig, handler)` wrapper needs
  (its handler takes the signal number). So the number is parked in a slot by
  the dispatch stub, next to si_code / si_addr / ucontext*, and read the same
  way — no backend op, no ABI change.

  The test registers ONE hook for three signals and counts per number. usr1
  twice is the row that matters: a hook that simply counted deliveries would
  pass with the slot stuck at any single value, and `zero=0` catches the slot
  never being written at all (it would then read 0 for every signal and pile
  every count into seen[0]).

  x86-64 only so far — the other four hosted targets install with SA_SIGINFO but
  do not park the number, and the intrinsic REFUSES there rather than answering
  0. feature-signal-siginfo-ucontext item 4. }
var seen: array[0..64] of Integer; r: Int64;
function Pid: Int64; begin Pid := __pxxrawsyscall(39, 0, 0, 0, 0, 0, 0); end;
procedure SendSig(s: Int64); begin r := __pxxrawsyscall(62, Pid, s, 0, 0, 0, 0); end;
procedure Hook;
begin
  seen[__pxxSigNum] := seen[__pxxSigNum] + 1;
end;
begin
  SetSignalHandler(10, @Hook);   { SIGUSR1 }
  SetSignalHandler(12, @Hook);   { SIGUSR2 }
  SetSignalHandler(2,  @Hook);   { SIGINT  }
  SendSig(10); SendSig(12); SendSig(10); SendSig(2);
  Writeln('usr1=', seen[10], ' usr2=', seen[12], ' int=', seen[2], ' zero=', seen[0]);
end.
