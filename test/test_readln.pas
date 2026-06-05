program test_readln;
{ readln(): reads a line from stdin and parses targets by type.
  - integer (incl. negative), with leading-blank skipping
  - several integers parsed from one line (whitespace separated)
  - whole-line string
  - single char
  - bare readln consumes/skips a line
  - separate read calls on one line preserve remainder
  Fed via a fixed stdin in the Makefile. }
var
  a, b, c: Integer;
  x, y, z: Integer;
  s: string;
  ch: Char;
begin
  read(x);            { 100 }
  read(y);            { 200 }
  readln(z);          { 300 }
  readln(a);          { 42 }
  readln(b, c);       { 10 20 -> from one line }
  readln(s);          { hello world }
  readln(ch);         { Q }
  readln;             { skip a line }
  readln(a);          { -5 (after skip) }
  writeln(x);
  writeln(y);
  writeln(z);
  writeln(a);
  writeln(b + c);
  writeln(s);
  writeln(ch);
end.
