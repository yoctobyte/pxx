program test_const_array_of_record;
{ Typed const array-of-RECORD with named-field element initializers —
  Pascal Script's keyword LookupTable shape (feature-embed-pascal-script). }
type
  TRTab = record
    name: AnsiString;
    c: Integer;
  end;
const
  Tab: array[0..2] of TRTab = (
    (name: 'AND'; c: 1),
    (name: 'OR'; c: 2),
    (name: 'XOR'; c: 3));
type
  TAlias = AnsiString;
var i: Integer; s: AnsiString;
begin
  for i := 0 to 2 do
    writeln(Tab[i].name, '=', Tab[i].c);
  s := 'x y';
  writeln(Pos(TAlias(' '), s));   { string-alias cast = value no-op }
end.
