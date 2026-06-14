program test_varrec_branch;

{ Regression: an `array of const` literal lowers to a managed dyn-array temp
  (TVarRec) that the function's exit cleanup finalizes. The temp is synthesised
  during IR lowering, after the prologue zero-init pass, so it must be flagged
  for codegen's prologue nil-init. Otherwise, when the `[...]` sits in a branch
  that is NOT taken, its handle slot keeps stale stack bytes and the cleanup
  frees a garbage pointer -> segfault. Several literals in one proc, reached
  selectively, exercise exactly that. }

procedure dump(const items: array of const);
var i: Integer;
begin
  for i := 0 to Length(items) - 1 do
    if items[i].VType = vtAnsiString then writeln(PChar(items[i].VAnsiString));
end;

procedure pick(sel: Integer);
begin
  if sel = 1 then dump(['a1', 'a2', 'a3'])
  else if sel = 2 then dump(['b1', 'b2'])
  else if sel = 3 then dump(['c1'])
  else if sel = 4 then dump(['d1', 'd2', 'd3', 'd4'])
  else if sel = 5 then dump(['e1', 'e2'])
  else writeln('none');
end;

var i: Integer;
begin
  for i := 0 to 6 do
    pick(i);
end.
