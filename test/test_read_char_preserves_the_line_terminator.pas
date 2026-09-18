program test_read_char_preserves_the_line_terminator;
{ `read(c: Char)` must hand over the #10 that ends a line.

  The canonical Pascal text scanner is `while not Eof do read(c)`, and a line
  terminator stripped out of the buffer made that loop step SILENTLY from the
  last character of one line to the first of the next — copying stdin produced
  one long line, and no statement in the loop looked wrong. Same family as the
  over-long line: the reader merges two lines and the damage surfaces in a
  LATER, innocent-looking read. The first half asserts exactly that: c3 used to
  come back as the `4` of the next line, so `rest` read [2] instead of [42],
  and it is the readln — not the read — that appears to be wrong.

  Ord() is printed rather than the character, because a newline compared AS a
  character is invisible in the diff that is supposed to show it.

  Values are FPC 3.2.2's own output for this program under {$H+}. On the
  pre-fix compiler: c3=52, rest=[2], then <120><121> / count=2. }
var
  c: Char;
  n: Integer;
  rest: string;
begin
  read(c);  writeln('c1=', Ord(c));
  read(c);  writeln('c2=', Ord(c));
  read(c);  writeln('c3=', Ord(c));      { the terminator of line 1 }
  readln(rest);
  writeln('rest=[', rest, ']');
  n := 0;
  while not Eof do
  begin
    read(c);
    Inc(n);
    write('<', Ord(c), '>');
  end;
  writeln;
  writeln('count=', n);
end.
