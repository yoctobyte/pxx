{ A function whose result is a typed pointer carries its element type, so the
  call result can be dereferenced and field-accessed directly — `f^.field` —
  without storing it in a typed intermediate variable first. Proves
  ProcRetPtrElem* plus ResolveNodeRec's AN_DEREF-over-AN_CALL case (the field
  offset must come from the callee's return element record, not REC_NONE). }
program test_func_ptr_return;
type
  Point = record x, y, z: Integer; end;
  PPoint = ^Point;
var
  g: Point;
function origin: PPoint;
begin
  Result := @g;
end;
begin
  g.x := 7; g.y := 8; g.z := 9;
  writeln(origin^.x);   { 7 }
  writeln(origin^.y);   { 8 — distinct offset, the bug this fixes }
  writeln(origin^.z);   { 9 }
end.
