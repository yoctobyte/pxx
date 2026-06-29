{$CASESENSITIVE ON}
program TestCaseIOCaseSensitiveIntrinsics;

var
  a, b: Integer;

begin
  Write('A');
  wRiTe('B');
  WriteLn;
  Read(a);
  ReadLn(b);
  WRITELN(a + b);
end.
