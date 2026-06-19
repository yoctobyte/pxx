program TestCaseIO;
{ Builtin I/O intrinsics resolve case-insensitively (standard Pascal), so
  FPC-idiomatic mixed-case Write/WriteLn parse. Regression for
  bug-builtin-write-case-sensitive. ReadLn is covered by a compile+run path in
  the test suite separately (needs stdin); here output-only for determinism. }
begin
  WriteLn('one');
  Write('a'); Write('b'); WriteLn;
  WRITELN('two');
  Writeln('three');
  wRiTeLn(42);
end.
