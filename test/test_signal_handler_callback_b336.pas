{ Libc-free signal HANDLERS with a Pascal callback (b336 — pins the slice).

  The SIG_IGN slice was pinned by test_pal_signal; the handler-with-callback
  path (restorer trampoline + dispatch stub + hook table, all default-on and
  emitted by the compiler) had no test. Covers, on x86-64 Linux:

  - SetSignalHandler(sig, @proc) installs a parameterless Pascal hook.
  - A delivered signal calls the hook and the program RESUMES at the
    interruption point (the kernel restores the register file on
    rt_sigreturn through our SA_RESTORER stub) — the graceful SIGINT/SIGTERM
    cleanup shape.
  - Both SIGTERM(15) and SIGINT(2) route through the same dispatch.
  The no-hook path (revert to default disposition + re-raise, so an unhandled
  SIGTERM still exits 143 killed-by-signal) is exercised by
  test_signal_default_revert_b336.pas — it must die, so it cannot live here. }
program test_signal_handler_callback_b336;
{$mode objfpc}{$h+}
uses platform;

var
  hits: Integer = 0;
  spin: Integer;

procedure OnSig;
begin
  hits := hits + 1;
end;

begin
  SetSignalHandler(15, @OnSig);          { SIGTERM }
  PalKill(PalGetpid, 15);
  for spin := 1 to 1000000 do ;          { give the kernel a moment to deliver }
  SetSignalHandler(2, @OnSig);           { SIGINT }
  PalKill(PalGetpid, 2);
  for spin := 1 to 1000000 do ;
  Writeln('hits=', hits);
  Writeln('resumed after handler');
end.
