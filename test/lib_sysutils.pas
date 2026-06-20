program lib_sysutils;
{ Unit test for lib/rtl/sysutils. Track B. Build with the pinned stable. }
uses sysutils;

type
  ELocal = class(Exception)
  end;

var s: AnsiString; e: Exception;
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
  writeln(UpCase('q'));                  { Q }
  writeln(UpCase('7'));                  { 7 }
  writeln(UpperCase('aB3z'));            { AB3Z }
  writeln(LowerCase('aB3z'));            { ab3z }
  { Delete }
  s := 'hello world';
  Delete(s, 6, 6);
  writeln(s);                            { hello }
  s := 'abcde';
  Delete(s, 3, 99);
  writeln(s);                            { ab }
  s := 'abcde';
  Delete(s, 1, 1);
  writeln(s);                            { bcde }
  s := 'abcde';
  Delete(s, 10, 1);
  writeln(s);                            { abcde (no-op: index > length) }
  s := 'abcde';
  Delete(s, 3, 0);
  writeln(s);                            { abcde (no-op: count <= 0) }
  { Insert }
  s := 'heworld';
  Insert('llo ', s, 3);
  writeln(s);                            { hello world }
  s := 'end';
  Insert('start ', s, 1);
  writeln(s);                            { start end }
  s := 'start';
  Insert(' end', s, 99);
  writeln(s);                            { start end }
  s := 'abc';
  Insert('', s, 2);
  writeln(s);                            { abc (no-op: empty src) }
  { Concat }
  writeln(Concat('foo', 'bar'));         { foobar }
  writeln(Concat('', 'x'));              { x }
  writeln(Concat('x', ''));              { x }
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
