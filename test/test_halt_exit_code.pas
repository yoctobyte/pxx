program test_halt_exit_code;
{ Halt(n) must exit WITH n — on every target
  (bug-a-halt-n-exits-zero-on-hosted-riscv32).

  riscv32 used to emit an unconditional `exit(0)` here, under a comment
  claiming "bare-metal: park in a self-loop". That is true for ESP bare and
  simply wrong for hosted riscv32 Linux, which is the same arch: the argument
  was evaluated nowhere and thrown away, so this program printed its two lines
  and then reported SUCCESS. A lost exit code is the worst shape of wrong
  answer — nothing crashes, nothing prints, and every caller that branches on
  `$?` (a shell script, a CI job, a Makefile assertion like the one running
  this test) silently takes the wrong branch.

  The computed case is the one that matters. A constant argument could be
  satisfied by a smarter EmitExit; `Halt(code)` where `code` is a variable can
  only pass if the expression is actually evaluated into the syscall's first
  argument register. The write before it is there so the test also fails if the
  exit is taken too early.

  Oracle: FPC prints the same two lines and exits 5. }

var
  code: Integer;

begin
  code := 2;
  WriteLn('working');
  code := code + 3;
  WriteLn('halting with ', code);
  Halt(code);
  WriteLn('unreachable');
end.
