{ Bare `Eof` (standard input) is special call id -210. Every backend lowers it
  to the builtin unit's PXXStdinEof. On xtensa windowed the call's result sits
  in the caller's a10, and the arm never moved it to a2, so the Boolean was
  whatever a2 held before the call: the loop below stopped after one line and
  printed `2 FALSE`. bug-a-bare-eof-reads-a-stale-register-on-xtensa-windowed }
program test_bare_eof_on_stdin_on_every_target;
var
  x, n, sum: Integer;
  a, b: Boolean;
begin
  n := 0; sum := 0;
  while not Eof do
  begin
    Readln(x);
    Write(x, ' ');
    n := n + 1;
    sum := sum + x;
    { Asking twice without reading must give the same answer both times. }
    a := Eof; b := Eof;
    if a <> b then Write('[unstable] ');
  end;
  Writeln;
  Writeln('lines ', n, ' sum ', sum);
  Writeln('eof ', Eof);
  if Eof then Writeln('eof in an if')
  else Writeln('not eof in an if');
end.
