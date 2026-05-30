program test_char_to_string;
{ char -> string coercion: single-char literal, Char var, Chr(), and
  char+char / char+string / string+char concatenation all materialise
  proper strings (previously segfaulted). }
type
  TRec = class
  public
    F: string;
  end;
var
  s, a: string;
  c: Char;
  i: Integer;
  r: TRec;
begin
  s := 'x';            writeln(s);          { x }
  c := 'y'; s := c;    writeln(s);          { y }
  s := 'a' + 'b';      writeln(s);          { ab }
  a := 'ZZ';
  s := a + c;          writeln(s);          { ZZy }
  s := c + a;          writeln(s);          { yZZ }
  s := c + c;          writeln(s);          { yy }
  s := Chr(65);        writeln(s);          { A }
  s := '';
  for i := 1 to 3 do s := s + 'q';
  writeln(s);                               { qqq }
  r := TRec.Create;
  r.F := 'z';          writeln(r.F);        { z: char -> string class field }
  writeln('done');
end.
