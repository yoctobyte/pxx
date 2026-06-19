program lib_strutils;
{ Unit test for lib/rtl/strutils. Track B. Build with the pinned stable. }
uses strutils;
begin
  writeln(IntToStr(0));
  writeln(IntToStr(7));
  writeln(IntToStr(42));
  writeln(IntToStr(-5));
  writeln(IntToStr(1000000));
  writeln(IntToStr(-123456789));
end.
