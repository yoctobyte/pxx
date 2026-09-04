program test_cross_ansiterm_through_the_pal;
{ ansiterm's five syscall bodies, on every target, through the PAL.

  Until 2026-09-04 this unit carried four private per-target syscall number
  tables. Two of them had already produced a silent failure -- GetSysWrite had
  no riscv32 or xtensa row, AnsiWrite's `if w = -1 then Exit` took it, and every
  TUI drew NOTHING on those two while ordinary WriteLn kept working
  (bug-b-ansiterm-has-no-syscall-numbers-for-riscv32-or-xtensa-so-every-tui-draws-nothing).
  The ioctl and fcntl tables STILL had that hole when they were deleted, with a
  comment saying it could not be filled because "this compiler never emits ioctl
  or fcntl for either target, so there is no in-tree source for the number".
  platform.pas had them for all six all along. The private table is what stopped
  anyone asking.

  TWO ROWS, and they measure different halves:

  `size` needs a REAL TERMINAL, so the Makefile runs this under `script` with a
  forced 132x40. It is the row riscv32 could not pass before -- measured FALSE
  80 24 with the old table and TRUE 132 40 through the PAL, same binary
  otherwise. Without a pty every target correctly answers FALSE 80 24, which is
  why the Makefile asserts the pty case: a no-tty run would pass on a target
  that cannot do ioctl at all and prove nothing.

  `raw` and `key` assert the OTHER shape -- that a round trip through
  AnsiSetRawMode leaves the terminal usable and AnsiReadKey does not block on an
  empty stdin. Both must hold whether or not the backend has fcntl/ioctl: wasi
  answers PAL_ERR_UNSUPPORTED to both, which is a DEFINED failure the callers
  handle (no raw mode, 80x24, no key) rather than the codegen refusal a missing
  table row used to produce. On wasm32 these five bodies were 45 of the 518
  IR_SYSCALL refusals in the corpus census, and PalRead/PalWrite are real there,
  so a TUI now genuinely draws. }
uses ansiterm;
var cols, rows: Integer; ok: Boolean;
begin
  AnsiWrite('write-through-pal' + #10);
  ok := TerminalSize(cols, rows);
  WriteLn('size ', ok, ' ', cols, ' ', rows);
  AnsiSetRawMode(True);
  AnsiSetRawMode(False);
  WriteLn('raw round-trip survived');
  WriteLn('key ', Ord(AnsiReadKey));
end.
