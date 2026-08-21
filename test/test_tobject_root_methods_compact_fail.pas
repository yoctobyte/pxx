program test_tobject_root_methods_compact_fail;
{ --compact-classes reserves NO root VMT slots (the pre-2026-08-21 layout, and
  what --platform=esp implies), so there is no TObject.Equals to override. That
  must be a compile ERROR naming the method, never a silently non-dispatching
  method. feature-a-tobject-root-method-vmt-slots }
type
  TThing = class
    function Equals(Obj: TObject): Boolean; override;
  end;
function TThing.Equals(Obj: TObject): Boolean;
begin
  Result := Obj = nil;
end;
var t: TThing;
begin
  t := TThing.Create;
  WriteLn(t.Equals(nil));
end.
