program test_cross_write_pchar;

{ write(PChar) must emit the string content (strlen + write), not the pointer
  value — and identically on every target. Previously only x86-64 had the
  C-string write path; i386/aarch64/arm32 printed the raw pointer, so output
  diverged per target. }

var s: AnsiString; p: PChar;
begin
  s := 'hello';
  p := PChar(s);
  writeln(p);
  writeln(PChar(s));
  s := s + ' world';
  writeln(PChar(s));
end.
