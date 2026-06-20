program lib_sysutils;
{ Unit test for lib/rtl/sysutils. Track B. Build with the pinned stable. }
uses sysutils;

type
  ELocal = class(Exception)
  end;

var e: Exception;
begin
  { IntToStr (Int64 range) }
  writeln(IntToStr(0));
  writeln(IntToStr(-123456789));
  writeln(IntToStr(10000000000));        { > 2^32 }
  { Copy }
  writeln(Copy('hello world', 1, 5));    { hello }
  writeln(Copy('hello world', 7, 99));   { world }
  writeln('[', Copy('abc', 5, 3), ']');  { [] }
  { Trim }
  writeln('[', Trim('  pad  '), ']');    { [pad] }
  { StrToIntDef / StrToInt }
  writeln(StrToIntDef('42', -1));        { 42 }
  writeln(StrToIntDef('  -7', -1));      { -7 }
  writeln(StrToIntDef('x', -1));         { -1 }
  writeln(StrToInt('100'));              { 100 }
  { case }
  writeln(UpperCase('aB3z'));            { AB3Z }
  writeln(LowerCase('aB3z'));            { ab3z }
  { Exception base class }
  e := Exception.Create('base');
  writeln(e.Message);
  e.HelpContext := 77;
  writeln(e.HelpContext);
  try
    raise ELocal.Create('derived');
  except
    on ex: ELocal do writeln(ex.Message);
  end;
end.
