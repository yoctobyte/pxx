program test_class_of;

uses typinfo;

type
  TBase = class
  published
    Tag: Integer;
  end;
  TChild = class(TBase)
  end;
  TBaseClass = class of TBase;

function ClassNameOf(C: TBaseClass): string;
var
  Meta: PClassRTTI;
begin
  Meta := C;
  Result := GetClassName(Meta);
end;

var
  C: TBaseClass;
begin
  C := TChild;
  writeln(ClassNameOf(C));
end.
