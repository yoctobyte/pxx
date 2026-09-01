{ AnsiWrite MUST ACTUALLY WRITE, on every target.

  ansiterm bypasses Pascal's buffered output and issues the write syscall
  directly, because a TUI cannot wait for a flush. The syscall NUMBER comes from
  GetSysWrite, a per-CPU ifdef table — and that table had arms for i386,
  aarch64, arm32 and x86-64 and none for riscv32 or xtensa. It returned -1,
  AnsiWrite's `if w = -1 then Exit` took the early exit, and every TUI drew
  NOTHING on those two targets while ordinary WriteLn kept working perfectly.

  examples/tui/menudemo and examples/g2048/console_2048 both printed their final
  ordinary line and not one byte of screen. Nothing crashed and nothing warned.
  A missing arm in an ifdef table fails by doing nothing, which is the quietest
  failure a table can have.

  This asserts the two paths INTERLEAVED, and the interleaving is the point: a
  test that only checked AnsiWrite could pass on a target where WriteLn was
  broken instead, and one that only checked WriteLn is what the old coverage
  effectively was. Ordering also proves AnsiWrite is unbuffered relative to
  WriteLn -- if it were buffered the two would come out grouped, not alternating.

  bug-b-ansiterm-has-no-syscall-numbers-for-riscv32-or-xtensa-so-every-tui-draws-nothing }
program test_ansiterm_raw_write;

uses ansiterm;

begin
  Write('a');       Flush(Output);
  AnsiWrite('B');
  Write('c');       Flush(Output);
  AnsiWrite('D');
  WriteLn;
  WriteLn('RAW WRITE OK');
end.
