program test_rtti;

uses typinfo;

type
  TAlign = (alNone, alLeft, alRight, alClient);
  TAlignSet = set of TAlign;

  TBase = class
  private
    FId: Integer;
  published
    property Id: Integer read FId write FId;
  end;

  TChild = class(TBase)
  private
    FCaption: string;
    FAlign:   TAlign;
    FAligns:  TAlignSet;
    FOnClick: TMethod;
  published
    property Caption: string read FCaption write FCaption;
    property Align:   TAlign read FAlign write FAlign;
    property Aligns:  TAlignSet read FAligns write FAligns;
    property OnClick: TMethod read FOnClick write FOnClick;
    procedure DummyHandler;
  end;

procedure TChild.DummyHandler;
begin
  writeln('handler executed');
end;

var
  c: TChild;
  cls: PClassRTTI;
  parentCls: PClassRTTI;
  p: PPropInfo;
  meth: TMethod;
  list: array[0..511] of PPropInfo;
  cnt, i: Integer;
  st: TAlignSet;
begin
  c := TChild.Create;

  { 1. GetClass RTTI }
  cls := GetClass('TChild');
  if cls = nil then
  begin
    writeln('TChild RTTI not found');
    Halt(1);
  end;
  writeln('Class: ', cls^.NamePtr^);
  writeln('InstanceSize: ', cls^.InstanceSize);

  { 2. Parent RTTI }
  if cls^.ParentRTTI = nil then
  begin
    writeln('TChild parent RTTI not found');
    Halt(1);
  end;
  parentCls := PClassRTTI(cls^.ParentRTTI);
  writeln('ParentRTTI value: ', Int64(parentCls));
  writeln('Parent Class: ', parentCls^.NamePtr^);

  { 3. GetPropList }
  cnt := GetPropList(cls, @list);
  writeln('PropCount: ', cnt);
  for i := 0 to cnt - 1 do
  begin
    writeln('Prop ', i, ' pointer: ', Int64(list[i]));
  end;
  for i := 0 to cnt - 1 do
  begin
    writeln('Prop ', i, ': ', list[i]^.NamePtr^, ' Kind: ', list[i]^.Kind);
  end;

  { 4. Id (Inherited Integer Property) }
  p := GetPropInfo(cls, 'Id');
  if p = nil then
  begin
    writeln('Id prop info not found');
    Halt(1);
  end;
  SetOrdProp(Pointer(c), p, 100);
  writeln('c.Id: ', c.Id);
  writeln('GetOrdProp(Id): ', GetOrdProp(Pointer(c), p));

  { 5. Caption (String Property) }
  p := GetPropInfo(cls, 'Caption');
  if p = nil then
  begin
    writeln('Caption prop info not found');
    Halt(1);
  end;
  SetStrProp(Pointer(c), p, 'Antigravity');
  writeln('c.Caption: ', c.Caption);
  writeln('GetStrProp(Caption): ', GetStrProp(Pointer(c), p));

  { 6. Align (Enum Property) }
  p := GetPropInfo(cls, 'Align');
  if p = nil then
  begin
    writeln('Align prop info not found');
    Halt(1);
  end;
  SetOrdProp(Pointer(c), p, Ord(alClient));
  writeln('c.Align: ', Ord(c.Align));
  writeln('GetOrdProp(Align): ', GetOrdProp(Pointer(c), p));

  { 7. Aligns (Set Property) }
  p := GetPropInfo(cls, 'Aligns');
  if p = nil then
  begin
    writeln('Aligns prop info not found');
    Halt(1);
  end;
  { Assign a set value directly }
  st := [alLeft, alClient];
  c.Aligns := st;
  if alLeft in c.Aligns then writeln('alLeft is in c.Aligns');
  if alClient in c.Aligns then writeln('alClient is in c.Aligns');
  if alRight in c.Aligns then writeln('alRight is in c.Aligns');

  { Verify SetOrdProp/GetOrdProp for sets }
  SetOrdProp(Pointer(c), p, GetOrdProp(Pointer(c), p));
  if alLeft in c.Aligns then writeln('alLeft still in c.Aligns');

  { 8. OnClick (Method/Event Property) }
  p := GetPropInfo(cls, 'OnClick');
  if p = nil then
  begin
    writeln('OnClick prop info not found');
    Halt(1);
  end;
  meth.Code := GetMethodAddr(cls, 'DummyHandler');
  meth.Data := Pointer(c);
  if meth.Code = nil then
  begin
    writeln('DummyHandler address not found');
    Halt(1);
  end;
  SetMethodProp(Pointer(c), p, meth);

  meth := GetMethodProp(Pointer(c), p);
  if meth.Code = GetMethodAddr(cls, 'DummyHandler') then
    writeln('OnClick event thunk matches DummyHandler');
end.
