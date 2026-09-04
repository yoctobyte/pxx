{ FPC-compatible Signal() over pxx's parameterless hook.

  The row with teeth is ONE handler registered for TWO signals, each asserting
  its own number: a single-signal test passes even with the trampoline hard-wired
  to a constant, which is exactly the bug this unit could have. }
program lib_signals_fpc;

uses signals, pxxcio;

var
  gotUsr1, gotUsr2, gotOther: Integer;
  prev: SignalHandler;
  allok: Boolean;

{ THIS TEST USED RAW SYSCALL NUMBERS 39 AND 62 AND THAT MADE IT AN X86-64 TEST
  WEARING A PORTABLE ONE'S CLOTHES. 39/62 are getpid/kill on x86-64 ONLY: they
  are 20/37 on i386 and arm32 and 172/129 on aarch64 and riscv32, so on every
  other target this file called two unrelated syscalls, sent no signal, and
  reported `per-signal-number=FAIL usr1=0 usr2=0 other=0` — a failure that reads
  exactly like a broken signal runtime and was the test's own arithmetic.
  Measured 2026-09-04 on all four. Going through the PAL costs nothing and has
  no per-arch table to keep in step; test_cross_syscall.pas is the other shape
  (a deliberate per-CPU branch) and is correct because raw syscalls ARE its
  subject. Here they were incidental. }
function Pid: Int64; begin Pid := __pxx_getpid; end;
procedure Raise_(s: Int64);
var r: Integer;
begin r := __pxx_kill(__pxx_getpid, Integer(s)); end;

procedure OneHandler(sig: Longint); cdecl;
begin
  if sig = SIGUSR1 then Inc(gotUsr1)
  else if sig = SIGUSR2 then Inc(gotUsr2)
  else Inc(gotOther);
end;

procedure Other(sig: Longint); cdecl;
begin
end;

begin
  allok := True;
  gotUsr1 := 0; gotUsr2 := 0; gotOther := 0;

  { One procedure, two signals. }
  prev := Signal(SIGUSR1, @OneHandler);
  if prev = SIG_DFL then WriteLn('prev-initial=ok')
  else begin WriteLn('prev-initial=FAIL'); allok := False; end;

  Signal(SIGUSR2, @OneHandler);

  Raise_(SIGUSR1);
  Raise_(SIGUSR2);
  Raise_(SIGUSR1);

  if (gotUsr1 = 2) and (gotUsr2 = 1) and (gotOther = 0) then
    WriteLn('per-signal-number=ok')
  else
  begin
    WriteLn('per-signal-number=FAIL usr1=', gotUsr1, ' usr2=', gotUsr2, ' other=', gotOther);
    allok := False;
  end;

  { FPC's contract: Signal returns the PREVIOUS handler. }
  prev := Signal(SIGUSR1, @Other);
  if prev = @OneHandler then WriteLn('prev-returned=ok')
  else begin WriteLn('prev-returned=FAIL'); allok := False; end;

  { Out of range, and the two that cannot be caught. }
  if (Signal(0, @Other) = SIG_ERR) and (Signal(999, @Other) = SIG_ERR)
     and (Signal(SIGKILL, @Other) = SIG_ERR) and (Signal(SIGSTOP, @Other) = SIG_ERR) then
    WriteLn('range=ok')
  else begin WriteLn('range=FAIL'); allok := False; end;

  { SIG_IGN must genuinely ignore: the process must survive a signal whose
    default disposition is fatal, and the handler must not run. }
  gotOther := 0;
  Signal(SIGPIPE, SIG_IGN);
  Raise_(SIGPIPE);
  if gotOther = 0 then WriteLn('ignore=ok')
  else begin WriteLn('ignore=FAIL'); allok := False; end;

  if allok then WriteLn('SIGNALS OK')
  else begin WriteLn('SIGNALS FAIL'); Halt(1); end;
end.
