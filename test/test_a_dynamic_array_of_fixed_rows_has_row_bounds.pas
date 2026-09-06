{ `var v: array of array[2..5] of LongInt` — the ANONYMOUS spelling of a
  dynamic array whose element is a fixed row, and the row bounds of `v[i]`.

  Two defects, and the first one's diagnostic was the trap. The anonymous
  spelling answered *"mixed static/dynamic nested arrays not supported"*, which
  is FALSE about the capability: `type TR = array[2..5] of LongInt; var v:
  array of TR` compiles and runs today through the alias arm. The refusal was
  about the SPELLING, and a message saying "not supported" about a shape the
  compiler supports sends every reader to build what already exists.

  Second, on BOTH spellings: Length, Low and High of a row answered 0, 0 and -1
  against fpc's 4, 2 and 5. The row's extent is on the base SYMBOL and nothing
  puts it on the index node, so all three fell through to the dynamic-array
  answer while `v[i][j]` indexed correctly. `for j := Low(r) to High(r)` did not
  run — a silent wrong value in the canonical spelling.

  EVERY ROW IS ASSERTED FOR BOTH SPELLINGS SIDE BY SIDE, because the point of
  the fix is that they produce ONE symbol: three separate functions in this
  compiler answer "how deep is this array" and two are already known to
  disagree, so a construct whose two spellings build one symbol is the only kind
  that cannot host a fourth divergence.
  feature-pascal-corpus-fpc-testsuite (tarray15) }
{$mode objfpc}
type
  TR = array[2..5] of LongInt;

procedure Take(const a: array of TR);
begin
  Writeln('take len=', Length(a), ' a[0][3]=', a[0][3]);
end;

var
  alias: array of TR;
  anon: array of array[2..5] of LongInt;
  i, j: Integer;
begin
  SetLength(alias, 2);
  SetLength(anon, 2);
  for i := 0 to 1 do
    for j := 2 to 5 do
    begin
      alias[i][j] := i * 10 + j;
      anon[i][j] := i * 10 + j;
    end;
  Writeln('len ', Length(alias), ' ', Length(anon));
  Writeln('high ', High(alias), ' ', High(anon));
  Writeln('row len ', Length(alias[0]), ' ', Length(anon[0]));
  Writeln('row lo ', Low(alias[0]), ' ', Low(anon[0]));
  Writeln('row hi ', High(alias[0]), ' ', High(anon[0]));
  for i := 0 to 1 do
  begin
    for j := Low(alias[i]) to High(alias[i]) do Write(alias[i][j], ' ');
    Write('| ');
    for j := Low(anon[i]) to High(anon[i]) do Write(anon[i][j], ' ');
    Writeln;
  end;
  Take(alias);
  Take(anon);
  SetLength(anon, 3);
  anon[2][2] := 99;
  Writeln('grown ', Length(anon), ' ', anon[2][2], ' ', anon[1][5]);
end.
