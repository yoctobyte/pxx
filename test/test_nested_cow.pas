program test_nested_cow;

{ Copy-on-write at nested dynamic-array levels. Aliasing a nested array
  (`b := a`) shares the outer block; a write through one alias
  (`b[i][j] := v`) must clone every shared level down the index path so the
  other alias is untouched. Each IR_DYNUNIQUE on the write chain clones its
  level if shared (retaining sub-array handles and managed leaves so the clone
  holds its own references) and leaves a unique handle behind. Reads never
  clone. Covers 2- and 3-level integer arrays, nested managed strings, sibling
  integrity, and repeated reuse. }

{$define PXX_MANAGED_STRING}

procedure Check(ok: Boolean);
begin
  if ok then writeln(1) else writeln(0);
end;

var
  a, b: array of array of Integer;
  c, d: array of array of array of Integer;
  s, t: array of array of AnsiString;
  i, good: Integer;
begin
  { 2-level: write through one alias leaves the other and its siblings intact. }
  SetLength(a, 2);
  SetLength(a[0], 2); SetLength(a[1], 2);
  a[0][0] := 5; a[0][1] := 6; a[1][0] := 7;
  b := a;
  b[0][0] := 99;
  Check(a[0][0] = 5);     { original untouched }
  Check(b[0][0] = 99);    { alias mutated }
  Check(a[0][1] = 6);     { sibling in the cloned sub-array intact }
  Check(b[0][1] = 6);     { clone copied the sibling }
  Check(a[1][0] = 7);     { untouched sub-array still shared/correct }
  Check(b[1][0] = 7);

  { 3-level. }
  SetLength(c, 2); SetLength(c[0], 2); SetLength(c[0][0], 2);
  c[0][0][0] := 11; c[0][0][1] := 12;
  d := c;
  d[0][0][0] := 88;
  Check(c[0][0][0] = 11);
  Check(d[0][0][0] = 88);
  Check(c[0][0][1] = 12);
  Check(d[0][0][1] = 12);

  { Nested managed strings: clone must retain string elements. }
  SetLength(s, 2); SetLength(s[0], 2);
  s[0][0] := 'orig'; s[0][1] := 'keep';
  t := s;
  t[0][0] := 'changed';
  Check(s[0][0] = 'orig');
  Check(t[0][0] = 'changed');
  Check(s[0][1] = 'keep');
  Check(t[0][1] = 'keep');

  { Reuse: repeated alias+write must stay correct (no corruption/leak path). }
  good := 0;
  for i := 1 to 1000 do
  begin
    b := a;
    b[0][0] := i;
    if (a[0][0] = 5) and (b[0][0] = i) then Inc(good);
  end;
  Check(good = 1000);
end.
