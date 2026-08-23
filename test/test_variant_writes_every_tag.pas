program test_variant_writes_every_tag;
{ How `writeln` renders a Variant, one line per payload tag.

  This test asserts its whole OUTPUT rather than printing ALL OK, because the
  output IS the thing under test. The expected stream is in the Makefile rule.

  `writeln(v)` with v a Boolean Variant printed True/False on x86-64 and 1/0 on
  i386, arm32 and aarch64 -- same source, same program, a rendering that
  depended on the target, and the 1/0 form was not what FPC prints either.
  x86-64 lowers the write inline (EmitWriteVariant) and every other target
  calls the runtime PXXWriteVariant; the runtime one folded VT_BOOL in with the
  integer tags. The other rows are here so the next edit to either renderer
  cannot drift a tag without a test noticing -- that drift is the whole defect
  class, twice over now (the operator table was the same shape).
  bug-a-a-boolean-variant-writes-as-1-or-0-off-x86-64

  Every row below matches fpc 3.2.2 -Mobjfpc -O1 exactly, verified on x86-64,
  i386, aarch64 and arm32.

  NOT covered: an EMPTY slot and an OBJECT slot. x86-64 spells them `None` and
  `<object>` (Python), FPC prints nothing for a cleared Variant and RAISES for
  Null, and the runtime renders neither -- an open question tracked as
  bug-a-a-null-variant-renders-as-none-in-pascal, not a drift to pin down here. }
uses variants;
var
  v: Variant;
  c: Char;
  d: Double;
begin
  v := True;   writeln(v);
  v := False;  writeln(v);
  v := 42;     writeln(v);
  v := -7;     writeln(v);
  d := 1.25;
  v := d;      writeln(v);
  c := 'q';
  v := c;      writeln(v);
  v := 'hey';  writeln(v);
end.
