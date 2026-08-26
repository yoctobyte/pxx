program test_typeinfo_typedata;
{ TypeInfo(T)^.DataPtr must carry a TTypeData, not nil.

  Every row below was diffed against an FPC 3.2.2 oracle (the same program
  written against FPC's own variant TTypeData), not recalled. The LAYOUT is
  ours — see TYPEDATA_SIZE in compiler/defs.inc for why we owe FPC no
  byte-layout parity — but the VALUES are FPC's, with exactly two documented
  exceptions, both marked below:

    * a SUBRANGE's OrdType reports the width pxx stores it in (4 bytes), not
      FPC's narrowed one. MinValue/MaxValue still match FPC exactly. A comparer
      selected from OrdType reads that many bytes, so FPC's answer would make it
      read one byte of a four-byte value here.
    * pxx's Integer is its own kind, so TypeInfo(Integer) says "Integer" where
      FPC says "LongInt" — decide-typeinfo-scalar-name-spelling, pre-existing
      and unrelated to the payload.

  feature-typeinfo-ttypedata-payloads }

uses typinfo;

type
  TSub    = 1..10;
  TSubB   = -5..5;
  TEn     = (eA, eB, eC);
  TMyInt  = Integer;
  TS      = set of TEn;
  TStr20  = string[20];
  TArr    = array[0..3] of Integer;
  TArr2   = array[1..2, 1..3] of Byte;
  TDyn    = array of Integer;

var
  p: PTypeInfo;
  d: PTypeData;
  et: PEnumRTTI;
  dims: PTypeDataDims;
  i: Integer;

{ ordinal row: kind, name, OrdType, MinValue, MaxValue }
procedure O(const w: string; q: Pointer);
begin
  p := PTypeInfo(q);
  d := GetTypeData(p);
  Write(w, ' kind=', p^.Kind, ' name=', p^.NamePtr^);
  if d = nil then WriteLn(' <no typedata>')
  else WriteLn(' ord=', Ord(d^.OrdType), ' min=', d^.MinValue,
               ' max=', d^.MaxValue);
end;

{ float row: kind, name, FloatType (which shares the OrdType slot) }
procedure F(const w: string; q: Pointer);
begin
  p := PTypeInfo(q);
  d := GetTypeData(p);
  Write(w, ' kind=', p^.Kind, ' name=', p^.NamePtr^);
  if d = nil then WriteLn(' <no typedata>')
  else WriteLn(' float=', Ord(d^.FloatType));
end;

{ set row: the element's kind, ord width and range }
procedure S(const w: string; q: Pointer);
begin
  p := PTypeInfo(q);
  d := GetTypeData(p);
  Write(w, ' kind=', p^.Kind, ' name=', p^.NamePtr^);
  if d = nil then WriteLn(' <no typedata>')
  else
  begin
    Write(' ord=', Ord(d^.OrdType), ' elemkind=', d^.ElemKind,
          ' elemsize=', d^.ElemSize, ' min=', d^.MinValue,
          ' max=', d^.MaxValue);
    { ElemRef must reach the element enum's OWN blob -- FPC's oracle answers
      CompType^.Name = 'TEn' here, and a broken data->data fixup is exactly the
      failure a nil or a wrong name would expose. }
    if d^.ElemRef <> nil then
    begin
      et := PEnumRTTI(d^.ElemRef);
      Write(' comp=', et^.NamePtr^, ' compcount=', et^.Count);
    end;
    WriteLn;
  end;
end;

{ array row: element kind/size, total count, dimensions and their bounds }
procedure A(const w: string; q: Pointer);
begin
  p := PTypeInfo(q);
  d := GetTypeData(p);
  Write(w, ' kind=', p^.Kind, ' name=', p^.NamePtr^);
  if d = nil then begin WriteLn(' <no typedata>'); Exit; end;
  Write(' elemkind=', d^.ElemKind, ' elemsize=', d^.ElemSize,
        ' elemcount=', d^.ElemCount, ' dims=', d^.DimCount);
  if d^.DimsPtr <> nil then
  begin
    dims := PTypeDataDims(d^.DimsPtr);
    for i := 0 to Integer(d^.DimCount) - 1 do
      Write(' [', dims^[i].Lo, '..', dims^[i].Hi, ']');
  end;
  WriteLn;
end;

begin
  { --- builtin ordinals: OrdType + full range, all thirteen match FPC --- }
  O('ShortInt', TypeInfo(ShortInt));
  O('Byte', TypeInfo(Byte));
  O('SmallInt', TypeInfo(SmallInt));
  O('Word', TypeInfo(Word));
  O('Integer', TypeInfo(Integer));
  O('LongWord', TypeInfo(LongWord));
  O('Int64', TypeInfo(Int64));
  O('Boolean', TypeInfo(Boolean));
  O('Char', TypeInfo(Char));

  { --- floats: the OrdType slot carries Ord(TFloatType) --- }
  F('Single', TypeInfo(Single));
  F('Double', TypeInfo(Double));

  { --- named types --- }
  O('TSub', TypeInfo(TSub));      { bounds match FPC; ord is OUR width (4) }
  O('TSubB', TypeInfo(TSubB));
  O('TMyInt', TypeInfo(TMyInt));  { a plain rename inherits the base range }
  O('TStr20', TypeInfo(TStr20));  { max IS FPC's MaxLength }
  S('TS', TypeInfo(TS));
  A('TArr', TypeInfo(TArr));
  A('TArr2', TypeInfo(TArr2));
  A('TDyn', TypeInfo(TDyn));

  { --- the kinds that deliberately have NO descriptor --- }
  O('Pointer', TypeInfo(Pointer));
  O('Variant', TypeInfo(Variant));
end.
