program test_range_checked_seed;
{ Constants whose lowering needs DELIBERATE 32-bit wraparound. Each one aborted
  the range-checked FPC seed (`make fpc-seed-checked`) before
  bug-a-the-range-checked-seed-traps-on-deliberate-wraparound-arithmetic:

    $FFFFFFFF  a Cardinal arrives as Int64 4294967295 and is handed to a
               32-bit backend's Int32 immediate parameter -- outside Int32,
               but exactly the bit pattern the target loads (Low32, util.inc).
    $7FFFFFFF  on riscv32 the addi sign-extension borrow makes lui's operand
               $80000000, which is not an Int32 either.

  So this file is only a gate row when compiled to a 32-BIT target by the
  checked seed; natively it is an ordinary value test. Both halves matter --
  the values below are what says the wraparound is a reinterpretation and not
  a loss. }
var
  a, b, c, d: Cardinal;
begin
  a := $FFFFFFFF;
  b := $7FFFFFFF;
  c := $80000000;
  d := $7FFFF800;
  writeln(a);
  writeln(b);
  writeln(c);
  writeln(d);
  writeln(a - b);
end.
