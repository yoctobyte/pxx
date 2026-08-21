program test_dynarray_copy_nested;
{ Copy() on a NESTED dynamic array
  (feature-dynarray-copy-nested-element-type).

  This used to SEGFAULT and was then refused with a diagnostic. The crash is
  the thing to remember while reading: AN_DYN_COPY took its element size from
  the source's BASE element type, so `array of array of Integer` strode the raw
  copy by 4 while the elements are sub-array HANDLES. Element 0 was right by
  luck (offset 0) and element 1 onward read a bogus handle.

  Three properties, one per thing that had to change together:

  1. STRIDE — `h[1][1]` is the assertion. `h[0][0]` alone passes even with the
     wrong stride, which is exactly why the original bug looked like it worked.

  2. ONE-LEVEL DETACH — `Copy` gives a fresh OUTER block whose elements are the
     SAME sub-arrays, so writing through the copy is visible in the source.
     Verified against FPC, and the same semantics test_nested_alias.pas pins for
     plain assignment. A deep copy is per level, spelled `Copy(g[i])`.

  3. THE RETAIN — without it the copy's scope-exit release, now recursive
     because the temp is allocated at the source's depth, frees blocks the
     SOURCE still owns. That is invisible on a plain run (the bytes are still
     there until something reuses them) and shows up under -dPXX_HEAP_DEBUG,
     which fills freed memory with $DD. The `after-copy-scope` reads below are
     the ones that catch it, and they are meaningless unless this test is ALSO
     run with that flag — the Makefile runs it both ways for that reason.

  Depth 3 is here because depth 2 can pass with an off-by-one in the depth
  plumbing (1 vs "the source's depth" differ only from 2 upward, and 2 vs 3
  catches passing a constant 2). AnsiString leaves check that a managed base
  under nesting is not double-freed: the sub-arrays own the strings, the outer
  copy owns only handles.

  Oracle: FPC prints the same lines. }

type
  TG = array of array of Integer;
  TG3 = array of array of array of Integer;
  TS = array of array of AnsiString;

procedure CopyInAScope(const src: TG);
var
  tmp: TG;
begin
  { The copy dies at this procedure's exit. If the retain is missing, its
    recursive release takes the caller's sub-arrays with it. }
  tmp := Copy(src, 0, 2);
  WriteLn('inner=', tmp[1][1]);
end;

var
  g, h: TG;
  t, u: TG3;
  s, v: TS;
  i, j, k: Integer;

begin
  { --- depth 2 --- }
  SetLength(g, 3);
  for i := 0 to 2 do
  begin
    SetLength(g[i], 2);
    for j := 0 to 1 do
      g[i][j] := i * 2 + j + 1;
  end;
  h := Copy(g, 0, 2);
  WriteLn('lenh=', Length(h), ' h00=', h[0][0], ' h11=', h[1][1]);
  h[0][0] := 99;
  WriteLn('one-level-detach g00=', g[0][0]);

  { --- the retain, observed after the copy's scope is gone --- }
  CopyInAScope(g);
  WriteLn('after-copy-scope g11=', g[1][1], ' g22=', g[2][1]);

  { --- depth 3 --- }
  SetLength(t, 2);
  for i := 0 to 1 do
  begin
    SetLength(t[i], 2);
    for j := 0 to 1 do
    begin
      SetLength(t[i][j], 2);
      for k := 0 to 1 do
        t[i][j][k] := (i * 4) + (j * 2) + k;
    end;
  end;
  u := Copy(t, 0, 2);
  WriteLn('t3 len=', Length(u), ' u111=', u[1][1][1], ' u010=', u[0][1][0]);

  { --- managed leaves under nesting --- }
  SetLength(s, 2);
  for i := 0 to 1 do
  begin
    SetLength(s[i], 2);
    s[i][0] := 'row';
    s[i][1] := 'end';
  end;
  v := Copy(s, 0, 2);
  WriteLn('str v00=', v[0][0], ' v11=', v[1][1]);
  v := nil;
  WriteLn('source-survives s11=', s[1][1]);
end.
