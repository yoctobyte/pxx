program test_str_concat_chain_appends_in_place;
{ On riscv32 a chain `a + b + c ...` is flattened and built by one
  PXXStrConcatN call into an exact-size block, instead of concatenating the
  whole left side again per term.
  Every operand kind a term can be -- a managed string, a literal, a Char, a
  short string, an empty or unset string, a call result, the target itself --
  must give the same bytes as x86-64, and nothing may leak (run under
  -dPXX_ALLOC_CENSUS). }
{$mode objfpc}
var
  x, y, e, u: AnsiString;
  ss: ShortString;
  c: Char;
  i, sum: Integer;

function Tag(n: Integer): AnsiString;
begin
  Str(n, Result);
  Result := '<' + Result + '>';
end;

function Join3(const a, b, c: AnsiString): AnsiString;
begin
  Result := a + '|' + b + '|' + c;
end;

begin
  x := 'mid';
  y := 'abc' + x + ',' + 'def';
  writeln(y);
  c := '!';
  ss := 'short';
  e := '';
  y := x + c + ss + e + u + x + 'end';
  writeln(y, ' ', Length(y));
  y := e + u + e;
  writeln('[', y, '] ', Length(y));
  y := e + 'x' + u;
  writeln('[', y, ']');
  y := Tag(1) + Tag(22) + Tag(333) + c;
  writeln(y);
  writeln(Join3('a', x, Tag(4)));
  { the target on both sides, and twice }
  x := 'a' + x + x + 'b';
  writeln(x);
  { a long left side: the case the chain exists for }
  x := '';
  for i := 1 to 70 do x := x + '0123456789';
  sum := 0;
  for i := 1 to 200 do
  begin
    x := 'abc' + x + ',' + 'def';
    sum := sum + Length(x);
    Delete(x, 1, 3);
    Delete(x, Length(x) - 3, 4);
  end;
  writeln(Length(x), ' ', sum, ' ', Copy(x, 1, 12), ' ', Copy(x, Length(x) - 5, 6));
  { a chain as an argument and inside a comparison }
  if ('p' + x + 'q') = ('p' + x + 'q') then writeln('eq ok');
  writeln(Length('[' + Tag(5) + ']' + c + ss));
  { more terms than one flattened call takes (64): the rest is a nested chain }
  y := ss + '1' + '2' + c + '4' + '5' + ss + '7' + '8' + c + '0' + '1' + ss + '3' + '4' + c + '6' + '7' + ss + '9' + '0' + c + '2' + '3' + ss + '5' + '6' + c + '8' + '9' + ss + '1' + '2' + c + '4' + '5' + ss + '7' + '8' + c + '0' + '1' + ss + '3' + '4' + c + '6' + '7' + ss + '9' + '0' + c + '2' + '3' + ss + '5' + '6' + c + '8' + '9' + ss + '1' + '2' + c + '4' + '5' + ss + '7' + '8' + c;
  writeln(Length(y), ' ', y);
  writeln('done');
end.
