{ No-hook signal disposition: revert to default and re-raise (b336 companion).

  A signal we manage but that has no registered hook must NOT be swallowed: the
  dispatch stub restores SIG_DFL and re-raises, so the process dies with the
  proper killed-by-signal status (SIGTERM -> 143). Run by the Makefile, which
  asserts the exit status; the program deliberately terminates. }
program test_signal_default_revert_b336;
{$mode objfpc}{$h+}
uses platform;
begin
  Writeln('raising SIGTERM with no hook');
  PalKill(PalGetpid, 15);
  Writeln('SHOULD NOT REACH');
end.
