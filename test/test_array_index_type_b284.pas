{ An array indexed by an ordinal TYPE rather than a literal range:

      ElementSeps : Array[Boolean] of TJSONStringType = (', ', ',');   { fpjson }
      Counts      : array[TColor] of Integer;
      Table       : array[Char] of Byte;

  meaning [0..1], [0..High(TColor)] and [0..255]. Only `lo..hi` parsed before, so the type
  name went into ConstEval and died on the missing `..`.

  A bare identifier is ambiguous -- `array[MaxLen..2]` starts with one too -- so an ident is
  read as a TYPE only when it is NOT followed by `..` and it names an enum type. }
program test_array_index_type_b284;
type
  TColor = (Red, Green, Blue);
const
  Seps: array[Boolean] of string = (', ', ',');
  Names: array[TColor] of string = ('red', 'green', 'blue');
var
  counts: array[TColor] of Integer;
  flags: array[Boolean] of Integer;
  tab: array[Char] of Byte;
  c: TColor;
begin
  writeln('sep[false]=[', Seps[False], '] sep[true]=[', Seps[True], ']');
  for c := Red to Blue do write(Names[c], ' ');
  writeln;
  counts[Green] := 7;
  writeln('counts[Green]=', counts[Green]);
  flags[True] := 42;
  writeln('flags[True]=', flags[True]);
  tab[Ord('A')] := 9;
  writeln('tab[A]=', tab[Ord('A')]);
  { the ordinary range form must still work }
  writeln('ok');
end.
