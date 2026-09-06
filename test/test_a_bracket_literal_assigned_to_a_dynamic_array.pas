{ `a := [1, 2, 3]` where a is a DYNAMIC ARRAY.

  `[...]` has to parse as a set literal — nothing at the bracket knows the
  target — and the set's 32-byte MASK was then stored into the array's handle
  slot. It compiled clean, printed `len=435728179526`, and segfaulted. fpc 3.2.2
  accepts every line here and this file's .expected is its output.

  The rows are chosen so that each can fail on its own:
    - the SET rows must still be sets, and one of them is `lo..hi`, which is the
      shape an array constructor has no meaning for;
    - `'y' + 'z'` and `1 + 2` are elements the folded fast paths used to eat one
      token of and then die on (`expected ']' before '+'`);
    - `['Alpha', 'Beta']` was refused outright as `set item must be one
      character` — the refusal now belongs to the set lowering, not the element;
    - the NESTED row is the same defect one level down: retagging only the outer
      literal leaves each ROW lowering as a mask stored into a handle slot.
  feature-pascal-corpus-fpc-testsuite (tarray15/tarray16) }
{$mode objfpc}
type
  TS = set of Char;
var
  a: array of LongInt;
  s: array of String;
  m: array of array of LongInt;
  st: TS;
  bs: set of Byte;
  i, j, k: Integer;
begin
  a := [];
  Writeln('empty len=', Length(a));
  k := 7;
  a := [k, k * 2, k + 1];
  Write('expr:');
  for i := 0 to High(a) do Write(' ', a[i]);
  Writeln;
  s := ['Alpha', 'y' + 'z', 'Delta'];
  Write('str:');
  for i := 0 to High(s) do Write(' ', s[i]);
  Writeln;
  m := [[1, 2], [3, 4, 5]];
  Write('nest:');
  for i := 0 to High(m) do
  begin
    Write(' (');
    for j := 0 to High(m[i]) do Write(m[i][j], ' ');
    Write(')');
  end;
  Writeln;
  st := ['a'..'c', 'z'];
  Write('set:');
  for i := 0 to 255 do if Chr(i) in st then Write(' ', Chr(i));
  Writeln;
  st := [];
  Writeln('set empty: ', 'a' in st);
  bs := [1 + 2, 10];
  Write('byteset:');
  for i := 0 to 20 do if i in bs then Write(' ', i);
  Writeln;
end.
