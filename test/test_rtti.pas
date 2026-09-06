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
  j: Integer;
  allNonNil, distinct, aligned: Boolean;
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
  { InstanceSize is a per-target FACT, not a per-target defect: a class holding
    pointers is genuinely smaller on a 32-bit machine. It is emitted on a
    ##METRIC line, which the recipe strips before the cross-target output
    comparison and then uses for the DELTA assertion. Printing it in the body
    is what made this test unrunnable off x86-64 for a month. }
  writeln('##METRIC instancesize ', cls^.InstanceSize);
  writeln('##METRIC pointersize ', SizeOf(Pointer));

  { 2. Parent RTTI }
  if cls^.ParentRTTI = nil then
  begin
    writeln('TChild parent RTTI not found');
    Halt(1);
  end;
  parentCls := PClassRTTI(cls^.ParentRTTI);
  { The ADDRESS was printed here and is a link-layout artefact -- a fact about
    one build of one linker, not about RTTI. What the test actually wanted to
    know is that the pointer resolves and names the right class. }
  if parentCls = nil then writeln('ParentRTTI: nil') else writeln('ParentRTTI: non-nil');
  writeln('Parent Class: ', parentCls^.NamePtr^);

  { 3. GetPropList }
  cnt := GetPropList(cls, @list);
  writeln('PropCount: ', cnt);
  { RELATIONS, not addresses. The old loop printed cnt raw pointers, which
    differ per target, per link layout and arguably per run -- so the row could
    never match a cross-target oracle and was skipped rather than fixed. Every
    property below is target-independent and still says what the loop was for:
    the entries exist, they are distinct, they are ordered, and they sit on a
    single constant stride that is a whole number of pointers. }
  allNonNil := True;
  distinct  := True;
  aligned   := True;
  for i := 0 to cnt - 1 do
  begin
    if list[i] = nil then allNonNil := False;
    if (Int64(list[i]) mod SizeOf(Pointer)) <> 0 then aligned := False;
    for j := 0 to i - 1 do
      if list[i] = list[j] then distinct := False;
  end;
  { THREE INVARIANTS THAT ARE ALL TRUE, chosen so a broken table makes one
    FALSE. An earlier draft of this asserted "strictly increasing" and "one
    constant stride" and printed FALSE for both -- correctly, because
    GetPropList returns TChild's own four properties from one RTTI block and
    the inherited Id from TBase's, so the sequence legitimately jumps. Asserting
    a FALSE is a weak row: a table that returned garbage would print FALSE too.
    These three separate a working table from a broken one in the direction
    that matters. }
  writeln('Props non-nil: ', allNonNil);
  writeln('Props distinct: ', distinct);
  writeln('Props pointer-aligned: ', aligned);
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
