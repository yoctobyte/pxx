{ Sleep MUST LOWER AND THE PROGRAM MUST CONTINUE PAST IT, on every target.

  sysutils.Sleep used to carry its own four-arm nanosleep syscall-number table
  and issue __pxxrawsyscall itself, guarded by `if n = -1 then Exit`. That guard
  reads as a soft failure on a target with no number and it is not one: it is a
  RUNTIME test in front of an instruction that is still EMITTED, so a backend
  with no syscall lowering refuses the whole BODY. On wasm32 -- where wasi has
  imports and can never have syscall numbers -- that was `value IR op 54` and
  this one procedure gated 209 of the 518 IR_SYSCALL refusals in the corpus.
  It now goes through PalNanosleep, which answers PAL_ERR_UNSUPPORTED there:
  the same defined failure the guard MEANT, decided at COMPILE time.

  WHAT THIS FILE CAN AND CANNOT ASSERT. It asserts that the body lowers, that
  the call returns, and that execution continues -- which is precisely the
  property that was broken, and it is deterministic on all six targets. It does
  NOT assert that any time passed, because on wasi none does and that is
  correct; a timing row here would be a row that must be excluded on the one
  target this file exists for.

  Whether the sleep actually SLEEPS is a separate measurement and has its own
  ticket where it fails:
  bug-b-palnanosleep-answers-enosys-on-riscv32-because-rv32-has-no-nanosleep-syscall
  (rv32 has no `nanosleep` syscall at all; -38 measured). That was invisible
  while sysutils' private table had no riscv32 arm and exited first -- two
  silences stacked, and this file removes neither. It only makes sure the
  BODY is there to be wrong in. }
program test_cross_sleep_lowers_everywhere;
uses sysutils;
var i, n: Integer;
begin
  WriteLn('before');
  Sleep(1);
  WriteLn('after 1');
  Sleep(0);
  WriteLn('after 0');
  n := 0;
  for i := 1 to 3 do
  begin
    Sleep(1);
    n := n + i;
  end;
  WriteLn('loop n=', n);
end.
