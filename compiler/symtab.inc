{ ===== User-class helpers (must precede hardcoded record helpers) ===== }

function ULower(const s: AnsiString): AnsiString;
var res: AnsiString; i: Integer; c: Char;
begin
  res := s;
  i := 1;
  while i <= Length(res) do
  begin
    c := res[i];
    if (c >= 'A') and (c <= 'Z') then res[i] := Chr(Ord(c) + 32);
    Inc(i);
  end;
  Result := res;
end;

function UNameMatch(off, len: Integer; const lo: AnsiString): Boolean;
var i: Integer; c: Char;
begin
  Result := False;
  if len <> Length(lo) then Exit;
  i := 0;
  while i < len do
  begin
    c := TokChars[off + i];
    if (c >= 'A') and (c <= 'Z') then c := Chr(Ord(c) + 32);
    if c <> lo[i + 1] then Exit;
    Inc(i);
  end;
  Result := True;
end;

function TokSlicesMatch(off1, len1, off2, len2: Integer): Boolean;
var i: Integer; c1, c2: Char;
begin
  Result := False;
  if len1 <> len2 then Exit;
  for i := 0 to len1 - 1 do
  begin
    c1 := TokChars[off1 + i];
    c2 := TokChars[off2 + i];
    if (c1 >= 'A') and (c1 <= 'Z') then c1 := Chr(Ord(c1) + 32);
    if (c2 >= 'A') and (c2 <= 'Z') then c2 := Chr(Ord(c2) + 32);
    if c1 <> c2 then Exit;
  end;
  Result := True;
end;

function FindTypeAlias(const name: AnsiString): Integer;
var i: Integer; lo, name2, s: AnsiString; j: Integer;
begin
  Result := -1;
  name2 := name;
  lo := ULower(name2);
  i := 0;
  while i < AliasCount do
  begin
    if UNameMatch(AliasNOff[i], AliasNLen[i], lo) then begin Result := i; Exit; end;
    Inc(i);
  end;
  if lo = 'puint8' then
  begin
    writeln('FindTypeAlias failed to find puint8! AliasCount=', AliasCount);
    for i := 0 to AliasCount - 1 do
    begin
      s := '';
      for j := 0 to AliasNLen[i] - 1 do
        AppendChar(s, TokChars[AliasNOff[i] + j]);
      writeln('  Alias ', i, ': ', s, ' (noff=', AliasNOff[i], ', nlen=', AliasNLen[i], ')');
    end;
  end;
end;

procedure RegisterPtrAlias(noff, nlen, elemTk, elemRec: Integer);
var i: Integer; s: AnsiString;
begin
  if AliasCount >= MAX_TYPEALIAS then Error('too many type aliases');
  AliasNOff[AliasCount] := noff;
  AliasNLen[AliasCount] := nlen;
  AliasTk[AliasCount] := Ord(tyPointer);
  AliasElemTk[AliasCount] := elemTk;
  AliasElemRec[AliasCount] := elemRec;
  
  s := '';
  for i := 0 to nlen - 1 do AppendChar(s, TokChars[noff + i]);
  writeln('RegisterPtrAlias: idx=', AliasCount, ' name="', s, '" noff=', noff, ' nlen=', nlen, ' elemTk=', elemTk, ' elemRec=', elemRec);

  Inc(AliasCount);
end;

procedure RegisterSetAlias(noff, nlen, elemEnumId: Integer);
{ Named set type: TFooSet = set of TFoo. Stored in the alias table with
  AliasTk=tySet; AliasElemTk holds the element enum id (or -1). }
begin
  if AliasCount >= MAX_TYPEALIAS then Error('too many type aliases');
  AliasNOff[AliasCount] := noff;
  AliasNLen[AliasCount] := nlen;
  AliasTk[AliasCount] := Ord(tySet);
  AliasElemTk[AliasCount] := elemEnumId;
  AliasElemRec[AliasCount] := REC_NONE;
  Inc(AliasCount);
end;

function FindEnumType(const name: AnsiString): Integer;
var i: Integer; lo, name2: AnsiString;
begin
  Result := -1;
  name2 := name;
  lo := ULower(name2);
  i := 0;
  while i < EnumTypeCount do
  begin
    if UNameMatch(EnumTypeNOff[i], EnumTypeNLen[i], lo) then begin Result := i; Exit; end;
    Inc(i);
  end;
end;

function RegisterEnumType(noff, nlen: Integer): Integer;
{ Open a new enum type; value names added via AddEnumVal, then closed by the
  caller via EnumTypeValCount[etid] (set to EnumValCount - ValBase). }
begin
  if EnumTypeCount >= MAX_ENUMTYPE then Error('too many enum types');
  Result := EnumTypeCount;
  EnumTypeNOff[Result] := noff;
  EnumTypeNLen[Result] := nlen;
  EnumTypeValBase[Result] := EnumValCount;
  EnumTypeValCount[Result] := 0;
  EnumTypeRTTIOff[Result] := -1;
  Inc(EnumTypeCount);
end;

procedure AddEnumVal(noff, nlen: Integer);
begin
  if EnumValCount >= MAX_ENUMVAL then Error('too many enum values');
  EnumValNOff[EnumValCount] := noff;
  EnumValNLen[EnumValCount] := nlen;
  Inc(EnumValCount);
end;

function FindUClass(const name: AnsiString): Integer;
var i: Integer; lo, name2: AnsiString;
begin
  Result := -1;
  name2 := name;
  lo := ULower(name2);
  i := 0;
  while i < UClsCount do
  begin
    if UNameMatch(UClsNOff[i], UClsNLen[i], lo) then begin Result := i; Exit; end;
    Inc(i);
  end;
end;

function FindUField(ci: Integer; const name: AnsiString): Integer;
var i, base, cnt: Integer; lo, name2: AnsiString; curr: Integer;
begin
  Result := -1;
  name2 := name;
  lo := ULower(name2);
  curr := ci;
  while curr >= 0 do
  begin
    base := UClsFBase[curr];
    cnt  := UClsFCount[curr];
    i := 0;
    while i < cnt do
    begin
      if UNameMatch(UFldNOff[base + i], UFldNLen[base + i], lo) then begin Result := base + i; Exit; end;
      Inc(i);
    end;
    curr := UClsParent[curr];
  end;
end;

function FindUMeth(ci: Integer; const name: AnsiString): Integer;
var i, base, cnt: Integer; lo, name2: AnsiString; curr: Integer;
begin
  Result := -1;
  name2 := name;
  lo := ULower(name2);
  curr := ci;
  while curr >= 0 do
  begin
    base := UClsMBase[curr];
    cnt  := UClsMCount[curr];
    i := 0;
    while i < cnt do
    begin
      if UNameMatch(UMthNOff[base + i], UMthNLen[base + i], lo) then begin Result := base + i; Exit; end;
      Inc(i);
    end;
    curr := UClsParent[curr];
  end;
end;

function IsSubclassOf(otherCi, ci: Integer): Boolean;
var curr: Integer;
begin
  Result := False;
  curr := UClsParent[otherCi];
  while curr >= 0 do
  begin
    if curr = ci then begin Result := True; Exit; end;
    curr := UClsParent[curr];
  end;
end;

function FindParentVirtualSlot(parentCi: Integer; const name: AnsiString): Integer;
var curr, mmi: Integer;
begin
  Result := -1;
  curr := parentCi;
  while curr >= 0 do
  begin
    mmi := FindUMeth(curr, name);
    if (mmi >= 0) and (UMthVirSlot[mmi] >= 0) then
    begin
      Result := UMthVirSlot[mmi];
      Exit;
    end;
    curr := UClsParent[curr];
  end;
end;

function ResolveVMTSlotProc(ci, slot: Integer): Integer;
{ Effective proc occupying virtual slot `slot` for class ci: search ci's own
  methods first (an override wins), then walk ancestors. -1 if none. }
var curr, i, base, cnt: Integer;
begin
  Result := -1;
  curr := ci;
  while curr >= 0 do
  begin
    base := UClsMBase[curr]; cnt := UClsMCount[curr];
    for i := 0 to cnt - 1 do
      if UMthVirSlot[base + i] = slot then
      begin
        Result := UMthProc_[base + i];
        Exit;
      end;
    curr := UClsParent[curr];
  end;
end;

function FindUProp(ci: Integer; const name: AnsiString): Integer;
var i, base, cnt: Integer; lo, name2: AnsiString; curr: Integer;
begin
  Result := -1;
  name2 := name;
  lo := ULower(name2);
  curr := ci;
  while curr >= 0 do
  begin
    base := UClsPBase[curr];
    cnt  := UClsPCount[curr];
    i := 0;
    while i < cnt do
    begin
      if UNameMatch(UPropNOff[base + i], UPropNLen[base + i], lo) then begin Result := base + i; Exit; end;
      Inc(i);
    end;
    curr := UClsParent[curr];
  end;
end;

function AddUProperty(ci, noff, nlen, tk, recId: Integer): Integer;
var pri: Integer;
begin
  pri := UPropCount;
  UPropNOff[pri] := noff; UPropNLen[pri] := nlen;
  UPropTk[pri] := tk; UPropRec[pri] := recId;
  UPropReadFOff[pri] := 0; UPropReadFLen[pri] := 0;
  UPropReadMOff[pri] := 0; UPropReadMLen[pri] := 0;
  UPropWriteFOff[pri] := 0; UPropWriteFLen[pri] := 0;
  UPropWriteMOff[pri] := 0; UPropWriteMLen[pri] := 0;
  UPropPub[pri] := 0;
  UPropEnumId[pri] := -1;
  UPropSetEnumId[pri] := -1;
  UPropCount := UPropCount + 1;
  UClsPCount[ci] := UClsPCount[ci] + 1;
  Result := pri;
end;

function AddUClass(off, len: Integer): Integer;
begin
  Result := UClsCount;
  UClsNOff[UClsCount]   := off;
  UClsNLen[UClsCount]   := len;
  UClsSize_[UClsCount]  := 0;
  UClsFBase[UClsCount]  := UFldCount;
  UClsFCount[UClsCount] := 0;
  UClsMBase[UClsCount]  := UMthCount;
  UClsMCount[UClsCount] := 0;
  UClsPBase[UClsCount]  := UPropCount;
  UClsPCount[UClsCount] := 0;
  UClsParent[UClsCount] := -1;
  UClsVirtCount[UClsCount] := 0;
  UClsVMTOffset[UClsCount] := -1;
  UClsIsRecord[UClsCount] := False;
  UClsCount := UClsCount + 1;
end;

procedure AddUField(ci, noff, nlen, byteOff, tk, recId: Integer);
var fi: Integer;
begin
  fi := UFldCount;
  UFldNOff[fi] := noff;  UFldNLen[fi] := nlen;
  UFldOff_[fi] := byteOff; UFldTk[fi] := tk; UFldRec_[fi] := recId;
  if tk = Ord(tyPointer) then
  begin
    UFldPtrElemTk[fi] := Ord(LastTypePointerElemTk);
    UFldPtrElemRec[fi] := LastTypePointerElemRec;
  end
  else
  begin
    UFldPtrElemTk[fi] := Ord(tyUnknown);
    UFldPtrElemRec[fi] := REC_NONE;
  end;
  UFldPub[fi] := 0;
  UFldCount := UFldCount + 1;
  UClsFCount[ci] := UClsFCount[ci] + 1;
end;

procedure AddUMeth(ci, noff, nlen, pi: Integer);
var mi: Integer;
begin
  mi := UMthCount;
  UMthNOff[mi] := noff; UMthNLen[mi] := nlen; UMthProc_[mi] := pi;
  UMthVirSlot[mi] := -1;
  UMthIsStatic[mi] := False;
  UMthPub[mi] := 0;
  UMthCount := UMthCount + 1;
  UClsMCount[ci] := UClsMCount[ci] + 1;
end;

{ ===== Record Helper Functions ===== }

const
  REC_TTOKEN = 1;
  REC_TSTRENTRY = 2;
  REC_TFIXUP = 3;
  REC_TGLOBFIX = 4;
  REC_TCALLFIX = 5;
  REC_TSYMBOL = 6;
  REC_TPARAM = 7;
  REC_TPROC = 8;
  REC_TRAWTOKEN = 9;
  REC_TMYCLASS = 10;
  REC_TTEMPLATE = 11;
  REC_TSPECIALIZATION = 12;
  REC_TGENERICFUNC = 13;
  REC_TPENDINGGFSPEC = 14;

function IsRecordType(const lo: AnsiString): Integer;
var ci: Integer; lo2: AnsiString;
begin
  Result := REC_NONE;
  if lo = 'TToken' then Result := REC_TTOKEN
  else if lo = 'TStrEntry' then Result := REC_TSTRENTRY
  else if lo = 'TFixup' then Result := REC_TFIXUP
  else if lo = 'TGlobFix' then Result := REC_TGLOBFIX
  else if lo = 'TCallFix' then Result := REC_TCALLFIX
  else if lo = 'TSymbol' then Result := REC_TSYMBOL
  else if lo = 'TParam' then Result := REC_TPARAM
  else if lo = 'TProc' then Result := REC_TPROC
  else if lo = 'TRawToken' then Result := REC_TRAWTOKEN
  else if (lo = 'TMyClass') or (lo = 'tmyclass') then Result := REC_TMYCLASS
  else if lo = 'TTemplate' then Result := REC_TTEMPLATE
  else if lo = 'TSpecialization' then Result := REC_TSPECIALIZATION
  else if lo = 'TGenericFunc' then Result := REC_TGENERICFUNC
  else if lo = 'TPendingGFSpec' then Result := REC_TPENDINGGFSPEC
  else if lo = 'TMethodFixup' then Result := REC_TMETHODFIXUP;
  if Result = REC_NONE then
  begin
    lo2 := lo;
    ci := FindUClass(lo2);
    if (ci >= 0) and UClsIsRecord[ci] then Result := REC_UCLASS_BASE + ci;
  end;
end;

function IsClassType(const lo: AnsiString): Boolean;
var ci: Integer; lo2: AnsiString;
begin
  Result := False;
  if (lo = 'TMyClass') or (lo = 'tmyclass') then Result := True;
  if not Result then
  begin
    lo2 := lo;
    ci := FindUClass(lo2);
    if (ci >= 0) and (not UClsIsRecord[ci]) then Result := True;
  end;
end;

function RecSize(rec: Integer): Integer;
begin
  Result := 8;
  if rec = REC_TTOKEN then Result := 288
  else if rec = REC_TSTRENTRY then Result := 280
  else if rec = REC_TFIXUP then Result := 16
  else if rec = REC_TGLOBFIX then Result := 16
  else if rec = REC_TCALLFIX then Result := 16
  else if rec = REC_TSYMBOL then Result := 360
  else if rec = REC_TPARAM then Result := 296
  else if rec = REC_TPROC then Result := 2688
  else if rec = REC_TRAWTOKEN then Result := 40
  else if rec = REC_TMYCLASS then Result := 16
  else if rec = REC_TTEMPLATE then Result := 544
  else if rec = REC_TSPECIALIZATION then Result := 800
  else if rec = REC_TGENERICFUNC then Result := 552
  else if rec = REC_TPENDINGGFSPEC then Result := 544
  else if rec = REC_TMETHODFIXUP then Result := 8
  else if rec >= REC_UCLASS_BASE then Result := UClsSize_[rec - REC_UCLASS_BASE];
end;

function RecFieldOffset(rec: Integer; const field: AnsiString): Integer;
var fi: Integer; field2: AnsiString;
begin
  Result := 0; fi := 0; field2 := field;
  if rec = REC_TTOKEN then
  begin
    if field = 'Kind' then Result := 0
    else if field = 'SVal' then Result := 8
    else if field = 'IVal' then Result := 272
    else if field = 'Line' then Result := 280;
  end
  else if rec = REC_TSTRENTRY then
  begin
    if field = 'Text' then Result := 0
    else if field = 'Offset' then Result := 264
    else if field = 'Len' then Result := 272;
  end
  else if rec = REC_TFIXUP then
  begin
    if field = 'CodePos' then Result := 0
    else if field = 'DataOff' then Result := 8;
  end
  else if rec = REC_TGLOBFIX then
  begin
    if field = 'CodePos' then Result := 0
    else if field = 'BSSoff' then Result := 8;
  end
  else if rec = REC_TCALLFIX then
  begin
    if field = 'CodePos' then Result := 0
    else if field = 'ProcIdx' then Result := 8;
  end
  else if rec = REC_TSYMBOL then
  begin
    if field = 'Name' then Result := 0
    else if field = 'TypeKind' then Result := 264
    else if field = 'Kind' then Result := 272
    else if field = 'Offset' then Result := 280
    else if field = 'ConstVal' then Result := 288
    else if field = 'IsArray' then Result := 296
    else if field = 'ArrLen' then Result := 304
    else if field = 'ElemType' then Result := 312
    else if field = 'RecName' then Result := 320
    else if field = 'ElemRecName' then Result := 328
    else if field = 'IsRef' then Result := 336
    else if field = 'PtrElemTk' then Result := 344
    else if field = 'PtrElemRec' then Result := 352;
  end
  else if rec = REC_TPARAM then
  begin
    if field = 'Name' then Result := 0
    else if field = 'TypeKind' then Result := 264
    else if field = 'SymIdx' then Result := 272
    else if field = 'IsRef' then Result := 280
    else if field = 'IsArray' then Result := 288;
  end
  else if rec = REC_TPROC then
  begin
    if field = 'Name' then Result := 0
    else if field = 'IsFunc' then Result := 264
    else if field = 'RetType' then Result := 272
    else if field = 'ParamCount' then Result := 280
    else if field = 'Params' then Result := 288
    else if field = 'BodyAddr' then Result := 2656
    else if field = 'FramePatch' then Result := 2664
    else if field = 'RetSymIdx' then Result := 2672
    else if field = 'ScopeBase' then Result := 2680;
  end
  else if rec = REC_TRAWTOKEN then
  begin
    if field = 'Kind'    then Result := 0
    else if field = 'IVal'    then Result := 8
    else if field = 'Line'    then Result := 16
    else if field = 'SOffset' then Result := 24
    else if field = 'SLen'    then Result := 32;
  end
  else if rec = REC_TMYCLASS then
  begin
    if (field = 'x') or (field = 'X') then Result := 0
    else if (field = 'y') or (field = 'Y') then Result := 8;
  end;
  if rec = REC_TTEMPLATE then
  begin
    if field = 'Name' then Result := 0
    else if field = 'Param' then Result := 264
    else if field = 'TokStart' then Result := 528
    else if field = 'TokCount' then Result := 536;
  end
  else if rec = REC_TSPECIALIZATION then
  begin
    if field = 'Name' then Result := 0
    else if field = 'TemplateName' then Result := 264
    else if field = 'ConcreteType' then Result := 528
    else if field = 'ConcreteName' then Result := 536;
  end
  else if rec = REC_TGENERICFUNC then
  begin
    if field = 'Name' then Result := 0
    else if field = 'Param' then Result := 264
    else if field = 'IsFunc' then Result := 528
    else if field = 'TokStart' then Result := 536
    else if field = 'TokCount' then Result := 544;
  end
  else if rec = REC_TPENDINGGFSPEC then
  begin
    if field = 'GenFuncIdx' then Result := 0
    else if field = 'ConcreteKind' then Result := 8
    else if field = 'ConcreteName' then Result := 16
    else if field = 'SpecName' then Result := 280;
  end
  else if rec = REC_TMETHODFIXUP then
  begin
    if field = 'DataPos' then Result := 0
    else if field = 'ProcIdx' then Result := 4;
  end
  else if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldOff_[fi];
  end;
end;

function RecFieldType(rec: Integer; const field: AnsiString): TTypeKind;
var fi: Integer; field2: AnsiString;
begin
  Result := tyInteger; fi := 0; field2 := field;
  if rec = REC_TTOKEN then
  begin
    if field = 'SVal' then Result := tyString
    else if field = 'IVal' then Result := tyInt64;
  end
  else if rec = REC_TRAWTOKEN then
  begin
    if field = 'IVal' then Result := tyInt64;
  end
  else if rec = REC_TSTRENTRY then
  begin
    if field = 'Text' then Result := tyString;
  end
  else if rec = REC_TSYMBOL then
  begin
    if field = 'Name' then Result := tyString
    else if (field = 'IsArray') or (field = 'IsRef') then Result := tyBoolean
    else if field = 'ConstVal' then Result := tyInt64;
  end
  else if rec = REC_TPARAM then
  begin
    if field = 'Name' then Result := tyString
    else if (field = 'IsRef') or (field = 'IsArray') then Result := tyBoolean;
  end
  else if rec = REC_TPROC then
  begin
    if field = 'Name' then Result := tyString
    else if field = 'IsFunc' then Result := tyBoolean
    else if field = 'Params' then Result := tyRecord;
  end
  else if rec = REC_TMYCLASS then
  begin
    Result := tyInteger;
  end;
  if rec = REC_TTEMPLATE then
  begin
    if (field = 'Name') or (field = 'Param') then Result := tyString;
  end
  else if rec = REC_TSPECIALIZATION then
  begin
    if (field = 'Name') or (field = 'TemplateName') or (field = 'ConcreteName') then Result := tyString;
  end
  else if rec = REC_TGENERICFUNC then
  begin
    if (field = 'Name') or (field = 'Param') then Result := tyString
    else if field = 'IsFunc' then Result := tyBoolean;
  end
  else if rec = REC_TPENDINGGFSPEC then
  begin
    if (field = 'ConcreteName') or (field = 'SpecName') then Result := tyString;
  end
  else if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := IntToTypeKind(UFldTk[fi]);
  end;
end;

function RecFieldRecId(rec: Integer; const field: AnsiString): Integer;
var fi: Integer; field2: AnsiString;
begin
  Result := REC_NONE; fi := 0; field2 := field;
  if rec = REC_TPROC then
  begin
    if field = 'Params' then Result := REC_TPARAM;
  end
  else if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldRec_[fi];
  end;
end;

function RecFieldIsArray(rec: Integer; const field: AnsiString): Boolean;
begin
  Result := False;
  if rec = REC_TPROC then
  begin
    if field = 'Params' then Result := True;
  end;
end;

function RecFieldPtrElemTk(rec: Integer; const field: AnsiString): TTypeKind;
{ Pointed-at element type of a pointer-typed class field (for FField[i]). }
var fi: Integer; field2: AnsiString;
begin
  Result := tyUnknown; field2 := field;
  if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := IntToTypeKind(UFldPtrElemTk[fi]);
  end;
end;

function RecFieldPtrElemRec(rec: Integer; const field: AnsiString): Integer;
{ Record id pointed at by a pointer-typed class field, else REC_NONE. }
var fi: Integer; field2: AnsiString;
begin
  Result := REC_NONE; field2 := field;
  if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldPtrElemRec[fi];
  end;
end;

{ ===== Central type-query helpers ===== }
{ These are the single authoritative source for size, alignment, and signedness.
  All new code must call these instead of hard-coding numbers. }

function TypeSize(tk: TTypeKind): Integer;
{ Returns byte count needed to store one value of type tk.
  For pointer-sized types, returns TARGET_PTR_SIZE (8 on x86-64). }
begin
  Result := 8; { default / legacy path — pointer-width slot }
  case Ord(tk) of
    { Bootstrap-stable kinds (0-6) }
    0: Result := 8;  { tyUnknown }
    1: Result := 4;  { tyInteger  — signed 32-bit }
    2: Result := 1;  { tyBoolean  — unsigned 8-bit }
    3: Result := 1;  { tyChar }
    4: Result := 8;  { tyString   — struct pointer / inline; caller manages actual buffer }
    5: Result := 8;  { tyRecord   — caller must use RecSize() for full record size }
    6: Result := TARGET_PTR_SIZE;  { tyClass }
    { New precise kinds (7-17) }
    7:  Result := 1;  { tyInt8 }
    8:  Result := 1;  { tyUInt8 }
    9:  Result := 2;  { tyInt16 }
    10: Result := 2;  { tyUInt16 }
    11: Result := 4;  { tyInt32 }
    12: Result := 4;  { tyUInt32 }
    13: Result := 8;  { tyInt64 }
    14: Result := 8;  { tyUInt64 }
    15: Result := TARGET_PTR_SIZE;  { tyNativeInt }
    16: Result := TARGET_PTR_SIZE;  { tyNativeUInt }
    17: Result := TARGET_PTR_SIZE;  { tyPointer }
    18: Result := 4;  { tySingle }
    19: Result := 8;  { tyDouble }
    20: Result := 10; { tyExtended }
    21: Result := 32; { tySet }
  end;
end;

function TypeAlign(tk: TTypeKind): Integer;
{ Returns alignment requirement (power of 2) for type tk.
  On x86-64 all scalar types are naturally aligned. }
var sz: Integer;
begin
  sz := TypeSize(tk);
  if sz <= 1 then Result := 1
  else if sz <= 2 then Result := 2
  else if sz <= 4 then Result := 4
  else Result := 8;
end;

function AlignTo(value, alignment: Integer): Integer;
begin
  if alignment <= 1 then
    Result := value
  else
    Result := ((value + alignment - 1) div alignment) * alignment;
end;

function TypeSigned(tk: TTypeKind): Boolean;
{ True for signed integer types. }
begin
  Result := False;
  case Ord(tk) of
    1:  Result := True;  { tyInteger  — legacy signed }
    7:  Result := True;  { tyInt8 }
    9:  Result := True;  { tyInt16 }
    11: Result := True;  { tyInt32 }
    13: Result := True;  { tyInt64 }
    15: Result := True;  { tyNativeInt }
  end;
end;

function TypeIsOrdinal(tk: TTypeKind): Boolean;
{ True for integer and character types — types that have a simple ordinal value. }
begin
  Result := False;
  case Ord(tk) of
    1, 2, 3,         { tyInteger, tyBoolean, tyChar — legacy }
    7, 8, 9, 10,     { tyInt8..tyUInt16 }
    11, 12, 13, 14,  { tyInt32..tyUInt64 }
    15, 16, 17:      { tyNativeInt, tyNativeUInt, tyPointer }
      Result := True;
  end;
end;

function TypeIsFloat(tk: TTypeKind): Boolean;
begin
  Result := (Ord(tk) = 18) or (Ord(tk) = 19) or (Ord(tk) = 20);  { tySingle or tyDouble or tyExtended }
end;

function TypeCompareUnsigned(lhs, rhs: TTypeKind): Boolean;
{ The wider operand determines the comparison domain; at equal width a signed
  operand wins. Values are still evaluated in 64-bit registers. }
begin
  Result := False;
  if not (TypeIsOrdinal(lhs) and TypeIsOrdinal(rhs)) then Exit;
  if TypeSize(lhs) > TypeSize(rhs) then
    Result := not TypeSigned(lhs)
  else if TypeSize(rhs) > TypeSize(lhs) then
    Result := not TypeSigned(rhs)
  else
    Result := (not TypeSigned(lhs)) and (not TypeSigned(rhs));
end;

function TypeArithmeticResult(lhs, rhs: TTypeKind): TTypeKind;
{ Integer arithmetic is evaluated as an 8-byte value. Signedness follows the
  same widening rule as relational comparisons. }
begin
  if TypeCompareUnsigned(lhs, rhs) then
    Result := tyUInt64
  else
    Result := tyInt64;
end;

function TypeDivideUnsigned(dividend: TTypeKind): Boolean;
begin
  Result := TypeIsOrdinal(dividend) and not TypeSigned(dividend);
end;

function TypeDivideResult(dividend: TTypeKind): TTypeKind;
begin
  if TypeDivideUnsigned(dividend) then
    Result := tyUInt64
  else
    Result := tyInt64;
end;

function TypeIsPointerSized(tk: TTypeKind): Boolean;
{ True for types that occupy exactly TARGET_PTR_SIZE bytes: Pointer, NativeInt,
  NativeUInt, tyClass. These grow with the target pointer width. }
begin
  Result := False;
  case Ord(tk) of
    6,       { tyClass }
    15, 16,  { tyNativeInt, tyNativeUInt }
    17:      { tyPointer }
      Result := True;
  end;
end;

{ ===== Symbol table ===== }

function StrEqual(const s1, s2: AnsiString): Boolean;
var len, i: Integer;
begin
  Result := False;
  len := Length(s1);
  if len = Length(s2) then
  begin
    Result := True;
    for i := 1 to len do
    begin
      if s1[i] <> s2[i] then Result := False;
    end;
  end;
end;

function FindSym(const name: AnsiString): Integer;
var i: Integer; lo: AnsiString;
begin
  lo := name;
  for i := SymCount-1 downto 0 do
    if StrEqual(Syms[i].Name, lo) then
    begin
      if DebugTrace then writeln('FindSym: ', lo, ' -> ', i);
      Result := i;
      Exit;
    end;

  if DebugTrace then writeln('FindSym: ', lo, ' -> -1');
  if DebugTrace and StrEqual(lo, 'ELF_HEADER_SIZE') then
  begin
    writeln('FindSym failed for ELF_HEADER_SIZE. lo = ', lo);
    writeln('SymCount = ', SymCount);
    for i := 0 to SymCount-1 do
      writeln('  Sym ', i, ': ', Syms[i].Name);
  end;
  Result := -1;
end;

function AllocVar(const name: AnsiString; tk: TTypeKind): Integer;
var sz, align: Integer;
begin
  if SymCount >= MAX_SYMS then Error('too many symbols');
  Syms[SymCount].Name     := name;
  Syms[SymCount].TypeKind := tk;
  Syms[SymCount].ConstVal := 0;
  Syms[SymCount].IsArray  := False;
  Syms[SymCount].ArrLen   := 0;
  Syms[SymCount].ElemType := tyInteger;
  Syms[SymCount].RecName  := LastTypeRecId;
  Syms[SymCount].IsRef    := False;
  Syms[SymCount].PtrElemTk := tyUnknown;
  Syms[SymCount].PtrElemRec := REC_NONE;
  if tk = tyPointer then
  begin
    Syms[SymCount].PtrElemTk := LastTypePointerElemTk;
    Syms[SymCount].PtrElemRec := LastTypePointerElemRec;
  end;

  sz := TypeSize(tk);
  if tk = tyString then
  begin
    if CurProc < 0 then sz := STRING_CAP + 8
    else sz := LOCAL_STR_CAP + 8;
  end
  else if tk = tyRecord then sz := RecSize(LastTypeRecId);
  align := TypeAlign(tk);

  if CurProc < 0 then
  begin
    BSSSize := AlignTo(BSSSize, align);
    Syms[SymCount].Kind   := skGlobal;
    Syms[SymCount].Offset := BSSSize;
    Inc(BSSSize, sz);
  end
  else
  begin
    FrameSize := AlignTo(FrameSize + sz, align);
    Syms[SymCount].Kind   := skLocal;
    Syms[SymCount].Offset := -FrameSize;
  end;
  Result := SymCount; Inc(SymCount);
end;

function ParamSize(idx: Integer): Integer;
begin
  if Syms[idx].IsRef or Syms[idx].IsArray or (Syms[idx].TypeKind = tyString) or
     (Syms[idx].TypeKind = tyRecord) or (Syms[idx].TypeKind = tyClass) or (Syms[idx].TypeKind = tyPointer) then
    Result := TARGET_PTR_SIZE
  else
    Result := TypeSize(Syms[idx].TypeKind);
end;

function AllocParam(const name: AnsiString; tk: TTypeKind; isRef, isArray: Boolean): Integer;
var sz, align: Integer;
begin
  if SymCount >= MAX_SYMS then Error('too many symbols');
  Syms[SymCount].Name     := name;
  Syms[SymCount].TypeKind := tk;
  Syms[SymCount].ConstVal := 0;
  Syms[SymCount].IsArray  := isArray;
  Syms[SymCount].ArrLen   := 0;
  if isArray then Syms[SymCount].ArrLen := 1000;
  Syms[SymCount].ElemType := tk;
  Syms[SymCount].RecName  := LastTypeRecId;
  Syms[SymCount].IsRef    := isRef;
  Syms[SymCount].Kind     := skParam;
  Syms[SymCount].PtrElemTk := tyUnknown;
  Syms[SymCount].PtrElemRec := REC_NONE;
  if tk = tyPointer then
  begin
    Syms[SymCount].PtrElemTk := LastTypePointerElemTk;
    Syms[SymCount].PtrElemRec := LastTypePointerElemRec;
  end;

  if isRef or isArray or (tk = tyString) or (tk = tyRecord) or (tk = tyClass) or (tk = tyPointer) then
    sz := TARGET_PTR_SIZE
  else
    sz := TypeSize(tk);

  if isRef or isArray or (tk = tyString) or (tk = tyRecord) or (tk = tyClass) or (tk = tyPointer) then
    align := TARGET_PTR_SIZE
  else
    align := TypeAlign(tk);
  FrameSize := AlignTo(FrameSize + sz, align);
  Syms[SymCount].Offset := -FrameSize;
  Result := SymCount; Inc(SymCount);
end;

function AllocArray(const name: AnsiString; elemType: TTypeKind; lo, hi: Integer): Integer;
var elemSize, totalSize, align: Integer;
begin
  if SymCount >= MAX_SYMS then Error('too many symbols');
  if elemType = tyString then
  begin
    if CurProc < 0 then elemSize := STRING_CAP + 8
    else elemSize := LOCAL_STR_CAP + 8;
  end
  else if elemType = tyRecord then elemSize := RecSize(LastTypeRecId)
  else elemSize := TypeSize(elemType);
  if (elemType = tyString) or (elemType = tyRecord) then
    align := TARGET_PTR_SIZE
  else
    align := TypeAlign(elemType);

  totalSize := (hi - lo + 1) * elemSize;
  Syms[SymCount].Name     := name;
  Syms[SymCount].TypeKind := elemType;
  Syms[SymCount].ConstVal := lo;   { lo bound stored in ConstVal }
  Syms[SymCount].IsArray  := True;
  Syms[SymCount].ArrLen   := hi - lo + 1;
  Syms[SymCount].ElemType := elemType;
  Syms[SymCount].ElemRecName := LastTypeRecId;
  Syms[SymCount].IsRef    := False;
  Syms[SymCount].PtrElemTk := tyUnknown;
  Syms[SymCount].PtrElemRec := REC_NONE;
  if elemType = tyPointer then
  begin
    Syms[SymCount].PtrElemTk := LastTypePointerElemTk;
    Syms[SymCount].PtrElemRec := LastTypePointerElemRec;
  end;

  if CurProc < 0 then
  begin
    BSSSize := AlignTo(BSSSize, align);
    Syms[SymCount].Kind   := skGlobal;
    Syms[SymCount].Offset := BSSSize;
    Inc(BSSSize, totalSize);
  end
  else
  begin
    FrameSize := AlignTo(FrameSize + totalSize, align);
    Syms[SymCount].Kind   := skLocal;
    Syms[SymCount].Offset := -FrameSize;
  end;
  Result := SymCount; Inc(SymCount);
end;

function AllocDynArray(const name: AnsiString; elemType: TTypeKind): Integer;
{ Dynamic array (array of T): a pointer-sized slot holding a heap data pointer.
  ArrLen = -1 marks the symbol as dynamic (static arrays always have ArrLen >= 1). }
begin
  if SymCount >= MAX_SYMS then Error('too many symbols');
  Syms[SymCount].Name        := name;
  Syms[SymCount].TypeKind    := elemType;
  Syms[SymCount].ConstVal    := 0;            { lower bound: dynamic arrays are 0-based }
  Syms[SymCount].IsArray     := True;
  Syms[SymCount].ArrLen      := -1;           { -1 = dynamic }
  Syms[SymCount].ElemType    := elemType;
  Syms[SymCount].ElemRecName := LastTypeRecId;
  Syms[SymCount].IsRef       := False;
  Syms[SymCount].PtrElemTk := tyUnknown;
  Syms[SymCount].PtrElemRec := REC_NONE;
  if elemType = tyPointer then
  begin
    Syms[SymCount].PtrElemTk := LastTypePointerElemTk;
    Syms[SymCount].PtrElemRec := LastTypePointerElemRec;
  end;
  if CurProc < 0 then
  begin
    BSSSize := AlignTo(BSSSize, TARGET_PTR_SIZE);
    Syms[SymCount].Kind   := skGlobal;
    Syms[SymCount].Offset := BSSSize;
    Inc(BSSSize, TARGET_PTR_SIZE);
  end
  else
  begin
    FrameSize := AlignTo(FrameSize + TARGET_PTR_SIZE, TARGET_PTR_SIZE);
    Syms[SymCount].Kind   := skLocal;
    Syms[SymCount].Offset := -FrameSize;
  end;
  Result := SymCount; Inc(SymCount);
end;

function AllocTemp: Integer;
begin Result := AllocVar('', tyInteger); end;

function AddConst(const name: AnsiString; tk: TTypeKind; v: Int64): Integer;
begin
  if SymCount >= MAX_SYMS then Error('too many symbols');
  Syms[SymCount].Name     := name;
  Syms[SymCount].TypeKind := tk;
  Syms[SymCount].Kind     := skConst;
  Syms[SymCount].ConstVal := v;
  Syms[SymCount].Offset   := 0;
  Syms[SymCount].IsRef    := False;
  Result := SymCount; Inc(SymCount);
end;

{ ===== Variable load/store ===== }

procedure EmitLoadVar(idx: Integer);
var tk: TTypeKind; sz: Integer; sgn: Boolean;
begin
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);
  sgn := TypeSigned(tk);

  if TypeIsFloat(tk) then
  begin
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
    begin
      EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[idx].Offset);  { mov rax, [rbp+off] }
      if tk = tySingle then
      begin
        EmitB($F3); EmitB($0F); EmitB($10); EmitB($00);                { movss xmm0, [rax] }
        EmitB($F3); EmitB($0F); EmitB($5A); EmitB($C0);                { cvtss2sd xmm0, xmm0 }
      end
      else if tk = tyExtended then
      begin
        EmitB($48); EmitB($83); EmitB($EC); EmitB($08);                 { sub rsp, 8 }
        EmitB($DB); EmitB($28);                                          { fldt [rax] }
        EmitB($DD); EmitB($1C); EmitB($24);                             { fstpl [rsp] }
        EmitB($F2); EmitB($0F); EmitB($10); EmitB($04); EmitB($24);    { movsd xmm0, [rsp] }
        EmitB($48); EmitB($83); EmitB($C4); EmitB($08);                 { add rsp, 8 }
      end
      else
        begin EmitB($F2); EmitB($0F); EmitB($10); EmitB($00); end;      { movsd xmm0, [rax] }
    end
    else case Syms[idx].Kind of
      skLocal, skParam:
        if tk = tySingle then
        begin
          EmitB($F3); EmitB($0F); EmitB($10); EmitB($85); EmitI32(Syms[idx].Offset);  { movss xmm0, [rbp+off] }
          EmitB($F3); EmitB($0F); EmitB($5A); EmitB($C0);                            { cvtss2sd xmm0, xmm0 }
        end
        else if tk = tyExtended then
        begin
          EmitB($48); EmitB($83); EmitB($EC); EmitB($08);               { sub rsp, 8 }
          EmitB($DB); EmitB($AD); EmitI32(Syms[idx].Offset);            { fldt [rbp+off] }
          EmitB($DD); EmitB($1C); EmitB($24);                           { fstpl [rsp] }
          EmitB($F2); EmitB($0F); EmitB($10); EmitB($04); EmitB($24);  { movsd xmm0, [rsp] }
          EmitB($48); EmitB($83); EmitB($C4); EmitB($08);               { add rsp, 8 }
        end
        else
          begin EmitB($F2); EmitB($0F); EmitB($10); EmitB($85); EmitI32(Syms[idx].Offset); end;  { movsd xmm0, [rbp+off] }
      skGlobal:
        if tk = tySingle then
        begin
          EmitB($F3); EmitB($0F); EmitB($10); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset);  { movss xmm0, [abs] }
          EmitB($F3); EmitB($0F); EmitB($5A); EmitB($C0);                                             { cvtss2sd xmm0, xmm0 }
        end
        else if tk = tyExtended then
        begin
          EmitB($48); EmitB($83); EmitB($EC); EmitB($08);               { sub rsp, 8 }
          EmitB($DB); EmitB($2C); EmitB($25); EmitGlobRef(Syms[idx].Offset);  { fldt [abs32] }
          EmitB($DD); EmitB($1C); EmitB($24);                           { fstpl [rsp] }
          EmitB($F2); EmitB($0F); EmitB($10); EmitB($04); EmitB($24);  { movsd xmm0, [rsp] }
          EmitB($48); EmitB($83); EmitB($C4); EmitB($08);               { add rsp, 8 }
        end
        else
          begin EmitB($F2); EmitB($0F); EmitB($10); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end; { movsd xmm0, [abs] }
      skConst: MovRaxImm(Syms[idx].ConstVal);
    end;
    Exit;
  end;

  if (Syms[idx].Kind = skParam) and Syms[idx].IsRef and
     (tk <> tyString) then
  begin
    { by-reference scalar: load pointer from slot, then load pointed value }
    EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[idx].Offset);
    if sz = 1 then
    begin
      if sgn then
        begin EmitB($48); EmitB($0F); EmitB($BE); EmitB($00); end { movsx rax, byte [rax] }
      else
        begin EmitB($48); EmitB($0F); EmitB($B6); EmitB($00); end;{ movzx rax, byte [rax] }
    end
    else if sz = 2 then
    begin
      if sgn then
        begin EmitB($48); EmitB($0F); EmitB($BF); EmitB($00); end { movsx rax, word [rax] }
      else
        begin EmitB($48); EmitB($0F); EmitB($B7); EmitB($00); end;{ movzx rax, word [rax] }
    end
    else if sz = 4 then
    begin
      if sgn then
        begin EmitB($48); EmitB($63); EmitB($00); end { movsxd rax, dword [rax] }
      else
        begin EmitB($8B); EmitB($00); end;{ mov eax, dword [rax] (zero-extends to rax) }
    end
    else
      begin EmitB($48); EmitB($8B); EmitB($00); end; { mov rax, [rax] }
  end
  else if (Syms[idx].Kind = skParam) and (tk = tyString) then
  begin
    { param slot holds pointer P to string struct; load P then deref for length }
    EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[idx].Offset); { mov rax, [rbp+off] = P }
    EmitB($48); EmitB($8B); EmitB($00);                              { mov rax, [P] = length }
  end
  else
  begin
    case Syms[idx].Kind of
      skLocal, skParam:
        begin
          if sz = 1 then
          begin
            if sgn then
              begin EmitB($48); EmitB($0F); EmitB($BE); EmitB($85); EmitI32(Syms[idx].Offset); end
            else
              begin EmitB($48); EmitB($0F); EmitB($B6); EmitB($85); EmitI32(Syms[idx].Offset); end;
          end
          else if sz = 2 then
          begin
            if sgn then
              begin EmitB($48); EmitB($0F); EmitB($BF); EmitB($85); EmitI32(Syms[idx].Offset); end
            else
              begin EmitB($48); EmitB($0F); EmitB($B7); EmitB($85); EmitI32(Syms[idx].Offset); end;
          end
          else if sz = 4 then
          begin
            if sgn then
              begin EmitB($48); EmitB($63); EmitB($85); EmitI32(Syms[idx].Offset); end
            else
              begin EmitB($8B); EmitB($85); EmitI32(Syms[idx].Offset); end;
          end
          else
            begin EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[idx].Offset); end;
        end;
      skGlobal:
        begin
          if sz = 1 then
          begin
            if sgn then
              begin EmitB($48); EmitB($0F); EmitB($BE); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end
            else
              begin EmitB($48); EmitB($0F); EmitB($B6); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
          end
          else if sz = 2 then
          begin
            if sgn then
              begin EmitB($48); EmitB($0F); EmitB($BF); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end
            else
              begin EmitB($48); EmitB($0F); EmitB($B7); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
          end
          else if sz = 4 then
          begin
            if sgn then
              begin EmitB($48); EmitB($63); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end
            else
              begin EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
          end
          else
            begin EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
        end;
      skConst:
        MovRaxImm(Syms[idx].ConstVal);
    end;
  end;
end;

procedure EmitStoreVar(idx: Integer);
var tk: TTypeKind; sz: Integer;
begin
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);

  if TypeIsFloat(tk) then
  begin
    if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
    begin
      EmitB($48); EmitB($8B); EmitB($8D); EmitI32(Syms[idx].Offset);  { mov rcx, [rbp+off] }
      if tk = tySingle then
      begin
        EmitB($F2); EmitB($0F); EmitB($5A); EmitB($C0);                { cvtsd2ss xmm0, xmm0 }
        EmitB($F3); EmitB($0F); EmitB($11); EmitB($01);                { movss [rcx], xmm0 }
      end
      else if tk = tyExtended then
      begin
        EmitB($48); EmitB($83); EmitB($EC); EmitB($08);                { sub rsp, 8 }
        EmitB($F2); EmitB($0F); EmitB($11); EmitB($04); EmitB($24);   { movsd [rsp], xmm0 }
        EmitB($DD); EmitB($04); EmitB($24);                            { fldl [rsp] }
        EmitB($48); EmitB($83); EmitB($C4); EmitB($08);                { add rsp, 8 }
        EmitB($DB); EmitB($39);                                         { fstpt [rcx] }
      end
      else
        begin EmitB($F2); EmitB($0F); EmitB($11); EmitB($01); end;     { movsd [rcx], xmm0 }
    end
    else case Syms[idx].Kind of
      skLocal, skParam:
        if tk = tySingle then
        begin
          EmitB($F2); EmitB($0F); EmitB($5A); EmitB($C0);                           { cvtsd2ss xmm0, xmm0 }
          EmitB($F3); EmitB($0F); EmitB($11); EmitB($85); EmitI32(Syms[idx].Offset); { movss [rbp+off], xmm0 }
        end
        else if tk = tyExtended then
        begin
          EmitB($48); EmitB($83); EmitB($EC); EmitB($08);              { sub rsp, 8 }
          EmitB($F2); EmitB($0F); EmitB($11); EmitB($04); EmitB($24); { movsd [rsp], xmm0 }
          EmitB($DD); EmitB($04); EmitB($24);                          { fldl [rsp] }
          EmitB($48); EmitB($83); EmitB($C4); EmitB($08);              { add rsp, 8 }
          EmitB($DB); EmitB($BD); EmitI32(Syms[idx].Offset);           { fstpt [rbp+off] }
        end
        else
          begin EmitB($F2); EmitB($0F); EmitB($11); EmitB($85); EmitI32(Syms[idx].Offset); end; { movsd [rbp+off], xmm0 }
      skGlobal:
        if tk = tySingle then
        begin
          EmitB($F2); EmitB($0F); EmitB($5A); EmitB($C0);                                      { cvtsd2ss xmm0, xmm0 }
          EmitB($F3); EmitB($0F); EmitB($11); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); { movss [abs], xmm0 }
        end
        else if tk = tyExtended then
        begin
          EmitB($48); EmitB($83); EmitB($EC); EmitB($08);              { sub rsp, 8 }
          EmitB($F2); EmitB($0F); EmitB($11); EmitB($04); EmitB($24); { movsd [rsp], xmm0 }
          EmitB($DD); EmitB($04); EmitB($24);                          { fldl [rsp] }
          EmitB($48); EmitB($83); EmitB($C4); EmitB($08);              { add rsp, 8 }
          EmitB($DB); EmitB($3C); EmitB($25); EmitGlobRef(Syms[idx].Offset);  { fstpt [abs32] }
        end
        else
          begin EmitB($F2); EmitB($0F); EmitB($11); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end; { movsd [abs], xmm0 }
      skConst: Error('cannot assign to constant');
    end;
    Exit;
  end;

  if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
  begin
    EmitB($48); EmitB($8B); EmitB($8D); EmitI32(Syms[idx].Offset);
    if sz = 1 then
      begin EmitB($88); EmitB($01); end
    else if sz = 2 then
      begin EmitB($66); EmitB($89); EmitB($01); end
    else if sz = 4 then
      begin EmitB($89); EmitB($01); end
    else
      begin EmitB($48); EmitB($89); EmitB($01); end;
  end
  else case Syms[idx].Kind of
    skLocal, skParam:
      begin
        if sz = 1 then
          begin EmitB($88); EmitB($85); EmitI32(Syms[idx].Offset); end
        else if sz = 2 then
          begin EmitB($66); EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset); end
        else if sz = 4 then
          begin EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset); end
        else
          begin EmitB($48); EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset); end;
      end;
    skGlobal:
      begin
        if sz = 1 then
          begin EmitB($88); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end
        else if sz = 2 then
          begin EmitB($66); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end
        else if sz = 4 then
          begin EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end
        else
          begin EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
      end;
    skConst: Error('cannot assign to constant');
  end;
end;

procedure EmitCmpRaxVar(idx: Integer);
{ cmp rax, var }
begin
  case Syms[idx].Kind of
    skLocal, skParam:
      begin EmitB($48); EmitB($3B); EmitB($85); EmitI32(Syms[idx].Offset); end;
    skGlobal:
      begin EmitB($48); EmitB($3B); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
    skConst:
      begin
        { cmp rax, imm32 }
        EmitB($48); EmitB($3D); EmitI32(Syms[idx].ConstVal);
      end;
  end;
end;

{ ===== String helpers ===== }

procedure EmitStoreStrLen(idx: Integer);
begin
  if (Syms[idx].Kind = skParam) and (Syms[idx].TypeKind = tyString) then
  begin
    { param slot holds pointer P; store rax (length) into [P] }
    EmitB($48); EmitB($8B); EmitB($8D); EmitI32(Syms[idx].Offset); { mov rcx, [rbp+off] = P }
    EmitB($48); EmitB($89); EmitB($01);                              { mov [P], rax }
  end
  else
  begin
    case Syms[idx].Kind of
      skLocal, skParam:
        begin EmitB($48); EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset); end;
      skGlobal:
        begin EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
    end;
  end;
end;

procedure EmitLoadStrLen(idx: Integer);
{ Load length of string variable into rcx }
begin
  if (Syms[idx].Kind = skParam) and (Syms[idx].TypeKind = tyString) then
  begin
    EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[idx].Offset); { mov rax, [rbp+off] = P }
    EmitB($48); EmitB($8B); EmitB($08);                              { mov rcx, [rax] }
  end
  else
  begin
    case Syms[idx].Kind of
      skLocal, skParam:
        begin EmitB($48); EmitB($8B); EmitB($8D); EmitI32(Syms[idx].Offset); end; { mov rcx, [rbp+off] }
      skGlobal:
        begin EmitB($48); EmitB($8B); EmitB($0C); EmitB($25); EmitGlobRef(Syms[idx].Offset); end; { mov rcx, [abs] }
    end;
  end;
end;

procedure EmitLeaStrDataRdi(idx: Integer);
begin
  if (Syms[idx].Kind = skParam) and (Syms[idx].TypeKind = tyString) then
  begin
    { param slot holds pointer P; data at P+8 }
    EmitB($48); EmitB($8B); EmitB($BD); EmitI32(Syms[idx].Offset); { mov rdi, [rbp+off] = P }
    EmitB($48); EmitB($83); EmitB($C7); EmitB($08);                  { add rdi, 8 → P+8 }
  end
  else
  begin
    case Syms[idx].Kind of
      skLocal, skParam:
        begin EmitB($48); EmitB($8D); EmitB($BD); EmitI32(Syms[idx].Offset + 8); end;
      skGlobal:
        begin EmitB($48); EmitB($8D); EmitB($3C); EmitB($25); EmitGlobRef(Syms[idx].Offset + 8); end;
    end;
  end;
end;

procedure EmitLeaStrDataRsi(idx: Integer);
begin
  if (Syms[idx].Kind = skParam) and (Syms[idx].TypeKind = tyString) then
  begin
    { param slot holds pointer P; data at P+8 }
    EmitB($48); EmitB($8B); EmitB($B5); EmitI32(Syms[idx].Offset); { mov rsi, [rbp+off] = P }
    EmitB($48); EmitB($83); EmitB($C6); EmitB($08);                  { add rsi, 8 → P+8 }
  end
  else
  begin
    case Syms[idx].Kind of
      skLocal, skParam:
        begin EmitB($48); EmitB($8D); EmitB($B5); EmitI32(Syms[idx].Offset + 8); end;
      skGlobal:
        begin EmitB($48); EmitB($8D); EmitB($34); EmitB($25); EmitGlobRef(Syms[idx].Offset + 8); end;
    end;
  end;
end;

procedure EmitwriteStrVar(idx: Integer);
{ sys_write the string variable at Syms[idx] }
begin
  if (Syms[idx].Kind = skParam) and (Syms[idx].TypeKind = tyString) then
  begin
    { param slot holds pointer P; length at [P], data at P+8 }
    EmitB($48); EmitB($8B); EmitB($B5); EmitI32(Syms[idx].Offset); { mov rsi, [rbp+off] = P }
    EmitB($48); EmitB($8B); EmitB($16);                              { mov rdx, [P] = length }
    EmitB($48); EmitB($83); EmitB($C6); EmitB($08);                  { add rsi, 8 → P+8 }
  end
  else
  begin
    case Syms[idx].Kind of
      skLocal, skParam:
        begin EmitB($48); EmitB($8B); EmitB($95); EmitI32(Syms[idx].Offset); end;
      skGlobal:
        begin EmitB($48); EmitB($8B); EmitB($14); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
    end;
    EmitLeaStrDataRsi(idx);
  end;
  MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); EmitSyscall;
end;

procedure EmitStrAssignLiteral(dstIdx, litOff, litLen: Integer);
{ s := 'literal': store length, rep movsb the literal bytes }
begin
  { Store length into [bss+Offset] }
  MovRaxImm(litLen);
  EmitStoreStrLen(dstIdx);
  if litLen > 0 then
  begin
    { mov rcx, litLen }
    EmitB($48); EmitB($B9); EmitI64(litLen);
    { lea rdi, [bss+Offset+8] }
    EmitLeaStrDataRdi(dstIdx);
    { mov rsi, data_addr (literal bytes in data section) }
    EmitB($48); EmitB($BE); EmitDataRef(litOff + 8);
    { rep movsb }
    EmitB($F3); EmitB($A4);
  end;
end;

procedure EmitStrAssignVar(dstIdx, srcIdx: Integer);
{ s := t: copy length then rep movsb the data }
begin
  { rax = src length }
  EmitLoadVar(srcIdx);
  { store length to dst }
  EmitStoreStrLen(dstIdx);
  { rcx = length (for rep) }
  EmitB($48); EmitB($89); EmitB($C1);   { mov rcx, rax }
  { lea rdi, [bss+dst.Offset+8] }
  EmitLeaStrDataRdi(dstIdx);
  { lea rsi, [bss+src.Offset+8] }
  EmitLeaStrDataRsi(srcIdx);
  { rep movsb }
  EmitB($F3); EmitB($A4);
end;

procedure EmitArgvToString(dstIdx: Integer);
begin
  { On entry: rax = argv index. Copy argv[rax] C-string to global string dstIdx. }
  EmitB($48); EmitB($C1); EmitB($E0); EmitB($03);   { shl rax, 3 }
  EmitB($48); EmitB($8B); EmitB($0C); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);
  EmitB($48); EmitB($83); EmitB($C1); EmitB($08);   { add rcx, 8 }
  EmitB($48); EmitB($01); EmitB($C8);               { add rax, rcx }
  EmitB($48); EmitB($8B); EmitB($00);               { mov rax, [rax] }
  EmitB($48); EmitB($89); EmitB($C6);               { mov rsi, rax }
  EmitB($48); EmitB($31); EmitB($C9);               { xor rcx, rcx }
  EmitB($80); EmitB($3C); EmitB($0E); EmitB($00);   { cmp byte [rsi+rcx], 0 }
  EmitB($74); EmitB($05);                           { je +5 }
  EmitB($48); EmitB($FF); EmitB($C1);               { inc rcx }
  EmitB($EB); EmitB($F5);                           { jmp -11 }
  EmitB($48); EmitB($89); EmitB($C8);               { mov rax, rcx }
  EmitStoreStrLen(dstIdx);
  EmitLeaStrDataRdi(dstIdx);
  EmitB($F3); EmitB($A4);
end;

procedure EmitTerminateString(idx: Integer);
begin
  { Linux path syscalls need a trailing NUL beyond the Pascal length. }
  EmitLoadVar(idx);
  EmitLeaStrDataRdi(idx);
  EmitB($C6); EmitB($04); EmitB($07); EmitB($00); { mov byte [rdi+rax], 0 }
end;

procedure EmitLoadFile(pathIdx, dstIdx: Integer);
begin
  { open(path, O_RDONLY) }
  EmitTerminateString(pathIdx);
  EmitLeaStrDataRdi(pathIdx);
  MovRsiImm(0);
  MovRdxImm(0);
  MovRaxImm(SYS_OPEN);
  EmitSyscall;
  EmitB($50);                                      { save fd }

  { read(fd, dst.data, STRING_CAP) }
  EmitB($48); EmitB($89); EmitB($C7);              { mov rdi, rax }
  EmitLeaStrDataRsi(dstIdx);
  MovRdxImm(STRING_CAP);
  MovRaxImm(SYS_READ);
  EmitSyscall;

  { If rax is negative (error), clamp it to 0 }
  EmitB($48); EmitB($85); EmitB($C0);              { test rax, rax }
  EmitB($79); EmitB($0A);                          { jns skip }
  MovRaxImm(0);                                    { mov rax, 0 }
  { skip }

  EmitStoreStrLen(dstIdx);

  { close(fd) }
  EmitB($5F);                                      { pop rdi }
  MovRaxImm(SYS_CLOSE);
  EmitSyscall;
end;

procedure EmitStrCmp(aIdx, bIdx: Integer; eq: Boolean);
{ rax = 1 if (a=b), 0 otherwise.  eq=False → rax = 1 if (a<>b). }
var skipJmp, okJmp: Integer;
begin
  { Compare lengths first }
  EmitLoadVar(aIdx);
  EmitB($48); EmitB($3B); EmitB($04); EmitB($25); EmitGlobRef(Syms[bIdx].Offset);
  { jne → not equal }
  EmitB($0F); EmitB($85); skipJmp := CodeLen; EmitI32(0);
  { Lengths equal — compare bytes; rcx = length }
  EmitLoadVar(aIdx);
  EmitB($48); EmitB($89); EmitB($C1);
  { lea rdi, [a_data] }
  EmitB($48); EmitB($8D); EmitB($3C); EmitB($25); EmitGlobRef(Syms[aIdx].Offset + 8);
  { lea rsi, [b_data] }
  EmitB($48); EmitB($8D); EmitB($34); EmitB($25); EmitGlobRef(Syms[bIdx].Offset + 8);
  { repe cmpsb }
  EmitB($F3); EmitB($A6);
  { je → bytes equal }
  EmitB($0F); EmitB($84); okJmp := CodeLen; EmitI32(0);
  { Not equal }
  Patch32(skipJmp, CodeLen - (skipJmp + 4));
  if eq then MovRaxImm(0) else MovRaxImm(1);
  EmitB($E9); skipJmp := CodeLen; EmitI32(0);
  Patch32(okJmp, CodeLen - (okJmp + 4));
  if eq then MovRaxImm(1) else MovRaxImm(0);
  Patch32(skipJmp, CodeLen - (skipJmp + 4));
end;

procedure EmitStrCmpReg(eq: Boolean);
var skipJmp, okJmp: Integer;
begin
  { mov rsi, rcx }
  EmitB($48); EmitB($89); EmitB($CE);
  { add rsi, 8 }
  EmitB($48); EmitB($83); EmitB($C6); EmitB($08);
  { mov rdi, rax }
  EmitB($48); EmitB($89); EmitB($C7);
  { add rdi, 8 }
  EmitB($48); EmitB($83); EmitB($C7); EmitB($08);
  { mov rcx, [rcx] }
  EmitB($48); EmitB($8B); EmitB($09);
  { cmp rcx, [rax] }
  EmitB($48); EmitB($3B); EmitB($08);

  { jne not_equal }
  EmitB($0F); EmitB($85); skipJmp := CodeLen; EmitI32(0);

  { repe cmpsb }
  EmitB($F3); EmitB($A6);

  { je equal }
  EmitB($0F); EmitB($84); okJmp := CodeLen; EmitI32(0);

  { not_equal: }
  Patch32(skipJmp, CodeLen - (skipJmp + 4));
  if eq then MovRaxImm(0) else MovRaxImm(1);
  EmitB($E9); skipJmp := CodeLen; EmitI32(0);

  { equal: }
  Patch32(okJmp, CodeLen - (okJmp + 4));
  if eq then MovRaxImm(1) else MovRaxImm(0);

  { end: }
  Patch32(skipJmp, CodeLen - (skipJmp + 4));
end;

{ ===== Array element access ===== }

procedure EmitBumpAlloc;
{ On entry: rax = byte count requested. On exit: rax = allocated block base.
  Rounds size up to 8, bumps BSS_HEAP_PTR, grows the break via brk if needed.
  Shared by GetMem/class-new (codegen.inc) and dynamic-array SetLength (both
  backends), so it lives here in symtab.inc ahead of every caller. }
var jbePatch: Integer;
begin
  { Round size up to multiple of 8 for alignment }
  EmitB($48); EmitB($83); EmitB($C0); EmitB($07); { add rax, 7 }
  EmitB($48); EmitB($83); EmitB($E0); EmitB($F8); { and rax, -8 }
  { mov rbx, [BSS_HEAP_PTR] }
  EmitB($48); EmitB($8B); EmitB($1C); EmitB($25); EmitGlobRef(BSS_HEAP_PTR);
  { add rbx, rax }
  EmitB($48); EmitB($01); EmitB($C3);
  { cmp rbx, [BSS_HEAP_END] }
  EmitB($48); EmitB($3B); EmitB($1C); EmitB($25); EmitGlobRef(BSS_HEAP_END);
  { jbe skip_brk }
  EmitB($76); jbePatch := CodeLen; EmitB(0);
  { push rbx }
  EmitB($53);
  { mov rdi, rbx }
  EmitB($48); EmitB($89); EmitB($DF);
  { mov rax, SYS_BRK }
  MovRaxImm(SYS_BRK);
  { syscall }
  EmitSyscall;
  { pop rbx }
  EmitB($5B);
  { mov [BSS_HEAP_END], rax }
  EmitB($48); EmitB($89); EmitB($04); EmitB($25); EmitGlobRef(BSS_HEAP_END);
  { Patch short jump offset }
  Code[jbePatch] := Byte(CodeLen - (jbePatch + 1));
  { mov rax, [BSS_HEAP_PTR] }
  EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(BSS_HEAP_PTR);
  { mov [BSS_HEAP_PTR], rbx }
  EmitB($48); EmitB($89); EmitB($1C); EmitB($25); EmitGlobRef(BSS_HEAP_PTR);
end;

procedure EmitArrElemAddr(arrIdx: Integer);
{ On entry: rax = array index. On exit: rax = element address. }
var elemSize: Integer;
begin
  if Syms[arrIdx].ElemType = tyString then
  begin
    if Syms[arrIdx].Kind = skGlobal then elemSize := STRING_CAP + 8
    else elemSize := LOCAL_STR_CAP + 8;
  end
  else if Syms[arrIdx].ElemType = tyRecord then elemSize := RecSize(Syms[arrIdx].ElemRecName)
  else elemSize := TypeSize(Syms[arrIdx].ElemType);

  if elemSize = 8 then
  begin
    { shl rax, 3  (multiply by 8) }
    EmitB($48); EmitB($C1); EmitB($E0); EmitB($03);
  end
  else if elemSize > 1 then
  begin
    { mov rcx, elemSize }
    EmitB($48); EmitB($C7); EmitB($C1); EmitI32(elemSize);
    { imul rax, rcx }
    EmitB($48); EmitB($0F); EmitB($AF); EmitB($C1);
  end;

  { Subtract lower bound * elemSize (if non-zero) }
  if Syms[arrIdx].ConstVal <> 0 then
  begin
    EmitB($48); EmitB($2D); EmitI32(Syms[arrIdx].ConstVal * elemSize);
  end;

  if Syms[arrIdx].Kind = skGlobal then
  begin
    { add eax, bss_arr_base  (32-bit add, zero-extends to rax) }
    EmitB($05); EmitGlobRef(Syms[arrIdx].Offset);
  end
  else
  begin
    EmitB($48); EmitB($01); EmitB($E8);       { add rax, rbp }
    EmitB($48); EmitB($05); EmitI32(Syms[arrIdx].Offset);
  end;
end;

procedure EmitArrLoad(arrIdx: Integer);
{ rax = index → rax = element value }
var sz: Integer; sgn: Boolean;
begin
  EmitArrElemAddr(arrIdx);
  sz := TypeSize(Syms[arrIdx].ElemType);
  sgn := TypeSigned(Syms[arrIdx].ElemType);
  if sz = 1 then
  begin
    if sgn then
      begin EmitB($48); EmitB($0F); EmitB($BE); EmitB($00); end { movsx rax, byte [rax] }
    else
      begin EmitB($48); EmitB($0F); EmitB($B6); EmitB($00); end;{ movzx rax, byte [rax] }
  end
  else if sz = 2 then
  begin
    if sgn then
      begin EmitB($48); EmitB($0F); EmitB($BF); EmitB($00); end { movsx rax, word [rax] }
    else
      begin EmitB($48); EmitB($0F); EmitB($B7); EmitB($00); end;{ movzx rax, word [rax] }
  end
  else if sz = 4 then
  begin
    if sgn then
      begin EmitB($48); EmitB($63); EmitB($00); end { movsxd rax, dword [rax] }
    else
      begin EmitB($8B); EmitB($00); end;{ mov eax, dword [rax] }
  end
  else
    begin EmitB($48); EmitB($8B); EmitB($00); end; { mov rax, [rax] }
end;

procedure EmitStringCharLoad(strIdx: Integer);
begin
  { On entry: rax = Pascal string index (1-based). On exit: rax = byte value. }
  EmitB($48); EmitB($FF); EmitB($C8);                 { dec rax }
  EmitB($48); EmitB($05); EmitGlobRef(Syms[strIdx].Offset + 8);
  EmitB($48); EmitB($0F); EmitB($B6); EmitB($00);     { movzx rax, byte [rax] }
end;

procedure EmitArrStore(arrIdx: Integer);
{ Stack: [..., addr]. rax = value. Store value at addr. }
var sz: Integer;
begin
  { addr was pushed before RHS eval }
  EmitB($59);                   { pop rcx -- element address }
  sz := TypeSize(Syms[arrIdx].ElemType);
  if sz = 1 then
    begin EmitB($88); EmitB($01); end
  else if sz = 2 then
    begin EmitB($66); EmitB($89); EmitB($01); end
  else if sz = 4 then
    begin EmitB($89); EmitB($01); end
  else
    begin EmitB($48); EmitB($89); EmitB($01); end;
end;

{ ===== Operator overload table ===== }

procedure RegisterOpOverload(opKind, typeKind, recId, procIdx: Integer);
begin
  if OvrlCount >= MAX_OP_OVERLOADS then Error('too many operator overloads');
  OvrlOpKind[OvrlCount]   := opKind;
  OvrlTypeKind[OvrlCount] := typeKind;
  OvrlRecId[OvrlCount]    := recId;
  OvrlProcIdx[OvrlCount]  := procIdx;
  Inc(OvrlCount);
end;

function FindOpOverload(opKind, typeKind, recId: Integer): Integer;
var i: Integer;
begin
  Result := -1;
  i := 0;
  while i < OvrlCount do
  begin
    if (OvrlOpKind[i] = opKind) and (OvrlTypeKind[i] = typeKind) and (OvrlRecId[i] = recId) then
    begin
      Result := OvrlProcIdx[i];
      Exit;
    end;
    Inc(i);
  end;
end;

{ ===== Procedure table ===== }

function FindProc(const name: AnsiString): Integer;
var i: Integer; lo: AnsiString;
begin
  lo := name;
  for i := 0 to ProcCount-1 do
    if Procs[i].Name = lo then begin Result := i; Exit; end;
  Result := -1;
end;

function HasNonOverloadProc(const name: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 0 to ProcCount-1 do
    if (Procs[i].Name = name) and not ProcOverloadDirective[i] then
    begin
      Result := True;
      Exit;
    end;
end;

function FindProcOverload(const name: AnsiString; nParams: Integer; const ptypes: array of TTypeKind; const parr: array of Boolean; const pbyref: array of Boolean): Integer;
var i, j: Integer; match: Boolean;
begin
  for i := 0 to ProcCount-1 do
  begin
    if Procs[i].Name = name then
    begin
      if Procs[i].ParamCount = nParams then
      begin
        match := True;
        for j := 0 to nParams-1 do
        begin
          if (Procs[i].Params[j].TypeKind <> ptypes[j]) or
             (Procs[i].Params[j].IsArray <> parr[j]) or
             (Procs[i].Params[j].IsRef <> pbyref[j]) then
            match := False;
        end;
        if match then
        begin
          Result := i;
          Exit;
        end;
      end;
    end;
  end;
  Result := -1;
end;

function TypesCompatible(pType, aType: TTypeKind): Boolean;
begin
  if pType = aType then
  begin
    Result := True;
    Exit;
  end;
  if TypeIsOrdinal(pType) and TypeIsOrdinal(aType) then
  begin
    Result := True;
    Exit;
  end;
  if (pType = tyString) and (aType = tyChar) then
  begin
    Result := True;
    Exit;
  end;
  Result := False;
end;

function MatchProcCall(const name: AnsiString; nArgs: Integer; const argTypes: array of TTypeKind): Integer;
var i, j: Integer; match: Boolean;
begin
  { Phase 1: Try exact match }
  for i := 0 to ProcCount-1 do
  begin
    if Procs[i].Name = name then
    begin
      if Procs[i].ParamCount = nArgs then
      begin
        match := True;
        for j := 0 to nArgs-1 do
        begin
          if Procs[i].Params[j].TypeKind <> argTypes[j] then
            match := False;
        end;
        if match then
        begin
          Result := i;
          Exit;
        end;
      end;
    end;
  end;

  { Phase 2: Try compatible match }
  for i := 0 to ProcCount-1 do
  begin
    if Procs[i].Name = name then
    begin
      if Procs[i].ParamCount = nArgs then
      begin
        match := True;
        for j := 0 to nArgs-1 do
        begin
          if not TypesCompatible(Procs[i].Params[j].TypeKind, argTypes[j]) then
            match := False;
        end;
        if match then
        begin
          Result := i;
          Exit;
        end;
      end;
    end;
  end;

  writeln('Mismatch in MatchProcCall: name = ', name, ', nArgs = ', nArgs);
  for j := 0 to nArgs-1 do
    writeln('  arg[', j, '] = ', Ord(argTypes[j]));
  for i := 0 to ProcCount-1 do
  begin
    if Procs[i].Name = name then
    begin
      writeln('  Candidate idx ', i, ': paramCount = ', Procs[i].ParamCount);
      for j := 0 to Procs[i].ParamCount-1 do
        writeln('    param[', j, '] = ', Ord(Procs[i].Params[j].TypeKind));
    end;
  end;

  Result := -1;
end;


function RegisterProc(const name: AnsiString; isFunc: Boolean;
  retType: TTypeKind; nParams: Integer;
  const pnames: array of AnsiString; const ptypes: array of TTypeKind): Integer;
var i: Integer;
begin
  if ProcCount >= MAX_PROCS then Error('too many procedures');
  Procs[ProcCount].Name       := name;
  Procs[ProcCount].IsFunc     := isFunc;
  Procs[ProcCount].RetType    := retType;
  Procs[ProcCount].ParamCount := nParams;
  Procs[ProcCount].BodyAddr   := -1;
  Procs[ProcCount].FramePatch := -1;
  Procs[ProcCount].RetSymIdx  := -1;
  Procs[ProcCount].ScopeBase  := 0;
  ProcExternal[ProcCount]     := False;
  ProcOverloadDirective[ProcCount] := False;
  ProcLibrary[ProcCount]      := -1;
  for i := 0 to nParams-1 do
  begin
    Procs[ProcCount].Params[i].Name     := pnames[i];
    Procs[ProcCount].Params[i].TypeKind := ptypes[i];
    Procs[ProcCount].Params[i].SymIdx   := -1;
    Procs[ProcCount].Params[i].IsArray  := False;
    Procs[ProcCount].Params[i].IsRef    := False;
  end;
  Result := ProcCount; Inc(ProcCount);
end;

{ ===== int-to-string write ===== }

procedure EmitwriteInt;
var jnsOff, loopStart: Integer;
begin
  EmitB($48); EmitB($85); EmitB($C0);
  EmitB($79); jnsOff := CodeLen; EmitB(0);
  EmitB($48); EmitB($F7); EmitB($D8);
  EmitB($50);
  EmitwriteSyscall(MINUS_OFFSET, 1);
  EmitB($58);
  Code[jnsOff] := Byte(CodeLen - (jnsOff + 1));
  EmitB($48); EmitB($31); EmitB($C9);
  MovRbxImm(10);
  EmitB($48); EmitB($BF); EmitDataRef(INTBUF_OFFSET + INTBUF_SIZE);
  loopStart := CodeLen;
  EmitB($48); EmitB($31); EmitB($D2);
  EmitB($48); EmitB($F7); EmitB($F3);
  EmitB($80); EmitB($C2); EmitB($30);
  EmitB($48); EmitB($FF); EmitB($CF);
  EmitB($88); EmitB($17);
  EmitB($48); EmitB($FF); EmitB($C1);
  EmitB($48); EmitB($85); EmitB($C0);
  EmitB($75); EmitB(Byte(loopStart - (CodeLen + 1)));
  EmitB($48); EmitB($89); EmitB($FE);
  EmitB($48); EmitB($89); EmitB($CA);
  MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); EmitSyscall;
end;

procedure EmitwriteUInt;
var loopStart: Integer;
begin
  EmitB($48); EmitB($31); EmitB($C9);
  MovRbxImm(10);
  EmitB($48); EmitB($BF); EmitDataRef(INTBUF_OFFSET + INTBUF_SIZE);
  loopStart := CodeLen;
  EmitB($48); EmitB($31); EmitB($D2);
  EmitB($48); EmitB($F7); EmitB($F3);
  EmitB($80); EmitB($C2); EmitB($30);
  EmitB($48); EmitB($FF); EmitB($CF);
  EmitB($88); EmitB($17);
  EmitB($48); EmitB($FF); EmitB($C1);
  EmitB($48); EmitB($85); EmitB($C0);
  EmitB($75); EmitB(Byte(loopStart - (CodeLen + 1)));
  EmitB($48); EmitB($89); EmitB($FE);
  EmitB($48); EmitB($89); EmitB($CA);
  MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); EmitSyscall;
end;

procedure EmitwriteChar;
{ rax = char byte value → write 1 byte to stdout }
begin
  EmitB($48); EmitB($BE); EmitDataRef(INTBUF_OFFSET);
  EmitB($88); EmitB($06);
  MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); MovRdxImm(1); EmitSyscall;
end;

procedure EnsureSpaces;
var j: Integer;
begin
  if SpacesOffset >= 0 then Exit;
  SpacesOffset := DataLen;
  for j := 0 to SPACES_SIZE - 1 do Data[DataLen + j] := $20;
  Inc(DataLen, SPACES_SIZE);
end;

procedure EmitwriteIntW(width: Integer);
{ rax = signed int → right-aligned in field of min width chars }
var jnsOff, jleOff, jzOff, loopStart: Integer;
begin
  { r8 = sign flag (0=positive, 1=negative) }
  EmitB($4D); EmitB($31); EmitB($C0);                    { xor r8, r8 }
  EmitB($48); EmitB($85); EmitB($C0);                    { test rax, rax }
  EmitB($79); jnsOff := CodeLen; EmitB(0);               { jns .positive }
  EmitB($48); EmitB($F7); EmitB($D8);                    { neg rax }
  EmitB($49); EmitB($FF); EmitB($C0);                    { inc r8 }
  Code[jnsOff] := Byte(CodeLen - (jnsOff + 1));
  { Digit conversion into INTBUF from end }
  EmitB($48); EmitB($31); EmitB($C9);                    { xor rcx, rcx }
  MovRbxImm(10);
  EmitB($48); EmitB($BF); EmitDataRef(INTBUF_OFFSET + INTBUF_SIZE);
  loopStart := CodeLen;
  EmitB($48); EmitB($31); EmitB($D2);                    { xor rdx, rdx }
  EmitB($48); EmitB($F7); EmitB($F3);                    { div rbx }
  EmitB($80); EmitB($C2); EmitB($30);                    { add dl, '0' }
  EmitB($48); EmitB($FF); EmitB($CF);                    { dec rdi }
  EmitB($88); EmitB($17);                                { mov [rdi], dl }
  EmitB($48); EmitB($FF); EmitB($C1);                    { inc rcx }
  EmitB($48); EmitB($85); EmitB($C0);                    { test rax, rax }
  EmitB($75); EmitB(Byte(loopStart - (CodeLen + 1)));    { jnz loop }
  { Save digit start/count; compute padding = width - digits - sign }
  EmitB($57);                                            { push rdi }
  EmitB($51);                                            { push rcx }
  MovRaxImm(width);
  EmitB($48); EmitB($29); EmitB($C8);                    { sub rax, rcx }
  EmitB($4C); EmitB($29); EmitB($C0);                    { sub rax, r8 }
  EmitB($7E); jleOff := CodeLen; EmitB(0);               { jle .no_pad }
  EnsureSpaces;
  EmitB($48); EmitB($BE); EmitDataRef(SpacesOffset);    { mov rsi, spaces }
  EmitB($48); EmitB($89); EmitB($C2);                    { mov rdx, rax }
  MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); EmitSyscall;
  Code[jleOff] := Byte(CodeLen - (jleOff + 1));
  { Write sign if negative }
  EmitB($4D); EmitB($85); EmitB($C0);                    { test r8, r8 }
  EmitB($74); jzOff := CodeLen; EmitB(0);                { jz .no_sign }
  EmitwriteSyscall(MINUS_OFFSET, 1);
  Code[jzOff] := Byte(CodeLen - (jzOff + 1));
  { Write digits }
  EmitB($5A);                                            { pop rdx }
  EmitB($5E);                                            { pop rsi }
  MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); EmitSyscall;
end;

procedure EmitwriteUIntW(width: Integer);
{ rax = unsigned int → right-aligned in field of min width chars }
var jleOff, loopStart: Integer;
begin
  EmitB($48); EmitB($31); EmitB($C9);                    { xor rcx, rcx }
  MovRbxImm(10);
  EmitB($48); EmitB($BF); EmitDataRef(INTBUF_OFFSET + INTBUF_SIZE);
  loopStart := CodeLen;
  EmitB($48); EmitB($31); EmitB($D2);                    { xor rdx, rdx }
  EmitB($48); EmitB($F7); EmitB($F3);                    { div rbx }
  EmitB($80); EmitB($C2); EmitB($30);                    { add dl, '0' }
  EmitB($48); EmitB($FF); EmitB($CF);                    { dec rdi }
  EmitB($88); EmitB($17);                                { mov [rdi], dl }
  EmitB($48); EmitB($FF); EmitB($C1);                    { inc rcx }
  EmitB($48); EmitB($85); EmitB($C0);                    { test rax, rax }
  EmitB($75); EmitB(Byte(loopStart - (CodeLen + 1)));    { jnz loop }
  EmitB($57);                                            { push rdi }
  EmitB($51);                                            { push rcx }
  MovRaxImm(width);
  EmitB($48); EmitB($29); EmitB($C8);                    { sub rax, rcx }
  EmitB($7E); jleOff := CodeLen; EmitB(0);               { jle .no_pad }
  EnsureSpaces;
  EmitB($48); EmitB($BE); EmitDataRef(SpacesOffset);
  EmitB($48); EmitB($89); EmitB($C2);                    { mov rdx, rax }
  MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); EmitSyscall;
  Code[jleOff] := Byte(CodeLen - (jleOff + 1));
  EmitB($5A);                                            { pop rdx }
  EmitB($5E);                                            { pop rsi }
  MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); EmitSyscall;
end;

procedure EmitWriteFloatFixed(decimals: Integer);
{ Double value in xmm0. Prints [-]intpart.frac with exactly 'decimals'
  fractional digits (decimals=0 -> rounded integer, no point). Reuses the
  integer printers; the value is scaled by 10^decimals and rounded to an
  Int64 so all digits come from integer division. No field-width padding. }
var pow10, divisor: Int64; i, k, jncOff: Integer;
begin
  pow10 := 1;
  for i := 1 to decimals do pow10 := pow10 * 10;

  { sign: if the sign bit is set, print '-' and clear it (abs) }
  EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0);   { movq rax, xmm0 }
  EmitB($48); EmitB($0F); EmitB($BA); EmitB($E0); EmitB($3F);   { bt rax, 63 }
  EmitB($73); jncOff := CodeLen; EmitB(0);                      { jnc .pos }
  EmitB($48); EmitB($0F); EmitB($BA); EmitB($F0); EmitB($3F);   { btr rax, 63 }
  EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C0);   { movq xmm0, rax }
  MovRaxImm(Ord('-')); EmitwriteChar;
  Code[jncOff] := Byte(CodeLen - (jncOff + 1));

  { xmm0 *= (double)pow10 ; rax = round(xmm0) }
  MovRaxImm(pow10);
  EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($C8);   { cvtsi2sd xmm1, rax }
  EmitB($F2); EmitB($0F); EmitB($59); EmitB($C1);               { mulsd xmm0, xmm1 }
  EmitB($F2); EmitB($48); EmitB($0F); EmitB($2D); EmitB($C0);   { cvtsd2si rax, xmm0 }

  if decimals <= 0 then begin EmitwriteUInt; Exit; end;

  { split: rax = intpart, rdx = frac }
  EmitB($48); EmitB($31); EmitB($D2);                           { xor rdx, rdx }
  EmitB($48); EmitB($BB); EmitI64(pow10);                       { mov rbx, pow10 }
  EmitB($48); EmitB($F7); EmitB($F3);                           { div rbx }
  EmitB($52);                                                   { push rdx (frac) }
  EmitwriteUInt;                                                { print intpart }
  MovRaxImm(Ord('.')); EmitwriteChar;
  EmitB($5B);                                                   { pop rbx (frac) }

  { print frac as 'decimals' zero-padded digits, most significant first.
    frac stays in rbx (preserved across the write syscall). }
  for i := decimals - 1 downto 0 do
  begin
    divisor := 1;
    for k := 1 to i do divisor := divisor * 10;
    EmitB($48); EmitB($89); EmitB($D8);                         { mov rax, rbx }
    EmitB($48); EmitB($31); EmitB($D2);                         { xor rdx, rdx }
    EmitB($48); EmitB($B9); EmitI64(divisor);                   { mov rcx, divisor }
    EmitB($48); EmitB($F7); EmitB($F1);                         { div rcx }
    EmitB($48); EmitB($89); EmitB($D3);                         { mov rbx, rdx }
    EmitB($48); EmitB($83); EmitB($C0); EmitB($30);             { add rax, '0' }
    EmitwriteChar;
  end;
end;

procedure EmitWriteFloatSci;
{ Double value in xmm0. Prints Pascal-style scientific notation:
  <' '|'-'>d.<15 digits>E<'+'|'-'>ddd  (16 significant digits, 3-digit exponent).
  Digit extraction uses double arithmetic, so the last 1-2 digits may differ
  from a bignum formatter; adequate for general output. e10 kept in r12. }
const FRAC = 15;
var jncPos, jmpSignDone, jnzNz, jmpDone: Integer;
    laTop, laJb, lbTop, lbJae, jnsPos2, jmpEd: Integer;
    k, j: Integer; divisor: Int64;
begin
  EmitB($41); EmitB($54);                                       { push r12 }

  { ---- sign ---- }
  EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0);   { movq rax, xmm0 }
  EmitB($48); EmitB($0F); EmitB($BA); EmitB($E0); EmitB($3F);   { bt rax, 63 }
  EmitB($73); jncPos := CodeLen; EmitB(0);                      { jnc .pos }
  EmitB($48); EmitB($0F); EmitB($BA); EmitB($F0); EmitB($3F);   { btr rax, 63 }
  EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C0);   { movq xmm0, rax }
  MovRaxImm(Ord('-')); EmitwriteChar;
  EmitB($EB); jmpSignDone := CodeLen; EmitB(0);                 { jmp .signdone }
  Code[jncPos] := Byte(CodeLen - (jncPos + 1));                 { .pos: }
  MovRaxImm(Ord(' ')); EmitwriteChar;
  Code[jmpSignDone] := Byte(CodeLen - (jmpSignDone + 1));       { .signdone: }

  { 10.0 -> xmm1, 1.0 -> xmm2 (preserved across syscalls) }
  MovRaxImm(10); EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($C8); { cvtsi2sd xmm1, rax }
  MovRaxImm(1);  EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($D0); { cvtsi2sd xmm2, rax }

  { ---- zero special case ---- }
  EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0);   { movq rax, xmm0 }
  EmitB($48); EmitB($85); EmitB($C0);                          { test rax, rax }
  EmitB($0F); EmitB($85); jnzNz := CodeLen; EmitI32(0);        { jnz .nz }
  MovRaxImm(Ord('0')); EmitwriteChar;
  MovRaxImm(Ord('.')); EmitwriteChar;
  for j := 1 to FRAC do begin MovRaxImm(Ord('0')); EmitwriteChar; end;
  MovRaxImm(Ord('E')); EmitwriteChar;
  MovRaxImm(Ord('+')); EmitwriteChar;
  for j := 1 to 3 do begin MovRaxImm(Ord('0')); EmitwriteChar; end;
  EmitB($E9); jmpDone := CodeLen; EmitI32(0);                  { jmp .done }
  Patch32(jnzNz, CodeLen - (jnzNz + 4));                       { .nz: }

  { ---- normalize value into [1,10), tracking decimal exponent in r12 ---- }
  EmitB($4D); EmitB($31); EmitB($E4);                          { xor r12, r12 }
  laTop := CodeLen;                                            { .la: while value>=10 }
  EmitB($66); EmitB($0F); EmitB($2E); EmitB($C1);              { ucomisd xmm0, xmm1 }
  EmitB($72); laJb := CodeLen; EmitB(0);                       { jb .ea }
  EmitB($F2); EmitB($0F); EmitB($5E); EmitB($C1);              { divsd xmm0, xmm1 }
  EmitB($49); EmitB($FF); EmitB($C4);                          { inc r12 }
  EmitB($EB); EmitB(Byte(laTop - (CodeLen + 1)));              { jmp .la }
  Code[laJb] := Byte(CodeLen - (laJb + 1));                    { .ea: }
  lbTop := CodeLen;                                            { .lb: while value<1 }
  EmitB($66); EmitB($0F); EmitB($2E); EmitB($C2);              { ucomisd xmm0, xmm2 }
  EmitB($73); lbJae := CodeLen; EmitB(0);                      { jae .eb }
  EmitB($F2); EmitB($0F); EmitB($59); EmitB($C1);              { mulsd xmm0, xmm1 }
  EmitB($49); EmitB($FF); EmitB($CC);                          { dec r12 }
  EmitB($EB); EmitB(Byte(lbTop - (CodeLen + 1)));              { jmp .lb }
  Code[lbJae] := Byte(CodeLen - (lbJae + 1));                  { .eb: }

  { m = round(value * 10^FRAC) in rbx (16-digit integer) }
  divisor := 1; for k := 1 to FRAC do divisor := divisor * 10;
  MovRaxImm(divisor);
  EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($D8);  { cvtsi2sd xmm3, rax }
  EmitB($F2); EmitB($0F); EmitB($59); EmitB($C3);              { mulsd xmm0, xmm3 }
  EmitB($F2); EmitB($48); EmitB($0F); EmitB($2D); EmitB($D8);  { cvtsd2si rbx, xmm0 }

  { print m as d.<FRAC digits>, most significant first }
  for k := FRAC downto 0 do
  begin
    divisor := 1; for j := 1 to k do divisor := divisor * 10;
    EmitB($48); EmitB($89); EmitB($D8);                        { mov rax, rbx }
    EmitB($48); EmitB($31); EmitB($D2);                        { xor rdx, rdx }
    EmitB($48); EmitB($B9); EmitI64(divisor);                  { mov rcx, divisor }
    EmitB($48); EmitB($F7); EmitB($F1);                        { div rcx }
    EmitB($48); EmitB($89); EmitB($D3);                        { mov rbx, rdx }
    EmitB($48); EmitB($83); EmitB($C0); EmitB($30);            { add rax, '0' }
    EmitwriteChar;
    if k = FRAC then begin MovRaxImm(Ord('.')); EmitwriteChar; end;
  end;

  { 'E', exponent sign, 3-digit exponent }
  MovRaxImm(Ord('E')); EmitwriteChar;
  EmitB($4C); EmitB($89); EmitB($E0);                          { mov rax, r12 }
  EmitB($48); EmitB($85); EmitB($C0);                          { test rax, rax }
  EmitB($79); jnsPos2 := CodeLen; EmitB(0);                    { jns .pos2 }
  EmitB($48); EmitB($F7); EmitB($D8);                          { neg rax }
  EmitB($48); EmitB($89); EmitB($C3);                          { mov rbx, rax }
  MovRaxImm(Ord('-')); EmitwriteChar;
  EmitB($EB); jmpEd := CodeLen; EmitB(0);                      { jmp .ed }
  Code[jnsPos2] := Byte(CodeLen - (jnsPos2 + 1));              { .pos2: }
  EmitB($48); EmitB($89); EmitB($C3);                          { mov rbx, rax }
  MovRaxImm(Ord('+')); EmitwriteChar;
  Code[jmpEd] := Byte(CodeLen - (jmpEd + 1));                  { .ed: }
  for k := 2 downto 0 do
  begin
    divisor := 1; for j := 1 to k do divisor := divisor * 10;
    EmitB($48); EmitB($89); EmitB($D8);                        { mov rax, rbx }
    EmitB($48); EmitB($31); EmitB($D2);                        { xor rdx, rdx }
    EmitB($48); EmitB($B9); EmitI64(divisor);                  { mov rcx, divisor }
    EmitB($48); EmitB($F7); EmitB($F1);                        { div rcx }
    EmitB($48); EmitB($89); EmitB($D3);                        { mov rbx, rdx }
    EmitB($48); EmitB($83); EmitB($C0); EmitB($30);            { add rax, '0' }
    EmitwriteChar;
  end;

  Patch32(jmpDone, CodeLen - (jmpDone + 4));                   { .done: }
  EmitB($41); EmitB($5C);                                       { pop r12 }
end;

function WriteExprIsFloat(node: Integer): Boolean;
{ True when a writeln argument expression has a floating-point type. }
begin
  if ASTKind[node] = AN_IDENT then
    Result := (ASTIVal[node] >= 0) and TypeIsFloat(Syms[ASTIVal[node]].TypeKind)
  else
    Result := TypeIsFloat(IntToTypeKind(ASTTk[node]));
end;

{ ===== Prologue/Epilogue ===== }

function EmitProcPrologue: Integer;
{ Returns patch position for sub rsp imm32 }
begin
  EmitB($55);
  EmitB($48); EmitB($89); EmitB($E5);
  EmitB($48); EmitB($81); EmitB($EC);
  Result := CodeLen; EmitI32(0);
end;

procedure PatchProcPrologue(patchPos, size: Integer);
var aligned: Integer;
begin
  aligned := ((size + 15) div 16) * 16;
  Patch32(patchPos, aligned);
end;

procedure EmitProcEpilog(retSymIdx: Integer);
begin
  if retSymIdx >= 0 then
  begin
    if Syms[retSymIdx].TypeKind = tyString then
    begin
      if Syms[retSymIdx].Kind = skGlobal then
      begin
        { Return BSS address of global string structure }
        EmitB($48); EmitB($C7); EmitB($C0); EmitGlobRef(Syms[retSymIdx].Offset);
      end
      else
      begin
        { Return address of the local string structure on the stack }
        EmitB($48); EmitB($8D); EmitB($85); EmitI32(Syms[retSymIdx].Offset);
      end;
    end
    else
    begin
      EmitLoadVar(retSymIdx);
    end;
  end;
  EmitB($C9); EmitB($C3);
end;

{ ===== Call emission ===== }

procedure EmitCallProc(pi: Integer);
var i, extIdx: Integer;
begin
  if ProcExternal[pi] then
  begin
    extIdx := -1;
    for i := 0 to ExternalCount-1 do
      if ExternalProc[i] = pi then extIdx := i;
    if extIdx < 0 then
    begin
      if ExternalCount >= MAX_EXTERNAL then Error('external function overflow');
      extIdx := ExternalCount;
      ExternalProc[extIdx] := pi;
      ExternalGotOff[extIdx] := DataLen;
      for i := 0 to 7 do
      begin
        Data[DataLen] := 0;
        Inc(DataLen);
      end;
      Inc(ExternalCount);
    end;
    if DynCallCount >= MAX_CALLFIX then Error('external call fixup overflow');
    { Realign the stack to 16 bytes for the SysV call: our internal call
      convention does not keep rsp 16-aligned at every call site, but C
      callees (GTK/GLib) use aligned SSE (movaps) and fault otherwise. Args
      are already in registers here (we only bind <=6-arg externals), so no
      stack arguments are disturbed. Old rsp is saved and restored around the
      call; r11 is scratch under SysV. }
    EmitB($49); EmitB($89); EmitB($E3);             { mov r11, rsp }
    EmitB($48); EmitB($83); EmitB($E4); EmitB($F0); { and rsp, -16 }
    EmitB($48); EmitB($83); EmitB($EC); EmitB($08); { sub rsp, 8 }
    EmitB($41); EmitB($53);                         { push r11 }
    { SysV: al = number of vector regs used by a variadic callee. We never
      pass float/SSE args to bound externals, so al = 0 is always correct;
      non-variadic callees ignore it. Required for gtk_message_dialog_new etc. }
    EmitB($31); EmitB($C0);                         { xor eax, eax }
    EmitB($FF); EmitB($14); EmitB($25); { call qword ptr [absolute address] }
    DynCallCodePos[DynCallCount] := CodeLen;
    DynCallExtIdx[DynCallCount] := extIdx;
    Inc(DynCallCount);
    EmitI32(0);
    EmitB($41); EmitB($5B);                         { pop r11 }
    EmitB($4C); EmitB($89); EmitB($DC);             { mov rsp, r11 }
    Exit;
  end;
  EmitB($E8);
  if Procs[pi].BodyAddr >= 0 then
    EmitI32(Procs[pi].BodyAddr - (CodeLen + 4))
  else
  begin
    if CallFixCount >= MAX_CALLFIX then Error('call fixup overflow');
    CallFix[CallFixCount].CodePos := CodeLen;
    CallFix[CallFixCount].ProcIdx := pi;
    Inc(CallFixCount);
    EmitI32(0);
  end;
end;

procedure ApplyCallFixups;
var i, pi: Integer;
begin
  if DebugTrace then
    for i := 0 to ProcCount-1 do
      writeln('Proc ', i, ': ', Procs[i].Name, ' at CodePos ', Procs[i].BodyAddr);
  for i := 0 to CallFixCount-1 do
  begin
    pi := CallFix[i].ProcIdx;
    if Procs[pi].BodyAddr < 0 then
      Error('unresolved forward');
    Patch32(CallFix[i].CodePos, Procs[pi].BodyAddr - (CallFix[i].CodePos + 4));
  end;
end;

function GetASTStrVal(node: Integer): AnsiString;
var s: AnsiString; i, off, len, j: Integer;
begin
  s := '';
  off := ASTSOffset[node];
  len := ASTSLen[node];
  i := 0;
  while i < len do
  begin
    j := off + i;
    AppendChar(s, TokChars[j]);
    Inc(i);
  end;
  Result := s;
end;

function GetASTIdentName(node: Integer): AnsiString;
var s: AnsiString; i, off, len, j: Integer;
begin
  s := '';
  off := ASTSOffset[node];
  len := ASTSLen[node];
  i := 0;
  while i < len do
  begin
    j := off + i;
    AppendChar(s, TokChars[j]);
    Inc(i);
  end;
  Result := s;
end;

function ResolveNodeRec(node: Integer): Integer;
var baseNode, baseRec, fIdx, innerNode: Integer; fieldName: AnsiString;
begin
  if ASTKind[node] = AN_IDENT then
    Result := Syms[ASTIVal[node]].RecName
  else if ASTKind[node] = AN_FIELD then
  begin
    Result := RecFieldRecId(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node));
  end
  else if ASTKind[node] = AN_INDEX then
  begin
    if ASTKind[ASTLeft[node]] = AN_IDENT then
    begin
      if Syms[ASTIVal[ASTLeft[node]]].TypeKind = tyPointer then
        Result := Syms[ASTIVal[ASTLeft[node]]].PtrElemRec
      else
        Result := Syms[ASTIVal[ASTLeft[node]]].ElemRecName;
    end
    else if ASTKind[ASTLeft[node]] = AN_FIELD then
    begin
      baseRec := ResolveNodeRec(ASTLeft[ASTLeft[node]]);
      fieldName := GetASTIdentName(ASTLeft[node]);
      fIdx := -1;
      if baseRec >= REC_UCLASS_BASE then
        fIdx := FindUField(baseRec - REC_UCLASS_BASE, fieldName);
      if (fIdx >= 0) and (UFldTk[fIdx] = Ord(tyPointer)) then
        Result := UFldPtrElemRec[fIdx]
      else
        Result := ResolveNodeRec(ASTLeft[node]);
    end
    else
      Result := REC_NONE;
  end
  else if ASTKind[node] = AN_DEREF then
  begin
    baseNode := ASTLeft[node];
    if ASTKind[baseNode] = AN_IDENT then
      Result := Syms[ASTIVal[baseNode]].PtrElemRec
    else if ASTKind[baseNode] = AN_FIELD then
    begin
      baseRec := ResolveNodeRec(ASTLeft[baseNode]);
      fieldName := GetASTIdentName(baseNode);
      fIdx := -1;
      if baseRec >= REC_UCLASS_BASE then
        fIdx := FindUField(baseRec - REC_UCLASS_BASE, fieldName);
      if fIdx >= 0 then
        Result := UFldPtrElemRec[fIdx]
      else
        Result := REC_NONE;
    end
    else if ASTKind[baseNode] = AN_INDEX then
    begin
      innerNode := ASTLeft[baseNode];
      if ASTKind[innerNode] = AN_IDENT then
        Result := Syms[ASTIVal[innerNode]].PtrElemRec
      else
        Result := REC_NONE;
    end
    else if ASTKind[baseNode] = AN_PTR_CAST then
    begin
      if ASTIVal[baseNode] >= 0 then
        Result := AliasElemRec[ASTIVal[baseNode]]
      else
        Result := REC_NONE;
    end
    else
      Result := REC_NONE;
  end
  else if (ASTKind[node] = AN_CALL) and (ASTIVal[node] = -Ord(tkGetMem)) then
    Result := ASTRight[node]
  else if ASTKind[node] = AN_PTR_CAST then
  begin
    if ASTIVal[node] >= 0 then
      Result := AliasElemRec[ASTIVal[node]]
    else
      Result := REC_NONE;
  end
  else
    Result := REC_NONE;
end;

function IsNodeArray(node: Integer): Boolean;
begin
  Result := False;
  if ASTKind[node] = AN_IDENT then
    Result := Syms[ASTIVal[node]].IsArray
  else if ASTKind[node] = AN_FIELD then
    Result := RecFieldIsArray(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node));
end;

{ ===== Expression parser ===== }
