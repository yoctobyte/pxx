program test_classref;

{ Metaclass / class-reference values: a class identifier used as a value yields
  its PClassRTTI. Must equal GetClass(name), expose the name, and allocate an
  instance whose published prop is settable via RTTI. }

uses typinfo;

type
  TFoo = class
  private
    FTag: Integer;
  published
    property Tag: Integer read FTag write FTag;
  end;

var
  cref, byname: PClassRTTI;
  nm: string;
  inst: Pointer;
  p: PPropInfo;

begin
  cref := TFoo;                 { class identifier as a value }
  byname := GetClass('TFoo');

  if cref = byname then writeln('same: yes') else writeln('same: no');

  nm := cref^.NamePtr^;
  writeln('name=', nm);

  inst := CreateInstance(cref);
  p := GetPropInfo(cref, 'Tag');
  SetOrdProp(inst, p, 99);
  writeln('Tag=', GetOrdProp(inst, p));
end.
