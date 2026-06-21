program test_eof_stdin;

{ Standard-input Eof: a no-arg Boolean builtin. Counts lines until Eof, proving
  the one-byte pushback (the peeked byte is not lost — the final line without a
  trailing newline is still read in full). Driven by piped input in the suite. }

var line: AnsiString; n: Integer;
begin
  n := 0;
  while not Eof do
  begin
    readln(line);
    n := n + 1;
    WriteLn(n, ': ', line);
  end;
  WriteLn('total ', n);
end.
