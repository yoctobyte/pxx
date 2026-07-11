program test_overload_record_identity_fail;
type
  TVec2 = record x, y: Double; end;
  TVec3 = record x, y, z: Double; end;
  TVec4 = record x, y, z, w: Double; end;
function Dot(const a, b: TVec2): Double; overload;
begin Dot := a.x*b.x + a.y*b.y; end;
function Dot(const a, b: TVec3): Double; overload;
begin Dot := a.x*b.x + a.y*b.y + a.z*b.z; end;
var v4a, v4b: TVec4;
begin
  v4a.x := 1; v4b.x := 2;
  writeln(Dot(v4a, v4b):0:1);   { must ERROR: no overload takes TVec4 }
end.
