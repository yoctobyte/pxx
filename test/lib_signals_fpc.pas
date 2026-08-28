{ FPC-compatible Signal() over pxx's parameterless hook.

  The row with teeth is ONE handler registered for TWO signals, each asserting
  its own number: a single-signal test passes even with the trampoline hard-wired
  to a constant, which is exactly the bug this unit could have. }
program lib_signals_fpc;

uses signals;

var
  gotUsr1, gotUsr2, gotOther: Integer;
  prev: SignalHandler;
  allok: Boolean;

function Pid: Int64; begin Pid := __pxxrawsyscall(39, 0, 0, 0, 0, 0, 0); end;
procedure Raise_(s: Int64);
var r: Int64;
begin r := __pxxrawsyscall(62, Pid, s, 0, 0, 0, 0); end;

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
