{ SPDX-License-Identifier: Zlib }
unit signals;
{$MODE PXX}
{ FPC-compatible `Signal(sig, handler)` over pxx's parameterless signal hook.

  pxx's own ABI is `SetSignalHandler(sig, @proc)` where proc takes NO arguments,
  and that is deliberately fixed — every existing user depends on it. FPC's
  surface hands the handler the signal NUMBER, which is the whole gap this unit
  closes: one table, one trampoline, and `__pxxSigNum` (the number parked by the
  dispatch stub) to tell the trampoline which signal it is serving.

  x86-64 Linux only, and deliberately so. `__pxxSigNum` REFUSES at codegen on the
  other hosted targets rather than answering 0, because answering 0 would route
  every signal to handler 0 — a wrong disposition that stays invisible until a
  signal arrives. The unit therefore compiles to an explicit refusal elsewhere
  instead of a silently wrong table. }

{ Refuse loudly rather than compiling to an empty unit. An empty `signals` would
  export nothing and fail at the USE site with a confusing missing-identifier
  error, or worse, satisfy a `uses` clause and provide no dispositions at all. }
{$ifndef CPUX86_64}
{$error unit signals needs __pxxSigNum, which is x86-64 Linux only today: the other hosted targets do not park the signal number in their dispatch stubs, and answering 0 would route every signal to handler 0}
{$endif}

interface

type
  { cdecl is meaningless here — pxx is libc-free and calls the trampoline with
    its own ABI — but corpus source spells it, and pxx accepts it on a procedure
    type, so the declaration matches what real code writes. }
  SignalHandler  = procedure(sig: Longint); cdecl;
  TSignalHandler = SignalHandler;

const
  SIG_DFL = SignalHandler(0);
  SIG_IGN = SignalHandler(1);
  SIG_ERR = SignalHandler(-1);

  { The numbers the existing signal tests currently spell as bare integers. }
  SIGHUP  = 1;  SIGINT  = 2;  SIGQUIT = 3;  SIGILL  = 4;
  SIGTRAP = 5;  SIGABRT = 6;  SIGBUS  = 7;  SIGFPE  = 8;
  SIGKILL = 9;  SIGUSR1 = 10; SIGSEGV = 11; SIGUSR2 = 12;
  SIGPIPE = 13; SIGALRM = 14; SIGTERM = 15; SIGCHLD = 17;
  SIGCONT = 18; SIGSTOP = 19; SIGTSTP = 20; SIGTTIN = 21;
  SIGTTOU = 22; SIGURG  = 23; SIGXCPU = 24; SIGXFSZ = 25;
  SIGWINCH = 28; SIGIO  = 29; SIGSYS  = 31;

  SIG_MAXSIG = 64;

{ FPC's contract: install `handler` for `signum`, return the PREVIOUS handler.
  Returns SIG_ERR for a signal number out of range, and for SIGKILL/SIGSTOP,
  which cannot be caught or ignored. }
function Signal(signum: Longint; handler: SignalHandler): SignalHandler;

{ The BaseUnix spelling of the same thing; corpus code uses either. }
function fpSignal(signum: Longint; handler: SignalHandler): SignalHandler;

implementation

uses platform;

var
  Handlers: array[1..SIG_MAXSIG] of SignalHandler;

{ One parameterless hook serves every signal; __pxxSigNum says which. The bounds
  check is not defensive noise: a stuck or unwritten slot reads as a number the
  table does not cover, and dispatching that would be worse than dropping it. }
procedure Trampoline;
var n: Longint;
begin
  n := __pxxSigNum;
  if (n >= 1) and (n <= SIG_MAXSIG) then
    if (Handlers[n] <> SIG_DFL) and (Handlers[n] <> SIG_IGN) then
      Handlers[n](n);
end;

function Signal(signum: Longint; handler: SignalHandler): SignalHandler;
var prev: SignalHandler;
begin
  if (signum < 1) or (signum > SIG_MAXSIG) or
     (signum = SIGKILL) or (signum = SIGSTOP) then
  begin
    Signal := SIG_ERR;
    Exit;
  end;

  prev := Handlers[signum];

  if handler = SIG_IGN then
  begin
    { A real ignore, not a disposition that merely looks like one:
      PalIgnoreSignal installs sa_handler=SIG_IGN through rt_sigaction. Mapping
      this onto SIG_DFL would be invisible until the signal arrived and then
      killed the process. }
    PalIgnoreSignal(signum);
    Handlers[signum] := SIG_IGN;
  end
  else if handler = SIG_DFL then
  begin
    SetSignalHandler(signum, nil);   { revert on next delivery }
    Handlers[signum] := SIG_DFL;
  end
  else
  begin
    { Store BEFORE installing: the signal can arrive between the two. }
    Handlers[signum] := handler;
    SetSignalHandler(signum, @Trampoline);
  end;

  Signal := prev;
end;

function fpSignal(signum: Longint; handler: SignalHandler): SignalHandler;
begin
  fpSignal := Signal(signum, handler);
end;

var i: Integer;

begin
  for i := 1 to SIG_MAXSIG do Handlers[i] := SIG_DFL;
end.
