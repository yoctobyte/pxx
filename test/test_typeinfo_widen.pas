program test_typeinfo_widen;
{ feature-pascal-corpus-generics: TypeInfo(T) widened beyond enums (scalars,
  strings, classes, records, and generic parameters at specialization time).
  Gates the new machinery in compiler/rtti_emit.inc (EmitTypeInfoHeaders) +
  lib/rtl/typinfo.pas's TTypeInfoHdr/PTypeInfo facade, and -- just as
  important -- that the ORIGINAL enum TypeInfo() path (TEnumRTTI, read by
  GetEnumName/GetEnumNameCount) is completely unaffected, since fpjson's RTTI
  streaming suite is gated on that path staying exactly as it was. }

uses typinfo;

type
  TColor = (cRed, cGreen, cBlue);

  TPoint = record
    X, Y: Integer;
  end;

  TAnimal = class
  public
    Legs: Integer;
  end;

  generic TBox<T> = class
  public
    function KindOfT: Int64;
  end;

function TBox.KindOfT: Int64;
var pi: PTypeInfo;
begin
  pi := PTypeInfo(TypeInfo(T));
  Result := pi^.Kind;
end;

type
  TIntBox = specialize TBox<Integer>;
  TStrBox = specialize TBox<AnsiString>;

var
  piInt, piBool, piCls, piRec: PTypeInfo;
  piEnum: PEnumRTTI;
  cls: PClassRTTI;
  ib: TIntBox;
  sb: TStrBox;
  failed: Boolean;

procedure Check(cond: Boolean; const msg: string);
begin
  if not cond then
  begin
    writeln('FAIL: ', msg);
    failed := True;
  end;
end;

begin
  failed := False;

  { scalar kinds: FPC's TTypeKind ordinals (tkInteger=1, tkBool=18, tkClass=15,
    tkRecord=13) -- kept faithful to FPC's own declared order even though no
    byte-layout parity is required, see typinfo.pas's TTypeKind comment. }
  piInt := PTypeInfo(TypeInfo(Integer));
  Check(piInt <> nil, 'TypeInfo(Integer) nil');
  Check(piInt^.Kind = 1, 'TypeInfo(Integer).Kind <> tkInteger');
  Check(piInt^.NamePtr^ = 'Integer', 'TypeInfo(Integer) name');

  piBool := PTypeInfo(TypeInfo(Boolean));
  Check(piBool^.Kind = 18, 'TypeInfo(Boolean).Kind <> tkBool');

  { class: DataPtr must point at the SAME TClassRTTI blob AN_CLASSREF/GetClass
    already use -- no new class blob format, pure reuse. }
  piCls := PTypeInfo(TypeInfo(TAnimal));
  Check(piCls^.Kind = 15, 'TypeInfo(TAnimal).Kind <> tkClass');
  Check(piCls^.NamePtr^ = 'TAnimal', 'TypeInfo(TAnimal) name');
  cls := PClassRTTI(piCls^.DataPtr);
  Check(cls <> nil, 'TypeInfo(TAnimal).DataPtr nil');
  Check(GetClassName(cls) = 'TAnimal', 'TypeInfo(TAnimal).DataPtr -> wrong class RTTI');

  piRec := PTypeInfo(TypeInfo(TPoint));
  Check(piRec^.Kind = 13, 'TypeInfo(TPoint).Kind <> tkRecord');

  { REGRESSION: enum TypeInfo() must be completely untouched -- still the bare
    PEnumRTTI address, not the new header, so fpjson's GetEnumName stays green. }
  piEnum := PEnumRTTI(TypeInfo(TColor));
  Check(GetEnumNameCount(piEnum) = 3, 'enum TypeInfo() regression: count');
  Check(GetEnumName(piEnum, 0) = 'cRed', 'enum TypeInfo() regression: name0');
  Check(GetEnumName(piEnum, 2) = 'cBlue', 'enum TypeInfo() regression: name2');

  { generic parameter: pxx specializes generics by literal token substitution
    (SpecializeStream, parser.inc), so TypeInfo(T) inside TBox<Integer> is
    just TypeInfo(Integer) by the time the parser sees it -- no separate
    generic-param plumbing needed. This is the actual rung-3 unblocker
    (Generics.Defaults selects a comparer by TypeInfo(T).Kind). }
  ib := TIntBox.Create;
  sb := TStrBox.Create;
  Check(ib.KindOfT = 1, 'TypeInfo(T) in TBox<Integer> <> tkInteger');
  Check(sb.KindOfT = 9, 'TypeInfo(T) in TBox<AnsiString> <> tkAString');

  if failed then
  begin
    writeln('test_typeinfo_widen: FAILED');
    Halt(1);
  end;
  writeln('test_typeinfo_widen: OK');
end.
