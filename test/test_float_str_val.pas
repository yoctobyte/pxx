program TestFloatStrVal;
{ Float Str/Val round-trip. Str(x:w:d) fixed-decimal formatting matches FPC;
  Val parses [-]int[.frac][e[-]exp] into a Double. Integer Str/Val unchanged. }
var
  x, y: Double;
  s: String;
  n: Int64;
  code: Integer;
begin
  { Str — fixed decimals + width }
  x := 3.14159;
  Str(x:0:2, s); writeln('[', s, ']');     { [3.14] }
  Str(x:10:4, s); writeln('[', s, ']');    { [    3.1416] }
  x := -2.75;
  Str(x:0:3, s); writeln('[', s, ']');     { [-2.750] }
  x := 1000.5;
  Str(x:0:1, s); writeln('[', s, ']');     { [1000.5] }

  { Val — Double destination }
  Val('42.75', x, code); writeln(x:0:4, ' code=', code);
  Val('-1.5', y, code); writeln(y:0:4, ' code=', code);
  Val('100', x, code); writeln(x:0:2, ' code=', code);
  Val('3.5e2', x, code); writeln(x:0:2, ' code=', code);
  Val('1.25e-1', x, code); writeln(x:0:4, ' code=', code);
  Val('bad', x, code); writeln('code=', code);

  { integer Str/Val still work }
  Str(42:5, s); writeln('[', s, ']');       { [   42] }
  Val('-99', n, code); writeln(n, ' code=', code);
end.
