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

  ALL FIVE HOSTED TARGETS as of 2026-08-31 (feature-signal-siginfo-ucontext item
  4's follow-up slice). It was x86-64 only until then, and the intrinsic REFUSED
  elsewhere rather than answer 0.

  tkill(gettid(), sig) rather than kill(getpid(), sig), and the two syscall
  numbers are lifted from test_signal_siginfo.pas rather than looked up fresh:
  they are already proven on all five targets there, and a wrong getpid number
  would fail as a *signal that never arrives*, which reads exactly like the
  dispatch bug this test exists to catch. Self-directed delivery also removes the
  pid round-trip. }

const
{$ifdef CPUX86_64}
  SYS_gettid = 186; SYS_tkill = 200;
{$endif}
{$ifdef CPUAARCH64}
  SYS_gettid = 178; SYS_tkill = 130;   { asm-generic unistd }
{$endif}
{$ifdef CPURISCV32}
  SYS_gettid = 178; SYS_tkill = 130;   { asm-generic unistd }
{$endif}
{$ifdef CPUARM}
  SYS_gettid = 224; SYS_tkill = 238;   { ARM EABI }
{$endif}
{$ifdef CPUI386}
  SYS_gettid = 224; SYS_tkill = 238;
{$endif}

var seen: array[0..64] of Integer; r: Int64;
procedure SendSig(s: Int64);
var tid: Int64;
begin
  tid := __pxxrawsyscall(SYS_gettid);
  r := __pxxrawsyscall(SYS_tkill, tid, s);
end;
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
