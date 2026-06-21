{ ===== User-class helpers (must precede hardcoded record helpers) ===== }

procedure IREmitCodeCall(addr: Integer); forward;
procedure EmitDynArrayReleaseForSym(symIdx: Integer); forward;
procedure EmitVariantClear; forward;
procedure EmitManagedRecordReleaseLocked(recId: Integer); forward;
procedure EmitAcquireHeapLock; forward;
procedure EmitReleaseHeapLock; forward;
procedure EmitLoadVarA64(idx: Integer); forward;
procedure EmitA64CopyBytes(countReg, srcReg, dstReg: Integer); forward;
procedure EmitArm32CopyBytes(countReg, srcReg, dstReg: Integer); forward;
procedure EmitLoadVarArm32(idx: Integer); forward;
procedure EmitLoadVar64Arm32(idx: Integer); forward;
procedure EmitLoadVarAddrArm32(idx: Integer); forward;
procedure EmitLoadDataRefArm32(rd, dataOff: Integer); forward;
procedure EmitLoadVarXtensa(idx: Integer); forward;
procedure EmitLoadVar64Xtensa(idx: Integer); forward;
procedure EmitLoadVarRISCV32(idx: Integer); forward;
procedure EmitLoadVar64RISCV32(idx: Integer); forward;
procedure EmitLoadImmRISCV32(rd: Integer; v: Int32); forward;
procedure EmitFrameAddrXtensa(rd: Integer; off: Integer); forward;
procedure EmitLoadConstXtensa(rd: Integer; v: Int32); forward;
procedure EmitCallProc(procIdx: Integer); forward;
procedure EmitManagedLocalCleanup(retSymIdx: Integer); forward;
function ProcHasManagedLocalCleanup(procIdx, retSymIdx: Integer): Boolean; forward;
procedure EmitLeaveExceptionFrameX64; forward;


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

procedure RegisterPtrAlias(noff, nlen, elemTk, elemRec, targetNOff, targetNLen: Integer);
begin
  if AliasCount >= MAX_TYPEALIAS then Error('too many type aliases');
  AliasNOff[AliasCount] := noff;
  AliasNLen[AliasCount] := nlen;
  AliasTk[AliasCount] := Ord(tyPointer);
  AliasElemTk[AliasCount] := elemTk;
  AliasElemRec[AliasCount] := elemRec;
  AliasTargetNOff[AliasCount] := targetNOff;
  AliasTargetNLen[AliasCount] := targetNLen;
  AliasProcSig[AliasCount] := -1;
  Inc(AliasCount);
end;

procedure RegisterGeneralAlias(noff, nlen, tk, rec: Integer);
begin
  if AliasCount >= MAX_TYPEALIAS then Error('too many type aliases');
  AliasNOff[AliasCount] := noff;
  AliasNLen[AliasCount] := nlen;
  AliasTk[AliasCount] := tk;
  AliasElemTk[AliasCount] := tk;
  AliasElemRec[AliasCount] := rec;
  AliasTargetNOff[AliasCount] := 0;
  AliasTargetNLen[AliasCount] := 0;
  AliasProcSig[AliasCount] := -1;
  Inc(AliasCount);
end;

procedure RegisterMethodPtrTypeAlias(noff, nlen, sigPi, methodRec: Integer);
{ Named method-pointer type: `T = procedure(...) of object`. The value is a
  16-byte {Code,Data} record (methodRec); AliasProcSig carries the call
  signature so an indirect `v(args)` injects Self (Data) and calls Code. }
begin
  if AliasCount >= MAX_TYPEALIAS then Error('too many type aliases');
  AliasNOff[AliasCount] := noff;
  AliasNLen[AliasCount] := nlen;
  AliasTk[AliasCount] := Ord(tyRecord);
  AliasElemTk[AliasCount] := Ord(tyRecord);
  AliasElemRec[AliasCount] := methodRec;
  AliasTargetNOff[AliasCount] := 0;
  AliasTargetNLen[AliasCount] := 0;
  AliasProcSig[AliasCount] := sigPi;
  Inc(AliasCount);
end;

procedure RegisterProcTypeAlias(noff, nlen, sigPi: Integer);
{ Named procedural type: `T = procedure(...)` / `function(...): R`. The runtime
  value is a code address (pointer-sized), so reuse the pointer alias shape;
  AliasProcSig carries the signature Procs[] index used to marshal an indirect
  call's arguments and return type. }
begin
  if AliasCount >= MAX_TYPEALIAS then Error('too many type aliases');
  AliasNOff[AliasCount] := noff;
  AliasNLen[AliasCount] := nlen;
  AliasTk[AliasCount] := Ord(tyPointer);
  AliasElemTk[AliasCount] := Ord(tyUnknown);
  AliasElemRec[AliasCount] := REC_NONE;
  AliasTargetNOff[AliasCount] := 0;
  AliasTargetNLen[AliasCount] := 0;
  AliasProcSig[AliasCount] := sigPi;
  Inc(AliasCount);
end;

function FindArrayType(const name: AnsiString): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to ArrTypeCount - 1 do
    if CaseEqual(ArrTypeName[i], name) then begin Result := i; Exit; end;
end;

function FindStrConst(const name: AnsiString): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to StrConstCount - 1 do
    if CaseEqual(StrConstName[i], name) then begin Result := i; Exit; end;
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
  AliasTargetNOff[AliasCount] := 0;
  AliasTargetNLen[AliasCount] := 0;
  AliasProcSig[AliasCount] := -1;
  Inc(AliasCount);
end;

function GetSliceName(off, len: Integer): AnsiString;
var s: AnsiString; i: Integer;
begin
  s := '';
  for i := 0 to len - 1 do
    AppendChar(s, TokChars[off + i]);
  Result := s;
end;



procedure RegisterClassRefAlias(noff, nlen, classRec: Integer);
{ Named metaclass type: TFooClass = class of TFoo. Runtime values are RTTI
  pointers, so reuse the typed-pointer alias representation with a tyClass
  element marker and the base class record id. }
begin
  if AliasCount >= MAX_TYPEALIAS then Error('too many type aliases');
  AliasNOff[AliasCount] := noff;
  AliasNLen[AliasCount] := nlen;
  AliasTk[AliasCount] := Ord(tyPointer);
  AliasElemTk[AliasCount] := Ord(tyClass);
  AliasElemRec[AliasCount] := classRec;
  AliasProcSig[AliasCount] := -1;
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

function FindIMT(classCi, intfCi: Integer): Integer;
{ Index into the IMT table for (classCi, intfCi), walking the parent chain so a
  subclass inherits a parent's interface implementation. -1 if none. }
var i, cur: Integer;
begin
  Result := -1;
  cur := classCi;
  while cur >= 0 do
  begin
    for i := 0 to IMTCount - 1 do
      if (IMTClass[i] = cur) and (IMTIntf[i] = intfCi) then begin Result := i; Exit; end;
    cur := UClsParent[cur];
  end;
end;

function SymIsComInterface(symIdx: Integer): Boolean;
{ True iff the local/var symbol is a COM/ARC interface value (a reference-counted
  fat pointer): modelled as a tyRecord whose rec id is a COM-interface UCls. }
var ci: Integer;
begin
  Result := False;
  if (symIdx < 0) or (Syms[symIdx].TypeKind <> tyRecord) or Syms[symIdx].IsArray then Exit;
  if Syms[symIdx].RecName < REC_UCLASS_BASE then Exit;
  ci := Syms[symIdx].RecName - REC_UCLASS_BASE;
  if (ci < 0) or (ci >= UClsCount) then Exit;
  Result := UClsIsInterface[ci] and UClsIsComInterface[ci];
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
  UClsAlign[UClsCount]  := 1;
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
  UClsIsInterface[UClsCount] := False;
  UClsCount := UClsCount + 1;
end;

function EnsureMethodPtrRec: Integer;
{ Record id of the shared 16-byte method-pointer layout {Code@0, Data@8}. Minted
  lazily on the first `procedure(...) of object` type. No named fields are needed:
  the method-pointer assignment (@obj.method) and call read Code/Data by fixed
  offset, so only the 16-byte size + 8-byte alignment matter. }
var ci: Integer;
begin
  if MethodPtrRecId <> REC_NONE then begin Result := MethodPtrRecId; Exit; end;
  ci := AddUClass(0, 0);
  UClsSize_[ci]    := 16;
  UClsAlign[ci]    := 8;
  UClsIsRecord[ci] := True;
  MethodPtrRecId := REC_UCLASS_BASE + ci;
  Result := MethodPtrRecId;
end;

procedure AddUField(ci, noff, nlen, byteOff, tk, recId: Integer);
var fi: Integer;
begin
  if UFldCount >= MAX_UFIELD then Error('too many record/class fields (MAX_UFIELD)');
  fi := UFldCount;
  UFldNOff[fi] := noff;  UFldNLen[fi] := nlen;
  UFldOff_[fi] := byteOff; UFldTk[fi] := tk; UFldRec_[fi] := recId;
  { Procedural-type field: remember the signature so `rec.field(args)` can lower
    to an indirect call (LastTypeProcSig set by ParseTypeKind for the field type;
    a plain proc field is tyPointer, a method-pointer field tyRecord). }
  UFldProcSig[fi] := LastTypeProcSig;
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
  if tk = Ord(tySet) then
  begin
    UFldSetEnumId[fi] := LastTypeSetEnumId;
    UFldSetElemTk[fi] := LastTypeSetElemTk;
  end
  else
  begin
    UFldSetEnumId[fi] := -1;
    UFldSetElemTk[fi] := 0;
  end;
  UFldIsArray[fi] := False;
  UFldArrLen[fi] := 1;
  UFldDynDepth[fi] := 0;
  UFldArrNDims[fi] := 0;
  UFldPub[fi] := 0;
  UFldCount := UFldCount + 1;
  UClsFCount[ci] := UClsFCount[ci] + 1;
end;

procedure AddUMeth(ci, noff, nlen, procIdx: Integer);
var mi: Integer;
begin
  mi := UMthCount;
  UMthNOff[mi] := noff; UMthNLen[mi] := nlen; UMthProc_[mi] := procIdx;
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
  lo2 := lo;
  ci := FindUClass(lo2);
  if (ci >= 0) and (not UClsIsRecord[ci]) then Result := True;
end;

const
  BRF_SCALAR8 = 1;
  BRF_STRING = 2;
  BRF_RECORD_ARRAY = 3;
  BRF_SCALAR4 = 4;

function RecSize(rec: Integer): Integer; forward;

function BuiltinRecFieldCount(rec: Integer): Integer;
begin
  Result := 0;
  case rec of
    REC_TTOKEN: Result := 4;
    REC_TSTRENTRY: Result := 3;
    REC_TFIXUP, REC_TGLOBFIX, REC_TCALLFIX, REC_TMYCLASS, REC_TMETHODFIXUP: Result := 2;
    REC_TSYMBOL: Result := 13;
    REC_TPARAM: Result := 5;
    REC_TPROC: Result := 9;
    REC_TRAWTOKEN: Result := 5;
    REC_TTEMPLATE: Result := 4;
    REC_TSPECIALIZATION: Result := 4;
    REC_TGENERICFUNC: Result := 5;
    REC_TPENDINGGFSPEC: Result := 4;
  end;
end;

function BuiltinRecFieldName(rec, idx: Integer): AnsiString;
begin
  Result := '';
  case rec of
    REC_TTOKEN:
      case idx of
        0: Result := 'Kind'; 1: Result := 'SVal';
        2: Result := 'IVal'; 3: Result := 'Line';
      end;
    REC_TSTRENTRY:
      case idx of
        0: Result := 'Text'; 1: Result := 'Offset'; 2: Result := 'Len';
      end;
    REC_TFIXUP:
      case idx of 0: Result := 'CodePos'; 1: Result := 'DataOff'; end;
    REC_TGLOBFIX:
      case idx of 0: Result := 'CodePos'; 1: Result := 'BSSoff'; end;
    REC_TCALLFIX:
      case idx of 0: Result := 'CodePos'; 1: Result := 'ProcIdx'; end;
    REC_TSYMBOL:
      case idx of
        0: Result := 'Name'; 1: Result := 'TypeKind';
        2: Result := 'Kind'; 3: Result := 'Offset';
        4: Result := 'ConstVal'; 5: Result := 'IsArray';
        6: Result := 'ArrLen'; 7: Result := 'ElemType';
        8: Result := 'RecName'; 9: Result := 'ElemRecName';
        10: Result := 'IsRef'; 11: Result := 'PtrElemTk';
        12: Result := 'PtrElemRec';
      end;
    REC_TPARAM:
      case idx of
        0: Result := 'Name'; 1: Result := 'TypeKind';
        2: Result := 'SymIdx'; 3: Result := 'IsRef';
        4: Result := 'IsArray';
      end;
    REC_TPROC:
      case idx of
        0: Result := 'Name'; 1: Result := 'IsFunc';
        2: Result := 'RetType'; 3: Result := 'ParamCount';
        4: Result := 'Params'; 5: Result := 'BodyAddr';
        6: Result := 'FramePatch'; 7: Result := 'RetSymIdx';
        8: Result := 'ScopeBase';
      end;
    REC_TRAWTOKEN:
      case idx of
        0: Result := 'Kind'; 1: Result := 'IVal';
        2: Result := 'Line'; 3: Result := 'SOffset';
        4: Result := 'SLen';
      end;
    REC_TMYCLASS:
      case idx of 0: Result := 'x'; 1: Result := 'y'; end;
    REC_TTEMPLATE:
      case idx of
        0: Result := 'Name'; 1: Result := 'Param';
        2: Result := 'TokStart'; 3: Result := 'TokCount';
      end;
    REC_TSPECIALIZATION:
      case idx of
        0: Result := 'Name'; 1: Result := 'TemplateName';
        2: Result := 'ConcreteType'; 3: Result := 'ConcreteName';
      end;
    REC_TGENERICFUNC:
      case idx of
        0: Result := 'Name'; 1: Result := 'Param';
        2: Result := 'IsFunc'; 3: Result := 'TokStart';
        4: Result := 'TokCount';
      end;
    REC_TPENDINGGFSPEC:
      case idx of
        0: Result := 'GenFuncIdx'; 1: Result := 'ConcreteKind';
        2: Result := 'ConcreteName'; 3: Result := 'SpecName';
      end;
    REC_TMETHODFIXUP:
      case idx of 0: Result := 'DataPos'; 1: Result := 'ProcIdx'; end;
  end;
end;

function BuiltinRecFieldKind(rec, idx: Integer): Integer;
begin
  Result := BRF_SCALAR8;
  case rec of
    REC_TTOKEN:
      if idx = 1 then Result := BRF_STRING;
    REC_TSTRENTRY:
      if idx = 0 then Result := BRF_STRING;
    REC_TSYMBOL:
      if idx = 0 then Result := BRF_STRING;
    REC_TPARAM:
      if idx = 0 then Result := BRF_STRING;
    REC_TPROC:
      if idx = 0 then Result := BRF_STRING
      else if idx = 4 then Result := BRF_RECORD_ARRAY;
    REC_TTEMPLATE:
      if (idx = 0) or (idx = 1) then Result := BRF_STRING;
    REC_TSPECIALIZATION:
      if (idx = 0) or (idx = 1) or (idx = 3) then Result := BRF_STRING;
    REC_TGENERICFUNC:
      if (idx = 0) or (idx = 1) then Result := BRF_STRING;
    REC_TPENDINGGFSPEC:
      if (idx = 2) or (idx = 3) then Result := BRF_STRING;
    REC_TMETHODFIXUP:
      Result := BRF_SCALAR4;
  end;
end;

function BuiltinRecFieldType(rec, idx: Integer): TTypeKind;
begin
  Result := tyInteger;
  if BuiltinRecFieldKind(rec, idx) = BRF_STRING then
  begin
    if PasDefineExists('PXX_MANAGED_STRING') then Result := tyAnsiString
    else Result := tyString;
    Exit;
  end;
  if BuiltinRecFieldKind(rec, idx) = BRF_RECORD_ARRAY then
  begin
    Result := tyRecord;
    Exit;
  end;
  case rec of
    REC_TTOKEN:
      if idx = 2 then Result := tyInt64;
    REC_TRAWTOKEN:
      if idx = 1 then Result := tyInt64;
    REC_TSYMBOL:
      if idx = 4 then Result := tyInt64
      else if (idx = 5) or (idx = 10) then Result := tyBoolean;
    REC_TPARAM:
      if (idx = 3) or (idx = 4) then Result := tyBoolean;
    REC_TPROC:
      if idx = 1 then Result := tyBoolean;
    REC_TGENERICFUNC:
      if idx = 2 then Result := tyBoolean;
  end;
end;

function BuiltinRecFieldRecId(rec, idx: Integer): Integer;
begin
  Result := REC_NONE;
  if (rec = REC_TPROC) and (idx = 4) then Result := REC_TPARAM;
end;

function BuiltinRecFieldArrayCount(rec, idx: Integer): Integer;
begin
  Result := 0;
  if (rec = REC_TPROC) and (idx = 4) then Result := 16;
end;

function BuiltinRecFieldSize(rec, idx: Integer): Integer;
begin
  Result := 8;
  case BuiltinRecFieldKind(rec, idx) of
    BRF_STRING:
      if PasDefineExists('PXX_MANAGED_STRING') then Result := TARGET_PTR_SIZE
      else Result := LOCAL_STR_CAP + 8;
    BRF_RECORD_ARRAY:
      Result := BuiltinRecFieldArrayCount(rec, idx) *
                RecSize(BuiltinRecFieldRecId(rec, idx));
    BRF_SCALAR4:
      Result := 4;
  end;
end;

function BuiltinRecFieldMatches(rec, idx: Integer; const field: AnsiString): Boolean;
begin
  if rec = REC_TMYCLASS then
    Result := ((idx = 0) and ((field = 'x') or (field = 'X'))) or
              ((idx = 1) and ((field = 'y') or (field = 'Y')))
  else
    Result := field = BuiltinRecFieldName(rec, idx);
end;

function RecSize(rec: Integer): Integer;
var i, cnt: Integer;
begin
  Result := 8;
  cnt := BuiltinRecFieldCount(rec);
  if cnt > 0 then
  begin
    Result := 0;
    for i := 0 to cnt - 1 do
      Result := Result + BuiltinRecFieldSize(rec, i);
  end
  else if rec >= REC_UCLASS_BASE then Result := UClsSize_[rec - REC_UCLASS_BASE];
end;

function RecFieldOffset(rec: Integer; const field: AnsiString): Integer;
var fi, i, cnt, off: Integer; field2: AnsiString;
begin
  Result := 0; fi := 0; field2 := field;
  cnt := BuiltinRecFieldCount(rec);
  if cnt > 0 then
  begin
    off := 0;
    for i := 0 to cnt - 1 do
    begin
      if BuiltinRecFieldMatches(rec, i, field) then
      begin
        Result := off;
        Exit;
      end;
      off := off + BuiltinRecFieldSize(rec, i);
    end;
  end
  else if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldOff_[fi];
  end;
end;

function RecFieldType(rec: Integer; const field: AnsiString): TTypeKind;
var fi, i, cnt: Integer; field2: AnsiString;
begin
  Result := tyInteger; fi := 0; field2 := field;
  cnt := BuiltinRecFieldCount(rec);
  if cnt > 0 then
  begin
    for i := 0 to cnt - 1 do
      if BuiltinRecFieldMatches(rec, i, field) then
      begin
        Result := BuiltinRecFieldType(rec, i);
        Exit;
      end;
  end
  else if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := IntToTypeKind(UFldTk[fi]);
  end;
end;

function RecFieldRecId(rec: Integer; const field: AnsiString): Integer;
var fi, i, cnt: Integer; field2: AnsiString;
begin
  Result := REC_NONE; fi := 0; field2 := field;
  cnt := BuiltinRecFieldCount(rec);
  if cnt > 0 then
  begin
    for i := 0 to cnt - 1 do
      if BuiltinRecFieldMatches(rec, i, field) then
      begin
        Result := BuiltinRecFieldRecId(rec, i);
        Exit;
      end;
  end
  else if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldRec_[fi];
  end;
end;

function RecFieldIsArray(rec: Integer; const field: AnsiString): Boolean;
var fi, i, cnt: Integer; field2: AnsiString;
begin
  Result := False;
  cnt := BuiltinRecFieldCount(rec);
  if cnt > 0 then
  begin
    for i := 0 to cnt - 1 do
      if BuiltinRecFieldMatches(rec, i, field) then
      begin
        Result := BuiltinRecFieldArrayCount(rec, i) > 0;
        Exit;
      end;
  end
  else if rec >= REC_UCLASS_BASE then
  begin
    field2 := field;
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldIsArray[fi];
  end;
end;

procedure BuiltinLayoutAssert(ok: Boolean; const msg: AnsiString);
begin
  if not ok then
  begin
    writeln('BuiltinLayoutAssert failed: ', msg);
    writeln('REC_TTOKEN size = ', RecSize(REC_TTOKEN));
    writeln('REC_TTOKEN Kind offset = ', RecFieldOffset(REC_TTOKEN, 'Kind'));
    writeln('REC_TTOKEN SVal offset = ', RecFieldOffset(REC_TTOKEN, 'SVal'));
    writeln('REC_TTOKEN IVal offset = ', RecFieldOffset(REC_TTOKEN, 'IVal'));
    writeln('REC_TTOKEN Line offset = ', RecFieldOffset(REC_TTOKEN, 'Line'));
    Error('built-in record layout validation failed: ' + msg);
  end;
end;

procedure CheckBuiltinRecSize(rec, expected: Integer; const name: AnsiString);
begin
  BuiltinLayoutAssert(RecSize(rec) = expected, name);
end;

procedure CheckBuiltinRecField(rec: Integer; const field: AnsiString; off: Integer;
  tk: TTypeKind; recId: Integer; isArray: Boolean);
var
  actOff, actRecId: Integer;
  actTk: TTypeKind;
  actIsArray: Boolean;
begin
  actOff := RecFieldOffset(rec, field);
  actTk := RecFieldType(rec, field);
  actRecId := RecFieldRecId(rec, field);
  actIsArray := RecFieldIsArray(rec, field);
  
  if actOff <> off then
    writeln('Field ', field, ' offset mismatch: expected ', off, ', got ', actOff);
  if actTk <> tk then
    writeln('Field ', field, ' type mismatch: expected ', Ord(tk), ', got ', Ord(actTk));
  if actRecId <> recId then
    writeln('Field ', field, ' recId mismatch: expected ', recId, ', got ', actRecId);
  if actIsArray <> isArray then
    writeln('Field ', field, ' isArray mismatch: expected ', isArray, ', got ', actIsArray);

  BuiltinLayoutAssert(actOff = off, field);
  BuiltinLayoutAssert(actTk = tk, field);
  BuiltinLayoutAssert(actRecId = recId, field);
  BuiltinLayoutAssert(actIsArray = isArray, field);
end;

procedure ValidateBuiltinRecordLayout;
begin
  if PasDefineExists('PXX_MANAGED_STRING') then Exit;

  CheckBuiltinRecSize(REC_TTOKEN, 288, 'TToken');
  CheckBuiltinRecField(REC_TTOKEN, 'Kind', 0, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TTOKEN, 'SVal', 8, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TTOKEN, 'IVal', 272, tyInt64, REC_NONE, False);
  CheckBuiltinRecField(REC_TTOKEN, 'Line', 280, tyInteger, REC_NONE, False);

  CheckBuiltinRecSize(REC_TSTRENTRY, 280, 'TStrEntry');
  CheckBuiltinRecField(REC_TSTRENTRY, 'Text', 0, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TSTRENTRY, 'Offset', 264, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TSTRENTRY, 'Len', 272, tyInteger, REC_NONE, False);

  CheckBuiltinRecSize(REC_TFIXUP, 16, 'TFixup');
  CheckBuiltinRecField(REC_TFIXUP, 'CodePos', 0, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TFIXUP, 'DataOff', 8, tyInteger, REC_NONE, False);

  CheckBuiltinRecSize(REC_TGLOBFIX, 16, 'TGlobFix');
  CheckBuiltinRecField(REC_TGLOBFIX, 'CodePos', 0, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TGLOBFIX, 'BSSoff', 8, tyInteger, REC_NONE, False);

  CheckBuiltinRecSize(REC_TCALLFIX, 16, 'TCallFix');
  CheckBuiltinRecField(REC_TCALLFIX, 'CodePos', 0, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TCALLFIX, 'ProcIdx', 8, tyInteger, REC_NONE, False);

  CheckBuiltinRecSize(REC_TSYMBOL, 360, 'TSymbol');
  CheckBuiltinRecField(REC_TSYMBOL, 'Name', 0, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'TypeKind', 264, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'Kind', 272, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'Offset', 280, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'ConstVal', 288, tyInt64, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'IsArray', 296, tyBoolean, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'ArrLen', 304, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'ElemType', 312, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'RecName', 320, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'ElemRecName', 328, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'IsRef', 336, tyBoolean, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'PtrElemTk', 344, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TSYMBOL, 'PtrElemRec', 352, tyInteger, REC_NONE, False);

  CheckBuiltinRecSize(REC_TPARAM, 296, 'TParam');
  CheckBuiltinRecField(REC_TPARAM, 'Name', 0, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TPARAM, 'TypeKind', 264, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPARAM, 'SymIdx', 272, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPARAM, 'IsRef', 280, tyBoolean, REC_NONE, False);
  CheckBuiltinRecField(REC_TPARAM, 'IsArray', 288, tyBoolean, REC_NONE, False);

  CheckBuiltinRecSize(REC_TPROC, 5056, 'TProc');
  CheckBuiltinRecField(REC_TPROC, 'Name', 0, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TPROC, 'IsFunc', 264, tyBoolean, REC_NONE, False);
  CheckBuiltinRecField(REC_TPROC, 'RetType', 272, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPROC, 'ParamCount', 280, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPROC, 'Params', 288, tyRecord, REC_TPARAM, True);
  CheckBuiltinRecField(REC_TPROC, 'BodyAddr', 5024, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPROC, 'FramePatch', 5032, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPROC, 'RetSymIdx', 5040, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPROC, 'ScopeBase', 5048, tyInteger, REC_NONE, False);

  CheckBuiltinRecSize(REC_TRAWTOKEN, 40, 'TRawToken');
  CheckBuiltinRecField(REC_TRAWTOKEN, 'Kind', 0, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TRAWTOKEN, 'IVal', 8, tyInt64, REC_NONE, False);
  CheckBuiltinRecField(REC_TRAWTOKEN, 'Line', 16, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TRAWTOKEN, 'SOffset', 24, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TRAWTOKEN, 'SLen', 32, tyInteger, REC_NONE, False);

  CheckBuiltinRecSize(REC_TMYCLASS, 16, 'TMyClass');
  CheckBuiltinRecField(REC_TMYCLASS, 'x', 0, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TMYCLASS, 'y', 8, tyInteger, REC_NONE, False);

  CheckBuiltinRecSize(REC_TTEMPLATE, 544, 'TTemplate');
  CheckBuiltinRecField(REC_TTEMPLATE, 'Name', 0, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TTEMPLATE, 'Param', 264, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TTEMPLATE, 'TokStart', 528, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TTEMPLATE, 'TokCount', 536, tyInteger, REC_NONE, False);

  CheckBuiltinRecSize(REC_TSPECIALIZATION, 800, 'TSpecialization');
  CheckBuiltinRecField(REC_TSPECIALIZATION, 'Name', 0, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TSPECIALIZATION, 'TemplateName', 264, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TSPECIALIZATION, 'ConcreteType', 528, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TSPECIALIZATION, 'ConcreteName', 536, tyString, REC_NONE, False);

  CheckBuiltinRecSize(REC_TGENERICFUNC, 552, 'TGenericFunc');
  CheckBuiltinRecField(REC_TGENERICFUNC, 'Name', 0, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TGENERICFUNC, 'Param', 264, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TGENERICFUNC, 'IsFunc', 528, tyBoolean, REC_NONE, False);
  CheckBuiltinRecField(REC_TGENERICFUNC, 'TokStart', 536, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TGENERICFUNC, 'TokCount', 544, tyInteger, REC_NONE, False);

  CheckBuiltinRecSize(REC_TPENDINGGFSPEC, 544, 'TPendingGFSpec');
  CheckBuiltinRecField(REC_TPENDINGGFSPEC, 'GenFuncIdx', 0, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPENDINGGFSPEC, 'ConcreteKind', 8, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPENDINGGFSPEC, 'ConcreteName', 16, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TPENDINGGFSPEC, 'SpecName', 280, tyString, REC_NONE, False);

  CheckBuiltinRecSize(REC_TMETHODFIXUP, 8, 'TMethodFixup');
  CheckBuiltinRecField(REC_TMETHODFIXUP, 'DataPos', 0, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TMETHODFIXUP, 'ProcIdx', 4, tyInteger, REC_NONE, False);
end;

function RecFieldDynDepth(rec: Integer; const field: AnsiString): Integer;
{ Dynamic-array nesting of a class/record field: 0 if the field is not a
  dynamic array, else 1 for `array of T`, 2 for `array of array of T`, ... }
var fi: Integer; field2: AnsiString;
begin
  Result := 0;
  if rec >= REC_UCLASS_BASE then
  begin
    field2 := field;
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldDynDepth[fi];
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

function RecordHasManagedFields(recId: Integer): Boolean;
{ Class/object references are deliberately unmanaged. Only recurse through
  fixed-size user records and compiler-managed value fields. }
var ci, base, cnt, i: Integer;
begin
  Result := False;
  if recId < REC_UCLASS_BASE then Exit;
  ci := recId - REC_UCLASS_BASE;
  if not UClsIsRecord[ci] then Exit;
  base := UClsFBase[ci];
  cnt := UClsFCount[ci];
  for i := 0 to cnt - 1 do
  begin
    if UFldTk[base + i] = Ord(tyAnsiString) then
      begin Result := True; Exit; end;
    { A dynamic-array field holds a heap handle that must be zero-initialised,
      retained on record copy, and released on finalization. }
    if UFldIsArray[base + i] and (UFldArrLen[base + i] = -1) then
      begin Result := True; Exit; end;
    if (UFldTk[base + i] = Ord(tyRecord)) and
       RecordHasManagedFields(UFldRec_[base + i]) then
      begin Result := True; Exit; end;
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
    22: Result := 16; { tyVariant — 8-byte tag + 8-byte payload }
    23: Result := TARGET_PTR_SIZE; { tyAnsiString }
    24: Result := 0;  { tyAuto }
  end;
end;

function SymNeedsZeroing(i: Integer; var zeroBytes: Integer): Boolean;
begin
  Result := False;
  zeroBytes := 0;
  if Syms[i].IsArray and (Syms[i].ArrLen = -1) then
  begin
    zeroBytes := TARGET_PTR_SIZE;
    Result := True;
  end
  else if Syms[i].TypeKind = tyAnsiString then
  begin
    if Syms[i].IsArray then
      zeroBytes := Syms[i].ArrLen * TARGET_PTR_SIZE
    else
      zeroBytes := TARGET_PTR_SIZE;
    Result := True;
  end
  else if Syms[i].TypeKind = tyVariant then
  begin
    zeroBytes := TypeSize(tyVariant);
    Result := True;
  end
  else if SymIsComInterface(i) then
  begin
    { COM/ARC interface value: a fat pointer that the ARC path releases on
      overwrite and at scope exit, so it must start nil (all-zero) — otherwise the
      first release dispatches through a garbage IMT. }
    zeroBytes := RecSize(Syms[i].RecName);
    Result := True;
  end
  else if (Syms[i].TypeKind = tyRecord) and not Syms[i].IsArray and
          RecordHasManagedFields(Syms[i].RecName) then
  begin
    zeroBytes := RecSize(Syms[i].RecName);
    Result := True;
  end
  else if (Syms[i].TypeKind = tyRecord) and Syms[i].IsArray and
          RecordHasManagedFields(Syms[i].ElemRecName) then
  begin
    zeroBytes := Syms[i].ArrLen * RecSize(Syms[i].ElemRecName);
    Result := True;
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

function TypeIsAggregate(tk: TTypeKind): Boolean;
begin
  Result := (tk = tyRecord) or (tk = tySet);
end;

function TypeIsFrozenString(tk: TTypeKind): Boolean;
{ True for the inline (non-managed) frozen string kinds: the legacy overloaded
  tyString, the classic byte-prefixed tyShortString, and the word-prefixed sized
  tyFixedString. Widen existing `= tyString` codegen checks to this predicate so
  the new kinds route through the frozen-string path without 250 new arms. }
begin
  Result := (tk = tyString) or (tk = tyShortString) or (tk = tyFixedString);
end;

function StrValTk(tk: TTypeKind): Integer;
{ Value (expression) kind of a symbol whose STORAGE kind is given. A frozen
  fixed/short string presents as a plain frozen tyString *value* — they are
  codegen-identical (same inline word-prefixed layout); only the slot SIZE
  differs, and that is carried by the storage kind + SymStrCap. Normalising the
  node value-kind here keeps every existing `= tyString` value check (write,
  concat, compare, ...) working without widening ~150 sites. Returns an Ord. }
begin
  if (tk = tyFixedString) or (tk = tyShortString) then
    Result := Ord(tyString)
  else
    Result := Ord(tk);
end;

function FrozenStrSlotSize(tk: TTypeKind; cap: Integer): Integer;
{ Byte size of an inline frozen fixed-string slot.
  tyFixedString = 8-byte NativeInt length word + cap chars (matches today's
  frozen tyString layout, so it reuses the existing tyString codegen unchanged).
  tyShortString = 1 length byte + cap chars (classic FPC shortstring, cap<=255). }
begin
  if cap <= 0 then cap := DEFAULT_STR_CAP;
  if tk = tyShortString then
    Result := cap + 1
  else
    Result := cap + 8;
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
    17,      { tyPointer }
    23:      { tyAnsiString }
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

function IsBlockVisible(symBlockId, curBlockId: Integer): Boolean;
var b: Integer;
begin
  if not EnableLazyVar then
  begin
    Result := True;
    Exit;
  end;
  b := curBlockId;
  while b <> -1 do
  begin
    if b = symBlockId then
    begin
      Result := True;
      Exit;
    end;
    if b = 0 then Break;
    b := BlockParent[b];
  end;
  Result := False;
end;

function FindSym(const name: AnsiString): Integer;
var i: Integer; lo: AnsiString;
begin
  lo := name;
  { Exact-case match first, innermost scope out (preserves shadowing). }
  for i := SymCount-1 downto 0 do
    if StrEqual(Syms[i].Name, lo) and IsBlockVisible(SymBlockId[i], CurBlockId) then
    begin
      if DebugTrace then writeln('FindSym: ', lo, ' -> ', i);
      Result := i;
      Exit;
    end;
  { Case-insensitive fallback for case-insensitive symbols only. }
  for i := SymCount-1 downto 0 do
    if (not SymCaseSensitive[i]) and CaseEqual(Syms[i].Name, lo) and
       IsBlockVisible(SymBlockId[i], CurBlockId) then
    begin
      if DebugTrace then writeln('FindSym: ', lo, ' -> ', i, ' (ci)');
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

function FindCompiledUnit(const name: AnsiString): Integer;
var i, j, unitIdx: Integer; lo: AnsiString;
begin
  lo := name;
  for j := 1 to Length(lo) do
    if lo[j] in ['A'..'Z'] then
      lo[j] := Chr(Ord(lo[j]) + 32);
  for i := 0 to CompiledUnitCount - 1 do
  begin
    unitIdx := CompiledUnits[i];
    if Strs[unitIdx].Text = lo then
    begin
      Result := unitIdx;
      Exit;
    end;
  end;
  Result := -1;
end;

function FindSymInUnit(const name: AnsiString; unitIdx: Integer): Integer;
var i: Integer;
begin
  for i := SymCount - 1 downto 0 do
    if (SymUnitIdx[i] = unitIdx) and StrEqual(Syms[i].Name, name) then
    begin
      Result := i;
      Exit;
    end;
  for i := SymCount - 1 downto 0 do
    if (SymUnitIdx[i] = unitIdx) and (not SymCaseSensitive[i]) and
       CaseEqual(Syms[i].Name, name) then
    begin
      Result := i;
      Exit;
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
  SymDynDepth[SymCount] := 0;
  SymGenSlot[SymCount] := -1;
  SymProcSig[SymCount] := -1;
  SymSetEnumId[SymCount] := -1;
  SymSetElemTk[SymCount] := 0;
  SymStrCap[SymCount] := 0;
  if TypeIsFrozenString(tk) and (tk <> tyString) then
    SymStrCap[SymCount] := LastTypeStrCap;
  SymRTTIOff[SymCount] := -1;
  SymIsHiddenArgTemp[SymCount] := False;
  SymBlockId[SymCount] := CurBlockId;
  Syms[SymCount].ElemType := tyInteger;
  if tk = tyAnsiString then
    Syms[SymCount].ElemType := tyChar;
  Syms[SymCount].RecName  := LastTypeRecId;
  Syms[SymCount].IsRef    := False;
  SymCaseSensitive[SymCount] := CaseSensitiveMode;
  SymUnitIdx[SymCount] := CurrentUnitIdx;
  Syms[SymCount].PtrElemTk := tyUnknown;
  Syms[SymCount].PtrElemRec := REC_NONE;
  if tk = tyPointer then
  begin
    Syms[SymCount].PtrElemTk := LastTypePointerElemTk;
    Syms[SymCount].PtrElemRec := LastTypePointerElemRec;
  end;

  if tk = tyAuto then
  begin
    Syms[SymCount].Offset := 0;
    if CurProc < 0 then
      Syms[SymCount].Kind := skGlobal
    else
      Syms[SymCount].Kind := skLocal;
  end
  else
  begin
    sz := TypeSize(tk);
    if tk = tyString then
    begin
      if CurProc < 0 then sz := STRING_CAP + 8
      else sz := LOCAL_STR_CAP + 8;
    end
    else if (tk = tyFixedString) or (tk = tyShortString) then
      sz := FrozenStrSlotSize(tk, SymStrCap[SymCount])
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
  end;
  Result := SymCount; Inc(SymCount);
end;

function ParamSize(idx: Integer): Integer;
begin
  if Syms[idx].IsRef or Syms[idx].IsArray or (Syms[idx].TypeKind = tyString) or
     (Syms[idx].TypeKind = tyRecord) or (Syms[idx].TypeKind = tySet) or
     (Syms[idx].TypeKind = tyClass) or (Syms[idx].TypeKind = tyPointer) then
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
  SymDynDepth[SymCount] := 0;
  SymGenSlot[SymCount] := -1;
  SymProcSig[SymCount] := -1;
  SymSetEnumId[SymCount] := -1;
  SymSetElemTk[SymCount] := 0;
  SymStrCap[SymCount] := 0;
  if TypeIsFrozenString(tk) and (tk <> tyString) then
    SymStrCap[SymCount] := LastTypeStrCap;
  SymRTTIOff[SymCount] := -1;
  Syms[SymCount].ElemType := tk;
  Syms[SymCount].RecName  := LastTypeRecId;
  Syms[SymCount].IsRef    := isRef;
  Syms[SymCount].Kind     := skParam;
  SymCaseSensitive[SymCount] := CaseSensitiveMode;
  SymUnitIdx[SymCount] := CurrentUnitIdx;
  Syms[SymCount].PtrElemTk := tyUnknown;
  Syms[SymCount].PtrElemRec := REC_NONE;
  if tk = tyPointer then
  begin
    Syms[SymCount].PtrElemTk := LastTypePointerElemTk;
    Syms[SymCount].PtrElemRec := LastTypePointerElemRec;
  end;

  if isRef or isArray or (tk = tyString) or (tk = tyRecord) or (tk = tyVariant) or (tk = tySet) or (tk = tyClass) or (tk = tyPointer) then
    sz := TARGET_PTR_SIZE
  else
    sz := TypeSize(tk);

  if isRef or isArray or (tk = tyString) or (tk = tyRecord) or (tk = tyVariant) or (tk = tySet) or (tk = tyClass) or (tk = tyPointer) then
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
  else if (elemType = tyFixedString) or (elemType = tyShortString) then
    elemSize := FrozenStrSlotSize(elemType, LastTypeStrCap)
  else if elemType = tyRecord then elemSize := RecSize(LastTypeRecId)
  else elemSize := TypeSize(elemType);
  if (elemType = tyString) or (elemType = tyFixedString) or (elemType = tyShortString) or (elemType = tyRecord) then
    align := TARGET_PTR_SIZE
  else
    align := TypeAlign(elemType);

  totalSize := (hi - lo + 1) * elemSize;
  Syms[SymCount].Name     := name;
  Syms[SymCount].TypeKind := elemType;
  Syms[SymCount].ConstVal := lo;   { lo bound stored in ConstVal }
  Syms[SymCount].IsArray  := True;
  Syms[SymCount].ArrLen   := hi - lo + 1;
  SymDynDepth[SymCount] := 0;
  SymArrNDims[SymCount] := 0;
  SymProcSig[SymCount] := -1;
  SymRTTIOff[SymCount] := -1;
  { Match AllocVar: reset recycled parallel-array fields (see AllocDynArray). }
  SymGenSlot[SymCount] := -1;
  SymSetEnumId[SymCount] := -1;
  SymSetElemTk[SymCount] := 0;
  SymStrCap[SymCount] := 0;
  if (elemType = tyFixedString) or (elemType = tyShortString) then
    SymStrCap[SymCount] := LastTypeStrCap;
  SymIsHiddenArgTemp[SymCount] := False;
  SymBlockId[SymCount] := CurBlockId;
  Syms[SymCount].ElemType := elemType;
  Syms[SymCount].ElemRecName := LastTypeRecId;
  Syms[SymCount].IsRef    := False;
  Syms[SymCount].PtrElemTk := tyUnknown;
  Syms[SymCount].PtrElemRec := REC_NONE;
  SymCaseSensitive[SymCount] := CaseSensitiveMode;
  SymUnitIdx[SymCount] := CurrentUnitIdx;
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

function AllocDynArray(const name: AnsiString; elemType: TTypeKind; depth: Integer): Integer;
{ Dynamic array (array of T): a pointer-sized slot holding a heap data pointer.
  ArrLen = -1 marks the symbol as dynamic (static arrays always have ArrLen >= 1).
  depth is the nesting count: 1 for `array of T`, 2 for `array of array of T`...
  elemType is the BASE element type at the deepest level. }
begin
  if SymCount >= MAX_SYMS then Error('too many symbols');
  Syms[SymCount].Name        := name;
  Syms[SymCount].TypeKind    := elemType;
  Syms[SymCount].ConstVal    := 0;            { lower bound: dynamic arrays are 0-based }
  Syms[SymCount].IsArray     := True;
  Syms[SymCount].ArrLen      := -1;           { -1 = dynamic }
  SymDynDepth[SymCount] := depth;
  SymProcSig[SymCount] := -1;
  SymRTTIOff[SymCount] := -1;
  { Reset the same recycled parallel-array fields AllocVar does — symbol slots
    are reused after a proc body restores SymCount, so a stale SymBlockId here
    would make a dyn-array global declared after a method (whose for-in/locals
    occupied this slot) invisible to FindSym ('undefined variable'). }
  SymGenSlot[SymCount] := -1;
  SymSetEnumId[SymCount] := -1;
  SymSetElemTk[SymCount] := 0;
  SymStrCap[SymCount] := 0;
  if (elemType = tyFixedString) or (elemType = tyShortString) then
    SymStrCap[SymCount] := LastTypeStrCap;
  SymIsHiddenArgTemp[SymCount] := False;
  SymBlockId[SymCount] := CurBlockId;
  Syms[SymCount].ElemType    := elemType;
  Syms[SymCount].ElemRecName := LastTypeRecId;
  Syms[SymCount].IsRef       := False;
  Syms[SymCount].PtrElemTk := tyUnknown;
  Syms[SymCount].PtrElemRec := REC_NONE;
  SymCaseSensitive[SymCount] := CaseSensitiveMode;
  SymUnitIdx[SymCount] := CurrentUnitIdx;
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
  SymCaseSensitive[SymCount] := CaseSensitiveMode;
  SymUnitIdx[SymCount] := CurrentUnitIdx;
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

procedure EmitAnsiStrCmpReg(eq: Boolean; lhsTk, rhsTk: TTypeKind);
var pLhsNil, pLhsDone, pRhsNil, pRhsDone, skipJmp, okJmp, okJmp2: Integer;
begin
  { --- Load LHS (rax) -> rsi (chars), rdx (len) --- }
  if lhsTk = tyAnsiString then
  begin
    { test rax, rax }
    EmitB($48); EmitB($85); EmitB($C0);
    { jz lhs_nil }
    EmitB($74); pLhsNil := CodeLen; EmitB(0);
    
    EmitB($48); EmitB($89); EmitB($C6);             { mov rsi, rax }
    EmitB($48); EmitB($8B); EmitB($50); EmitB($F8); { mov rdx, [rax-8] }
    { jmp lhs_done }
    EmitB($EB); pLhsDone := CodeLen; EmitB(0);
    
    { lhs_nil: }
    Code[pLhsNil] := Byte(CodeLen - (pLhsNil + 1));
    EmitB($31); EmitB($F6);                         { xor esi, esi }
    EmitB($31); EmitB($D2);                         { xor edx, edx }
    
    { lhs_done: }
    Code[pLhsDone] := Byte(CodeLen - (pLhsDone + 1));
  end
  else
  begin
    EmitB($48); EmitB($8D); EmitB($70); EmitB($08); { lea rsi, [rax+8] }
    EmitB($48); EmitB($8B); EmitB($10);             { mov rdx, [rax] }
  end;

  { --- Load RHS (rcx) -> rdi (chars), r8 (len) --- }
  if rhsTk = tyAnsiString then
  begin
    { test rcx, rcx }
    EmitB($48); EmitB($85); EmitB($C9);
    { jz rhs_nil }
    EmitB($74); pRhsNil := CodeLen; EmitB(0);
    
    EmitB($48); EmitB($89); EmitB($CF);             { mov rdi, rcx }
    EmitB($4C); EmitB($8B); EmitB($41); EmitB($F8); { mov r8, [rcx-8] }
    { jmp rhs_done }
    EmitB($EB); pRhsDone := CodeLen; EmitB(0);
    
    { rhs_nil: }
    Code[pRhsNil] := Byte(CodeLen - (pRhsNil + 1));
    EmitB($31); EmitB($FF);                         { xor edi, edi }
    EmitB($45); EmitB($31); EmitB($C0);             { xor r8d, r8d }
    
    { rhs_done: }
    Code[pRhsDone] := Byte(CodeLen - (pRhsDone + 1));
  end
  else
  begin
    EmitB($48); EmitB($8D); EmitB($79); EmitB($08); { lea rdi, [rcx+8] }
    EmitB($4C); EmitB($8B); EmitB($01);             { mov r8, [rcx] }
  end;

  { --- Comparison --- }
  { cmp rdx, r8 }
  EmitB($4C); EmitB($39); EmitB($C2);
  { jne not_equal }
  EmitB($0F); EmitB($85); skipJmp := CodeLen; EmitI32(0);

  { Lengths are equal. If length is 0, they are equal! }
  { test rdx, rdx }
  EmitB($48); EmitB($85); EmitB($D2);
  { jz equal }
  EmitB($0F); EmitB($84); okJmp := CodeLen; EmitI32(0);

  { Compare contents:
    rcx = rdx (length for repe) }
  EmitB($48); EmitB($89); EmitB($D1);             { mov rcx, rdx }
  EmitB($F3); EmitB($A6);                          { repe cmpsb }
  { je equal }
  EmitB($0F); EmitB($84); okJmp2 := CodeLen; EmitI32(0);

  { not_equal: }
  Patch32(skipJmp, CodeLen - (skipJmp + 4));
  if eq then MovRaxImm(0) else MovRaxImm(1);
  { jmp end }
  EmitB($E9); skipJmp := CodeLen; EmitI32(0);

  { equal: }
  Patch32(okJmp, CodeLen - (okJmp + 4));
  Patch32(okJmp2, CodeLen - (okJmp2 + 4));
  if eq then MovRaxImm(1) else MovRaxImm(0);

  { end: }
  Patch32(skipJmp, CodeLen - (skipJmp + 4));
end;

{ ===== Array element access ===== }

procedure EmitBumpAlloc;
{ On entry: rax = byte count requested. On exit: rax = allocated block base.
  Rounds size up to 8, bumps BSS_HEAP_PTR, grows the break via brk if needed.
  Shared by GetMem/class-new and dynamic-array SetLength (both
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
  { Exact-case match first — always, and the only path for case-sensitive
    symbols (C imports, or Pascal in case-sensitive mode). }
  for i := 0 to ProcCount-1 do
    if Procs[i].Name = lo then begin Result := i; Exit; end;
  { Case-insensitive fallback for case-insensitive symbols only (default Pascal).
    First match wins; ambiguity refinement (warn) is future work. }
  for i := 0 to ProcCount-1 do
    if (not ProcCaseSensitive[i]) and CaseEqual(Procs[i].Name, lo) then
    begin Result := i; Exit; end;
  Result := -1;
end;

function FindProcInUnit(const name: AnsiString; unitIdx: Integer): Integer;
var i: Integer;
begin
  for i := 0 to ProcCount - 1 do
    if (ProcUnitIdx[i] = unitIdx) and (Procs[i].Name = name) then
    begin
      Result := i;
      Exit;
    end;
  for i := 0 to ProcCount - 1 do
    if (ProcUnitIdx[i] = unitIdx) and (not ProcCaseSensitive[i]) and
       CaseEqual(Procs[i].Name, name) then
    begin
      Result := i;
      Exit;
    end;
  Result := -1;
end;

function HasNonOverloadProc(const name: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 0 to ProcCount-1 do
    if (ProcUnitIdx[i] = CurrentUnitIdx) and (Procs[i].Name = name) and
       not ProcOverloadDirective[i] then
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
    if (ProcUnitIdx[i] = CurrentUnitIdx) and (Procs[i].Name = name) then
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
  if (pType = tyVariant) or (aType = tyVariant) then
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
  if (pType = tyAnsiString) and (aType = tyChar) then
  begin
    Result := True;
    Exit;
  end;
  if (pType = tyAnsiString) and (aType = tyString) then
  begin
    Result := True;
    Exit;
  end;
  if (pType = tyString) and (aType = tyAnsiString) then
  begin
    Result := True;
    Exit;
  end;
  { A string argument marshals to a const char* (Pointer) parameter: IR lowering
    skips the inline length prefix (+8), so a C binding can pass a Pascal string
    without an explicit PChar() cast. Compatible-match only, after exact match. }
  if (pType = tyPointer) and (aType = tyString) then
  begin
    Result := True;
    Exit;
  end;
  { A managed string (tyAnsiString) likewise marshals to a const char* (Pointer)
    parameter. Its value is already a char pointer (no inline +8 prefix), so the
    IR side passes it as-is. Needed since scalar `string` resolves to tyAnsiString
    in managed mode (the default). }
  if (pType = tyPointer) and (aType = tyAnsiString) then
  begin
    Result := True;
    Exit;
  end;
  { A float formal accepts any float actual (widen/narrow at the ABI boundary,
    e.g. a Double or float-literal into a Single) or an ordinal actual (int ->
    float). Compatible-match only (after the exact-match phase), so a true
    same-width float arg still wins. Requires the internal-call Single ABI
    (feature-single-first-class) — without it a Single param would silently
    receive 0.0, which is why this clause depends on the ABI fix. }
  if TypeIsFloat(pType) and (TypeIsFloat(aType) or TypeIsOrdinal(aType)) then
  begin
    Result := True;
    Exit;
  end;
  Result := False;
end;

function ProcParamIsInterface(procIdx, j: Integer): Boolean;
{ True iff parameter j of proc procIdx is a CORBA interface type (a fat-pointer
  record), so overload matching can accept a class argument that implements it.
  The param's rec id comes from ProcParamRecId, not the param symbol: param sym
  slots are reused across procs, so Syms[SymIdx].RecName is unreliable here. }
var rec: Integer;
begin
  Result := False;
  if (j < 0) or (j >= Procs[procIdx].ParamCount) then Exit;
  if Procs[procIdx].Params[j].TypeKind <> tyRecord then Exit;
  rec := ProcParamRecId[procIdx * 16 + j];
  Result := (rec >= REC_UCLASS_BASE) and UClsIsInterface[rec - REC_UCLASS_BASE];
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

  { Phase 1b: Try exact match with return-lifting }
  for i := 0 to ProcCount-1 do
  begin
    if Procs[i].Name = name then
    begin
      if (Procs[i].ParamCount > nArgs) and (ProcParamPtrDepth[i * 16 + nArgs] = 2) then
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

  { Phase 2b: Try compatible match with return-lifting }
  for i := 0 to ProcCount-1 do
  begin
    if Procs[i].Name = name then
    begin
      if (Procs[i].ParamCount > nArgs) and (ProcParamPtrDepth[i * 16 + nArgs] = 2) then
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

  { Phase 2c: a class argument given to an interface parameter (the implicit
    class->interface coercion). Only fires when the param is a CORBA interface,
    so existing record/class overloads are unaffected. }
  for i := 0 to ProcCount-1 do
  begin
    if (Procs[i].Name = name) and (Procs[i].ParamCount = nArgs) then
    begin
      match := True;
      for j := 0 to nArgs-1 do
      begin
        if not (TypesCompatible(Procs[i].Params[j].TypeKind, argTypes[j]) or
                (ProcParamIsInterface(i, j) and (argTypes[j] = tyClass))) then
          match := False;
      end;
      if match then
      begin
        Result := i;
        Exit;
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

function MatchProcCallInUnit(const name: AnsiString; unitIdx, nArgs: Integer;
  const argTypes: array of TTypeKind): Integer;
var i, j: Integer; match: Boolean;
begin
  for i := 0 to ProcCount - 1 do
    if (ProcUnitIdx[i] = unitIdx) and
       ((Procs[i].Name = name) or
        ((not ProcCaseSensitive[i]) and CaseEqual(Procs[i].Name, name))) and
       (Procs[i].ParamCount = nArgs) then
    begin
      match := True;
      for j := 0 to nArgs - 1 do
        if Procs[i].Params[j].TypeKind <> argTypes[j] then match := False;
      if match then
      begin
        Result := i;
        Exit;
      end;
    end;

  { Phase 1b: Try exact match with return-lifting }
  for i := 0 to ProcCount - 1 do
    if (ProcUnitIdx[i] = unitIdx) and
       ((Procs[i].Name = name) or
        ((not ProcCaseSensitive[i]) and CaseEqual(Procs[i].Name, name))) and
       (Procs[i].ParamCount > nArgs) and
       (ProcParamPtrDepth[i * 16 + nArgs] = 2) then
    begin
      match := True;
      for j := 0 to nArgs - 1 do
        if Procs[i].Params[j].TypeKind <> argTypes[j] then match := False;
      if match then
      begin
        Result := i;
        Exit;
      end;
    end;

  for i := 0 to ProcCount - 1 do
    if (ProcUnitIdx[i] = unitIdx) and
       ((Procs[i].Name = name) or
        ((not ProcCaseSensitive[i]) and CaseEqual(Procs[i].Name, name))) and
       (Procs[i].ParamCount = nArgs) then
    begin
      match := True;
      for j := 0 to nArgs - 1 do
        if not TypesCompatible(Procs[i].Params[j].TypeKind, argTypes[j]) then match := False;
      if match then
      begin
        Result := i;
        Exit;
      end;
    end;

  { Phase 2b: Try compatible match with return-lifting }
  for i := 0 to ProcCount - 1 do
    if (ProcUnitIdx[i] = unitIdx) and
       ((Procs[i].Name = name) or
        ((not ProcCaseSensitive[i]) and CaseEqual(Procs[i].Name, name))) and
       (Procs[i].ParamCount > nArgs) and
       (ProcParamPtrDepth[i * 16 + nArgs] = 2) then
    begin
      match := True;
      for j := 0 to nArgs - 1 do
        if not TypesCompatible(Procs[i].Params[j].TypeKind, argTypes[j]) then match := False;
      if match then
      begin
        Result := i;
        Exit;
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
  ProcCaseSensitive[ProcCount] := CaseSensitiveMode;
  ProcOverloadDirective[ProcCount] := False;
  ProcLibrary[ProcCount]      := -1;
  ProcUnitIdx[ProcCount]      := CurrentUnitIdx;
  ProcRetRecId[ProcCount]     := REC_NONE;
  ProcAggregateDestSym[ProcCount] := -1;
  ProcRetIsDynArray[ProcCount] := False;
  ProcRetElemTk[ProcCount]     := tyUnknown;
  ProcRetElemRec[ProcCount]    := REC_NONE;
  ProcRetPtrElemTk[ProcCount]  := Ord(tyUnknown);
  ProcRetPtrElemRec[ProcCount] := REC_NONE;
  for i := 0 to 15 do
  begin
    ProcParamPtrDepth[ProcCount * 16 + i] := 0;
    ProcParamIsConst[ProcCount * 16 + i] := False;
  end;
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

procedure EmitWriteFloatNat;
{ Double in xmm0. Python-style natural decimal: [-]int.frac with trailing zeros
  trimmed but at least one fractional digit (so 5.0 prints "5.0"). Integer part
  is printed via the integer writer (no scaling overflow); the fractional part is
  (value - trunc)*1e15 rounded to an Int64, emitted most-significant-first and
  stopped once the remainder reaches zero. frac kept in r13 across the syscalls. }
const FRAC = 15;
var jncOff, jbCarry, i, k, nJz: Integer;
    endJz: array[0..FRAC-1] of Integer;
    divisor, scale: Int64;
begin
  scale := 1;
  for k := 1 to FRAC do scale := scale * 10;                   { 10^15 }

  EmitB($41); EmitB($55);                                       { push r13 }

  { sign: strip and print '-' }
  EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0);   { movq rax, xmm0 }
  EmitB($48); EmitB($0F); EmitB($BA); EmitB($E0); EmitB($3F);   { bt rax, 63 }
  EmitB($73); jncOff := CodeLen; EmitB(0);                      { jnc .pos }
  EmitB($48); EmitB($0F); EmitB($BA); EmitB($F0); EmitB($3F);   { btr rax, 63 }
  EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C0);   { movq xmm0, rax }
  MovRaxImm(Ord('-')); EmitwriteChar;
  Code[jncOff] := Byte(CodeLen - (jncOff + 1));                 { .pos: }

  { intpart = trunc(value) -> rax ; frac double = value - intpart }
  EmitB($F2); EmitB($48); EmitB($0F); EmitB($2C); EmitB($C0);   { cvttsd2si rax, xmm0 }
  EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($D8);   { cvtsi2sd xmm3, rax }
  EmitB($F2); EmitB($0F); EmitB($5C); EmitB($C3);               { subsd xmm0, xmm3 }
  { frac *= scale ; round -> rbx }
  EmitB($48); EmitB($B9); EmitI64(scale);                       { mov rcx, scale }
  EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($C9);   { cvtsi2sd xmm1, rcx }
  EmitB($F2); EmitB($0F); EmitB($59); EmitB($C1);               { mulsd xmm0, xmm1 }
  EmitB($F2); EmitB($48); EmitB($0F); EmitB($2D); EmitB($D8);   { cvtsd2si rbx, xmm0 }
  { carry: if rbx >= scale (frac rounded up to 1.0): rbx -= scale; intpart++ }
  EmitB($49); EmitB($B8); EmitI64(scale);                       { mov r8, scale }
  EmitB($4C); EmitB($39); EmitB($C3);                           { cmp rbx, r8 }
  EmitB($72); jbCarry := CodeLen; EmitB(0);                     { jb .nocarry }
  EmitB($4C); EmitB($29); EmitB($C3);                           { sub rbx, r8 }
  EmitB($48); EmitB($FF); EmitB($C0);                           { inc rax }
  Code[jbCarry] := Byte(CodeLen - (jbCarry + 1));               { .nocarry: }
  EmitB($49); EmitB($89); EmitB($DD);                           { mov r13, rbx (frac) }

  { print intpart (non-negative) then '.' }
  EmitwriteUInt;
  MovRaxImm(Ord('.')); EmitwriteChar;

  { frac digits MSD-first, stop after the remainder hits 0 (>=1 digit always) }
  nJz := 0;
  for i := 0 to FRAC - 1 do
  begin
    divisor := 1;
    for k := 1 to (FRAC - 1 - i) do divisor := divisor * 10;     { 10^(FRAC-1-i) }
    EmitB($4C); EmitB($89); EmitB($E8);                          { mov rax, r13 }
    EmitB($48); EmitB($31); EmitB($D2);                          { xor rdx, rdx }
    EmitB($48); EmitB($B9); EmitI64(divisor);                    { mov rcx, divisor }
    EmitB($48); EmitB($F7); EmitB($F1);                          { div rcx -> rax=digit, rdx=rem }
    EmitB($49); EmitB($89); EmitB($D5);                          { mov r13, rdx (remainder) }
    EmitB($48); EmitB($83); EmitB($C0); EmitB($30);             { add rax, '0' }
    EmitwriteChar;
    if i < FRAC - 1 then
    begin
      EmitB($4D); EmitB($85); EmitB($ED);                        { test r13, r13 }
      EmitB($0F); EmitB($84); endJz[nJz] := CodeLen; EmitI32(0); { jz .end }
      Inc(nJz);
    end;
  end;

  { .end: }
  for k := 0 to nJz - 1 do
    Patch32(endJz[k], CodeLen - (endJz[k] + 4));
  EmitB($41); EmitB($5D);                                        { pop r13 }
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
{ Returns patch position for sub rsp/esp imm32 }
begin
  if TargetArch = TARGET_I386 then
  begin
    EmitB($55);                          { push ebp }
    EmitB($89); EmitB($E5);              { mov ebp, esp }
    EmitB($81); EmitB($EC);              { sub esp, imm32 }
    Result := CodeLen; EmitI32(0);
    Exit;
  end;
  if TargetArch = TARGET_ARM32 then
  begin
    EmitI32($E92D4800);  { push {fp, lr} }
    EmitI32($E1A0B00D);  { mov fp, sp }
    { Frame size can exceed an ARM rotated-imm8, so load it from a literal
      into r9 (scratch, free at proc entry) and subtract. Patch the literal. }
    EmitI32($E59F9000);  { ldr r9, [pc]  (the literal below) }
    EmitI32($EA000000);  { b .+8         (skip the literal) }
    Result := CodeLen;
    EmitI32(0);          { frame-size literal (patched) }
    EmitI32($E04DD009);  { sub sp, sp, r9 }
    Exit;
  end;
  if TargetArch = TARGET_AARCH64 then
  begin
    EmitI32($A9BF7BFD);  { stp x29, x30, [sp, #-16]! }
    EmitI32($910003FD);  { mov x29, sp }
    Result := CodeLen;
    EmitI32($D10003FF);  { sub sp, sp, #0 }
    Exit;
  end;
  if TargetArch = TARGET_XTENSA then
  begin
    if XtensaABI = XTENSA_ABI_WINDOWED then
    begin
      xtensa_entry(reg_xtensa_sp, 32);
      { a15 is only a bootstrap frame base until params are spilled; the body
        frame pointer moves to a7, outside call8's outgoing window. The
        patchable addi lowers sp once to reserve locals + the constant-sp
        expression-stack region; sp then stays fixed for the whole body so the
        window spill area at [sp-16] never desyncs. }
      XtSpillDepth := 0;
      xtensa_mov(reg_xtensa_a15, reg_xtensa_sp);
      Result := CodeLen;
      xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 0);
    end
    else
    begin
      { Xtensa Call0 ABI prologue: push a0, a15 (save Return Address and Frame Pointer) }
      xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, -16);
      xtensa_s32i(reg_xtensa_a0, reg_xtensa_sp, 12);
      xtensa_s32i(reg_xtensa_a15, reg_xtensa_sp, 8);
      xtensa_mov(reg_xtensa_a15, reg_xtensa_sp);
      Result := CodeLen;
      xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 0);
    end;
    Exit;
  end;
  if TargetArch = TARGET_RISCV32 then
  begin
    { RISC-V prologue: push ra, s0 (save Return Address and Frame Pointer) }
    rv32_addi(reg_sp, reg_sp, -16);
    rv32_sw(reg_ra, reg_sp, 12);
    rv32_sw(reg_s0, reg_sp, 8);
    rv32_addi(reg_s0, reg_sp, 0);
    Result := CodeLen;
    rv32_addi(reg_sp, reg_sp, 0);
    Exit;
  end;
  EmitB($55);
  EmitB($48); EmitB($89); EmitB($E5);
  EmitB($48); EmitB($81); EmitB($EC);
  Result := CodeLen; EmitI32(0);
end;

procedure PatchProcPrologue(patchPos, size: Integer);
var aligned, a64imm: Integer;
begin
  aligned := ((size + 15) div 16) * 16;
  { Windowed xtensa keeps sp constant and runs its expression/argument stack in
    a reserved region below the locals. Round the one-shot frame (locals +
    region) up to 256 and lower sp with a single ADDMI — ADDI's +-128 immediate
    cannot reach it, and a too-large ADDI silently truncates. }
  if (TargetArch = TARGET_XTENSA) and (XtensaABI = XTENSA_ABI_WINDOWED) then
  begin
    aligned := ((size + XT_EXPR_REGION + 255) div 256) * 256;
    Patch24(patchPos, EncodeXtensaAddmi(reg_xtensa_sp, reg_xtensa_sp, -aligned));
    Exit;
  end;
  if TargetArch = TARGET_ARM32 then
    Patch32(patchPos, aligned)  { raw frame-size literal; loaded into r9, then sub sp,sp,r9 }
  else if TargetArch = TARGET_AARCH64 then
  begin
    { AArch64 `sub sp,sp,#imm` is a 12-bit immediate optionally shifted left 12.
      Frames <= 4095 use it directly; larger frames round up to a 4096 multiple
      and use the LSL #12 form (sh bit = bit 22). The epilog restores via
      `mov sp, x29`, so over-reserving the round-up slack is harmless. }
    if aligned <= 4095 then
      Patch32(patchPos, $D10003FF or (aligned shl 10))
    else
    begin
      a64imm := (aligned + 4095) div 4096;   { units of 4096, <= 4095 (frame < 16 MB) }
      Patch32(patchPos, $D14003FF or (a64imm shl 10));
    end;
  end
  else if TargetArch = TARGET_XTENSA then
  begin
    { Call0 ABI: the prologue saved a0/a15 and set a15 as a frame pointer; the
      epilog restores via `mov sp, a15`, so over-reserving the frame is harmless.
      ADDI's immediate is 8-bit signed (+-128); a larger frame silently wraps.
      Keep the exact ADDI encoding for small frames, and for anything beyond its
      reach round up to 256 and lower sp with a single ADDMI (imm8<<8, reaching
      -32768), mirroring the windowed path. }
    if aligned <= 128 then
      Patch24(patchPos, EncodeXtensaAddi(reg_xtensa_sp, reg_xtensa_sp, -aligned))
    else
    begin
      aligned := ((aligned + 255) div 256) * 256;
      if aligned > 32768 then
        Error('target xtensa (call0): stack frame too large (> 32 KB) for a single ADDMI');
      Patch24(patchPos, EncodeXtensaAddmi(reg_xtensa_sp, reg_xtensa_sp, -aligned));
    end;
  end
  else if TargetArch = TARGET_RISCV32 then
    Patch32(patchPos, EncodeRISCVAddi(reg_sp, reg_sp, -aligned))
  else
    Patch32(patchPos, aligned);
end;

function SymNeedsManagedCleanup(i: Integer): Boolean;
begin
  Result := False;
  if Syms[i].TypeKind = tyAnsiString then
    Result := True
  else if Syms[i].TypeKind = tyVariant then
    Result := True
  else if Syms[i].IsArray and (Syms[i].ArrLen = -1) then
    Result := True
  else if SymIsComInterface(i) then
    Result := True
  else if (Syms[i].TypeKind = tyRecord) and not Syms[i].IsArray and
          RecordHasManagedFields(Syms[i].RecName) then
    Result := True;
end;

function ProcHasManagedLocalCleanup(procIdx, retSymIdx: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  for i := Procs[procIdx].ScopeBase to SymCount - 1 do
    if (Syms[i].Kind = skLocal) and (i <> retSymIdx) and SymNeedsManagedCleanup(i) then
    begin
      Result := True;
      Exit;
    end;
end;

procedure EmitLeaveExceptionFrameX64;
begin
  x64_mov_reg_mem(8, rRAX, rRSP, 0, False); { mov rax, [rsp] }
  x64_mov_glob_reg(8, BSS_EXC_TOP, rRAX);   { mov [BSS_EXC_TOP], rax }
  x64_add_reg_imm(8, rRSP, EXC_FRAME_SIZE);  { add rsp, EXC_FRAME_SIZE }
end;

procedure EmitManagedLocalCleanup(retSymIdx: Integer);
var i, procIdx: Integer;
begin
  if CurProc < 0 then Exit;
  for i := Procs[CurProc].ScopeBase to SymCount - 1 do
  begin
    if (Syms[i].Kind = skLocal) and (i <> retSymIdx) then
    begin
      if SymIsComInterface(i) then
      begin
        { COM/ARC interface local: _Release the held reference (nil-safe). }
        procIdx := FindProc('PXXIntfRelease');
        if procIdx < 0 then Error('compiler error: PXXIntfRelease not found');
        x64_lea_reg_mem(8, rRDI, rRBP, Syms[i].Offset, True);  { lea rdi, [rbp+off] }
        EmitCallProc(procIdx);
      end
      else if Syms[i].TypeKind = tyAnsiString then
      begin
        { mov rax, [rbp + Offset] }
        x64_mov_reg_mem(8, rRAX, rRBP, Syms[i].Offset, True);
        IREmitCodeCall(AnsiStrReleaseAddr);
      end
      else if Syms[i].TypeKind = tyVariant then
      begin
        { lea rax, [rbp + Offset] }
        x64_lea_reg_mem(8, rRAX, rRBP, Syms[i].Offset, True);
        EmitVariantClear;
      end
      else if Syms[i].IsArray and (Syms[i].ArrLen = -1) then
      begin
        { mov rax, [rbp + Offset] }
        x64_mov_reg_mem(8, rRAX, rRBP, Syms[i].Offset, True);
        EmitDynArrayReleaseForSym(i);
      end
      else if (Syms[i].TypeKind = tyRecord) and not Syms[i].IsArray and
              RecordHasManagedFields(Syms[i].RecName) then
      begin
        { Record value local with managed fields (AnsiString, dynamic-array, or
          nested): release them under the heap lock. rbx = record address. }
        x64_push_reg(rRBX);                                      { push rbx }
        x64_lea_reg_mem(8, rRBX, rRBP, Syms[i].Offset, True);     { lea rbx, [rbp+off] }
        EmitAcquireHeapLock;
        EmitManagedRecordReleaseLocked(Syms[i].RecName);
        EmitReleaseHeapLock;
        x64_pop_reg(rRBX);                                       { pop rbx }
      end;
    end;
  end;
end;

procedure EmitProcEpilog(retSymIdx: Integer);
var sz, i, procIdx: Integer;
begin
  if TargetArch = TARGET_I386 then
  begin
    { Release local managed variables before returning }
    if CurProc >= 0 then
    begin
      for i := Procs[CurProc].ScopeBase to SymCount - 1 do
      begin
        if (Syms[i].Kind = skLocal) and (i <> retSymIdx) then
        begin
          if SymIsComInterface(i) then
          begin
            { COM/ARC interface local: _Release the held reference (nil-safe). }
            EmitB($8D); EmitB($85); EmitI32(Syms[i].Offset);  { lea eax, [ebp+off] }
            EmitB($50);                                        { push eax }
            procIdx := FindProc('PXXIntfRelease');
            if procIdx < 0 then Error('compiler error: PXXIntfRelease not found');
            EmitCallProc(procIdx);
            EmitB($81); EmitB($C4); EmitI32(4);                { add esp, 4 }
          end
          else if Syms[i].TypeKind = tyAnsiString then
          begin
            { mov eax, [ebp + Offset] }
            EmitB($8B); EmitB($85); EmitI32(Syms[i].Offset);
            { push eax }
            EmitB($50);
            procIdx := FindProc('PXXStrDecRef');
            if procIdx < 0 then Error('compiler error: PXXStrDecRef not found');
            EmitCallProc(procIdx);
            { add esp, 4 }
            EmitB($81); EmitB($C4); EmitI32(4);
          end;
        end;
      end;
    end;

    { Ordinal or pointer-sized (AnsiString/pointer/class handle) results.
      Legacy fixed string returns the address of its inline buffer. }
    if retSymIdx >= 0 then
    begin
      if TypeIsAggregate(Syms[retSymIdx].TypeKind) and
         (CurProc >= 0) and (ProcAggregateDestSym[CurProc] >= 0) then
      begin
        { Aggregate result: copy the Result local into the caller's hidden
          destination (pointer the prologue stashed in the dest-sym slot from
          ecx), return that pointer in eax. Mirrors the x86-64 rep-movsb path. }
        EmitB($8B); EmitB($BD); EmitI32(Syms[ProcAggregateDestSym[CurProc]].Offset); { mov edi, [ebp+destOff] }
        EmitB($89); EmitB($F8);                                  { mov eax, edi (return value) }
        EmitB($8D); EmitB($B5); EmitI32(Syms[retSymIdx].Offset); { lea esi, [ebp+resultOff] }
        if Syms[retSymIdx].TypeKind = tyRecord then
          sz := RecSize(Syms[retSymIdx].RecName)
        else
          sz := TypeSize(Syms[retSymIdx].TypeKind);
        EmitB($B9); EmitI32(sz);                                 { mov ecx, sz }
        EmitB($F3); EmitB($A4);                                  { rep movsb }
      end
      else if Syms[retSymIdx].TypeKind = tyString then
      begin
        if Syms[retSymIdx].Kind = skGlobal then
          begin EmitB($B8); EmitGlobRef(Syms[retSymIdx].Offset); end          { mov eax, abs32 }
        else if (Syms[retSymIdx].Kind = skParam) and Syms[retSymIdx].IsRef then
          begin EmitB($8B); EmitB($85); EmitI32(Syms[retSymIdx].Offset); end  { mov eax, [ebp+off] }
        else if Syms[retSymIdx].Kind = skLocal then
          begin EmitB($8D); EmitB($85); EmitI32(Syms[retSymIdx].Offset); end  { lea eax, [ebp+off] }
        else
          Error('target i386: only local/global string function results supported yet');
      end
      else
      begin
        if Syms[retSymIdx].IsArray or (Syms[retSymIdx].Kind <> skLocal) or
           not (TypeIsOrdinal(Syms[retSymIdx].TypeKind) or TypeIsFloat(Syms[retSymIdx].TypeKind) or
                (Syms[retSymIdx].TypeKind in [tyAnsiString, tyPointer, tyClass])) then
          Error('target i386: only ordinal/pointer/string function results supported yet');
        { Float result: the 8-byte Double slot loads into eax:edx (the sz=8 path
          below); a 4-byte Single loads into eax. The caller moves eax(:edx) ->
          xmm0 for the SSE value model. See feature-cross-float-returns. }
        { Load at the result's width and extend to a full eax. A 1-byte
          Boolean/Char slot loaded with a plain 4-byte mov drags in 3 garbage
          bytes, which then defeats callers that `not`/`xor` or test eax. }
        sz := TypeSize(Syms[retSymIdx].TypeKind);
        if sz = 1 then
        begin
          if TypeSigned(Syms[retSymIdx].TypeKind) then
            begin EmitB($0F); EmitB($BE); EmitB($85); EmitI32(Syms[retSymIdx].Offset); end  { movsx eax, byte [ebp+off] }
          else
            begin EmitB($0F); EmitB($B6); EmitB($85); EmitI32(Syms[retSymIdx].Offset); end; { movzx eax, byte [ebp+off] }
        end
        else if sz = 2 then
        begin
          if TypeSigned(Syms[retSymIdx].TypeKind) then
            begin EmitB($0F); EmitB($BF); EmitB($85); EmitI32(Syms[retSymIdx].Offset); end  { movsx eax, word [ebp+off] }
          else
            begin EmitB($0F); EmitB($B7); EmitB($85); EmitI32(Syms[retSymIdx].Offset); end; { movzx eax, word [ebp+off] }
        end
        else
        begin
          EmitB($8B); EmitB($85); EmitI32(Syms[retSymIdx].Offset);                          { mov eax, [ebp+off] }
          if sz = 8 then
            begin EmitB($8B); EmitB($95); EmitI32(Syms[retSymIdx].Offset + 4); end;          { mov edx, [ebp+off+4] (Int64 hi) }
        end;
      end;
    end;
    EmitB($C9); EmitB($C3);                                    { leave; ret }
    Exit;
  end;
  if TargetArch = TARGET_ARM32 then
  begin
    { Release local managed variables before returning. }
    if CurProc >= 0 then
    begin
      for i := Procs[CurProc].ScopeBase to SymCount - 1 do
      begin
        if (Syms[i].Kind = skLocal) and (i <> retSymIdx) and SymIsComInterface(i) then
        begin
          { COM/ARC interface local: _Release the held reference (nil-safe). }
          EmitLoadVarAddrArm32(i);                     { r0 = fat pointer address }
          EmitI32($E92D000E);                          { push {r1,r2,r3} }
          procIdx := FindProc('PXXIntfRelease');
          if procIdx < 0 then Error('compiler error: PXXIntfRelease not found');
          EmitCallProc(procIdx);
          EmitI32($E8BD000E);                          { pop {r1,r2,r3} }
        end
        else if (Syms[i].Kind = skLocal) and (i <> retSymIdx) and
           (Syms[i].TypeKind = tyAnsiString) then
        begin
          EmitLoadVarArm32(i);                         { r0 = handle }
          EmitI32($E92D000E);                          { push {r1,r2,r3} }
          procIdx := FindProc('PXXStrDecRef');
          if procIdx < 0 then Error('compiler error: PXXStrDecRef not found');
          EmitCallProc(procIdx);
          EmitI32($E8BD000E);                          { pop {r1,r2,r3} }
        end
        else if (Syms[i].Kind = skLocal) and (i <> retSymIdx) and
                (Syms[i].TypeKind = tyVariant) then
        begin
          { Variant local: clear (releases any managed payload). r0 = address. }
          EmitLoadVarAddrArm32(i);                     { r0 = variant address }
          EmitI32($E92D000E);                          { push {r1,r2,r3} }
          procIdx := FindProc('PXXVarClear');
          if procIdx < 0 then Error('compiler error: PXXVarClear not found');
          EmitCallProc(procIdx);
          EmitI32($E8BD000E);                          { pop {r1,r2,r3} }
        end
        else if (Syms[i].Kind = skLocal) and (i <> retSymIdx) and
                (Syms[i].TypeKind = tyRecord) and not Syms[i].IsArray and
                RecordHasManagedFields(Syms[i].RecName) then
        begin
          { Record-with-managed-fields local: release each managed field via the
            portable helper. r0 = record address, r1 = layout descriptor. }
          EmitLoadVarAddrArm32(i);                     { r0 = record address }
          EmitLoadDataRefArm32(1,
            -(RECORD_RTTI_DATAREF_BASE + (Syms[i].RecName - REC_UCLASS_BASE)));
          EmitI32($E92D000C);                          { push {r2,r3} }
          procIdx := FindProc('PXXRecordRelease');
          if procIdx < 0 then Error('compiler error: PXXRecordRelease not found');
          EmitCallProc(procIdx);
          EmitI32($E8BD000C);                          { pop {r2,r3} }
        end;
      end;
    end;

    if retSymIdx >= 0 then
    begin
      if TypeIsAggregate(Syms[retSymIdx].TypeKind) and
         (CurProc >= 0) and (ProcAggregateDestSym[CurProc] >= 0) then
      begin
        { Aggregate result: copy the Result local into the caller's hidden
          destination (pointer the prologue stashed from r12), return the
          pointer in r0. r5=src, r6=dst, r4=count for EmitArm32CopyBytes. }
        EmitLoadVarArm32(ProcAggregateDestSym[CurProc]);  { r0 = dest ptr }
        EmitI32($E1A06000);                               { mov r6, r0 (dst) }
        EmitLoadVarAddrArm32(retSymIdx);                  { r0 = &Result }
        EmitI32($E1A05000);                               { mov r5, r0 (src) }
        if Syms[retSymIdx].TypeKind = tyRecord then
          sz := RecSize(Syms[retSymIdx].RecName)
        else
          sz := TypeSize(Syms[retSymIdx].TypeKind);
        EmitLoadImmArm32(4, sz);                          { r4 = byte count }
        EmitArm32CopyBytes(4, 5, 6);
        EmitLoadVarArm32(ProcAggregateDestSym[CurProc]);  { r0 = dest (return value) }
      end
      else if Syms[retSymIdx].TypeKind = tyString then
        { Legacy inline string struct ([len][data]): return its address — the
          global lives in BSS, a local on the frame (mirrors the x86-64 path).
          Managed tyAnsiString results stay pointer-sized handles below. }
        EmitLoadVarAddrArm32(retSymIdx)
      else
      begin
        if Syms[retSymIdx].IsArray or (Syms[retSymIdx].Kind <> skLocal) or
           not (TypeIsOrdinal(Syms[retSymIdx].TypeKind) or TypeIsFloat(Syms[retSymIdx].TypeKind) or
                (Syms[retSymIdx].TypeKind in [tyAnsiString, tyPointer, tyClass])) then
          Error('target arm32: only ordinal/pointer/string function results supported yet');
        if (Syms[retSymIdx].TypeKind = tyInt64) or
           (Syms[retSymIdx].TypeKind = tyUInt64) or
           (Syms[retSymIdx].TypeKind = tyDouble) or (Syms[retSymIdx].TypeKind = tyExtended) then
          { Int64 / Double result: raw 8 bytes in r0:r1 (lo:hi). The caller moves
            r0:r1 -> d0 for the float value model. See feature-cross-float-returns. }
          EmitLoadVar64Arm32(retSymIdx)
        else
          { ordinal / pointer / Single (4-byte bits in r0). }
          EmitLoadVarArm32(retSymIdx);
      end;
    end;
    EmitI32($E1A0D00B);  { mov sp, fp }
    EmitI32($E8BD8800);  { pop {fp, pc} }
    Exit;
  end;
  if TargetArch = TARGET_AARCH64 then
  begin
    { Release local COM/ARC interface references before returning (nil-safe).
      Must precede the result load: each call clobbers x0. }
    if CurProc >= 0 then
      for i := Procs[CurProc].ScopeBase to SymCount - 1 do
        if (Syms[i].Kind = skLocal) and (i <> retSymIdx) and SymIsComInterface(i) then
        begin
          EmitLoadImmA64(9, Syms[i].Offset);
          EmitI32($8B0903A0);  { add x0, x29, x9  (x0 = fat pointer address) }
          procIdx := FindProc('PXXIntfRelease');
          if procIdx < 0 then Error('compiler error: PXXIntfRelease not found');
          EmitCallProc(procIdx);
        end;
    if retSymIdx >= 0 then
    begin
      if TypeIsAggregate(Syms[retSymIdx].TypeKind) and
         (CurProc >= 0) and (ProcAggregateDestSym[CurProc] >= 0) then
      begin
        { Aggregate result: copy the Result local into the caller's hidden
          destination (pointer the prologue stashed from x8), return the pointer
          in x0. EmitA64CopyBytes uses x4/x5/x6 + w8, leaving x0 intact. }
        EmitLoadVarA64(ProcAggregateDestSym[CurProc]);   { x0 = dest ptr }
        EmitI32($AA0003E6);                              { mov x6, x0 (dst) }
        EmitLoadImmA64(9, Syms[retSymIdx].Offset);
        EmitI32($8B0903A5);                              { add x5, x29, x9 (src = &Result) }
        if Syms[retSymIdx].TypeKind = tyRecord then
          sz := RecSize(Syms[retSymIdx].RecName)
        else
          sz := TypeSize(Syms[retSymIdx].TypeKind);
        EmitLoadImmA64(4, sz);                           { x4 = byte count }
        EmitA64CopyBytes(4, 5, 6);
      end
      else if Syms[retSymIdx].TypeKind = tyString then
      begin
        if Syms[retSymIdx].Kind = skGlobal then
        begin
          EmitI32($18000040);  { ldr w0, [pc+8] }
          EmitI32($14000002);  { b [pc+8] }
          EmitGlobRef(Syms[retSymIdx].Offset);
        end
        else if Syms[retSymIdx].Kind = skLocal then
        begin
          EmitLoadImmA64(9, Syms[retSymIdx].Offset);
          EmitI32($8B0903A0);  { add x0, x29, x9 }
        end
        else
          Error('target aarch64: only local/global string function results supported yet');
      end
      else
      begin
        if Syms[retSymIdx].IsArray or (Syms[retSymIdx].Kind <> skLocal) or
           not (TypeIsOrdinal(Syms[retSymIdx].TypeKind) or TypeIsFloat(Syms[retSymIdx].TypeKind) or
                (Syms[retSymIdx].TypeKind in [tyAnsiString, tyPointer, tyClass])) then
          Error('target aarch64: only ordinal/pointer/string function results supported yet');
        { Float result: the value model carries it as double-bits in x0 (the
          return reg). EmitLoadVarA64 loads a Double's 8 bytes / widens a Single
          into x0 already. See feature-cross-float-returns. }
        EmitLoadVarA64(retSymIdx);
      end;
    end;
    EmitI32($910003BF);  { mov sp, x29 }
    EmitI32($A8C17BFD);  { ldp x29, x30, [sp], #16 }
    EmitI32($D65F03C0);  { ret }
    Exit;
  end;
  if TargetArch = TARGET_XTENSA then
  begin
    { Release local managed strings before returning (ARC scope-exit DecRef).
      Must precede the result load: each DecRef call clobbers a2. The returned
      Result handle is skipped (ownership transfers to the caller). }
    if CurProc >= 0 then
      for i := Procs[CurProc].ScopeBase to SymCount - 1 do
        if (Syms[i].Kind = skLocal) and (i <> retSymIdx) and
           (Syms[i].TypeKind = tyAnsiString) and not Syms[i].IsArray then
        begin
          EmitLoadVarXtensa(i);                  { a2 = handle }
          procIdx := FindProc('PXXStrDecRef');
          if procIdx < 0 then Error('compiler error: PXXStrDecRef not found');
          if XtensaABI = XTENSA_ABI_WINDOWED then
            xtensa_mov(reg_xtensa_a10, reg_xtensa_a2);
          EmitCallProc(procIdx);
        end;
    if retSymIdx >= 0 then
    begin
      if Syms[retSymIdx].IsArray or (Syms[retSymIdx].Kind <> skLocal) or
         not (TypeIsOrdinal(Syms[retSymIdx].TypeKind) or
              (Syms[retSymIdx].TypeKind in [tyAnsiString, tyPointer, tyClass])) then
        Error('target xtensa: only ordinal/pointer/string function results supported yet');
      if (Syms[retSymIdx].TypeKind = tyInt64) or (Syms[retSymIdx].TypeKind = tyUInt64) then
        EmitLoadVar64Xtensa(retSymIdx)   { 64-bit result in a2:a3 }
      else
        EmitLoadVarXtensa(retSymIdx);
    end;
    if XtensaABI = XTENSA_ABI_WINDOWED then
    begin
      { sp stayed constant through the body, and the window spill area for our
        caller lives at [sp-16], so retw must keep sp as entry set it — no
        restore (matches gcc's bare `retw.n`). }
      xtensa_retw;
    end
    else
    begin
      xtensa_mov(reg_xtensa_sp, reg_xtensa_a15);
      xtensa_l32i(reg_xtensa_a15, reg_xtensa_sp, 8);
      xtensa_l32i(reg_xtensa_a0, reg_xtensa_sp, 12);
      xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 16);
      xtensa_ret;
    end;
    Exit;
  end;
  if TargetArch = TARGET_RISCV32 then
  begin
    { Release local managed strings before returning (ARC scope-exit DecRef).
      Must precede the result load: each DecRef call clobbers a0. The returned
      Result handle is skipped (ownership transfers to the caller). }
    if CurProc >= 0 then
      for i := Procs[CurProc].ScopeBase to SymCount - 1 do
        if (Syms[i].Kind = skLocal) and (i <> retSymIdx) and
           (Syms[i].TypeKind = tyAnsiString) and not Syms[i].IsArray then
        begin
          EmitLoadVarRISCV32(i);                 { a0 = handle }
          procIdx := FindProc('PXXStrDecRef');
          if procIdx < 0 then Error('compiler error: PXXStrDecRef not found');
          EmitCallProc(procIdx);
        end;
    if retSymIdx >= 0 then
    begin
      if Syms[retSymIdx].IsArray or (Syms[retSymIdx].Kind <> skLocal) or
         not (TypeIsOrdinal(Syms[retSymIdx].TypeKind) or
              (Syms[retSymIdx].TypeKind in [tyAnsiString, tyPointer, tyClass])) then
        Error('target riscv32: only ordinal/pointer/string function results supported yet');
      if (Syms[retSymIdx].TypeKind = tyInt64) or (Syms[retSymIdx].TypeKind = tyUInt64) then
        EmitLoadVar64RISCV32(retSymIdx)   { 64-bit result in a0:a1 }
      else
        EmitLoadVarRISCV32(retSymIdx);
    end;
    rv32_addi(reg_sp, reg_s0, 0);
    rv32_lw(reg_s0, reg_sp, 8);
    rv32_lw(reg_ra, reg_sp, 12);
    rv32_addi(reg_sp, reg_sp, 16);
    rv32_jalr(reg_zero, reg_ra, 0);
    Exit;
  end;
  { Release local managed variables before returning }
  if ProcExceptionCleanupFrameActive then
    EmitLeaveExceptionFrameX64;
  if CurProc >= 0 then
    EmitManagedLocalCleanup(retSymIdx);

  if retSymIdx >= 0 then
  begin
    if TypeIsAggregate(Syms[retSymIdx].TypeKind) and
       (CurProc >= 0) and (ProcAggregateDestSym[CurProc] >= 0) then
    begin
      { Aggregate results use a hidden caller-owned destination pointer in r10.
        The prologue saves it in a local so nested calls cannot clobber it. }
      EmitLoadVar(ProcAggregateDestSym[CurProc]);
      EmitB($50);                                  { push original destination }
      EmitB($48); EmitB($89); EmitB($C7);          { mov rdi, rax }
      EmitB($48); EmitB($8D); EmitB($B5); EmitI32(Syms[retSymIdx].Offset); { lea rsi, [rbp+off] }
      if Syms[retSymIdx].TypeKind = tyRecord then
        sz := RecSize(Syms[retSymIdx].RecName)
      else
        sz := TypeSize(Syms[retSymIdx].TypeKind);
      EmitB($48); EmitB($B9); EmitI64(sz);          { movabs rcx, byte count }
      EmitB($F3); EmitB($A4);                       { rep movsb }
      EmitB($58);                                   { pop rax = result address }
    end
    else if Syms[retSymIdx].TypeKind = tyString then
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
    else if Syms[retSymIdx].IsArray and (Syms[retSymIdx].ArrLen = -1) then
    begin
      { Dynamic-array result: the slot holds a pointer-sized heap handle. Return
        all 8 bytes; a narrow EmitLoadVar keyed on the element type would
        truncate (and sign-extend) the pointer. }
      EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[retSymIdx].Offset); { mov rax, [rbp+off] }
    end
    else
    begin
      EmitLoadVar(retSymIdx);
      { EmitLoadVar leaves a float in xmm0, but the internal call ABI / value
        model carries a float return as double-bits in rax (the caller bridges
        rax->xmm0 after the call). Without this bridge the return value is only
        correct when rax happens to still hold the bits from the last store; a
        loop in the body clobbers rax (e.g. the condition's setcc/test) and the
        result reads as 0. Mirrors the IR_LOAD_SYM bridge in ir_codegen.inc.
        See feature-result-in-loop. }
      if TypeIsFloat(Syms[retSymIdx].TypeKind) then
        begin EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0); end; { movq rax, xmm0 }
    end;
  end;
  EmitB($C9); EmitB($C3);
end;

{ ===== Call emission ===== }

{ Ensure the external procIdx has a GOT slot; return its ExternalProc[] index. }
function RegisterExternal(procIdx: Integer): Integer;
var i, extIdx: Integer;
begin
  extIdx := -1;
  for i := 0 to ExternalCount-1 do
    if ExternalProc[i] = procIdx then extIdx := i;
  if extIdx < 0 then
  begin
    if ExternalCount >= MAX_EXTERNAL then Error('external function overflow');
    extIdx := ExternalCount;
    ExternalProc[extIdx] := procIdx;
    ExternalGotOff[extIdx] := DataLen;
    for i := 0 to 7 do
    begin
      Data[DataLen] := 0;
      Inc(DataLen);
    end;
    Inc(ExternalCount);
  end;
  Result := extIdx;
end;

{ Emit the indirect call through the external's GOT slot and register the
  fixup. Caller is responsible for argument marshalling, stack alignment, and
  the variadic AL count. }
procedure EmitExternalIndirectCall(extIdx: Integer);
begin
  if DynCallCount >= MAX_CALLFIX then Error('external call fixup overflow');
  EmitB($FF); EmitB($14); EmitB($25); { call qword ptr [absolute address] }
  DynCallCodePos[DynCallCount] := CodeLen;
  DynCallExtIdx[DynCallCount] := extIdx;
  Inc(DynCallCount);
  EmitI32(0);
end;

{ aarch64 external call through the GOT slot. The slot's absolute VA (< 2^32
  under ET_EXEC) is built into x16 with movz/movk — both imm16 fields are patched
  by the writeELF DynCall pass (PatchDynCallSites) — then the resolved pointer is
  loaded and called. Caller marshals args into x0..x7 (AAPCS) first. }
procedure EmitExternalCallA64(extIdx: Integer);
begin
  if DynCallCount >= MAX_CALLFIX then Error('external call fixup overflow');
  DynCallCodePos[DynCallCount] := CodeLen;
  DynCallExtIdx[DynCallCount] := extIdx;
  Inc(DynCallCount);
  EmitI32($D2800010);   { movz x16, #0      (lo16 patched) }
  EmitI32($F2A00010);   { movk x16, #0, lsl 16  (hi16 patched) }
  EmitI32($F9400210);   { ldr  x16, [x16]   (resolved fn ptr) }
  EmitI32($D63F0200);   { blr  x16 }
end;

{ arm32 external call through the GOT slot. The slot's absolute VA is built into
  ip (r12) with movw/movt (both patched by the writeELF32 DynCall pass), then the
  resolved pointer is loaded and called. Caller marshals args into r0..r3 first. }
procedure EmitExternalCallArm32(extIdx: Integer);
begin
  if DynCallCount >= MAX_CALLFIX then Error('external call fixup overflow');
  DynCallCodePos[DynCallCount] := CodeLen;
  DynCallExtIdx[DynCallCount] := extIdx;
  Inc(DynCallCount);
  EmitI32($E300C000);   { movw ip, #0    (lo16 patched) }
  EmitI32($E340C000);   { movt ip, #0    (hi16 patched) }
  EmitI32($E59CC000);   { ldr  ip, [ip]  (resolved fn ptr) }
  EmitI32($E12FFF3C);   { blx  ip }
end;

procedure EmitCallProc(procIdx: Integer);
var extIdx: Integer;
begin
  if ProcExternal[procIdx] then
  begin
    extIdx := RegisterExternal(procIdx);
    { esp32 targets: indirect call through a 32-bit literal slot. The slot is
      recorded as a DynCall fixup; the ET_REL writer turns it into an
      R_XTENSA_32/R_RISCV_32 data-word reloc against the undefined symbol, so
      no code relocations are needed (the zero-code-reloc property). }
    if TargetArch = TARGET_XTENSA then
    begin
      if DynCallCount >= MAX_CALLFIX then Error('external call fixup overflow');
      XtensaEmitLitHeader;
      DynCallCodePos[DynCallCount] := CodeLen;
      DynCallExtIdx[DynCallCount] := extIdx;
      Inc(DynCallCount);
      EmitI32(0);
      xtensa_l32r(reg_xtensa_a8, $FFFF);
      if XtensaABI = XTENSA_ABI_WINDOWED then
        xtensa_callx8(reg_xtensa_a8)
      else
        xtensa_callx0(reg_xtensa_a8);
      Exit;
    end;
    if TargetArch = TARGET_RISCV32 then
    begin
      if DynCallCount >= MAX_CALLFIX then Error('external call fixup overflow');
      rv32_auipc(reg_t0, 0);
      rv32_jal(reg_zero, 8);
      DynCallCodePos[DynCallCount] := CodeLen;
      DynCallExtIdx[DynCallCount] := extIdx;
      Inc(DynCallCount);
      EmitI32(0);
      rv32_lw(reg_t0, reg_t0, 8);
      rv32_jalr(reg_ra, reg_t0, 0);
      Exit;
    end;
    { Realign the stack to 16 bytes for the SysV call: our internal call
      convention does not keep rsp 16-aligned at every call site, but C
      callees (GTK/GLib) use aligned SSE (movaps) and fault otherwise. This
      path is for register-only externals (no stack args to disturb); the
      stack-spill path in IR_CALL handles its own alignment. Old rsp is saved
      and restored around the call; r11 is scratch under SysV. }
    EmitB($49); EmitB($89); EmitB($E3);             { mov r11, rsp }
    EmitB($48); EmitB($83); EmitB($E4); EmitB($F0); { and rsp, -16 }
    EmitB($48); EmitB($83); EmitB($EC); EmitB($08); { sub rsp, 8 }
    EmitB($41); EmitB($53);                         { push r11 }
    EmitB($31); EmitB($C0);                         { xor eax, eax (al=0) }
    EmitExternalIndirectCall(extIdx);
    EmitB($41); EmitB($5B);                         { pop r11 }
    EmitB($4C); EmitB($89); EmitB($DC);             { mov rsp, r11 }
    Exit;
  end;
  { Cross-section internal call (flash <-> iram): a direct PC-relative call can't
    span the two ELF sections (the linker places .iram1.text far from flash
    .text), so load the callee's absolute address from a relocated 32-bit literal
    and call indirect — same shape as an external call, but the literal is
    relocated against the callee proc's own local symbol (IramCallFix). ESP only;
    flash<->flash and iram<->iram stay direct PC-relative below. }
  if (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32) then
    if (((CurProc >= 0) and ProcIram[CurProc]) <> ProcIram[procIdx]) then
    begin
      if IramCallFixCount >= MAX_CALLFIX then Error('iram call fixup overflow');
      if TargetArch = TARGET_RISCV32 then
      begin
        rv32_auipc(reg_t0, 0);
        rv32_jal(reg_zero, 8);
        IramCallFix[IramCallFixCount].CodePos := CodeLen;
        IramCallFix[IramCallFixCount].ProcIdx := procIdx;
        Inc(IramCallFixCount);
        EmitI32(0);
        rv32_lw(reg_t0, reg_t0, 8);
        rv32_jalr(reg_ra, reg_t0, 0);
      end
      else
      begin
        XtensaEmitLitHeader;
        IramCallFix[IramCallFixCount].CodePos := CodeLen;
        IramCallFix[IramCallFixCount].ProcIdx := procIdx;
        Inc(IramCallFixCount);
        EmitI32(0);
        xtensa_l32r(reg_xtensa_a8, $FFFF);
        if XtensaABI = XTENSA_ABI_WINDOWED then
          xtensa_callx8(reg_xtensa_a8)
        else
          xtensa_callx0(reg_xtensa_a8);
      end;
      Exit;
    end;
  if TargetArch = TARGET_ARM32 then
  begin
    if Procs[procIdx].BodyAddr >= 0 then
      EmitI32($EB000000 or ((((Procs[procIdx].BodyAddr - CodeLen) div 4) - 2) and $00ffffff))
    else
    begin
      if CallFixCount >= MAX_CALLFIX then Error('call fixup overflow');
      CallFix[CallFixCount].CodePos := CodeLen;
      CallFix[CallFixCount].ProcIdx := procIdx;
      Inc(CallFixCount);
      EmitI32($EB000000);
    end;
    Exit;
  end;
  if TargetArch = TARGET_AARCH64 then
  begin
    if Procs[procIdx].BodyAddr >= 0 then
      EmitI32($94000000 or (((Procs[procIdx].BodyAddr - CodeLen) div 4) and $03ffffff))
    else
    begin
      if CallFixCount >= MAX_CALLFIX then Error('call fixup overflow');
      CallFix[CallFixCount].CodePos := CodeLen;
      CallFix[CallFixCount].ProcIdx := procIdx;
      Inc(CallFixCount);
      EmitI32($94000000);
    end;
    Exit;
  end;
  if TargetArch = TARGET_XTENSA then
  begin
    if Procs[procIdx].BodyAddr >= 0 then
    begin
      if XtensaABI = XTENSA_ABI_WINDOWED then
        xtensa_call8(Procs[procIdx].BodyAddr - CodeLen)
      else
        xtensa_call0(Procs[procIdx].BodyAddr - CodeLen);
    end
    else
    begin
      if CallFixCount >= MAX_CALLFIX then Error('call fixup overflow');
      CallFix[CallFixCount].CodePos := CodeLen;
      CallFix[CallFixCount].ProcIdx := procIdx;
      Inc(CallFixCount);
      if XtensaABI = XTENSA_ABI_WINDOWED then
        xtensa_call8(0)
      else
        xtensa_call0(0);
    end;
    Exit;
  end;
  if TargetArch = TARGET_RISCV32 then
  begin
    if Procs[procIdx].BodyAddr >= 0 then
      rv32_jal(reg_ra, Procs[procIdx].BodyAddr - CodeLen)
    else
    begin
      if CallFixCount >= MAX_CALLFIX then Error('call fixup overflow');
      CallFix[CallFixCount].CodePos := CodeLen;
      CallFix[CallFixCount].ProcIdx := procIdx;
      Inc(CallFixCount);
      rv32_jal(reg_ra, 0);
    end;
    Exit;
  end;
  EmitB($E8);
  if Procs[procIdx].BodyAddr >= 0 then
    EmitI32(Procs[procIdx].BodyAddr - (CodeLen + 4))
  else
  begin
    if CallFixCount >= MAX_CALLFIX then Error('call fixup overflow');
    CallFix[CallFixCount].CodePos := CodeLen;
    CallFix[CallFixCount].ProcIdx := procIdx;
    Inc(CallFixCount);
    EmitI32(0);
  end;
end;

procedure ApplyCallFixups;
var i, procIdx: Integer;
begin
  if DebugTrace then
    for i := 0 to ProcCount-1 do
      writeln('Proc ', i, ': ', Procs[i].Name, ' at CodePos ', Procs[i].BodyAddr);
  for i := 0 to CallFixCount-1 do
  begin
    procIdx := CallFix[i].ProcIdx;
    if Procs[procIdx].BodyAddr < 0 then
      Error('unresolved forward: ' + Procs[procIdx].Name);
    if TargetArch = TARGET_ARM32 then
      Patch32(CallFix[i].CodePos, $EB000000 or ((((Procs[procIdx].BodyAddr - CallFix[i].CodePos) div 4) - 2) and $00ffffff))
    else if TargetArch = TARGET_AARCH64 then
      Patch32(CallFix[i].CodePos, $94000000 or (((Procs[procIdx].BodyAddr - CallFix[i].CodePos) div 4) and $03ffffff))
    else if TargetArch = TARGET_XTENSA then
    begin
      if XtensaABI = XTENSA_ABI_WINDOWED then
        Patch24(CallFix[i].CodePos, EncodeXtensaCall8(CallFix[i].CodePos, Procs[procIdx].BodyAddr))
      else
        Patch24(CallFix[i].CodePos, EncodeXtensaCall0(CallFix[i].CodePos, Procs[procIdx].BodyAddr));
    end
    else if TargetArch = TARGET_RISCV32 then
      Patch32(CallFix[i].CodePos, EncodeRISCVJAL(reg_ra, Procs[procIdx].BodyAddr - CallFix[i].CodePos))
    else
      Patch32(CallFix[i].CodePos, Procs[procIdx].BodyAddr - (CallFix[i].CodePos + 4));
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
  else if ASTKind[node] = AN_AS_CAST then
    { `obj as T` yields type T — so (obj as T).field/.method resolves against T. }
    Result := REC_UCLASS_BASE + Integer(ASTIVal[node])
  else if ASTKind[node] = AN_CLASS_CAST then
    { `TClass(obj)` hard cast yields type TClass — same record resolution. }
    Result := REC_UCLASS_BASE + Integer(ASTIVal[node])
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
    else if ASTKind[ASTLeft[node]] = AN_INDEX then
      Result := ResolveNodeRec(ASTLeft[node])
    else
      Result := REC_NONE;
  end
  else if ASTKind[node] = AN_DEREF then
  begin
    baseNode := ASTLeft[node];
    if ASTIVal[node] > 0 then
      { Synthesised record deref (e.g. the for-in generator desugar derefs the
        CoCurrent address into the loop var): the record id is carried directly
        on the deref node, since the base is an untyped Int64 call result. }
      Result := ASTIVal[node]
    else if ASTKind[baseNode] = AN_IDENT then
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
    else if ASTKind[baseNode] = AN_CALL then
    begin
      { f()^ : the pointed-at record comes from the callee's return element. }
      if ASTIVal[baseNode] >= 0 then
        Result := ProcRetPtrElemRec[ASTIVal[baseNode]]
      else
        Result := REC_NONE;
    end
    else
      Result := REC_NONE;
  end
  else if ASTKind[node] = AN_CALL then
  begin
    if ASTIVal[node] = -Ord(tkGetMem) then
      Result := ASTRight[node]
    else if ASTIVal[node] >= 0 then
      Result := ProcRetRecId[ASTIVal[node]]
    else
      Result := REC_NONE;
  end
  else if ASTKind[node] = AN_PTR_CAST then
  begin
    if ASTIVal[node] >= 0 then
      Result := AliasElemRec[ASTIVal[node]]
    else
      Result := REC_NONE;
  end
  else if ASTKind[node] = AN_BINOP then
  begin
    { An overloaded operator on record/class operands resolves to its result
      record (the call returns an aggregate). Without this, an inferred
      `var c := a + b` gets REC_NONE -> wrong RecSize -> truncated/garbage copy. }
    fIdx := FindOpOverload(ASTIVal[node], ASTTk[ASTLeft[node]], ResolveNodeRec(ASTLeft[node]));
    if fIdx >= 0 then
      Result := ProcRetRecId[fIdx]
    else
      Result := REC_NONE;
  end
  else
    Result := REC_NONE;
end;

function DynArrayNodeDepth(node: Integer): Integer;
{ Remaining dynamic-array nesting of an AST expression. Keep this parser-side
  helper here because selectors are typed before IR lowering runs. }
var depth: Integer;
begin
  Result := 0;
  if node < 0 then Exit;
  if ASTKind[node] = AN_IDENT then
  begin
    if Syms[ASTIVal[node]].IsArray and (Syms[ASTIVal[node]].ArrLen = -1) then
      Result := SymDynDepth[ASTIVal[node]];
  end
  else if ASTKind[node] = AN_INDEX then
  begin
    depth := DynArrayNodeDepth(ASTLeft[node]);
    if depth > 0 then Result := depth - 1;
  end;
end;

function IsNodeArray(node: Integer): Boolean;
begin
  Result := False;
  if DynArrayNodeDepth(node) > 0 then
    Result := True
  else if ASTKind[node] = AN_IDENT then
    Result := Syms[ASTIVal[node]].IsArray
  else if ASTKind[node] = AN_FIELD then
    Result := RecFieldIsArray(ResolveNodeRec(ASTLeft[node]), GetASTIdentName(node));
end;

procedure ResolvePendingPointerAliases;
var
  i, ci: Integer;
  targetName: AnsiString;
begin
  for i := 0 to AliasCount - 1 do
  begin
    if (AliasTk[i] = Ord(tyPointer)) and (AliasElemRec[i] = REC_NONE) and (AliasTargetNLen[i] > 0) then
    begin
      targetName := GetSliceName(AliasTargetNOff[i], AliasTargetNLen[i]);
      ci := FindUClass(targetName);
      if ci >= 0 then
      begin
        if UClsIsRecord[ci] then
          AliasElemTk[i] := Ord(tyRecord)
        else
          AliasElemTk[i] := Ord(tyClass);
        AliasElemRec[i] := REC_UCLASS_BASE + ci;
      end;
    end;
  end;
end;

{ ===== Expression parser ===== }
