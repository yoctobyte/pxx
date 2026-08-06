program test_nested_alias;

{ ALIASING at nested dynamic-array levels. `b := a` makes the two names one
  array, and a write through either — at any depth — is visible through the
  other, because there is only one array. `SetLength` and `Copy` are what
  detach.

  This file replaces test_nested_cow.pas, which asserted the opposite. Nested
  copy-on-write was a deliberate x86-64 invariant ("a write through one alias
  never mutates another at any depth"); it was also unique to x86-64 among the
  targets and the opposite of FPC/Delphi, where a dynamic array is a reference
  type all the way down. decide-dynamic-array-value-vs-reference-semantics
  settled on matching FPC and
  bug-a-x86-64-dynarray-assignment-copies-instead-of-aliasing removed the clone
  from all four backends.

  Renamed rather than edited in place: the old name states the behaviour it
  tested, and that behaviour is gone. Every value below was diffed against an
  FPC build of this same file — the coverage axes are the old file's (2-level,
  3-level, managed strings, sibling integrity, repeated reuse) because those
  were the right axes; only the expected answers changed. }

{$define PXX_MANAGED_STRING}

procedure Check(ok: Boolean);
begin
  if ok then writeln(1) else writeln(0);
end;

var
  a, b: array of array of Integer;
  c, d: array of array of array of Integer;
  s, t: array of array of AnsiString;
  e, f: array of array of Integer;
  i, good: Integer;
begin
  { 2-level: the write through one name is visible through the other, and the
    siblings it did NOT touch keep their values through both. }
  SetLength(a, 2);
  SetLength(a[0], 2); SetLength(a[1], 2);
  a[0][0] := 5; a[0][1] := 6; a[1][0] := 7;
  b := a;
  b[0][0] := 99;
  Check(a[0][0] = 99);    { shared, at depth }
  Check(b[0][0] = 99);
  Check(a[0][1] = 6);     { the sibling element is untouched }
  Check(b[0][1] = 6);
  Check(a[1][0] = 7);     { and so is the other sub-array }
  Check(b[1][0] = 7);

  { the write may just as well go through the FIRST name }
  a[1][0] := 70;
  Check(b[1][0] = 70);

  { 3-level: the whole index path is shared, not just the first level. }
  SetLength(c, 2); SetLength(c[0], 2); SetLength(c[0][0], 2);
  c[0][0][0] := 11; c[0][0][1] := 12;
  d := c;
  d[0][0][0] := 88;
  Check(c[0][0][0] = 88);
  Check(d[0][0][0] = 88);
  Check(c[0][0][1] = 12);
  Check(d[0][0][1] = 12);

  { Nested MANAGED strings: sharing must not depend on the leaf being a scalar,
    and the released/retained element must not be corrupted by the shared write. }
  SetLength(s, 2); SetLength(s[0], 2);
  s[0][0] := 'orig'; s[0][1] := 'keep';
  t := s;
  t[0][0] := 'changed';
  Check(s[0][0] = 'changed');
  Check(t[0][0] = 'changed');
  Check(s[0][1] = 'keep');
  Check(t[0][1] = 'keep');

  { SetLength on the OUTER level detaches, as in FPC — the one place a copy
    still happens, and the reason Copy(a) had to exist before this landed. }
  SetLength(e, 1); SetLength(e[0], 1); e[0][0] := 1;
  f := e;
  SetLength(f, 2);
  f[0][0] := 42;
  { NOTE: the outer block is fresh, but its element still holds the SAME
    sub-array handle it was copied from — so a write through f[0][0] reaches
    e[0][0]. That is FPC's answer too, and it is the subtle half of "SetLength
    detaches": it detaches ONE level, not the whole tree. }
  Check(e[0][0] = 42);
  Check(Length(e) = 1);
  Check(Length(f) = 2);

  { Reuse: repeated alias+write must stay correct and not corrupt anything.
    a[0][0] now tracks the last value written, since the two are one array. }
  good := 0;
  for i := 1 to 1000 do
  begin
    b := a;
    b[0][0] := i;
    if (a[0][0] = i) and (b[0][0] = i) then Inc(good);
  end;
  Check(good = 1000);
end.
