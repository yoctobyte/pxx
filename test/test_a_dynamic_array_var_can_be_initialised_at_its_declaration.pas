{ `var v: array of LongInt = (1, 2, 3);` — objfpc spells it with parens,
  Delphi with brackets, and a FIXED array of dynamic arrays takes one list per
  element. A dynamic array is a HEAP object, so there is no constant form to
  bake: the initialiser stays an expression and runs at program entry as the
  assignment it is, which means it meets the SAME retag a written `v := [...]`
  meets and the two spellings cannot disagree.

  Two rows carry a defect that only appears in company:
    - TWO initialised arrays. The AST arena is per-proc scratch and this is the
      one pending-init kind that keeps a NODE rather than a constant, so the
      second one's nodes were re-allocated as the first one's assignment
      (`invalid IR node reference in store_mem value`). One array was fine.
    - `array[0..2] of array of LongInt`, both the TYPE (which answered
      `unknown type: array` while the named-alias spelling of the same shape
      worked) and the per-element initialiser (whose inner lists were read as
      extra DIMENSIONS: `too many array initializer elements`).
  feature-pascal-corpus-fpc-testsuite (tarray15/tarray16) }
{$mode objfpc}
var
  v1: array of LongInt = Nil;
  v2: array of LongInt = ();
  v3: array of LongInt = (1, 2, 3);
  v4: array of String = ('Alpha', 'Beta', 'Gamma');
  v5: array[0..2] of array of LongInt = (Nil, (), (1, 2, 3));
  v6: array of LongInt = (9, 8);
  i, j: Integer;
begin
  Writeln('v1=', Length(v1), ' v2=', Length(v2));
  Write('v3:');
  for i := 0 to High(v3) do Write(' ', v3[i]);
  Writeln;
  Write('v4:');
  for i := 0 to High(v4) do Write(' ', v4[i]);
  Writeln;
  for i := 0 to 2 do
  begin
    Write('v5[', i, ']:');
    for j := 0 to High(v5[i]) do Write(' ', v5[i][j]);
    Writeln(' (len ', Length(v5[i]), ')');
  end;
  Write('v6:');
  for i := 0 to High(v6) do Write(' ', v6[i]);
  Writeln;
  { still assignable afterwards — an initialised dynamic array is a variable,
    not a constant }
  v3 := [7];
  Writeln('v3 after: ', Length(v3), ' ', v3[0]);
end.
