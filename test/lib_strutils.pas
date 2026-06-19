program lib_strutils;
{ Unit test for lib/rtl/strutils. Track B. Build with the pinned stable. }
uses strutils;
begin
  { IntToStr }
  writeln(IntToStr(0));
  writeln(IntToStr(7));
  writeln(IntToStr(42));
  writeln(IntToStr(-5));
  writeln(IntToStr(1000000));
  writeln(IntToStr(-123456789));
  { Copy: 1-based, count clamped to end, out-of-range -> '' }
  writeln(Copy('hello world', 1, 5));     { hello }
  writeln(Copy('hello world', 7, 99));    { world (count clamped) }
  writeln('[', Copy('abc', 5, 3), ']');   { [] (index past end) }
  { Trim: strips <= ' ' both ends }
  writeln('[', Trim('   pad me   '), ']'); { [pad me] }
  writeln('[', Trim(''), ']');             { [] }
end.
