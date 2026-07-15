program test_dynarray_of_fixed_array;
{ Dynamic array / open-array param whose ELEMENT is a named FIXED array
  (bug-pascal-openarray-of-array-param-marshal). The element is a whole ROW:
  d[i] strides RowLen*base size, d[i][j] indexes within the row (honouring the
  row's own low bound), r := d[i] / d[i] := r row-copy, SetLength allocates
  count*rowsize, the `[e0, e1]` open-array ctor builds row-sized elements, and
  for-in over an open-array param uses the runtime Length (not the ArrLen=1000
  placeholder; tforin14). Self-checks print `ok <n>`; last line is the count. }

type
  T = array[1..3] of Integer;
  TDA = array of T;   { named dyn alias of a fixed-array element }

var
  okCount: Integer;

procedure Chk(n: Integer; cond: Boolean);
begin
  if cond then begin writeln('ok ', n); okCount := okCount + 1; end
  else writeln('FAIL ', n);
end;

procedure POpen(a: array of T);
var
  r: T;
  sum, i: Integer;
begin
  Chk(10, Length(a) = 2);
  r := a[1];                          { row-copy out of the open array }
  Chk(11, (r[1] = 3) and (r[2] = 4) and (r[3] = 8));
  Chk(12, a[0][2] = 2);               { direct sub-index }
  sum := 0;
  for r in a do                       { runtime-Length bound, row elements }
    for i in r do sum := sum + i;
  Chk(13, sum = 1 + 2 + 7 + 3 + 4 + 8);
end;

procedure DirectDyn;
var
  d: array of T;
  g: T;
  r: T;
begin
  g[1] := 1; g[2] := 2; g[3] := 7;
  SetLength(d, 2);
  Chk(1, Length(d) = 2);
  d[0] := g;                          { row store }
  d[1][1] := 3; d[1][2] := 4; d[1][3] := 8;   { sub-index stores, low bound 1 }
  Chk(2, (d[0][1] = 1) and (d[0][3] = 7));
  Chk(3, (d[1][1] = 3) and (d[1][3] = 8));
  r := d[1];                          { row load }
  Chk(4, (r[1] = 3) and (r[2] = 4) and (r[3] = 8));
  d[0][2] := 55;
  Chk(5, d[0][2] = 55);
  Chk(6, d[1][2] = 4);                { neighbour row untouched: stride is a row }
  SetLength(d, 3);                    { grow preserves rows }
  Chk(7, (Length(d) = 3) and (d[1][3] = 8) and (d[2][1] = 0));
end;

procedure AliasDyn;
var
  d: TDA;
  r: T;
begin
  SetLength(d, 2);
  d[1][1] := 21; d[1][3] := 23;
  r := d[1];
  Chk(8, (r[1] = 21) and (r[2] = 0) and (r[3] = 23));
  Chk(9, d[0][1] = 0);
end;

var
  g0, g1: T;
begin
  okCount := 0;
  DirectDyn;
  AliasDyn;
  g0[1] := 1; g0[2] := 2; g0[3] := 7;
  g1[1] := 3; g1[2] := 4; g1[3] := 8;
  POpen([g0, g1]);                    { open-array ctor with row elements }
  writeln('total ok ', okCount, ' / 13');
end.
