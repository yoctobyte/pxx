{ Regression: bug-overload-resolution-record-identity — overloads differing
  only in RECORD type must dispatch on record identity (both declaration
  orders), records and classes must not cross-match, and a call with a record
  type no overload takes must error (checked by the *_fail companion). }
program test_overload_record_identity;
type
  TVec2 = record x, y: Double; end;
  TVec3 = record x, y, z: Double; end;
  TThing = class public v: Integer; end;

{ reversed declaration order }
function Dot(const a, b: TVec3): Double; overload;
begin
  Dot := a.x*b.x + a.y*b.y + a.z*b.z;
end;

function Dot(const a, b: TVec2): Double; overload;
begin
  Dot := a.x*b.x + a.y*b.y;
end;

{ record vs class overload }
function Kind(const r: TVec2): string; overload;
begin
  Kind := 'vec2';
end;

function Kind(o: TThing): string; overload;
begin
  Kind := 'thing';
end;

var v2a, v2b: TVec2; v3a, v3b: TVec3; th: TThing;
begin
  v2a.x := 1; v2a.y := 2; v2b.x := 3; v2b.y := 4;
  v3a.x := 1; v3a.y := 0; v3a.z := 5;
  v3b.x := 2; v3b.y := 0; v3b.z := 7;
  writeln(Dot(v2a, v2b):0:1);   { 11.0 }
  writeln(Dot(v3a, v3b):0:1);   { 37.0 }
  writeln(Kind(v2a));           { vec2 }
  th := TThing.Create;
  writeln(Kind(th));            { thing }
end.
