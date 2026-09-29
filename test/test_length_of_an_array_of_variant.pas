program test_length_of_an_array_of_variant;
{ An array's kind is its element kind, so `array of Variant` reads tyVariant:
  Length/High of an open, dynamic or field array of Variant must count the
  array, not measure element 0's string. Expected output is fpc 3.2.2's
  (built with cwstring for UpCase of a Variant).
  bug-a-length-of-an-array-of-variant-measures-its-first-element }
{$mode objfpc}
type
  TR = record
    xs: array of Variant;
  end;
var
  d, e: array of Variant;
  f: array[0..3] of Variant;
  r: TR;
  v: Variant;

function Cnt(const a: array of Variant): Integer;
begin
  Cnt := Length(a) * 100 + High(a);
end;

begin
  SetLength(d, 5);
  d[0] := 'hello world';
  d[1] := 2;
  writeln(Length(d), ' ', High(d));
  writeln(Cnt(d), ' ', Cnt(f), ' ', Cnt([1, 'ab', 3]));
  e := Copy(d, 0, 2);
  writeln(Length(e), ' ', e[0]);
  e := Copy(d);
  writeln(Length(e));
  SetLength(r.xs, 7);
  r.xs[0] := 'x';
  writeln(Length(r.xs), ' ', High(r.xs));
  writeln(Length(f), ' ', High(f));
  v := 'abc';
  writeln(Length(v), ' ', Copy(v, 2, 2), ' ', UpCase(v));
  writeln(Length(d[0]));
end.
