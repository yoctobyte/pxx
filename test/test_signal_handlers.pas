program test_signal_handlers;
{ Signal runtime, x86-64 first slice (feature-signal-handlers): default-on
  dispatch for SIGINT/SIGTERM + SetSignalHandler(sig, @proc) for any signal
  1..64. Hooks are parameterless procs called in signal context (kernel
  restores the full register file on return, SA_RESTART keeps blocking
  syscalls transparent). No hook = revert to default disposition + re-raise,
  so unhandled signals still terminate with killed-by-signal status (the
  companion Makefile check runs a no-hook SIGTERM death expecting 143).
  --no-signals opts the whole runtime out. }
var
  gotUsr1, gotInt, gotTerm: Integer;
  r: Int64;

procedure OnUsr1;
begin gotUsr1 := gotUsr1 + 1; end;

procedure OnInt;
begin gotInt := gotInt + 1; end;

procedure OnTerm;
begin gotTerm := gotTerm + 1; end;

function Pid: Int64;
begin Pid := __pxxrawsyscall(39, 0, 0, 0, 0, 0, 0); end;

procedure SendSig(s: Int64);
begin r := __pxxrawsyscall(62, Pid, s, 0, 0, 0, 0); end;

begin
  SetSignalHandler(10, @OnUsr1);        { SIGUSR1: not in the default set — install on demand }
  SetSignalHandler(2, @OnInt);          { SIGINT }
  SetSignalHandler(15, @OnTerm);        { SIGTERM }
  SendSig(10);
  SendSig(10);
  SendSig(2);
  SendSig(15);
  writeln('usr1=', gotUsr1, ' int=', gotInt, ' term=', gotTerm);
  SetSignalHandler(15, nil);            { revert: next SIGTERM = default death }
  writeln('reverted');
  SendSig(15);
  writeln('unreachable');
end.
