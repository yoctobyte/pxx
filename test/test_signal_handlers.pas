program test_signal_handlers;
{ Signal runtime, x86-64 first slice (feature-signal-handlers): default-on
  dispatch for SIGINT/SIGTERM + SetSignalHandler(sig, @proc) for any signal
  1..64. Hooks are parameterless procs called in signal context (kernel
  restores the full register file on return, SA_RESTART keeps blocking
  syscalls transparent). No hook = revert to default disposition + re-raise,
  so unhandled signals still terminate with killed-by-signal status (the
  companion Makefile check runs a no-hook SIGTERM death expecting 143).
  --no-signals opts the whole runtime out. }
uses pxxcio;
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
begin Pid := __pxx_getpid; end;

{ 39/62 ARE getpid/kill ON X86-64 ONLY -- 20/37 on i386 and arm32, 172/129 on
  aarch64 and riscv32 -- so the raw spelling made this an x86-64 test that
  looked portable, and on any other target it called two unrelated syscalls and
  reported zero deliveries. Same edit and same reason as lib_signals_fpc.pas;
  see the note there. The PAL bridge has no per-arch table to keep in step. }
procedure SendSig(s: Int64);
begin r := __pxx_kill(__pxx_getpid, Integer(s)); end;

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
