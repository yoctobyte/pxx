{ A PASCAL unit compiled into a NilPy program, reaching TObject members through
  a plain local rather than a cast.

  bug-classname-on-a-tobject-local-compiles-to-a-dynamic-attr-fetch: the NilPy
  dynamic-attribute fallback was gated on `isNilPy`, which is true for the WHOLE
  compilation — every Pascal unit loaded into it included. So inside this unit
  `o.ClassName` on a `TObject` local became a pydynattr_get and died at run time
  with "'Dog' object has no attribute 'ClassName'", while the identical
  `TObject(p).ClassName` resolved to the RTTI call and worked. Same type, same
  meaning, different SHAPE — the shape-blindspot pattern.

  Both spellings live here on purpose: the cast form is the control, and a
  regression that re-broke only the local form would otherwise look like a
  whole-file failure rather than the one-line divergence it is. }
unit tobjprobe;
interface
function NameViaLocal(p: Pointer): AnsiString;
function NameViaCast(p: Pointer): AnsiString;
function ClassTypeNameViaLocal(p: Pointer): AnsiString;
implementation

function NameViaLocal(p: Pointer): AnsiString;
var o: TObject;
begin
  o := TObject(p);
  Result := o.ClassName;
end;

function NameViaCast(p: Pointer): AnsiString;
begin
  Result := TObject(p).ClassName;
end;

function ClassTypeNameViaLocal(p: Pointer): AnsiString;
var o: TObject;
begin
  o := TObject(p);
  Result := o.ClassType.ClassName;
end;

end.
