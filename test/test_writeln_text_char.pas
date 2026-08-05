program test_writeln_text_char;
{ Regression: write/writeln of a Char to a TEXT FILE. The Text lowering's
  ordinal arm excludes tyChar (correctly — StrInt would print the ORDINAL, 120
  for 'x') but no Char arm existed, so it fell through to
  "unsupported argument type" and `write(f, 'a')` did not compile. A
  one-character literal IS a Char in Pascal, so the most ordinary line anyone
  writes was rejected while `write(f, 'ab')` compiled, and stdout accepted both.
  Routed through a new StrChar(c, width) builtin, mirroring StrInt/StrFloat.
  Output verified byte-identical to FPC, width padding included.
  bug-p-writeln-text-rejects-char }
var f: Text; c: Char; i: Integer; sline: string;
begin
  Assign(f, '/tmp/test_writeln_text_char.txt'); Rewrite(f);
  c := 'x';
  write(f, 'a');            { Char literal }
  write(f, c);              { Char var }
  write(f, c:4);            { Char with width }
  write(f, 'Z':3);          { Char literal with width }
  writeln(f, '|');
  write(f, 'ab');           { string still fine }
  write(f, 42, ' ', 3.5:0:1);
  writeln(f, '|');
  for i := 0 to 3 do write(f, Chr(65 + i));   { Chr() result }
  writeln(f);
  Close(f);
  Assign(f, '/tmp/test_writeln_text_char.txt'); Reset(f);
  while not Eof(f) do begin readln(f, sline); writeln(sline); end;
  Close(f);
  writeln('OK');
end.
