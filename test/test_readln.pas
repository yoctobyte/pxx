program test_readln;
{ readln(): reads a line from stdin and parses targets by type.
  - integer (incl. negative), with leading-blank skipping
  - several integers parsed from one line (whitespace separated)
  - whole-line string
  - single char
  - bare readln consumes/skips a line
  Fed via a fixed stdin in the Makefile. }
var
  a, b, c: Integer;
  s: string;
  ch: Char;
begin
  readln(a);          { 42 }
  readln(b, c);       { 10 20 -> from one line }
  readln(s);          { hello world }
  readln(ch);         { Q }
  readln;             { skip a line }
  readln(a);          { -5 (after skip) }
  writeln(a);
  writeln(b + c);
  writeln(s);
  writeln(ch);
end.
