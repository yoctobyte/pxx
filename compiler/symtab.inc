{ SPDX-License-Identifier: MPL-2.0 }
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
procedure EmitSlotAddrRISCV32(rd, si: Integer); forward;
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

function UNameMatchCS(off, len: Integer; const s: AnsiString): Boolean;
{ Exact, case-SENSITIVE slice match (C struct/union fields — C distinguishes
  `b` from `B`). Mirror of UNameMatch without the ASCII case fold. }
var i: Integer;
begin
  Result := False;
  if len <> Length(s) then Exit;
  i := 0;
  while i < len do
  begin
    if TokChars[off + i] <> s[i + 1] then Exit;
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
  AliasPtrDepth[AliasCount] := 0;
  AliasPtrBaseTk[AliasCount] := Ord(tyUnknown);
  AliasPtrBaseRec[AliasCount] := REC_NONE;
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
  AliasPtrDepth[AliasCount] := 0;
  AliasPtrBaseTk[AliasCount] := Ord(tyUnknown);
  AliasPtrBaseRec[AliasCount] := REC_NONE;
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
  AliasPtrDepth[AliasCount] := 0;
  AliasPtrBaseTk[AliasCount] := Ord(tyUnknown);
  AliasPtrBaseRec[AliasCount] := REC_NONE;
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
  AliasPtrDepth[AliasCount] := 1;
  AliasPtrBaseTk[AliasCount] := Ord(tyUnknown);
  AliasPtrBaseRec[AliasCount] := REC_NONE;
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

function FindSetConst(const name: AnsiString): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to SetConstCount - 1 do
    if CaseEqual(SetConstName[i], name) then begin Result := i; Exit; end;
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
  AliasPtrDepth[AliasCount] := 0;
  AliasPtrBaseTk[AliasCount] := Ord(tyUnknown);
  AliasPtrBaseRec[AliasCount] := REC_NONE;
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
  AliasPtrDepth[AliasCount] := 1;
  AliasPtrBaseTk[AliasCount] := Ord(tyClass);
  AliasPtrBaseRec[AliasCount] := classRec;
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
  EnumTypeHasHoles[Result] := False;
  EnumTypeScoped[Result] := False;
  EnumTypeValCount[Result] := 0;
  EnumTypeRTTIOff[Result] := -1;
  Inc(EnumTypeCount);
end;

procedure AddEnumVal(noff, nlen, ordVal: Integer);
begin
  if EnumValCount >= MAX_ENUMVAL then Error('too many enum values');
  EnumValNOff[EnumValCount] := noff;
  EnumValNLen[EnumValCount] := nlen;
  EnumValOrd[EnumValCount] := ordVal;
  Inc(EnumValCount);
end;

function FindEnumMemberOrd(etid: Integer; const name: AnsiString; var ordOut: Integer): Boolean;
{ Member lookup within one enum type (TEnum.member resolution). }
var i: Integer;
begin
  Result := False;
  for i := EnumTypeValBase[etid] to EnumTypeValBase[etid] + EnumTypeValCount[etid] - 1 do
    if CaseEqual(GetTokenStrFromRaw(EnumValNOff[i], EnumValNLen[i]), name) then
    begin
      ordOut := EnumValOrd[i];
      Result := True;
      Exit;
    end;
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
  { class-name alias (`TOptionList = TList;`) — resolve to the target row }
  for i := 0 to UClsAliasCount - 1 do
    if UNameMatch(UClsAliasNOff[i], UClsAliasNLen[i], lo) then
    begin
      Result := UClsAliasCi[i];
      Exit;
    end;
end;

procedure RegisterUClassAlias(noff, nlen, ci: Integer);
begin
  if UClsAliasCount >= MAX_TYPEALIAS then Error('too many class aliases');
  UClsAliasNOff[UClsAliasCount] := noff;
  UClsAliasNLen[UClsAliasCount] := nlen;
  UClsAliasCi[UClsAliasCount]   := ci;
  Inc(UClsAliasCount);
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
var i, base, cnt: Integer; lo, name2: AnsiString; curr: Integer; cs, hit: Boolean;
begin
  Result := -1;
  name2 := name;
  lo := ULower(name2);
  curr := ci;
  while curr >= 0 do
  begin
    base := UClsFBase[curr];
    cnt  := UClsFCount[curr];
    { C structs/unions distinguish `b` from `B` — match case-sensitively when the
      owning class flags it; Pascal records stay case-insensitive (default). }
    cs := UClsCaseSensFields[curr];
    i := 0;
    while i < cnt do
    begin
      if cs then hit := UNameMatchCS(UFldNOff[base + i], UFldNLen[base + i], name)
      else       hit := UNameMatch(UFldNOff[base + i], UFldNLen[base + i], lo);
      if hit then begin Result := base + i; Exit; end;
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

{ The default indexed property of a class (walking ancestors), or -1. Drives the
  `obj[i]` shorthand. }
function FindDefaultProp(ci: Integer): Integer;
var i, base, cnt, curr: Integer;
begin
  Result := -1;
  curr := ci;
  while curr >= 0 do
  begin
    base := UClsPBase[curr];
    cnt  := UClsPCount[curr];
    i := 0;
    while i < cnt do
    begin
      if UPropIsDefault[base + i] then begin Result := base + i; Exit; end;
      Inc(i);
    end;
    curr := UClsParent[curr];
  end;
end;

function AddUProperty(ci, noff, nlen, tk, recId: Integer): Integer;
var pri: Integer;
begin
  { Overflow here silently corrupts the sibling UProp* parallel arrays (the
    entry spills into the NEXT array's low indices) -- flipping random flags
    like UPropIsIndexed on unrelated properties, order-dependently
    (bug-property-setter-resolution-uses-order). Fail loudly instead. }
  if UPropCount >= MAX_UPROP then Error('too many class properties (MAX_UPROP)');
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
  UPropIsIndexed[pri] := False;
  UPropIsDefault[pri] := False;
  UPropCount := UPropCount + 1;
  UClsPCount[ci] := UClsPCount[ci] + 1;
  Result := pri;
end;

function AddUClass(off, len: Integer): Integer;
begin
  if UClsCount >= MAX_UCLASS then Error('too many classes/records (MAX_UCLASS)');
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
  UClsForward[UClsCount] := False;
  UClsCaseSensFields[UClsCount] := False;
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
var fi, k, src, dst: Integer;
begin
  if UFldCount >= MAX_UFIELD then Error('too many record/class fields (MAX_UFIELD)');
  { Empty window re-base: AddUClass stamps UClsFBase at CLASS-CREATION time, so a
    frontend that creates struct SHELLS up front then fills fields later (rparser's
    two-pass, so a field type can reference another struct) leaves every empty
    class pointing at the then-current tail. The first field of a NON-first shell
    would append at the live tail while UClsFBase still holds a stale earlier index
    — the window then overlaps an earlier class's fields (bug-uclass-field-window-
    stale-base: two field-bearing structs, second reads the first's slot). Re-anchor
    an empty window to the tail before appending. Safe vs the two special cases
    below: both the anonymous-record relocation and the C parser's manual re-anchor
    only fire for FCount>0; an empty window carries no data to move. }
  if UClsFCount[ci] = 0 then UClsFBase[ci] := UFldCount;
  { The field window [UClsFBase[ci] .. +UClsFCount[ci]) must stay contiguous
    (FindUField/RecordHasManagedFields walk it as a range). A nested anonymous
    record type parsed mid-record (feature-anonymous-record-type) mints its
    own UCls row and registers ITS fields between two of ours — when that
    happened, relocate our fields so far to the tail and re-base. }
  { Strictly BEHIND the tail only: the C struct parser re-anchors UClsFBase[ci]
    to the tail before re-appending buffered fields while UClsFCount[ci] still
    holds a previous definition's count — that manual-rebase state (window
    extending PAST the tail) must be left alone. }
  if (UClsFCount[ci] > 0) and (UClsFBase[ci] + UClsFCount[ci] < UFldCount) then
  begin
    if UFldCount + UClsFCount[ci] >= MAX_UFIELD then
      Error('too many record/class fields (MAX_UFIELD)');
    dst := UFldCount;
    for k := 0 to UClsFCount[ci] - 1 do
    begin
      src := UClsFBase[ci] + k;
      UFldNOff[dst+k] := UFldNOff[src];  UFldNLen[dst+k] := UFldNLen[src];
      UFldOff_[dst+k] := UFldOff_[src];  UFldTk[dst+k] := UFldTk[src];
      UFldRec_[dst+k] := UFldRec_[src];  UFldProcSig[dst+k] := UFldProcSig[src];
      UFldElemProcSig[dst+k] := UFldElemProcSig[src];
      UFldAnonRec[dst+k] := UFldAnonRec[src];
      UFldPtrElemTk[dst+k] := UFldPtrElemTk[src];
      UFldPtrElemRec[dst+k] := UFldPtrElemRec[src];
      UFldSetEnumId[dst+k] := UFldSetEnumId[src];
      UFldSetElemTk[dst+k] := UFldSetElemTk[src];
      UFldIsArray[dst+k] := UFldIsArray[src];  UFldArrLen[dst+k] := UFldArrLen[src];
      UFldDynDepth[dst+k] := UFldDynDepth[src];
      UFldArrNDims[dst+k] := UFldArrNDims[src];
      UFldBitWidth[dst+k] := UFldBitWidth[src];
      UFldBitShift[dst+k] := UFldBitShift[src];
      UFldBitBytes[dst+k] := UFldBitBytes[src];
      UFldPub[dst+k] := UFldPub[src];
      for fi := 0 to MAX_ARR_DIMS - 1 do
      begin
        UFldArrDimLo[(dst+k) * MAX_ARR_DIMS + fi]   := UFldArrDimLo[src * MAX_ARR_DIMS + fi];
        UFldArrDimSpan[(dst+k) * MAX_ARR_DIMS + fi] := UFldArrDimSpan[src * MAX_ARR_DIMS + fi];
      end;
    end;
    UClsFBase[ci] := dst;
    UFldCount := UFldCount + UClsFCount[ci];
    if UFldCount >= MAX_UFIELD then Error('too many record/class fields (MAX_UFIELD)');
  end;
  fi := UFldCount;
  UFldNOff[fi] := noff;  UFldNLen[fi] := nlen;
  UFldOff_[fi] := byteOff; UFldTk[fi] := tk; UFldRec_[fi] := recId;
  UFldAnonRec[fi] := REC_NONE;   { anon-promotion marker; C struct parser overrides for flattened anon members }
  { Procedural-type field: remember the signature so `rec.field(args)` can lower
    to an indirect call (LastTypeProcSig set by ParseTypeKind for the field type;
    a plain proc field is tyPointer, a method-pointer field tyRecord). }
  UFldProcSig[fi] := LastTypeProcSig;
  UFldElemProcSig[fi] := -1;   { ptr-to-fn-ptr field sig: C struct builder overrides post-AddUField; Pascal fields never set it }
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
  UFldBitWidth[fi] := 0;
  UFldBitShift[fi] := 0;
  UFldBitBytes[fi] := 0;
  UFldPub[fi] := 0;
  UFldCount := UFldCount + 1;
  UClsFCount[ci] := UClsFCount[ci] + 1;
end;

procedure AddUMeth(ci, noff, nlen, procIdx: Integer);
var mi, k, src, dst: Integer;
begin
  if UMthCount >= MAX_UMETH then Error('too many class/record methods (MAX_UMETH)');
  { The method window [UClsMBase[ci] .. +UClsMCount[ci]) must stay contiguous
    (FindUMeth walks it as a range). A NESTED specialization inside a class
    body (fgl's `TFPGListEnumeratorSpec = specialize ...` class-local type)
    registers ITS methods between two of ours — relocate ours to the tail and
    re-base, mirroring AddUField's window relocation. }
  if (UClsMCount[ci] > 0) and (UClsMBase[ci] + UClsMCount[ci] < UMthCount) then
  begin
    if UMthCount + UClsMCount[ci] >= MAX_UMETH then
      Error('too many class/record methods (MAX_UMETH)');
    dst := UMthCount;
    for k := 0 to UClsMCount[ci] - 1 do
    begin
      src := UClsMBase[ci] + k;
      UMthNOff[dst+k] := UMthNOff[src];
      UMthNLen[dst+k] := UMthNLen[src];
      UMthProc_[dst+k] := UMthProc_[src];
      UMthVirSlot[dst+k] := UMthVirSlot[src];
      UMthIsStatic[dst+k] := UMthIsStatic[src];
      UMthIsCtor[dst+k] := UMthIsCtor[src];
      UMthPub[dst+k] := UMthPub[src];
    end;
    UClsMBase[ci] := dst;
    UMthCount := UMthCount + UClsMCount[ci];
    if UMthCount >= MAX_UMETH then Error('too many class/record methods (MAX_UMETH)');
  end;
  mi := UMthCount;
  UMthNOff[mi] := noff; UMthNLen[mi] := nlen; UMthProc_[mi] := procIdx;
  UMthVirSlot[mi] := -1;
  UMthIsStatic[mi] := False;
  UMthIsCtor[mi] := False;
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
  { MUST track TProc.Params' declared bound in defs.inc. This descriptor is
    what the compiler uses for its OWN TProc when self-compiling; a stale
    count here silently laid out Procs[] with the old extent while code
    written against the new bound overran into BodyAddr and beyond
    (bug-max-proc-params-32-selfmiscompile: Params[16].Name aliased
    BodyAddr = -1 -> AnsiStrRelease(-1) SIGSEGV). NOTE the value is baked
    into the COMPILING binary, so growing MAX_PROC_PARAMS takes an extra
    self-host generation to converge (gen1 mislays its own Procs; gen2+
    are correct) — reseed with the converged binary. }
  if (rec = REC_TPROC) and (idx = 4) then Result := MAX_PROC_PARAMS;
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

{ Procedural-call signature Procs[] index of a (fn-pointer) record field, or -1.
  Used to lower `rec.field(args)` / `p->field(args)` to an indirect call. }
function RecFieldProcSig(rec: Integer; const field: AnsiString): Integer;
var fi: Integer; field2: AnsiString;
begin
  Result := -1; field2 := field;
  if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldProcSig[fi];
  end;
end;

{ Pointee call-signature of a POINTER-to-fn-ptr record field (`ft *pf`), or -1.
  Used to lower `(*s.pf)(args)` to an indirect call through the loaded fn-pointer. }
function RecFieldElemProcSig(rec: Integer; const field: AnsiString): Integer;
var fi: Integer; field2: AnsiString;
begin
  Result := -1; field2 := field;
  if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldElemProcSig[fi];
  end;
end;

function RecFieldBitWidth(rec: Integer; const field: AnsiString): Integer;
var fi: Integer; field2: AnsiString;
begin
  Result := 0; field2 := field;
  if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldBitWidth[fi];
  end;
end;

function RecFieldBitShift(rec: Integer; const field: AnsiString): Integer;
var fi: Integer; field2: AnsiString;
begin
  Result := 0; field2 := field;
  if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldBitShift[fi];
  end;
end;

function RecFieldBitBytes(rec: Integer; const field: AnsiString): Integer;
var fi: Integer; field2: AnsiString;
begin
  Result := 0; field2 := field;
  if rec >= REC_UCLASS_BASE then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldBitBytes[fi];
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

function RecFieldArrLen(rec: Integer; const field: AnsiString): Integer;
{ Element count of a static-array field (>=0); -1 for a dynamic-array field or a
  non-array. Only user-class fields carry a recorded length; builtin records
  return -1 (none are static-array open-array sources). }
var fi: Integer; field2: AnsiString;
begin
  Result := -1; field2 := field;
  if (rec >= REC_UCLASS_BASE) and (BuiltinRecFieldCount(rec) = 0) then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldArrLen[fi];
  end;
end;

function RecFieldArrNDims(rec: Integer; const field: AnsiString): Integer;
{ Dimension count of an array field (1 for a 1-D array); 0 when unknown/non-array. }
var fi: Integer; field2: AnsiString;
begin
  Result := 0; field2 := field;
  if (rec >= REC_UCLASS_BASE) and (BuiltinRecFieldCount(rec) = 0) then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if fi >= 0 then Result := UFldArrNDims[fi];
  end;
end;

function RecFieldArrDimSpanAt(rec: Integer; const field: AnsiString; d: Integer): Integer;
{ Span (element count) of dimension `d` of a multidim array field; 1 if unknown. }
var fi: Integer; field2: AnsiString;
begin
  Result := 1; field2 := field;
  if (rec >= REC_UCLASS_BASE) and (BuiltinRecFieldCount(rec) = 0) then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if (fi >= 0) and (d >= 0) and (d < UFldArrNDims[fi]) then
      Result := UFldArrDimSpan[fi * MAX_ARR_DIMS + d];
  end;
end;

function RecFieldRowStride(rec: Integer; const field: AnsiString): Integer;
{ Byte stride of one OUTER-dimension row of a multidimensional array field
  (product of the inner dim spans * element size); 0 if the field is not a
  recorded multidim array. Used by the C frontend's partial-index row decay:
  `field[i]` (single subscript of an `[N][M]..` field) yields the row address
  `&field + i*RowStride`. }
var fi, d, inner: Integer; field2: AnsiString; etk: TTypeKind;
begin
  Result := 0; field2 := field;
  if (rec >= REC_UCLASS_BASE) and (BuiltinRecFieldCount(rec) = 0) then
  begin
    fi := FindUField(rec - REC_UCLASS_BASE, field2);
    if (fi >= 0) and (UFldArrNDims[fi] >= 2) then
    begin
      inner := 1;
      for d := 1 to UFldArrNDims[fi] - 1 do
        inner := inner * UFldArrDimSpan[fi * MAX_ARR_DIMS + d];
      etk := IntToTypeKind(UFldTk[fi]);
      if etk = tyRecord then
        Result := inner * RecSize(UFldRec_[fi])
      else
        Result := inner * TypeSize(etk);
    end;
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

  { TProc trailing-field offsets scale with the Params bound (frozen TParam =
    296 bytes/element), so express them via MAX_PROC_PARAMS. }
  CheckBuiltinRecSize(REC_TPROC, 288 + MAX_PROC_PARAMS * 296 + 32, 'TProc');
  CheckBuiltinRecField(REC_TPROC, 'Name', 0, tyString, REC_NONE, False);
  CheckBuiltinRecField(REC_TPROC, 'IsFunc', 264, tyBoolean, REC_NONE, False);
  CheckBuiltinRecField(REC_TPROC, 'RetType', 272, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPROC, 'ParamCount', 280, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPROC, 'Params', 288, tyRecord, REC_TPARAM, True);
  CheckBuiltinRecField(REC_TPROC, 'BodyAddr', 288 + MAX_PROC_PARAMS * 296, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPROC, 'FramePatch', 288 + MAX_PROC_PARAMS * 296 + 8, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPROC, 'RetSymIdx', 288 + MAX_PROC_PARAMS * 296 + 16, tyInteger, REC_NONE, False);
  CheckBuiltinRecField(REC_TPROC, 'ScopeBase', 288 + MAX_PROC_PARAMS * 296 + 24, tyInteger, REC_NONE, False);

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

function RecordHasManagedFieldsDepth(recId, depth: Integer): Boolean;
{ Class/object references are deliberately unmanaged. Only recurse through
  fixed-size user records and compiler-managed value fields. The depth cap is a
  robustness backstop: a malformed record that (transitively) contains ITSELF
  by value — which a valid C program can't produce, but a struct-tag
  redefinition bug once did — would otherwise recurse without bound and crash
  the compiler. Past the cap, treat as unmanaged rather than fault. }
var ci, base, cnt, i: Integer;
begin
  Result := False;
  if depth > 64 then Exit;
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
    if (UFldTk[base + i] = Ord(tyRecord)) and (UFldRec_[base + i] <> recId) and
       RecordHasManagedFieldsDepth(UFldRec_[base + i], depth + 1) then
      begin Result := True; Exit; end;
  end;
end;

function RecordHasManagedFields(recId: Integer): Boolean;
begin
  Result := RecordHasManagedFieldsDepth(recId, 0);
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
  else if Syms[i].IsArray and (Syms[i].ArrLen <> -1) and (SymElemDynDepth[i] > 0) then
  begin
    { Fixed array whose elements are dynamic-array handles (`array[..] of TA`):
      each slot must start nil so SetLength on an element does not release a
      garbage "old" handle. }
    zeroBytes := Syms[i].ArrLen * TARGET_PTR_SIZE;
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

function RetViaHiddenDest(tk: TTypeKind): Boolean;
{ Return types whose ABI is a caller-owned hidden destination pointer (NRVO):
  records/sets AND the inline frozen string kinds. The callee copies its Result
  local into [dest] and returns the dest pointer; the caller allocates the
  destination. Frozen strings previously returned a shared BSS-global Result
  address (not reentrant, bug-frozen-string-result-global). A default frozen
  `string` result is capped at LOCAL_STR_CAP (256, the ShortString norm). }
begin
  Result := TypeIsAggregate(tk) or TypeIsFrozenString(tk);
end;

function AggRetCopySize(retSymIdx: Integer): Integer;
{ Byte count copied from the Result local into the caller's hidden destination. }
var tk: TTypeKind;
begin
  tk := Syms[retSymIdx].TypeKind;
  if tk = tyRecord then Result := RecSize(Syms[retSymIdx].RecName)
  else if tk = tyString then Result := LOCAL_STR_CAP + 8
  else if (tk = tyFixedString) or (tk = tyShortString) then
    Result := FrozenStrSlotSize(tk, SymStrCap[retSymIdx])
  else Result := TypeSize(tk);
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

function TypeArithmeticResultOp(lhs, rhs: TTypeKind; op: TTokenKind): TTypeKind;
{ Operator-aware integer promotion, matching FPC's range-based result type.
  Most operators keep the TypeCompareUnsigned widening (e.g. LongWord * LongWord
  can reach ~2^64, so it stays UInt64). SUBTRACTION of unsigned operands can go
  negative, and FPC yields a signed Int64 unless a true 64-bit unsigned operand
  (UInt64/QWord/NativeUInt) forces UInt64 — so `cardinal(3) - cardinal(5)` = -2,
  not 2^64-2, while `qword - qword` stays unsigned. }
begin
  if (op = tkMinus) and (lhs <> tyUInt64) and (rhs <> tyUInt64) and
     (lhs <> tyNativeUInt) and (rhs <> tyNativeUInt) then
    Result := tyInt64
  else
    Result := TypeArithmeticResult(lhs, rhs);
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

{ True if `nm` would resolve to a program/unit GLOBAL that FindSym is currently
  hiding ONLY because of decl-order gating (declared textually later than the
  routine being compiled). Lets undefined-name error sites give a clearer hint.
  Cost is irrelevant — only called on an error path that aborts the compile. }
function HiddenByDeclOrder(const nm: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  if not DeclOrderStrict then Exit;
  for i := SymCount-1 downto 0 do
    if (Syms[i].Kind = skGlobal) and (SymDeclTok[i] > CurBodyHdrTok) and
       IsBlockVisible(SymBlockId[i], CurBlockId) and
       (StrEqual(Syms[i].Name, nm) or
        ((not SymCaseSensitive[i]) and CaseEqual(Syms[i].Name, nm))) then
    begin
      Result := True;
      Exit;
    end;
end;

{ Same fold+FNV, masked to the (larger) symbol bucket count. }
function SymNameFoldHash(const s: AnsiString): Integer;
var i, b: Integer; h: LongWord;
begin
  h := LongWord($811C9DC5);
  for i := 1 to Length(s) do
  begin
    b := Ord(s[i]);
    if (b >= 65) and (b <= 90) then b := b + 32;
    h := (h xor LongWord(b)) * LongWord($01000193);
  end;
  Result := Integer(h and LongWord(SYM_HASH_SIZE - 1));
end;

procedure SymHashReset;
var i: Integer;
begin
  for i := 0 to SYM_HASH_SIZE - 1 do
    SymHashHead[i] := -1;
end;

{ Push a just-registered slot onto its bucket, newest-first. MUST be called at
  the moment the slot becomes visible (the Inc(SymCount) in the Alloc*
  functions), NOT when the name is first assigned — the linear scans were
  bounded by SymCount, so a lookup made while a registration is still filling
  in its fields must not see the in-flight slot. }
procedure SymHashInsert(idx: Integer);
var b: Integer;
begin
  b := SymNameFoldHash(Syms[idx].Name);
  SymHashPrev[idx] := SymHashHead[b];
  SymHashHead[b] := idx;
end;

{ Truncate the symbol table to newCount, unlinking the removed range from the
  hash. Descending order: the highest live idx is always its bucket's current
  head, so each pop is O(1). Replaces bare `SymCount := savedSC` at scope
  exits — a bare truncation would leave dead heads pointing at slots the next
  scope re-registers under different names. }
procedure SymRollbackTo(newCount: Integer);
var i: Integer;
begin
  for i := SymCount - 1 downto newCount do
  begin
    SymHashHead[SymNameFoldHash(Syms[i].Name)] := SymHashPrev[i];
  end;
  SymCount := newCount;
end;

function FindSym(const name: AnsiString): Integer;
var i: Integer; lo: AnsiString;
begin
  lo := name;
  { Inside an FPC named-result operator body the declared result name is an
    alias of Result (feature-pascal-operator-decl-fpc-compat). }
  if (OpResultAlias <> '') and CaseEqual(lo, OpResultAlias) then lo := 'Result';
  { Exact-case match first, innermost scope out (preserves shadowing). A global
    variable declared textually after the current routine is hidden (decl-order
    gating, DeclOrderStrict) so it cannot bind — declare-before-use, FPC-parity.
    Hash chain is NEWEST-first, so walking it is the linear downto order. }
  i := SymHashHead[SymNameFoldHash(lo)];
  while i >= 0 do
  begin
    if StrEqual(Syms[i].Name, lo) and IsBlockVisible(SymBlockId[i], CurBlockId)
       and not (DeclOrderStrict and (Syms[i].Kind = skGlobal) and (SymDeclTok[i] > CurBodyHdrTok)) then
    begin
      if DebugTrace then writeln('FindSym: ', lo, ' -> ', i);
      Result := i;
      Exit;
    end;
    i := SymHashPrev[i];
  end;
  { Case-insensitive fallback for case-insensitive symbols only (same folded
    bucket holds every case variant). }
  i := SymHashHead[SymNameFoldHash(lo)];
  while i >= 0 do
  begin
    if (not SymCaseSensitive[i]) and CaseEqual(Syms[i].Name, lo) and
       IsBlockVisible(SymBlockId[i], CurBlockId)
       and not (DeclOrderStrict and (Syms[i].Kind = skGlobal) and (SymDeclTok[i] > CurBodyHdrTok)) then
    begin
      if DebugTrace then writeln('FindSym: ', lo, ' -> ', i, ' (ci)');
      Result := i;
      Exit;
    end;
    i := SymHashPrev[i];
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

function FindUnitOrAlias(const name: AnsiString): Integer;
{ Like FindCompiledUnit, but also resolves a `uses .. as alias` name to the REAL
  unit's Strs[] index (symbols are tagged with that index, so the qualifier must
  match it — feature-uses-alias-as). }
var i, j: Integer; lo: AnsiString;
begin
  Result := FindCompiledUnit(name);
  if Result >= 0 then Exit;
  lo := name;
  for j := 1 to Length(lo) do
    if lo[j] in ['A'..'Z'] then lo[j] := Chr(Ord(lo[j]) + 32);
  for i := 0 to UnitAliasCount - 1 do
    if Strs[UnitAliasName[i]].Text = lo then
    begin
      Result := UnitAliasReal[i];
      Exit;
    end;
  Result := -1;
end;

function FindSymInUnit(const name: AnsiString; unitIdx: Integer): Integer;
var i: Integer;
begin
  i := SymHashHead[SymNameFoldHash(name)];
  while i >= 0 do
  begin
    if (SymUnitIdx[i] = unitIdx) and StrEqual(Syms[i].Name, name) then
    begin
      Result := i;
      Exit;
    end;
    i := SymHashPrev[i];
  end;
  i := SymHashHead[SymNameFoldHash(name)];
  while i >= 0 do
  begin
    if (SymUnitIdx[i] = unitIdx) and (not SymCaseSensitive[i]) and
       CaseEqual(Syms[i].Name, name) then
    begin
      Result := i;
      Exit;
    end;
    i := SymHashPrev[i];
  end;
  Result := -1;
end;

procedure StampDeclSeq(symIdx: Integer);
{ Record a program/unit global var's declaration token so FindSym can hide it from
  routines whose body is positioned before it (declare-before-use for globals,
  FPC-parity). Locals/params/consts/types are not skGlobal, so they are never
  stamped and stay visible as before. Only source-order globals registered during
  the declaration pre-scan are gated; synthetic globals allocated while compiling a
  body (e.g. the string-Result slot) run with PreScanPass=False and stay visible. }
begin
  if PreScanPass and (Syms[symIdx].Kind = skGlobal) then
    { Record the declaration's SOffset (immutable char-pool position, monotonic in
      lex/source order), NOT the token INDEX: token indices are renumbered by pass-2
      excisions/inserts while SOffsets never move, keeping decl-order stable — see
      the CurBodyHdrTok note in ParseSubroutine (bug-impl-prescan-late-include-var-section). }
    SymDeclTok[symIdx] := Tokens[TokPos].SOffset;
end;

function AllocVar(const name: AnsiString; tk: TTypeKind): Integer;
var sz, align: Integer;
begin
  if SymCount >= MAX_SYMS then Error('too many symbols');
  Syms[SymCount].Name     := name;
  Syms[SymCount].TypeKind := tk;
  Syms[SymCount].ConstVal := 0;
  SymCLongRank[SymCount]  := 0;
  Syms[SymCount].IsArray  := False;
  Syms[SymCount].ArrLen   := 0;
  SymDynDepth[SymCount] := 0;
  SymElemDynDepth[SymCount] := 0;
  SymArrNDims[SymCount] := 0;
  SymGenSlot[SymCount] := -1;
  SymProcSig[SymCount] := -1;
  SymElemProcSig[SymCount] := -1;
  SymSetEnumId[SymCount] := -1;
  SymEnumId[SymCount] := -1;
  SymSetElemTk[SymCount] := 0;
  SymStrCap[SymCount] := 0;
  SymPtrDepth[SymCount] := 0;
  SymPtrBaseTk[SymCount] := Ord(tyUnknown);
  SymPtrBaseRec[SymCount] := REC_NONE;
  SymPtrElemArrLen[SymCount] := 0;
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
    SymPtrDepth[SymCount] := LastTypePointerDepth;
    SymPtrBaseTk[SymCount] := LastTypePointerBaseTk;
    SymPtrBaseRec[SymCount] := LastTypePointerBaseRec;
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
      { A NAMED global frozen string reserves the full capacity (it may hold any
        string / be reset). A hidden temp (name = '', e.g. a concat result
        materialised as a call argument in the main body) never needs 8 MB — give
        it the bounded local capacity, like the same temp inside a procedure
        (bug-ansistring-concat-arg-static-bloat: each such main-scope site
        otherwise reserved ~8 MB of BSS). }
      if (CurProc < 0) and (name <> '') then sz := STRING_CAP + 8
      else sz := LOCAL_STR_CAP + 8;
    end
    else if (tk = tyFixedString) or (tk = tyShortString) then
      sz := FrozenStrSlotSize(tk, SymStrCap[SymCount])
    else if tk = tyRecord then sz := RecSize(LastTypeRecId);
    if (tk = tyRecord) and (LastTypeRecId >= REC_UCLASS_BASE) and
       (UClsAlign[LastTypeRecId - REC_UCLASS_BASE] > TARGET_PTR_SIZE) then
      align := UClsAlign[LastTypeRecId - REC_UCLASS_BASE]
    else
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
  Result := SymCount; SymHashInsert(Result); Inc(SymCount); StampDeclSeq(Result);
end;

function ParamSize(idx: Integer): Integer;
begin
  if Syms[idx].IsRef or Syms[idx].IsArray or (Syms[idx].TypeKind = tyString) or
     (Syms[idx].TypeKind = tyRecord) or
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
  SymElemDynDepth[SymCount] := 0;
  { Reset recycled parallel-array fields — a stale SymArrNDims >= 2 from a
    popped local reappearing under a new symbol at the same slot made a 1-D
    named-array param index with the old N-D dims (silent stride corruption;
    bug-transitive-dns_cache-import-corrupts-managed-strings). }
  SymArrNDims[SymCount] := 0;
  { Same recycled-slot landmine for the lazy-var block id: a param reusing the
    slot of a popped MID-BLOCK local (an on-handler binder, a lifted temp)
    inherited that dead block and IsBlockVisible filtered the param out of
    FindSym — every routine following a `try..except on E: ... do` lost its
    params (blcksock's SetLinger, bug-on-handler-poisons-next-proc-params). }
  SymBlockId[SymCount] := CurBlockId;
  SymGenSlot[SymCount] := -1;
  SymProcSig[SymCount] := -1;
  SymElemProcSig[SymCount] := -1;
  SymSetEnumId[SymCount] := -1;
  SymEnumId[SymCount] := -1;
  SymSetElemTk[SymCount] := 0;
  SymStrCap[SymCount] := 0;
  SymPtrDepth[SymCount] := 0;
  SymPtrBaseTk[SymCount] := Ord(tyUnknown);
  SymPtrBaseRec[SymCount] := REC_NONE;
  SymPtrElemArrLen[SymCount] := 0;
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
    SymPtrDepth[SymCount] := LastTypePointerDepth;
    SymPtrBaseTk[SymCount] := LastTypePointerBaseTk;
    SymPtrBaseRec[SymCount] := LastTypePointerBaseRec;
  end;

  if (tk = tyRecord) and not isRef and not isArray and (RecSize(LastTypeRecId) <= 8) then
  begin
    { A genuinely by-value record (not var/const/out, not forced to by-ref by
      size -- that only happens for RecSize > 8) is stored inline in this
      param's own slot, not behind a pointer -- so the slot must hold the
      whole record, not just one machine word. On a 64-bit target
      TARGET_PTR_SIZE (8) already covers any RecSize <= 8, so this is a
      no-op there; on a 32-bit target (TARGET_PTR_SIZE = 4) a 5-8 byte
      record previously got only a 4-byte slot, so writing its second word
      (e.g. the arm32 by-value record-arg fix in ir_codegen_arm32.inc /
      parser.inc's prologue spill) silently overflowed into whatever symbol's
      slot happened to sit right after it
      (bug-arm32-record-byvalue-over-4-bytes-abi-gap). Never smaller than
      TARGET_PTR_SIZE, matching the existing tiny-record (<=4-byte) case. }
    sz := RecSize(LastTypeRecId);
    if sz < TARGET_PTR_SIZE then sz := TARGET_PTR_SIZE;
  end
  else if isRef or isArray or (tk = tyString) or (tk = tyRecord) or (tk = tyVariant) or (tk = tyClass) or (tk = tyPointer) then
    sz := TARGET_PTR_SIZE
  else
    sz := TypeSize(tk);

  if isRef or isArray or (tk = tyString) or (tk = tyRecord) or (tk = tyVariant) or (tk = tyClass) or (tk = tyPointer) then
    align := TARGET_PTR_SIZE
  else
    align := TypeAlign(tk);
  FrameSize := AlignTo(FrameSize + sz, align);
  Syms[SymCount].Offset := -FrameSize;
  Result := SymCount; SymHashInsert(Result); Inc(SymCount); StampDeclSeq(Result);
end;

function AllocArray(const name: AnsiString; elemType: TTypeKind; lo, hi: Integer): Integer;
var elemSize, totalSize, align: Integer;
begin
  if SymCount >= MAX_SYMS then Error('too many symbols');
  if LastTypeElemDynDepth > 0 then
  begin
    { Element is itself a dynamic array (`array[..] of TDynAlias`): each slot holds
      a pointer-sized heap handle. The base element type/rec stay in
      elemType/LastTypeRecId; SymElemDynDepth (set below) marks the slots dynamic. }
    elemSize := TARGET_PTR_SIZE;
    align := TARGET_PTR_SIZE;
  end
  else if elemType = tyString then
  begin
    if CurProc < 0 then elemSize := STRING_CAP + 8
    else elemSize := LOCAL_STR_CAP + 8;
    align := TARGET_PTR_SIZE;
  end
  else if (elemType = tyFixedString) or (elemType = tyShortString) then
  begin
    elemSize := FrozenStrSlotSize(elemType, LastTypeStrCap);
    align := TARGET_PTR_SIZE;
  end
  else if elemType = tyRecord then
  begin
    elemSize := RecSize(LastTypeRecId);
    if (LastTypeRecId >= REC_UCLASS_BASE) and
       (UClsAlign[LastTypeRecId - REC_UCLASS_BASE] > TARGET_PTR_SIZE) then
      align := UClsAlign[LastTypeRecId - REC_UCLASS_BASE]
    else
      align := TARGET_PTR_SIZE;
  end
  else
  begin
    elemSize := TypeSize(elemType);
    align := TypeAlign(elemType);
  end;

  totalSize := (hi - lo + 1) * elemSize;
  Syms[SymCount].Name     := name;
  Syms[SymCount].TypeKind := elemType;
  Syms[SymCount].ConstVal := lo;   { lo bound stored in ConstVal }
  Syms[SymCount].IsArray  := True;
  Syms[SymCount].ArrLen   := hi - lo + 1;
  SymDynDepth[SymCount] := 0;
  SymElemDynDepth[SymCount] := LastTypeElemDynDepth;
  SymArrNDims[SymCount] := 0;
  SymProcSig[SymCount] := -1;
  SymElemProcSig[SymCount] := -1;
  SymRTTIOff[SymCount] := -1;
  { Match AllocVar: reset recycled parallel-array fields (see AllocDynArray). }
  SymGenSlot[SymCount] := -1;
  SymSetEnumId[SymCount] := -1;
  SymEnumId[SymCount] := -1;
  SymSetElemTk[SymCount] := 0;
  SymStrCap[SymCount] := 0;
  SymPtrDepth[SymCount] := 0;
  SymPtrBaseTk[SymCount] := Ord(tyUnknown);
  SymPtrBaseRec[SymCount] := REC_NONE;
  SymPtrElemArrLen[SymCount] := 0;
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
    SymPtrDepth[SymCount] := LastTypePointerDepth;
    SymPtrBaseTk[SymCount] := LastTypePointerBaseTk;
    SymPtrBaseRec[SymCount] := LastTypePointerBaseRec;
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
  LastTypeElemDynDepth := 0;   { consumed }
  Result := SymCount; SymHashInsert(Result); Inc(SymCount); StampDeclSeq(Result);
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
  SymElemDynDepth[SymCount] := 0;
  SymArrNDims[SymCount] := 0;
  SymProcSig[SymCount] := -1;
  SymElemProcSig[SymCount] := -1;
  SymRTTIOff[SymCount] := -1;
  { Reset the same recycled parallel-array fields AllocVar does — symbol slots
    are reused after a proc body restores SymCount, so a stale SymBlockId here
    would make a dyn-array global declared after a method (whose for-in/locals
    occupied this slot) invisible to FindSym ('undefined variable'). }
  SymGenSlot[SymCount] := -1;
  SymSetEnumId[SymCount] := -1;
  SymEnumId[SymCount] := -1;
  SymSetElemTk[SymCount] := 0;
  SymStrCap[SymCount] := 0;
  SymPtrDepth[SymCount] := 0;
  SymPtrBaseTk[SymCount] := Ord(tyUnknown);
  SymPtrBaseRec[SymCount] := REC_NONE;
  SymPtrElemArrLen[SymCount] := 0;
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
    SymPtrDepth[SymCount] := LastTypePointerDepth;
    SymPtrBaseTk[SymCount] := LastTypePointerBaseTk;
    SymPtrBaseRec[SymCount] := LastTypePointerBaseRec;
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
  Result := SymCount; SymHashInsert(Result); Inc(SymCount); StampDeclSeq(Result);
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
  Syms[SymCount].IsArray  := False;
  Syms[SymCount].ArrLen   := 0;
  SymArrNDims[SymCount] := 0;   { slot recycling — see AllocParam }
  SymBlockId[SymCount] := CurBlockId;   { slot recycling — see AllocParam }
  SymCaseSensitive[SymCount] := CaseSensitiveMode;
  SymUnitIdx[SymCount] := CurrentUnitIdx;
  Result := SymCount; SymHashInsert(Result); Inc(SymCount); StampDeclSeq(Result);
end;

{ ===== Variable load/store ===== }

{ Register calling convention (feature-callconv-register-args, -O2 x86-64): if
  idx is a param currently resident in r14/r15, return that register number (14
  or 15), else 0. O(RcResidentCount<=2). Non-x86-64 and -O0/-O1 keep the count at
  0, so this always returns 0 there and the residency emit paths never fire. }
function ResidentRegOf(idx: Integer): Integer;
var k: Integer;
begin
  ResidentRegOf := 0;
  for k := 0 to RcResidentCount - 1 do
    if RcResidentSym[k] = idx then
    begin
      ResidentRegOf := RcResidentReg[k];
      Exit;
    end;
end;

{ -O3 float loop residency (x86-64): if idx is a tyDouble local/param currently
  resident in xmm8/xmm9, return that xmm number (8 or 9), else 0. Only bodies
  proven call-free enable this (FloatResidencyAssign), so the caller-saved
  registers are never clobbered mid-body. }
function FloatResidentXmmOf(idx: Integer): Integer;
var k: Integer;
begin
  FloatResidentXmmOf := 0;
  for k := 0 to FrResidentCount - 1 do
    if FrResidentSym[k] = idx then
    begin
      FloatResidentXmmOf := 8 + k;
      Exit;
    end;
end;

procedure EmitLoadVar(idx: Integer);
var tk: TTypeKind; sz: Integer; sgn: Boolean; rreg: Integer;
begin
  { Resident param read: mov rax, r14/r15 (the frame slot is authoritative but the
    register is a same-value cache — a correctly size/sign-extended value was
    loaded into it at body entry, and every store re-extends it). }
  rreg := ResidentRegOf(idx);
  if rreg <> 0 then
  begin
    EmitB($4C); EmitB($89); EmitB($C0 or ((rreg - 8) shl 3));         { mov rax, r12..r15 }
    Exit;
  end;
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);
  sgn := TypeSigned(tk);

  if TypeIsFloat(tk) then
  begin
    { -O3 float loop residency: the value lives in xmm8/xmm9 (call-free body,
      tyDouble only — see FloatResidencyAssign). Same contract as a frame
      load: value in xmm0. }
    rreg := FloatResidentXmmOf(idx);
    if rreg <> 0 then
    begin
      EmitB($41); EmitB($0F); EmitB($28); EmitB($C0 or (rreg - 8));  { movaps xmm0, xmm8/xmm9 }
      Exit;
    end;
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

{ -O1 pass 2 (leaf-sym operand direct load): load a plain scalar local/param/
  global straight into RCX, so a BINOP right operand that is a side-effect-free
  IR_LOAD_SYM skips the push-left / eval-right-into-rax / mov rcx,rax / pop-rax
  dance. Mirrors EmitLoadVar's scalar else-branch byte-for-byte with the reg
  field switched rax(000)->rcx(001): [rbp+disp] ModRM 85->8D, [abs] ModRM+SIB
  04 25->0C 25, mov eax->mov ecx (8B). Guarded by LeafSymRcxLoadable, which
  admits only skLocal/skParam(non-ref)/skGlobal non-float, non-string,
  non-array scalars — every managed/float/by-ref/frozen path stays on the
  general push/pop route untouched. }
function LeafSymRcxLoadable(node: Integer): Boolean;
var idx: Integer; tk: TTypeKind;
begin
  LeafSymRcxLoadable := False;
  if IRKind[node] <> IR_LOAD_SYM then Exit;
  idx := IRA[node];
  if Syms[idx].IsArray then Exit;
  tk := Syms[idx].TypeKind;
  if TypeIsFloat(tk) then Exit;
  if (tk = tyString) or (tk = tyAnsiString) then Exit;
  if TypeIsFrozenString(tk) then Exit;
  if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then Exit;
  case Syms[idx].Kind of
    skLocal, skParam, skGlobal: LeafSymRcxLoadable := True;
  end;
end;

{ -O3 W1 operand scheduler (x86-64): is this value subtree PROVEN safe to emit
  while a live value is parked in r8/r9 — and free of observable side effects
  (so it may also be emitted before, instead of after, a leaf left operand)?
  Whitelist of IR kinds whose x86-64 emission touches only rax/rcx/rdx/xmm0/
  xmm1 (+cl shifts), performs no call and no store. Everything not listed is
  UNSAFE by default, so a new IR op stays on the push/pop path until someone
  proves it here. Deliberate exclusions with reasons:
  - IR_BINOP op=tkIn: its emit code uses r8 as a scratch (bit-index mask).
  - string-typed BINOPs (operands or result): AnsiString concat/compare CALL
    runtime helpers (clobber all caller-saved); frozen tyString concat inlines
    a copy loop through rsi/rdi/rdx/r8/r10/r11.
  - IR_CALL / IR_CALL_IND / IR_VIRTUAL_CALL: calls clobber r8-r11 — and a call
    is the side effect the mirror reorder must never move across.
  - IR_DYNUNIQUE / anything InLValueWrite-sensitive that can call (COW clone):
    both transform sites additionally gate on `not InLValueWrite`, and the
    IR_INDEX read paths admitted here emit plain derefs only. }
function ScratchSafeSubtree(node: Integer): Boolean;
var op: TTokenKind; nt, lt, rt: TTypeKind;
begin
  ScratchSafeSubtree := False;
  if node < 0 then Exit;
  case IRKind[node] of
    IR_CONST_INT, IR_CONST_STR, IR_CONST_DATA,
    IR_LOAD_SYM, IR_LEA, IR_SLOTADDR, IR_DYNDATA:
      ScratchSafeSubtree := True;
    IR_NEG, IR_NOT, IR_FIELD, IR_LOAD_MEM:
      ScratchSafeSubtree := ScratchSafeSubtree(IRA[node]);
    IR_INDEX:
      ScratchSafeSubtree := ScratchSafeSubtree(IRA[node]) and
                            ScratchSafeSubtree(IRB[node]);
    IR_BINOP:
      begin
        op := IntToTokenKind(IRC[node]);
        if op = tkIn then Exit;
        nt := IntToTypeKind(IRTk[node]);
        lt := IntToTypeKind(IRTk[IRA[node]]);
        rt := IntToTypeKind(IRTk[IRB[node]]);
        if (nt = tyAnsiString) or TypeIsFrozenString(nt) or (nt = tyVariant) then Exit;
        if (lt = tyAnsiString) or TypeIsFrozenString(lt) or (lt = tyVariant) or (lt = tySet) then Exit;
        if (rt = tyAnsiString) or TypeIsFrozenString(rt) or (rt = tyVariant) or (rt = tySet) then Exit;
        ScratchSafeSubtree := ScratchSafeSubtree(IRA[node]) and
                              ScratchSafeSubtree(IRB[node]);
      end;
  end;
end;

procedure EmitLoadVarRcx(idx: Integer);
var tk: TTypeKind; sz: Integer; sgn: Boolean; rreg: Integer;
begin
  { Resident param direct-load into rcx: mov rcx, r14/r15. }
  rreg := ResidentRegOf(idx);
  if rreg <> 0 then
  begin
    EmitB($4C); EmitB($89); EmitB($C1 or ((rreg - 8) shl 3));         { mov rcx, r12..r15 }
    Exit;
  end;
  tk := Syms[idx].TypeKind;
  sz := TypeSize(tk);
  sgn := TypeSigned(tk);
  case Syms[idx].Kind of
    skLocal, skParam:
      begin
        if sz = 1 then
        begin
          if sgn then
            begin EmitB($48); EmitB($0F); EmitB($BE); EmitB($8D); EmitI32(Syms[idx].Offset); end
          else
            begin EmitB($48); EmitB($0F); EmitB($B6); EmitB($8D); EmitI32(Syms[idx].Offset); end;
        end
        else if sz = 2 then
        begin
          if sgn then
            begin EmitB($48); EmitB($0F); EmitB($BF); EmitB($8D); EmitI32(Syms[idx].Offset); end
          else
            begin EmitB($48); EmitB($0F); EmitB($B7); EmitB($8D); EmitI32(Syms[idx].Offset); end;
        end
        else if sz = 4 then
        begin
          if sgn then
            begin EmitB($48); EmitB($63); EmitB($8D); EmitI32(Syms[idx].Offset); end
          else
            begin EmitB($8B); EmitB($8D); EmitI32(Syms[idx].Offset); end;
        end
        else
          begin EmitB($48); EmitB($8B); EmitB($8D); EmitI32(Syms[idx].Offset); end;
      end;
    skGlobal:
      begin
        if sz = 1 then
        begin
          if sgn then
            begin EmitB($48); EmitB($0F); EmitB($BE); EmitB($0C); EmitB($25); EmitGlobRef(Syms[idx].Offset); end
          else
            begin EmitB($48); EmitB($0F); EmitB($B6); EmitB($0C); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
        end
        else if sz = 2 then
        begin
          if sgn then
            begin EmitB($48); EmitB($0F); EmitB($BF); EmitB($0C); EmitB($25); EmitGlobRef(Syms[idx].Offset); end
          else
            begin EmitB($48); EmitB($0F); EmitB($B7); EmitB($0C); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
        end
        else if sz = 4 then
        begin
          if sgn then
            begin EmitB($48); EmitB($63); EmitB($0C); EmitB($25); EmitGlobRef(Syms[idx].Offset); end
          else
            begin EmitB($8B); EmitB($0C); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
        end
        else
          begin EmitB($48); EmitB($8B); EmitB($0C); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
      end;
  end;
end;

{ Reload a resident param's frame slot into its r14/r15 cache with the canonical
  size/sign extension (by temporarily de-listing it so EmitLoadVar reads memory).
  Called after a store to keep the register byte-equal to a fresh load. }
procedure RegcallRefreshResident(idx: Integer);
var k, rreg, saved: Integer;
begin
  rreg := 0; saved := -1;
  for k := 0 to RcResidentCount - 1 do
    if RcResidentSym[k] = idx then begin rreg := RcResidentReg[k]; saved := k; Break; end;
  if rreg = 0 then Exit;
  RcResidentSym[saved] := -1;      { de-list: force a frame load }
  EmitLoadVar(idx);                { rax = re-extended value from the frame slot }
  RcResidentSym[saved] := idx;     { re-list }
  EmitB($49); EmitB($89); EmitB($C0 or (rreg - 8));                 { mov r12..r15, rax }
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
    { -O3 float loop residency dual-write: the frame slot was just written from
      xmm0; mirror the value into the resident xmm8/xmm9 cache. tyDouble only
      (no narrowing happened above), so register == a fresh frame load. }
    if FloatResidentXmmOf(idx) <> 0 then
    begin
      EmitB($44); EmitB($0F); EmitB($28);
      EmitB($C0 or ((FloatResidentXmmOf(idx) - 8) shl 3));  { movaps xmm8/xmm9, xmm0 }
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
  { Resident param dual-write (feature-callconv-register-args): the frame slot
    was just written above; refresh the r14/r15 cache so it stays byte-equal to a
    fresh load. Reload through EmitLoadVar (with this sym temporarily de-listed so
    it reads the frame, not the stale register) to reuse the exact size/sign
    extension every other load applies, then copy into the resident register. }
  if ResidentRegOf(idx) <> 0 then
    RegcallRefreshResident(idx);
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
  if (Syms[idx].Kind = skParam) and TypeIsFrozenString(Syms[idx].TypeKind) then
  begin
    { param slot holds pointer P; length at [P], data at P+8. ALL frozen
      string kinds — the `= tyString` key missed tyFixedString/tyShortString
      params, which then read the slot as an inline string and dumped wild
      memory (bug-pascal-writeln-shortstring-param). }
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
  MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;
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
var inRangePatch, doneOutPatch: Integer;
begin
  { On entry: rax = argv index. Copy argv[rax] C-string to global string dstIdx. }
  { Bounds check: an out-of-range index (>= argc, or negative) yields '' rather
    than dereferencing a NULL/out-of-bounds argv slot (which segfaulted). argc is
    at [initial_rsp]. }
  EmitB($48); EmitB($8B); EmitB($0C); EmitB($25); EmitGlobRef(BSS_INITIAL_RSP);  { mov rcx, [initial_rsp] }
  EmitB($48); EmitB($8B); EmitB($09);               { mov rcx, [rcx] = argc }
  EmitB($48); EmitB($39); EmitB($C8);               { cmp rax, rcx }
  EmitB($72); inRangePatch := CodeLen; EmitB(0);    { jb in_range (unsigned: 0<=index<argc) }
  EmitB($48); EmitB($31); EmitB($C0);               { xor rax, rax }
  EmitStoreStrLen(dstIdx);                           { dst := '' }
  EmitB($EB); doneOutPatch := CodeLen; EmitB(0);    { jmp done }
  Code[inRangePatch] := Byte(CodeLen - (inRangePatch + 1));
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
  Code[doneOutPatch] := Byte(CodeLen - (doneOutPatch + 1));
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

procedure EmitAnsiStrCmp3Reg(op: TTokenKind; lhsTk, rhsTk: TTypeKind);
{ Lexicographic ordering for managed strings (tyAnsiString / tyString).
  rax = LHS handle, rcx = RHS handle.  Sets rax := 0/1 per op (< <= > >=).
  Mirrors EmitAnsiStrCmpReg's loading prologue, then a min-length repe cmpsb
  with a length tie-break, then an unsigned setcc. }
var pLhsNil, pLhsDone, pRhsNil, pRhsDone, pMinOk, pLenCmp, pSetcc: Integer;
begin
  { --- Load LHS (rax) -> rsi (chars), rdx (len) --- }
  if lhsTk = tyAnsiString then
  begin
    EmitB($48); EmitB($85); EmitB($C0);             { test rax, rax }
    EmitB($74); pLhsNil := CodeLen; EmitB(0);       { jz lhs_nil }
    EmitB($48); EmitB($89); EmitB($C6);             { mov rsi, rax }
    EmitB($48); EmitB($8B); EmitB($50); EmitB($F8); { mov rdx, [rax-8] }
    EmitB($EB); pLhsDone := CodeLen; EmitB(0);      { jmp lhs_done }
    Code[pLhsNil] := Byte(CodeLen - (pLhsNil + 1));
    EmitB($31); EmitB($F6);                         { xor esi, esi }
    EmitB($31); EmitB($D2);                         { xor edx, edx }
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
    EmitB($48); EmitB($85); EmitB($C9);             { test rcx, rcx }
    EmitB($74); pRhsNil := CodeLen; EmitB(0);       { jz rhs_nil }
    EmitB($48); EmitB($89); EmitB($CF);             { mov rdi, rcx }
    EmitB($4C); EmitB($8B); EmitB($41); EmitB($F8); { mov r8, [rcx-8] }
    EmitB($EB); pRhsDone := CodeLen; EmitB(0);      { jmp rhs_done }
    Code[pRhsNil] := Byte(CodeLen - (pRhsNil + 1));
    EmitB($31); EmitB($FF);                         { xor edi, edi }
    EmitB($45); EmitB($31); EmitB($C0);             { xor r8d, r8d }
    Code[pRhsDone] := Byte(CodeLen - (pRhsDone + 1));
  end
  else
  begin
    EmitB($48); EmitB($8D); EmitB($79); EmitB($08); { lea rdi, [rcx+8] }
    EmitB($4C); EmitB($8B); EmitB($01);             { mov r8, [rcx] }
  end;

  { --- minlen in rcx --- }
  EmitB($48); EmitB($89); EmitB($D1);               { mov rcx, rdx }
  EmitB($4C); EmitB($39); EmitB($C1);               { cmp rcx, r8 }
  EmitB($76); pMinOk := CodeLen; EmitB(0);          { jbe min_ok }
  EmitB($4C); EmitB($89); EmitB($C1);               { mov rcx, r8 }
  Code[pMinOk] := Byte(CodeLen - (pMinOk + 1));     { min_ok: }
  EmitB($48); EmitB($85); EmitB($C9);               { test rcx, rcx }
  EmitB($74); pLenCmp := CodeLen; EmitB(0);         { jz len_cmp }
  EmitB($F3); EmitB($A6);                           { repe cmpsb }
  EmitB($75); pSetcc := CodeLen; EmitB(0);          { jne set_cc (flags = lhs-rhs) }
  Code[pLenCmp] := Byte(CodeLen - (pLenCmp + 1));   { len_cmp: }
  EmitB($4C); EmitB($39); EmitB($C2);               { cmp rdx, r8 }
  Code[pSetcc] := Byte(CodeLen - (pSetcc + 1));     { set_cc: }
  case op of
    tkLt: begin EmitB($0F); EmitB($92); EmitB($C0); end;  { setb }
    tkLe: begin EmitB($0F); EmitB($96); EmitB($C0); end;  { setbe }
    tkGt: begin EmitB($0F); EmitB($97); EmitB($C0); end;  { seta }
    tkGe: begin EmitB($0F); EmitB($93); EmitB($C0); end;  { setae }
  end;
  EmitB($48); EmitB($0F); EmitB($B6); EmitB($C0);   { movzx rax, al }
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

{ FNV-1a over the case-folded name. $811C9DC5 / $01000193 are the published
  32-bit FNV offset-basis and prime (avalanche constants, NOT integer limits);
  the LongWord multiply wraps mod 2^32 by design. Result masked to the
  power-of-two bucket count. }
function NameFoldHash(const s: AnsiString): Integer;
var i, b: Integer; h: LongWord;
begin
  h := LongWord($811C9DC5);
  for i := 1 to Length(s) do
  begin
    b := Ord(s[i]);
    if (b >= 65) and (b <= 90) then b := b + 32;   { fold A..Z }
    h := (h xor LongWord(b)) * LongWord($01000193);
  end;
  Result := Integer(h and LongWord(PROC_HASH_SIZE - 1));
end;

procedure ProcHashReset;
var i: Integer;
begin
  for i := 0 to PROC_HASH_SIZE - 1 do
  begin
    ProcHashHead[i] := -1;
    ProcHashTail[i] := -1;
  end;
end;

{ Append idx to its bucket's FIFO chain. Called once per RegisterProc; proc
  names are immutable after registration, so the index never goes stale. }
procedure ProcHashInsert(idx: Integer);
var b: Integer;
begin
  b := NameFoldHash(Procs[idx].Name);
  ProcHashNext[idx] := -1;
  if ProcHashHead[b] < 0 then
    ProcHashHead[b] := idx
  else
    ProcHashNext[ProcHashTail[b]] := idx;
  ProcHashTail[b] := idx;
end;

{ First candidate (registration order) for a name; walk via ProcHashNext.
  The chain holds every proc with the same FOLDED name (plus rare unrelated
  collisions) — callers still do their own exact/CaseEqual compare. }
function ProcChainHead(const name: AnsiString): Integer;
begin
  Result := ProcHashHead[NameFoldHash(name)];
end;

function FindProc(const name: AnsiString): Integer;
var i: Integer; lo: AnsiString;
begin
  lo := name;
  { Exact-case match first — always, and the only path for case-sensitive
    symbols (C imports, or Pascal in case-sensitive mode). Hash-chain walk
    (FIFO = registration order) replaces the full linear scan; same result. }
  i := ProcChainHead(lo);
  while i >= 0 do
  begin
    if Procs[i].Name = lo then begin Result := i; Exit; end;
    i := ProcHashNext[i];
  end;
  { Case-insensitive fallback for case-insensitive symbols only (default Pascal).
    First match wins; ambiguity refinement (warn) is future work. External
    (C-import) symbols are excluded: a C linker symbol IS case-sensitive
    (`printf` <> `Printf`), so they match exact-only by default and relax only
    under {$LAZYCASING ON} below. Same chain: folded-name buckets hold every
    case variant. }
  i := ProcChainHead(lo);
  while i >= 0 do
  begin
    if (not ProcCaseSensitive[i]) and (not ProcExternal[i]) and
       CaseEqual(Procs[i].Name, lo) then
    begin Result := i; Exit; end;
    i := ProcHashNext[i];
  end;
  { LAZYCASING fallback: only for C-import symbols (external), only when the
    switch is on, and only when EXACTLY ONE matches case-insensitively. Resolves
    to that proc's exact declared spelling (ELF linkage is unaffected) and warns
    so the case mismatch stays visible. Ambiguous -> error. Never reached by
    ordinary Pascal procs (they are not external). }
  if LazyCasing then
  begin
    Result := -1;
    for i := 0 to ProcCount-1 do
      if ProcExternal[i] and CaseEqual(Procs[i].Name, lo) then
      begin
        if Result >= 0 then
          Error('lazycasing: ambiguous case-insensitive match for ''' + name +
                ''' (''' + Procs[Result].Name + ''' vs ''' + Procs[i].Name + ''')');
        Result := i;
      end;
    if Result >= 0 then
    begin
      Warn('lazycasing: ''' + name + ''' resolved to C import ''' +
           Procs[Result].Name + ''' (case mismatch)');
      Exit;
    end;
  end;
  Result := -1;
end;

{ Canonicalize a C-import call name to the exact declared spelling under
  {$LAZYCASING ON}. Returns `name` unchanged when the switch is off, when a proc
  already matches exactly, or when no external symbol matches case-insensitively.
  Ambiguity (>1 external match) is an error. Silent — the user-facing warning is
  emitted once by FindProc during call classification; this only rebinds the
  name so MatchProcCall's exact-name phases find the proc. }
function LazyCanonName(const name: AnsiString): AnsiString;
var i, found: Integer;
begin
  Result := name;
  if not LazyCasing then Exit;
  for i := 0 to ProcCount-1 do
    if Procs[i].Name = name then Exit;            { exact match exists: no rebind }
  found := -1;
  for i := 0 to ProcCount-1 do
    if ProcExternal[i] and CaseEqual(Procs[i].Name, name) then
    begin
      if found >= 0 then
        Error('lazycasing: ambiguous case-insensitive match for ''' + name +
              ''' (''' + Procs[found].Name + ''' vs ''' + Procs[i].Name + ''')');
      found := i;
    end;
  if found >= 0 then Result := Procs[found].Name;
end;

function FindProcInUnit(const name: AnsiString; unitIdx: Integer): Integer;
var i: Integer;
begin
  i := ProcChainHead(name);
  while i >= 0 do
  begin
    if (ProcUnitIdx[i] = unitIdx) and (Procs[i].Name = name) then
    begin
      Result := i;
      Exit;
    end;
    i := ProcHashNext[i];
  end;
  i := ProcChainHead(name);
  while i >= 0 do
  begin
    if (ProcUnitIdx[i] = unitIdx) and (not ProcCaseSensitive[i]) and
       CaseEqual(Procs[i].Name, name) then
    begin
      Result := i;
      Exit;
    end;
    i := ProcHashNext[i];
  end;
  Result := -1;
end;

function HasNonOverloadProc(const name: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  i := ProcChainHead(name);
  while i >= 0 do
  begin
    if (ProcUnitIdx[i] = CurrentUnitIdx) and (Procs[i].Name = name) and
       not ProcOverloadDirective[i] then
    begin
      Result := True;
      Exit;
    end;
    i := ProcHashNext[i];
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

{ True when a and b are two KNOWN, DISTINCT, NAMED record/class identities.
  Anonymous inline `record ... end` types match structurally (a pxx
  extension) — and each textual occurrence mints a fresh rec id (prescan vs
  body parse!), so identity must never discriminate them. }
function RecContainsRecIdDepth(ri, target, depth: Integer): Boolean;
var ci, fb, i: Integer;
begin
  Result := False;
  if (depth > 8) or (target = REC_NONE) then Exit;
  if ri = target then begin Result := True; Exit; end;
  if ri < REC_UCLASS_BASE then Exit;
  ci := ri - REC_UCLASS_BASE;
  fb := UClsFBase[ci];
  for i := 0 to UClsFCount[ci] - 1 do
    if (UFldRec_[fb + i] <> REC_NONE) and (UFldRec_[fb + i] <> ri) and
       (UFldDynDepth[fb + i] = 0) and
       (UFldTk[fb + i] = Ord(tyRecord)) and  { by-value only: class fields are pointers }
       RecContainsRecIdDepth(UFldRec_[fb + i], target, depth + 1) then
    begin
      Result := True;
      Exit;
    end;
end;

{ True when record ri (transitively, by value) contains record `target`. }
function RecContainsRecId(ri, target: Integer): Boolean;
begin
  Result := RecContainsRecIdDepth(ri, target, 0);
end;

{ True when record ri (transitively) contains a Text/TextFile field — the RTL
  `text` record — so Default() and similar can reject it (FPC forbids file
  types there). }
function RecContainsTextRec(ri: Integer): Boolean;
begin
  Result := RecContainsRecIdDepth(ri, IsRecordType('text'), 0);
end;

function RecIdsDistinctNamed(a, b: Integer): Boolean;
begin
  Result := False;
  if (a = REC_NONE) or (b = REC_NONE) or (a = b) then Exit;
  if (a >= REC_UCLASS_BASE) and (UClsNLen[a - REC_UCLASS_BASE] = 0) then Exit;
  if (b >= REC_UCLASS_BASE) and (UClsNLen[b - REC_UCLASS_BASE] = 0) then Exit;
  Result := True;
end;

{ Rec-aware variant of FindProcOverload for declaration-time matching: two
  routines whose params differ only in RECORD/CLASS identity are DIFFERENT
  overloads. Without this the second `Dot(const a, b: TVec3)` matched the
  registered `Dot(const a, b: TVec2)` slot (both params tyRecord) and its body
  overwrote the first's — every call then ran the last-declared body
  (bug-overload-resolution-record-identity). A rec id is only compared when
  both sides are known (<> REC_NONE), so registration paths that never stored
  ProcParamRecId keep matching as before. }
function FindProcOverloadRec(const name: AnsiString; nParams: Integer; const ptypes: array of TTypeKind; const precs: array of Integer; const parr: array of Boolean; const pbyref: array of Boolean): Integer;
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
          if ((ptypes[j] = tyRecord) or (ptypes[j] = tyClass)) and
             (j < MAX_PROC_PARAMS) and
             RecIdsDistinctNamed(precs[j], ProcParamRecId[i * MAX_PROC_PARAMS + j]) then
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
  { A FROZEN-string parameter (ShortString / string[N]) accepts a managed or
    frozen string (or char) argument — IRLowerCallArg converts through a
    hidden frozen temp (Pascal Script's Const S: ShortString). }
  if ((pType = tyFixedString) or (pType = tyShortString)) and
     ((aType = tyAnsiString) or (aType = tyString) or (aType = tyChar)) then
  begin
    Result := True;
    Exit;
  end;
  { A class instance converts implicitly to a rooted object reference — the
    builtin TObject / `object` param type is a tyPointer (elem tyClass), so a
    `P(o: TObject)` plain routine must accept any tyClass argument, matching
    the method path (bug-tobject-param-truncated-32bit, symptom 2). The
    reverse (class param <- pointer arg) stays rejected. }
  if (pType = tyPointer) and (aType = tyClass) then
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
  rec := ProcParamRecId[procIdx * MAX_PROC_PARAMS + j];
  Result := (rec >= REC_UCLASS_BASE) and UClsIsInterface[rec - REC_UCLASS_BASE];
end;

function HasExactCaseSensitiveProc(const name: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  i := ProcChainHead(name);
  while i >= 0 do
  begin
    if ProcCaseSensitive[i] and (Procs[i].Name = name) then
    begin
      Result := True;
      Exit;
    end;
    i := ProcHashNext[i];
  end;
end;

{ Does proc `idx` answer to `name`? Exact always; case-insensitively too for a
  case-insensitive Pascal proc (default), but never for an external C import
  (printf <> Printf — those relax only under {$LAZYCASING ON}, handled in
  FindProc/LazyCanonName). Mirrors the FindProc fallback so unqualified calls
  resolve mixed-case spellings (inttostr -> IntToStr) like variable names do. }
function ProcNameMatches(idx: Integer; const name: AnsiString): Boolean;
begin
  Result := (Procs[idx].Name = name) or
            ((not (CProgramMode and HasExactCaseSensitiveProc(name))) and
             (not ProcCaseSensitive[idx]) and (not ProcExternal[idx]) and
             CaseEqual(Procs[idx].Name, name));
end;

function ProcArityMatches(i, nArgs: Integer): Boolean;
{ Exact arity, OR a call that omits trailing args whose params all carry a default
  value (`f(a; b: T = d)` callable as `f(x)`). The type-match phases only check
  the supplied args[0..nArgs-1]; the omitted ones are filled with their defaults
  at call lowering. }
var k: Integer;
begin
  if Procs[i].ParamCount = nArgs then begin Result := True; Exit; end;
  if (nArgs >= 0) and (nArgs < Procs[i].ParamCount) then
  begin
    Result := True;
    for k := nArgs to Procs[i].ParamCount - 1 do
      if (k >= MAX_PROC_PARAMS) or (not ProcParamHasDefault[i * MAX_PROC_PARAMS + k]) then
      begin Result := False; Exit; end;
    Exit;
  end;
  Result := False;
end;

function FindUMethArity(ci: Integer; const name: AnsiString; nExplicitArgs: Integer): Integer;
{ Overload-aware method lookup: first name match (walking the parent chain)
  whose proc accepts the call's EXPLICIT arg count (self added per entry;
  exact arity or trailing defaults cover the rest). Falls back to the plain
  first-name-match so single-method behavior and error paths are unchanged. }
var i, base, cnt, curr, want: Integer; lo, name2: AnsiString;
begin
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
      if UNameMatch(UMthNOff[base + i], UMthNLen[base + i], lo) then
      begin
        want := nExplicitArgs;
        if not UMthIsStatic[base + i] then want := want + 1;
        if ProcArityMatches(UMthProc_[base + i], want) then
        begin Result := base + i; Exit; end;
      end;
      Inc(i);
    end;
    curr := UClsParent[curr];
  end;
  Result := FindUMeth(ci, name);
end;

function FindUMethByProc(ci, procIdx: Integer): Integer;
{ The UMeth entry bound to a specific proc — an overloaded method's impl must
  update ITS OWN entry (slot/proc mapping), not the first name match. }
var i, base, cnt, curr: Integer;
begin
  Result := -1;
  curr := ci;
  while curr >= 0 do
  begin
    base := UClsMBase[curr];
    cnt  := UClsMCount[curr];
    for i := 0 to cnt - 1 do
      if UMthProc_[base + i] = procIdx then begin Result := base + i; Exit; end;
    curr := UClsParent[curr];
  end;
end;

{ True when call arg j's RECORD identity contradicts candidate i's param j.
  Only fires when both rec ids are known and the arg rec ids were filled for
  this call (MatchArgRecValid) — otherwise the matcher stays rec-blind, so
  callers that don't provide rec ids keep the legacy behavior. Records only:
  class params keep their inheritance-tolerant matching.
  (bug-overload-resolution-record-identity) }
function MatchArgRecMismatch(i, j: Integer; aTk: TTypeKind): Boolean;
var pr, ar, curr: Integer;
begin
  Result := False;
  if not MatchArgRecValid then Exit;
  if j >= MAX_PROC_PARAMS then Exit;
  if (aTk <> tyRecord) or (Procs[i].Params[j].TypeKind <> tyRecord) then Exit;
  pr := ProcParamRecId[i * MAX_PROC_PARAMS + j];
  ar := MatchArgRec[j];
  if not RecIdsDistinctNamed(ar, pr) then Exit;
  { Interface (and any future record) inheritance: an argument whose type
    DESCENDS from the param's type is a valid widening (IBar -> IFoo param),
    not a mismatch. Walk the arg's ancestor chain. }
  if (pr >= REC_UCLASS_BASE) and (ar >= REC_UCLASS_BASE) then
  begin
    curr := ar - REC_UCLASS_BASE;
    while curr >= 0 do
    begin
      if curr = pr - REC_UCLASS_BASE then Exit;   { descendant: compatible }
      curr := UClsParent[curr];
    end;
  end;
  Result := True;
end;

function MatchProcCall(const name: AnsiString; nArgs: Integer; const argTypes: array of TTypeKind): Integer;
var i, j: Integer; match: Boolean; cn: AnsiString;
begin
  { LAZYCASING: rebind a wrong-case C-import call to its exact declared spelling
    once, then match normally (the exact-name phases below then find it). }
  cn := LazyCanonName(name);
  if cn <> name then
  begin
    Result := MatchProcCall(cn, nArgs, argTypes);
    Exit;
  end;
  { Phase 1: Try exact match }
  i := ProcChainHead(name);
  while i >= 0 do
  begin
    if ProcNameMatches(i, name) then
    begin
      if ProcArityMatches(i, nArgs) then
      begin
        match := True;
        for j := 0 to nArgs-1 do
        begin
          if ((Procs[i].Params[j].TypeKind <> argTypes[j]) and
             not ProcParamUntyped[i * MAX_PROC_PARAMS + j]) or
             MatchArgRecMismatch(i, j, argTypes[j]) then
            match := False;
        end;
        if match then
        begin
          Result := i;
          Exit;
        end;
      end;
    end;
    i := ProcHashNext[i];
  end;

  { Phase 1b: Try exact match with return-lifting }
  i := ProcChainHead(name);
  while i >= 0 do
  begin
    if ProcNameMatches(i, name) then
    begin
      if (Procs[i].ParamCount > nArgs) and (ProcParamPtrDepth[i * MAX_PROC_PARAMS + nArgs] = 2) then
      begin
        match := True;
        for j := 0 to nArgs-1 do
        begin
          if ((Procs[i].Params[j].TypeKind <> argTypes[j]) and
             not ProcParamUntyped[i * MAX_PROC_PARAMS + j]) or
             MatchArgRecMismatch(i, j, argTypes[j]) then
            match := False;
        end;
        if match then
        begin
          Result := i;
          Exit;
        end;
      end;
    end;
    i := ProcHashNext[i];
  end;

  { Phase 1c: a Char argument prefers a string-typed parameter over the ordinal
    (char -> integer) compatible match. A single-char literal types as tyChar,
    so without this an earlier f(integer) overload silently won f('x') even when
    an f(string) overload exists (FPC ranks a char literal as a string). Runs
    before the general compatible phase so the string overload wins regardless of
    declaration order; every other arg must still be an exact type match. }
  i := ProcChainHead(name);
  while i >= 0 do
  begin
    if ProcNameMatches(i, name) and ProcArityMatches(i, nArgs) then
    begin
      match := True;
      for j := 0 to nArgs-1 do
      begin
        if (not ((Procs[i].Params[j].TypeKind = argTypes[j]) or
                ProcParamUntyped[i * MAX_PROC_PARAMS + j] or
                ((argTypes[j] = tyChar) and
                 ((Procs[i].Params[j].TypeKind = tyString) or
                  (Procs[i].Params[j].TypeKind = tyAnsiString))))) or
           MatchArgRecMismatch(i, j, argTypes[j]) then
          match := False;
      end;
      if match then
      begin
        Result := i;
        Exit;
      end;
    end;
    i := ProcHashNext[i];
  end;

  { Phase 2: Try compatible match }
  i := ProcChainHead(name);
  while i >= 0 do
  begin
    if ProcNameMatches(i, name) then
    begin
      if ProcArityMatches(i, nArgs) then
      begin
        match := True;
        for j := 0 to nArgs-1 do
        begin
          if (not (TypesCompatible(Procs[i].Params[j].TypeKind, argTypes[j]) or
                  ProcParamUntyped[i * MAX_PROC_PARAMS + j])) or
             MatchArgRecMismatch(i, j, argTypes[j]) then
            match := False;
        end;
        if match then
        begin
          Result := i;
          Exit;
        end;
      end;
    end;
    i := ProcHashNext[i];
  end;

  { Phase 2b: Try compatible match with return-lifting }
  i := ProcChainHead(name);
  while i >= 0 do
  begin
    if ProcNameMatches(i, name) then
    begin
      if (Procs[i].ParamCount > nArgs) and (ProcParamPtrDepth[i * MAX_PROC_PARAMS + nArgs] = 2) then
      begin
        match := True;
        for j := 0 to nArgs-1 do
        begin
          if (not (TypesCompatible(Procs[i].Params[j].TypeKind, argTypes[j]) or
                  ProcParamUntyped[i * MAX_PROC_PARAMS + j])) or
             MatchArgRecMismatch(i, j, argTypes[j]) then
            match := False;
        end;
        if match then
        begin
          Result := i;
          Exit;
        end;
      end;
    end;
    i := ProcHashNext[i];
  end;

  { Phase 2c: a class argument given to an interface parameter (the implicit
    class->interface coercion). Only fires when the param is a CORBA interface,
    so existing record/class overloads are unaffected. }
  i := ProcChainHead(name);
  while i >= 0 do
  begin
    if ProcNameMatches(i, name) and ProcArityMatches(i, nArgs) then
    begin
      match := True;
      for j := 0 to nArgs-1 do
      begin
        if (not (TypesCompatible(Procs[i].Params[j].TypeKind, argTypes[j]) or
                (ProcParamIsInterface(i, j) and (argTypes[j] = tyClass)) or
                ProcParamUntyped[i * MAX_PROC_PARAMS + j])) or
           MatchArgRecMismatch(i, j, argTypes[j]) then
          match := False;
      end;
      if match then
      begin
        Result := i;
        Exit;
      end;
    end;
    i := ProcHashNext[i];
  end;

  if not MatchQuiet then
  begin
    writeln('Mismatch in MatchProcCall: name = ', name, ', nArgs = ', nArgs);
    for j := 0 to nArgs-1 do
      writeln('  arg[', j, '] = ', Ord(argTypes[j]));
    i := ProcChainHead(name);
    while i >= 0 do
    begin
      if ProcNameMatches(i, name) then
      begin
        writeln('  Candidate idx ', i, ': paramCount = ', Procs[i].ParamCount);
        for j := 0 to Procs[i].ParamCount-1 do
          writeln('    param[', j, '] = ', Ord(Procs[i].Params[j].TypeKind));
      end;
      i := ProcHashNext[i];
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
        if ((Procs[i].Params[j].TypeKind <> argTypes[j]) and not ProcParamUntyped[i * MAX_PROC_PARAMS + j]) or MatchArgRecMismatch(i, j, argTypes[j]) then match := False;
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
       (ProcParamPtrDepth[i * MAX_PROC_PARAMS + nArgs] = 2) then
    begin
      match := True;
      for j := 0 to nArgs - 1 do
        if ((Procs[i].Params[j].TypeKind <> argTypes[j]) and not ProcParamUntyped[i * MAX_PROC_PARAMS + j]) or MatchArgRecMismatch(i, j, argTypes[j]) then match := False;
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
        if (not (TypesCompatible(Procs[i].Params[j].TypeKind, argTypes[j]) or ProcParamUntyped[i * MAX_PROC_PARAMS + j])) or MatchArgRecMismatch(i, j, argTypes[j]) then match := False;
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
       (ProcParamPtrDepth[i * MAX_PROC_PARAMS + nArgs] = 2) then
    begin
      match := True;
      for j := 0 to nArgs - 1 do
        if (not (TypesCompatible(Procs[i].Params[j].TypeKind, argTypes[j]) or ProcParamUntyped[i * MAX_PROC_PARAMS + j])) or MatchArgRecMismatch(i, j, argTypes[j]) then match := False;
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
  if nParams > MAX_PROC_PARAMS then Error('too many procedure parameters');
  Procs[ProcCount].Name       := name;
  ProcHashInsert(ProcCount);
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
  ProcFlexColumn[ProcCount]   := False;
  ProcLibrary[ProcCount]      := -1;
  ProcExtName[ProcCount]      := -1;
  ProcCdecl[ProcCount]        := False;
  ProcUnitIdx[ProcCount]      := CurrentUnitIdx;
  ProcRetRecId[ProcCount]     := REC_NONE;
  ProcAggregateDestSym[ProcCount] := -1;
  ProcRetIsDynArray[ProcCount] := False;
  ProcRetElemTk[ProcCount]     := tyUnknown;
  ProcRetElemRec[ProcCount]    := REC_NONE;
  ProcRetPtrElemTk[ProcCount]  := Ord(tyUnknown);
  ProcRetPtrElemRec[ProcCount] := REC_NONE;
  ProcRetProcSig[ProcCount]    := -1;
  CProcHasLocalDef[ProcCount]  := False;
  ProcInline[ProcCount]        := False;
  InlineBodyRoot[ProcCount]    := -1;
  InlineParamCnt[ProcCount]    := 0;
  InlineBodyIsStmt[ProcCount]  := False;
  InlineLocalCnt[ProcCount]    := 0;
  for i := 0 to MAX_PROC_PARAMS - 1 do
  begin
    ProcParamPtrDepth[ProcCount * MAX_PROC_PARAMS + i] := 0;
    ProcParamIsConst[ProcCount * MAX_PROC_PARAMS + i] := False;
    ProcParamExplicitByRef[ProcCount * MAX_PROC_PARAMS + i] := False;
    ProcParamUntyped[ProcCount * MAX_PROC_PARAMS + i] := False;
    ProcParamHasDefault[ProcCount * MAX_PROC_PARAMS + i] := False;
    ProcParamDefaultVal[ProcCount * MAX_PROC_PARAMS + i] := 0;
    ProcParamDefaultIsStr[ProcCount * MAX_PROC_PARAMS + i] := False;
    ProcParamDefaultSOff[ProcCount * MAX_PROC_PARAMS + i] := 0;
    ProcParamDefaultSLen[ProcCount * MAX_PROC_PARAMS + i] := 0;
    ProcParamRecId[ProcCount * MAX_PROC_PARAMS + i] := REC_NONE;
    ProcParamDynDepth[ProcCount * MAX_PROC_PARAMS + i] := 0;
  end;
  for i := 0 to nParams-1 do
  begin
    Procs[ProcCount].Params[i].Name     := pnames[i];
    Procs[ProcCount].Params[i].TypeKind := ptypes[i];
    Procs[ProcCount].Params[i].SymIdx   := -1;
    Procs[ProcCount].Params[i].IsArray  := False;
    { C struct-by-value params use the by-ref ABI (an 8-byte pointer slot the
      callee derefs; the caller copies to a temp and passes &temp — see cparser
      AllocParam and ir.inc IRLowerCallArg). The proc's Params[].IsRef must agree
      so the CALLER marshals it as one pointer word, not a 2-word by-value record
      (which pushed a stale second word -> a NULL 2nd struct arg on arm32/riscv32).
      C-mode-gated so Pascal proc registration stays byte-identical. }
    Procs[ProcCount].Params[i].IsRef    := CProgramMode and (ptypes[i] = tyRecord);
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
  MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;
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
  MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;
end;

procedure EmitwriteChar;
{ rax = char byte value → write 1 byte to stdout }
begin
  EmitB($48); EmitB($BE); EmitDataRef(INTBUF_OFFSET);
  EmitB($88); EmitB($06);
  MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); MovRdxImm(1); EmitSyscall;
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
  MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;
  Code[jleOff] := Byte(CodeLen - (jleOff + 1));
  { Write sign if negative }
  EmitB($4D); EmitB($85); EmitB($C0);                    { test r8, r8 }
  EmitB($74); jzOff := CodeLen; EmitB(0);                { jz .no_sign }
  EmitwriteSyscall(MINUS_OFFSET, 1);
  Code[jzOff] := Byte(CodeLen - (jzOff + 1));
  { Write digits }
  EmitB($5A);                                            { pop rdx }
  EmitB($5E);                                            { pop rsi }
  MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;
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
  MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;
  Code[jleOff] := Byte(CodeLen - (jleOff + 1));
  EmitB($5A);                                            { pop rdx }
  EmitB($5E);                                            { pop rsi }
  MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;
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

procedure EmitWriteFloatFixed(width, decimals: Integer);
{ Double value in xmm0. Prints [-]intpart.frac with exactly 'decimals'
  fractional digits (decimals=0 -> rounded integer, no point), right-justified in
  a field of `width` columns (width<=0 = no padding). Reuses the integer
  printers; the value is scaled by 10^decimals and rounded to an Int64 so all
  digits come from integer division. }
var pow10, divisor: Int64; i, k, jncOff: Integer;
    pNotNeg, pCntTop, pCntDone, pNoPad: Integer;
begin
  pow10 := 1;
  for i := 1 to decimals do pow10 := pow10 * 10;

  { Field-width padding: a pre-pass computes the formatted length and emits the
    leading spaces, right-justifying the value (FPC `:w:d`). It must not disturb
    xmm0 (the emission below re-reads it); it works in rax/rcx/rdx/rsi + xmm1/xmm2
    only. Skipped for width<=0 (the common writeln(x:0:d) form). }
  if width > 0 then
  begin
    EmitB($66); EmitB($48); EmitB($0F); EmitB($7E); EmitB($C0);   { movq rax, xmm0 }
    EmitB($48); EmitB($31); EmitB($F6);                           { xor rsi, rsi }
    EmitB($48); EmitB($0F); EmitB($BA); EmitB($E0); EmitB($3F);   { bt rax, 63 }
    EmitB($73); pNotNeg := CodeLen; EmitB(0);                     { jnc .notneg }
    EmitB($48); EmitB($FF); EmitB($C6);                           { inc rsi (sign char) }
    Code[pNotNeg] := Byte(CodeLen - (pNotNeg + 1));
    EmitB($48); EmitB($0F); EmitB($BA); EmitB($F0); EmitB($3F);   { btr rax, 63 (abs bits) }
    EmitB($66); EmitB($48); EmitB($0F); EmitB($6E); EmitB($C8);   { movq xmm1, rax }
    MovRaxImm(pow10);
    EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($D0);   { cvtsi2sd xmm2, rax }
    EmitB($F2); EmitB($0F); EmitB($59); EmitB($CA);               { mulsd xmm1, xmm2 }
    EmitB($F2); EmitB($48); EmitB($0F); EmitB($2D); EmitB($C1);   { cvtsd2si rax, xmm1 }
    EmitB($48); EmitB($31); EmitB($D2);                           { xor rdx, rdx }
    EmitB($48); EmitB($B9); EmitI64(pow10);                       { mov rcx, pow10 }
    EmitB($48); EmitB($F7); EmitB($F1);                           { div rcx -> rax=intpart }
    EmitB($48); EmitB($FF); EmitB($C6);                           { inc rsi (first int digit) }
    EmitB($48); EmitB($B9); EmitI64(10);                          { mov rcx, 10 }
    pCntTop := CodeLen;                                           { .cnt: }
    EmitB($48); EmitB($83); EmitB($F8); EmitB($0A);               { cmp rax, 10 }
    EmitB($72); pCntDone := CodeLen; EmitB(0);                    { jb .cntdone }
    EmitB($48); EmitB($31); EmitB($D2);                           { xor rdx, rdx }
    EmitB($48); EmitB($F7); EmitB($F1);                           { div rcx }
    EmitB($48); EmitB($FF); EmitB($C6);                           { inc rsi }
    EmitB($EB); EmitB(Byte(pCntTop - (CodeLen + 1)));             { jmp .cnt }
    Code[pCntDone] := Byte(CodeLen - (pCntDone + 1));            { .cntdone: }
    if decimals > 0 then
    begin
      EmitB($48); EmitB($81); EmitB($C6); EmitI32(decimals + 1); { add rsi, decimals+1 }
    end;
    MovRaxImm(width);
    EmitB($48); EmitB($29); EmitB($F0);                           { sub rax, rsi (padcount) }
    EmitB($7E); pNoPad := CodeLen; EmitB(0);                      { jle .nopad }
    EnsureSpaces;
    EmitB($48); EmitB($BE); EmitDataRef(SpacesOffset);           { mov rsi, spaces }
    EmitB($48); EmitB($89); EmitB($C2);                           { mov rdx, rax }
    MovRaxImm(SYS_WRITE); MovRdiImm(CurWriteFd); EmitSyscall;
    Code[pNoPad] := Byte(CodeLen - (pNoPad + 1));                { .nopad: }
  end;

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
  <' '|'-'>d.<16 digits>E<'+'|'-'>ddd  (17 significant digits, 3-digit exponent),
  matching FPC's default Str(Double) field width. Digit extraction uses double
  arithmetic, so the last 1-2 digits may differ from a correctly-rounded bignum
  formatter; adequate for general output. e10 kept in r12. }
const FRAC = 16;
var jncPos, jmpSignDone, jnzNz, jmpDone: Integer;
    laTop, laJb, lbTop, lbJae, jnsPos2, jmpEd: Integer;
    clampJle, bdLoop, roundJl, ovJb: Integer;
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

  { m = round-to-nearest(value * 10^FRAC) built as a (FRAC+1)-digit integer in
    rbx, extracted MSD-first by iteration so each step only truncates a value in
    [0,10). This keeps ~17 accurate digits, unlike one (value*10^16) double
    multiply which overflows the 53-bit mantissa and zeroes the low digits. rcx
    counts the FRAC+1 leading digits; one extra guard digit then rounds half-up.
    No syscalls here, so rax/rcx/rdx are free scratch; xmm1 still holds 10.0. }
  EmitB($48); EmitB($31); EmitB($DB);                          { xor rbx, rbx }
  EmitB($B9); EmitI32(FRAC + 1);                               { mov ecx, 17 }
  bdLoop := CodeLen;                                           { .bd: }
  EmitB($F2); EmitB($48); EmitB($0F); EmitB($2C); EmitB($C0);  { cvttsd2si rax, xmm0 }
  EmitB($48); EmitB($83); EmitB($F8); EmitB($09);              { cmp rax, 9 }
  EmitB($7E); clampJle := CodeLen; EmitB(0);                   { jle .ok }
  EmitB($B8); EmitI32(9);                                      { mov eax, 9 }
  Code[clampJle] := Byte(CodeLen - (clampJle + 1));            { .ok: }
  EmitB($48); EmitB($6B); EmitB($DB); EmitB($0A);              { imul rbx, rbx, 10 }
  EmitB($48); EmitB($01); EmitB($C3);                          { add rbx, rax }
  EmitB($F2); EmitB($48); EmitB($0F); EmitB($2A); EmitB($D8);  { cvtsi2sd xmm3, rax }
  EmitB($F2); EmitB($0F); EmitB($5C); EmitB($C3);              { subsd xmm0, xmm3 }
  EmitB($F2); EmitB($0F); EmitB($59); EmitB($C1);              { mulsd xmm0, xmm1 }
  EmitB($48); EmitB($FF); EmitB($C9);                          { dec rcx }
  EmitB($75); EmitB(Byte(bdLoop - (CodeLen + 1)));             { jnz .bd }
  { guard digit: round half-up }
  EmitB($F2); EmitB($48); EmitB($0F); EmitB($2C); EmitB($C0);  { cvttsd2si rax, xmm0 }
  EmitB($48); EmitB($83); EmitB($F8); EmitB($05);              { cmp rax, 5 }
  EmitB($7C); roundJl := CodeLen; EmitB(0);                    { jl .noround }
  EmitB($48); EmitB($FF); EmitB($C3);                          { inc rbx }
  Code[roundJl] := Byte(CodeLen - (roundJl + 1));              { .noround: }
  { carry past the leading digit (9.99..->10.0): drop a digit, bump exponent }
  divisor := 1; for k := 0 to FRAC do divisor := divisor * 10;  { 10^(FRAC+1) }
  EmitB($48); EmitB($B8); EmitI64(divisor);                    { mov rax, 10^17 }
  EmitB($48); EmitB($39); EmitB($C3);                          { cmp rbx, rax }
  EmitB($72); ovJb := CodeLen; EmitB(0);                       { jb .nov }
  EmitB($48); EmitB($89); EmitB($D8);                          { mov rax, rbx }
  EmitB($48); EmitB($31); EmitB($D2);                          { xor rdx, rdx }
  EmitB($B9); EmitI32(10);                                     { mov ecx, 10 }
  EmitB($48); EmitB($F7); EmitB($F1);                          { div rcx }
  EmitB($48); EmitB($89); EmitB($C3);                          { mov rbx, rax }
  EmitB($49); EmitB($FF); EmitB($C4);                          { inc r12 }
  Code[ovJb] := Byte(CodeLen - (ovJb + 1));                    { .nov: }

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
      { Raw `interrupt;` handler (Call0): a hardware exception can preempt arbitrary
        code, so the interrupted caller-saved a-regs the body clobbers (a2-a8,
        a10-a13) must be preserved. a0/a1(sp)/a15 are covered by the normal Call0
        frame below; a9/a14 are never touched by codegen. Saved in a 48-byte area
        (11 regs, 16-byte aligned) ABOVE the normal frame; the epilogue restores
        them and returns via `rfe` (general level-1 exception). Windowed ABI is
        gated off in the parser (mid-window spill is a follow-up). }
      if (CurProc >= 0) and ProcIsInterrupt[CurProc] then
      begin
        xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, -48);
        xtensa_s32i(reg_xtensa_a2, reg_xtensa_sp, 0);  xtensa_s32i(reg_xtensa_a3, reg_xtensa_sp, 4);
        xtensa_s32i(reg_xtensa_a4, reg_xtensa_sp, 8);  xtensa_s32i(reg_xtensa_a5, reg_xtensa_sp, 12);
        xtensa_s32i(reg_xtensa_a6, reg_xtensa_sp, 16); xtensa_s32i(reg_xtensa_a7, reg_xtensa_sp, 20);
        xtensa_s32i(reg_xtensa_a8, reg_xtensa_sp, 24); xtensa_s32i(reg_xtensa_a10, reg_xtensa_sp, 28);
        xtensa_s32i(reg_xtensa_a11, reg_xtensa_sp, 32); xtensa_s32i(reg_xtensa_a12, reg_xtensa_sp, 36);
        xtensa_s32i(reg_xtensa_a13, reg_xtensa_sp, 40);
      end;
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
    { Raw `interrupt;` handler: a hardware trap can preempt arbitrary code, so the
      interrupted caller-saved context (t0-t6, a0-a7) must be preserved across the
      body — the normal prologue below only saves ra/s0. Saved in a 64-byte area
      ABOVE the normal frame; the epilogue restores them then `mret`s. ra/s0 are
      covered by the normal prologue. (Codegen never touches s1-s11.) }
    if (CurProc >= 0) and ProcIsInterrupt[CurProc] then
    begin
      rv32_addi(reg_sp, reg_sp, -64);
      rv32_sw(reg_t0, reg_sp, 0);  rv32_sw(reg_t1, reg_sp, 4);  rv32_sw(reg_t2, reg_sp, 8);
      rv32_sw(reg_t3, reg_sp, 12); rv32_sw(reg_t4, reg_sp, 16); rv32_sw(reg_t5, reg_sp, 20);
      rv32_sw(reg_t6, reg_sp, 24);
      rv32_sw(reg_a0, reg_sp, 28); rv32_sw(reg_a1, reg_sp, 32); rv32_sw(reg_a2, reg_sp, 36);
      rv32_sw(reg_a3, reg_sp, 40); rv32_sw(reg_a4, reg_sp, 44); rv32_sw(reg_a5, reg_sp, 48);
      rv32_sw(reg_a6, reg_sp, 52); rv32_sw(reg_a7, reg_sp, 56);
    end;
    { RISC-V prologue: push ra, s0 (save Return Address and Frame Pointer) }
    rv32_addi(reg_sp, reg_sp, -16);
    rv32_sw(reg_ra, reg_sp, 12);
    rv32_sw(reg_s0, reg_sp, 8);
    rv32_addi(reg_s0, reg_sp, 0);
    Result := CodeLen;
    { Reserve THREE words for the frame adjustment (patched in PatchProcPrologue):
      a single `addi sp,sp,-frame` only reaches +/-2048, so a larger frame needs
      `lui t0,hi; addi t0,t0,lo; sub sp,sp,t0`. Small frames patch addi + 2 nops.
      (t0 is scratch at entry — the interrupt path already saved it above.) }
    rv32_addi(reg_sp, reg_sp, 0);
    rv32_addi(reg_zero, reg_zero, 0);
    rv32_addi(reg_zero, reg_zero, 0);
    Exit;
  end;
  EmitB($55);
  EmitB($48); EmitB($89); EmitB($E5);
  EmitB($48); EmitB($81); EmitB($EC);
  Result := CodeLen; EmitI32(0);
end;

procedure PatchProcPrologue(patchPos, size: Integer);
var aligned, a64imm, rvLo, rvHi: Integer;
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
  begin
    { addi's immediate is 12-bit signed (+/-2048); a larger frame silently
      truncated to a positive value and allocated the frame UPWARD, so callees
      overwrote this function's locals (bug-riscv32-large-frame-addi-truncate).
      Small frames: `addi sp,sp,-aligned` + 2 nops. Large: build the size in t0
      (lui+addi) and `sub sp,sp,t0` — three words, matching the reservation. }
    if aligned <= 2047 then
    begin
      Patch32(patchPos, EncodeRISCVAddi(reg_sp, reg_sp, -aligned));
      Patch32(patchPos + 4, EncodeRISCVAddi(0, 0, 0));   { nop }
      Patch32(patchPos + 8, EncodeRISCVAddi(0, 0, 0));   { nop }
    end
    else
    begin
      rvLo := aligned and $FFF;
      if (rvLo and $800) <> 0 then rvLo := rvLo - $1000;  { addi's lo is sign-extended }
      rvHi := aligned - rvLo;                             { multiple of 4096 for lui }
      Patch32(patchPos,     EncodeRISCVLui(reg_t0, rvHi));
      Patch32(patchPos + 4, EncodeRISCVAddi(reg_t0, reg_t0, rvLo));
      Patch32(patchPos + 8, EncodeRISCVSub(reg_sp, reg_sp, reg_t0));
    end;
  end
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

{ ---- Zero-init contract (feature-zero-init-contract) ---------------------
  The "a managed slot is nil before first use" guarantee has ONE owner in the
  compiler: EmitZeroFrameSlot. Callers state the frame offset and the extent in
  bytes; the machine sequence is this routine's business, nobody else's. The
  extent may be any size — the >pointer-sized case routes to the RTL primitive
  PXXMemZero, so there is no per-target "managed aggregates not supported" hole.
  x86-64 keeps `rep stosb` inline (the hardware memset), which is the same
  guarantee produced by the same owner, not a second implementation of it. }
procedure EmitZeroFrameSlot(frameOff, nBytes: Integer);
var helperPi: Integer;
begin
  if nBytes <= 0 then Exit;

  if nBytes <= TARGET_PTR_SIZE then
  begin
    { Single pointer-sized handle (AnsiString / dyn-array): one nil store. }
    if TargetArch = TARGET_I386 then
      begin EmitB($C7); EmitB($85); EmitI32(frameOff); EmitI32(0); end  { mov dword [ebp+off], 0 }
    else if TargetArch = TARGET_ARM32 then
    begin
      EmitLoadImmArm32(9, frameOff);
      EmitI32($E08B9009);                        { add r9, fp, r9 }
      EmitI32($E3A00000);                        { mov r0, #0 }
      EmitI32($E5890000);                        { str r0, [r9] }
    end
    else if TargetArch = TARGET_AARCH64 then
    begin
      EmitLoadImmA64(9, frameOff);
      EmitI32($8B0903A9);                        { add x9, x29, x9 }
      EmitI32($F900013F);                        { str xzr, [x9] }
    end
    else if TargetArch = TARGET_XTENSA then
    begin
      EmitFrameAddrXtensa(reg_xtensa_a8, frameOff);
      xtensa_movi(reg_xtensa_a9, 0);
      xtensa_s32i(reg_xtensa_a9, reg_xtensa_a8, 0);
    end
    else if TargetArch = TARGET_RISCV32 then
    begin
      EmitLoadImmRISCV32(reg_t0, frameOff);
      rv32_add(reg_t0, reg_s0, reg_t0);
      rv32_sw(reg_zero, reg_t0, 0);
    end
    else
      begin EmitB($48); EmitB($C7); EmitB($85); EmitI32(frameOff); EmitI32(0); end; { mov qword [rbp+off], 0 }
    Exit;
  end;

  { Managed aggregate (record with managed fields / variant / COM fat pointer /
    array of managed): zero the whole extent. }
  if TargetArch = TARGET_X86_64 then
  begin
    EmitB($48); EmitB($8D); EmitB($BD); EmitI32(frameOff);   { lea rdi, [rbp+off] }
    EmitB($48); EmitB($31); EmitB($C0);                      { xor rax, rax }
    EmitB($48); EmitB($C7); EmitB($C1); EmitI32(nBytes);     { mov rcx, nBytes }
    EmitB($F3); EmitB($AA);                                  { rep stosb }
    Exit;
  end;

  helperPi := FindProc('PXXMemZero');
  if helperPi < 0 then Error('compiler error: PXXMemZero not found');
  if TargetArch = TARGET_I386 then
  begin
    EmitB($8D); EmitB($85); EmitI32(frameOff);   { lea eax, [ebp+off] }
    EmitB($50);                                  { push dest (param 0, deepest) }
    EmitB($68); EmitI32(nBytes);                 { push count }
    EmitCallProc(helperPi);
    EmitB($81); EmitB($C4); EmitI32(8);          { add esp, 8 }
  end
  else if TargetArch = TARGET_ARM32 then
  begin
    EmitLoadImmArm32(0, frameOff);
    EmitI32($E08B0000);                          { add r0, fp, r0 (dest) }
    EmitLoadImmArm32(1, nBytes);                 { r1 = count }
    EmitCallProc(helperPi);
  end
  else if TargetArch = TARGET_AARCH64 then
  begin
    EmitLoadImmA64(9, frameOff);
    EmitI32($8B0903A0);                          { add x0, x29, x9 (dest) }
    EmitLoadImmA64(1, nBytes);                   { x1 = count }
    EmitCallProc(helperPi);
  end
  else if TargetArch = TARGET_RISCV32 then
  begin
    EmitLoadImmRISCV32(reg_t0, frameOff);
    rv32_add(reg_a0, reg_s0, reg_t0);            { a0 = dest }
    EmitLoadImmRISCV32(reg_a1, nBytes);          { a1 = count }
    EmitCallProc(helperPi);
  end
  else if TargetArch = TARGET_XTENSA then
  begin
    EmitFrameAddrXtensa(reg_xtensa_a8, frameOff);
    if XtensaABI = XTENSA_ABI_WINDOWED then
    begin
      xtensa_mov(reg_xtensa_a10, reg_xtensa_a8);       { arg0 = dest }
      EmitLoadConstXtensa(reg_xtensa_a11, nBytes);     { arg1 = count }
    end
    else
    begin
      xtensa_mov(reg_xtensa_a2, reg_xtensa_a8);        { arg0 = dest }
      EmitLoadConstXtensa(reg_xtensa_a3, nBytes);      { arg1 = count }
    end;
    EmitCallProc(helperPi);
  end
  else
    Error('compiler error: EmitZeroFrameSlot: unhandled target');
end;

{ Stash the caller's hidden aggregate-result destination pointer (passed in the
  per-target indirect-result register) into the proc's dest-sym frame slot, right
  after the prologue and before the param-copy loop can clobber that register.
  Shared by the Pascal (parser.inc) and C (cparser.inc) routine emitters so an
  aggregate-returning C function uses the same convention as a Pascal one. }
procedure EmitAggregateDestStash(procIdx: Integer);
var idx: Integer;
begin
  if (procIdx < 0) or (ProcAggregateDestSym[procIdx] < 0) then Exit;
  idx := ProcAggregateDestSym[procIdx];
  if TargetArch = TARGET_I386 then
    { i386 carries the hidden destination pointer in ecx; stash it before the
      param-copy loop clobbers ecx. }
    begin EmitB($89); EmitB($8D); EmitI32(Syms[idx].Offset); end { mov [ebp+off], ecx }
  else if TargetArch = TARGET_AARCH64 then
  begin
    { aarch64 carries the hidden destination in x8 (AAPCS XR). }
    EmitLoadImmA64(9, Syms[idx].Offset);
    EmitI32($8B0903A9);                                 { add x9, x29, x9 }
    EmitI32($F9000128);                                 { str x8, [x9] }
  end
  else if TargetArch = TARGET_ARM32 then
  begin
    { arm32 carries the hidden destination in r12 (ip, a scratch reg). }
    EmitLoadImmArm32(9, Syms[idx].Offset);
    EmitI32($E08B9009);                                 { add r9, fp, r9 }
    EmitI32($E589C000);                                 { str r12, [r9] }
  end
  else if TargetArch = TARGET_RISCV32 then
  begin
    { riscv32 carries the hidden destination in t1 (no dedicated indirect-result
      reg); stash it before the param-copy loop clobbers t1. }
    EmitLoadImmRISCV32(reg_t0, Syms[idx].Offset);
    rv32_add(reg_t0, reg_s0, reg_t0);
    rv32_sw(reg_t1, reg_t0, 0);
  end
  else if TargetArch = TARGET_XTENSA then
  begin
    { xtensa Call0 carries the hidden destination in a8 (a caller-saved temp
      outside the a2-a7 arg set); stash it before the param-copy clobbers a8.
      Windowed record results are unsupported (rejected at the epilogue). }
    if XtensaABI = XTENSA_ABI_CALL0 then
    begin
      EmitFrameAddrXtensa(reg_xtensa_a9, Syms[idx].Offset);
      xtensa_s32i(reg_xtensa_a8, reg_xtensa_a9, 0);
    end;
  end
  else
    begin EmitB($4C); EmitB($89); EmitB($95); EmitI32(Syms[idx].Offset); end; { mov [rbp+off], r10 }
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
      if RetViaHiddenDest(Syms[retSymIdx].TypeKind) and
         (CurProc >= 0) and (ProcAggregateDestSym[CurProc] >= 0) then
      begin
        { Aggregate result: copy the Result local into the caller's hidden
          destination (pointer the prologue stashed in the dest-sym slot from
          ecx), return that pointer in eax. Mirrors the x86-64 rep-movsb path. }
        EmitB($8B); EmitB($BD); EmitI32(Syms[ProcAggregateDestSym[CurProc]].Offset); { mov edi, [ebp+destOff] }
        EmitB($89); EmitB($F8);                                  { mov eax, edi (return value) }
        EmitB($8D); EmitB($B5); EmitI32(Syms[retSymIdx].Offset); { lea esi, [ebp+resultOff] }
        sz := AggRetCopySize(retSymIdx);
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
      if RetViaHiddenDest(Syms[retSymIdx].TypeKind) and
         (CurProc >= 0) and (ProcAggregateDestSym[CurProc] >= 0) then
      begin
        { Aggregate result: copy the Result local into the caller's hidden
          destination (pointer the prologue stashed from r12), return the
          pointer in r0. r5=src, r6=dst, r4=count for EmitArm32CopyBytes. }
        EmitLoadVarArm32(ProcAggregateDestSym[CurProc]);  { r0 = dest ptr }
        EmitI32($E1A06000);                               { mov r6, r0 (dst) }
        EmitLoadVarAddrArm32(retSymIdx);                  { r0 = &Result }
        EmitI32($E1A05000);                               { mov r5, r0 (src) }
        sz := AggRetCopySize(retSymIdx);
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
      if RetViaHiddenDest(Syms[retSymIdx].TypeKind) and
         (CurProc >= 0) and (ProcAggregateDestSym[CurProc] >= 0) then
      begin
        { Aggregate result: copy the Result local into the caller's hidden
          destination (pointer the prologue stashed from x8), return the pointer
          in x0. EmitA64CopyBytes uses x4/x5/x6 + w8, leaving x0 intact. }
        EmitLoadVarA64(ProcAggregateDestSym[CurProc]);   { x0 = dest ptr }
        EmitI32($AA0003E6);                              { mov x6, x0 (dst) }
        EmitLoadImmA64(9, Syms[retSymIdx].Offset);
        EmitI32($8B0903A5);                              { add x5, x29, x9 (src = &Result) }
        sz := AggRetCopySize(retSymIdx);
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
      if RetViaHiddenDest(Syms[retSymIdx].TypeKind) and
         (CurProc >= 0) and (ProcAggregateDestSym[CurProc] >= 0) then
      begin
        { Aggregate (record) result, Call0 only: copy the Result local into the
          caller's hidden destination (the pointer the prologue stashed from a8),
          return it in a2. PXXMemMove(dest, &Result, size). Windowed is rejected —
          its call-window rotation has no clean caller->callee hidden-dest reg. }
        if XtensaABI <> XTENSA_ABI_CALL0 then
          Error('target xtensa: record function results require Call0 (windowed not yet supported)');
        EmitFrameAddrXtensa(reg_xtensa_a3, Syms[retSymIdx].Offset);   { a3 = &Result (src) }
        EmitLoadVarXtensa(ProcAggregateDestSym[CurProc]);             { a2 = dest ptr }
        sz := AggRetCopySize(retSymIdx);
        EmitLoadConstXtensa(reg_xtensa_a4, sz);                       { a4 = byte count }
        procIdx := FindProc('PXXMemMove');
        if procIdx < 0 then Error('compiler error: PXXMemMove not found');
        EmitCallProc(procIdx);
        EmitLoadVarXtensa(ProcAggregateDestSym[CurProc]);             { a2 = dest (return value) }
      end
      else
      begin
        if Syms[retSymIdx].IsArray or (Syms[retSymIdx].Kind <> skLocal) or
           not (TypeIsOrdinal(Syms[retSymIdx].TypeKind) or TypeIsFloat(Syms[retSymIdx].TypeKind) or
                (Syms[retSymIdx].TypeKind in [tyAnsiString, tyPointer, tyClass])) then
          Error('target xtensa: only ordinal/float/pointer/string function results supported yet');
        { Float result carried as raw bits in the return reg(s): Double = a2:a3
          (8-byte slot), Single = a2 (4-byte slot) — same shape as Int64/ordinal. }
        if (Syms[retSymIdx].TypeKind = tyInt64) or (Syms[retSymIdx].TypeKind = tyUInt64) or
           (Syms[retSymIdx].TypeKind = tyDouble) then
          EmitLoadVar64Xtensa(retSymIdx)   { 64-bit result in a2:a3 }
        else
          EmitLoadVarXtensa(retSymIdx);
      end;
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
      if (CurProc >= 0) and ProcIsInterrupt[CurProc] then
      begin
        { Restore the interrupted context (mirror of the prologue save area, now at
          sp after the normal frame unwound), then return from the exception via
          `rfe` (PC <- EPC1, PS.EXCM cleared). }
        xtensa_l32i(reg_xtensa_a2, reg_xtensa_sp, 0);  xtensa_l32i(reg_xtensa_a3, reg_xtensa_sp, 4);
        xtensa_l32i(reg_xtensa_a4, reg_xtensa_sp, 8);  xtensa_l32i(reg_xtensa_a5, reg_xtensa_sp, 12);
        xtensa_l32i(reg_xtensa_a6, reg_xtensa_sp, 16); xtensa_l32i(reg_xtensa_a7, reg_xtensa_sp, 20);
        xtensa_l32i(reg_xtensa_a8, reg_xtensa_sp, 24); xtensa_l32i(reg_xtensa_a10, reg_xtensa_sp, 28);
        xtensa_l32i(reg_xtensa_a11, reg_xtensa_sp, 32); xtensa_l32i(reg_xtensa_a12, reg_xtensa_sp, 36);
        xtensa_l32i(reg_xtensa_a13, reg_xtensa_sp, 40);
        xtensa_addi(reg_xtensa_sp, reg_xtensa_sp, 48);
        xtensa_rfe;
      end
      else
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
      if RetViaHiddenDest(Syms[retSymIdx].TypeKind) and
         (CurProc >= 0) and (ProcAggregateDestSym[CurProc] >= 0) then
      begin
        { Aggregate (record) result: copy the Result local into the caller's
          hidden destination (the pointer the prologue stashed from t1), return
          that pointer in a0. PXXMemMove(dest, &Result, size). }
        EmitSlotAddrRISCV32(reg_a1, retSymIdx);              { a1 = &Result (src) }
        EmitLoadVarRISCV32(ProcAggregateDestSym[CurProc]);   { a0 = dest ptr }
        sz := AggRetCopySize(retSymIdx);
        EmitLoadImmRISCV32(reg_a2, sz);                       { a2 = byte count }
        procIdx := FindProc('PXXMemMove');
        if procIdx < 0 then Error('compiler error: PXXMemMove not found');
        EmitCallProc(procIdx);
        EmitLoadVarRISCV32(ProcAggregateDestSym[CurProc]);   { a0 = dest (return value) }
      end
      else
      begin
        if Syms[retSymIdx].IsArray or (Syms[retSymIdx].Kind <> skLocal) or
           not (TypeIsOrdinal(Syms[retSymIdx].TypeKind) or TypeIsFloat(Syms[retSymIdx].TypeKind) or
                (Syms[retSymIdx].TypeKind in [tyAnsiString, tyPointer, tyClass])) then
          Error('target riscv32: only ordinal/float/pointer/string function results supported yet');
        { Float result carried as raw bits in the return reg(s): Double = a0:a1
          (8-byte slot), Single = a0 (4-byte slot) — same shape as Int64/ordinal. }
        if (Syms[retSymIdx].TypeKind = tyInt64) or (Syms[retSymIdx].TypeKind = tyUInt64) or
           (Syms[retSymIdx].TypeKind = tyDouble) then
          EmitLoadVar64RISCV32(retSymIdx)   { 64-bit result in a0:a1 }
        else
          EmitLoadVarRISCV32(retSymIdx);
      end;
    end;
    rv32_addi(reg_sp, reg_s0, 0);
    rv32_lw(reg_s0, reg_sp, 8);
    rv32_lw(reg_ra, reg_sp, 12);
    rv32_addi(reg_sp, reg_sp, 16);
    if (CurProc >= 0) and ProcIsInterrupt[CurProc] then
    begin
      { Restore the interrupted caller-saved context (mirror of the prologue),
        then return from the trap via mret (PC <- mepc). }
      rv32_lw(reg_t0, reg_sp, 0);  rv32_lw(reg_t1, reg_sp, 4);  rv32_lw(reg_t2, reg_sp, 8);
      rv32_lw(reg_t3, reg_sp, 12); rv32_lw(reg_t4, reg_sp, 16); rv32_lw(reg_t5, reg_sp, 20);
      rv32_lw(reg_t6, reg_sp, 24);
      rv32_lw(reg_a0, reg_sp, 28); rv32_lw(reg_a1, reg_sp, 32); rv32_lw(reg_a2, reg_sp, 36);
      rv32_lw(reg_a3, reg_sp, 40); rv32_lw(reg_a4, reg_sp, 44); rv32_lw(reg_a5, reg_sp, 48);
      rv32_lw(reg_a6, reg_sp, 52); rv32_lw(reg_a7, reg_sp, 56);
      rv32_addi(reg_sp, reg_sp, 64);
      rv32_mret;
    end
    else
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
    if RetViaHiddenDest(Syms[retSymIdx].TypeKind) and
       (CurProc >= 0) and (ProcAggregateDestSym[CurProc] >= 0) then
    begin
      { Aggregate results use a hidden caller-owned destination pointer in r10.
        The prologue saves it in a local so nested calls cannot clobber it. }
      EmitLoadVar(ProcAggregateDestSym[CurProc]);
      EmitB($50);                                  { push original destination }
      EmitB($48); EmitB($89); EmitB($C7);          { mov rdi, rax }
      EmitB($48); EmitB($8D); EmitB($B5); EmitI32(Syms[retSymIdx].Offset); { lea rsi, [rbp+off] }
      sz := AggRetCopySize(retSymIdx);
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
    else if (CurProc >= 0) and ProcCdecl[CurProc] and
            (Syms[retSymIdx].TypeKind = tySingle) and
            (Syms[retSymIdx].Kind = skLocal) then
    begin
      { cdecl (C) function returning `float`: SysV returns a SINGLE in xmm0, and
        the cdecl call site widens it (cvtss2sd) into the double value model. So
        the callee must leave a RAW single in xmm0 — NOT the double that
        EmitLoadVar produces (movss + cvtss2sd). Emitting the widened double let
        the caller's cvtss2sd reinterpret double bits as single => garbage (~0);
        double returns were fine because neither side converts. Load the single
        with no widen and no rax bridge (the cdecl caller reads xmm0, not rax). }
      EmitB($F3); EmitB($0F); EmitB($10); EmitB($85); EmitI32(Syms[retSymIdx].Offset); { movss xmm0, [rbp+off] }
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
  { Register calling convention (feature-callconv-register-args): restore the
    caller's r14/r15 (callee-saved) from their reserved frame slots before the
    frame teardown. Reached by every return (early Exit and fall-through both go
    through EmitProcEpilog). rbp is still valid here; rax (the result) untouched. }
  for i := 0 to RcResidentCount - 1 do
  begin
    EmitB($4C); EmitB($8B); EmitB($85 or ((RcResidentReg[i] - 8) shl 3));           { mov r12..r15, [rbp+off] }
    EmitI32(RcResidentSaveOff[i]);
  end;
  { -O3 W1 callee-saved scratch: restore the caller's r12/r13 from their frame
    slots (saved once by CalleeScratchAssign). Reached by every return path,
    exactly like the r14/r15 residency restore above. }
  if CsScratchOn then
  begin
    EmitB($4C); EmitB($8B); EmitB($A5); EmitI32(CsSaveOff12);  { mov r12, [rbp+off] }
    EmitB($4C); EmitB($8B); EmitB($AD); EmitI32(CsSaveOff13);  { mov r13, [rbp+off] }
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

{ Load the resolved address of an external routine into rax. Reuses the dynamic
  GOT slot/fixup table used by external calls; x86-64 encodes `mov rax,[abs32]`.
  Other backends still reject this until they grow an equivalent address-load
  sequence. }
procedure EmitExternalProcAddr(procIdx: Integer);
var extIdx: Integer;
begin
  extIdx := RegisterExternal(procIdx);
  if DynCallCount >= MAX_CALLFIX then Error('external call fixup overflow');
  { @extern -> the resolved function pointer in the result register, via the same
    GOT slot the call path uses (PatchDynCallSites patches the address), but with
    a plain load instead of a call. Lets sqlite's unix VFS build its aSyscall[]
    table of pointers to open/close/fstat/... (never called with a :memory: DB). }
  if TargetArch = TARGET_X86_64 then
  begin
    EmitB($48); EmitB($8B); EmitB($04); EmitB($25); { mov rax, [abs GOT slot] }
    DynCallCodePos[DynCallCount] := CodeLen;
    DynCallExtIdx[DynCallCount] := extIdx;
    Inc(DynCallCount);
    EmitI32(0);
  end
  else if TargetArch = TARGET_AARCH64 then
  begin
    DynCallCodePos[DynCallCount] := CodeLen;   { movz/movk pair patched with slot VA }
    DynCallExtIdx[DynCallCount] := extIdx;
    Inc(DynCallCount);
    EmitI32($D2800010);   { movz x16, #0        (lo16 patched) }
    EmitI32($F2A00010);   { movk x16, #0, lsl 16 (hi16 patched) }
    EmitI32($F9400200);   { ldr  x0, [x16]      (resolved fn ptr) }
  end
  else if TargetArch = TARGET_ARM32 then
  begin
    DynCallCodePos[DynCallCount] := CodeLen;   { movw/movt pair patched with slot VA }
    DynCallExtIdx[DynCallCount] := extIdx;
    Inc(DynCallCount);
    EmitI32($E300C000);   { movw ip, #0   (lo16 patched) }
    EmitI32($E340C000);   { movt ip, #0   (hi16 patched) }
    EmitI32($E59C0000);   { ldr  r0, [ip] (resolved fn ptr) }
  end
  else if TargetArch = TARGET_RISCV32 then
  begin
    { Same inline-literal slot the riscv32 external CALL uses (EmitCallProc): the
      DynCall pass patches the 4-byte literal to the resolved fn address. Here we
      just load it into a0 instead of calling it — lets sqlite's unix VFS build
      its aSyscall[] table of open/close/fstat/... pointers. }
    rv32_auipc(reg_a0, 0);            { a0 = PC of this auipc }
    rv32_jal(reg_zero, 8);            { skip the 4-byte literal }
    DynCallCodePos[DynCallCount] := CodeLen;
    DynCallExtIdx[DynCallCount] := extIdx;
    Inc(DynCallCount);
    EmitI32(0);                       { literal: resolved fn addr (patched) }
    rv32_lw(reg_a0, reg_a0, 8);       { a0 = [auipc_pc + 8] = fn addr }
  end
  else
    Error('@ on external routine not supported on this target');
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
var extIdx, rvHi, rvLo: Integer;
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
    { auipc+jalr (full 32-bit range) rather than a single JAL (+/-1MB) — a large
      binary like cross lua (1.75MB code) places callees beyond JAL's reach, so a
      truncated offset jumped to garbage. reg_t0 is a caller-saved scratch. }
    if Procs[procIdx].BodyAddr >= 0 then
    begin
      RISCVPcrelSplit(Procs[procIdx].BodyAddr - CodeLen, rvHi, rvLo);
      rv32_auipc(reg_t0, rvHi);
      rv32_jalr(reg_ra, reg_t0, rvLo);
    end
    else
    begin
      if CallFixCount >= MAX_CALLFIX then Error('call fixup overflow');
      CallFix[CallFixCount].CodePos := CodeLen;
      CallFix[CallFixCount].ProcIdx := procIdx;
      Inc(CallFixCount);
      rv32_auipc(reg_t0, 0);
      rv32_jalr(reg_ra, reg_t0, 0);
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
var i, procIdx, rvHi, rvLo: Integer;
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
    begin
      { auipc+jalr pair (see EmitCallProc): patch both words. }
      RISCVPcrelSplit(Procs[procIdx].BodyAddr - CallFix[i].CodePos, rvHi, rvLo);
      Patch32(CallFix[i].CodePos, EncodeRISCVAuipc(reg_t0, rvHi));
      Patch32(CallFix[i].CodePos + 4, EncodeRISCVJalr(reg_ra, reg_t0, rvLo));
    end
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
  begin
    { Array symbols store their ELEMENT record in ElemRecName, not RecName
      (RecName is for a plain scalar/record-typed symbol) -- a recurring
      landmine throughout this codebase. Reachable from C's `arr->field`
      where `arr` is an array (C array-to-pointer decay lets `->` apply to
      an array; CNodeIsPointer's array exclusion means cparser.inc builds a
      plain AN_FIELD directly over the array AN_IDENT, not a dereferenced
      pointer, so this path sees an array base where Pascal code never
      would). Reading RecName there previously resolved REC_NONE, which
      cascaded into the field's type tag defaulting to tyInteger (4 bytes)
      instead of the real (often 8-byte pointer) field type — the
      truncated/sign-extended values in
      bug-c-arrow-on-array-store-of-call-result-clobbered. }
    if Syms[ASTIVal[node]].IsArray then
      Result := Syms[ASTIVal[node]].ElemRecName
    else
      Result := Syms[ASTIVal[node]].RecName;
  end
  else if ASTKind[node] = AN_COMPOUND_LITERAL then
    { C99 compound literal — its record is the hidden temp's RecName. }
    Result := Syms[Integer(ASTIVal[node])].RecName
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
    else if ASTKind[ASTLeft[node]] = AN_ADDR then
      { `(&X)[i]` indexes a pointer to X, so the element record is X's own record. }
      Result := ResolveNodeRec(ASTLeft[ASTLeft[node]])
    else if ASTKind[ASTLeft[node]] = AN_PTR_CAST then
      { `((T *) x)[i]` — element record is the cast's pointee record (alias table).
        Without this the record id is lost and the subsequent `.field` type-tag
        defaults to tyInteger (4 bytes), truncating 8-byte pointer fields — the
        duktape value-stack `((duk_tval *) ...)[i].v.heaphdr` access, whose
        truncated pointer later crashes duk_pcompile. }
      if ASTIVal[ASTLeft[node]] >= 0 then
        Result := AliasElemRec[ASTIVal[ASTLeft[node]]]
      else
        Result := REC_NONE
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
    else if ASTKind[baseNode] = AN_ADDR then
      Result := ResolveNodeRec(ASTLeft[baseNode])
    else if ASTKind[baseNode] = AN_INDEX then
    begin
      innerNode := ASTLeft[baseNode];
      if ASTKind[innerNode] = AN_IDENT then
        Result := Syms[ASTIVal[innerNode]].PtrElemRec
      else if ASTKind[innerNode] = AN_FIELD then
      begin
        baseRec := ResolveNodeRec(ASTLeft[innerNode]);
        fieldName := GetASTIdentName(innerNode);
        fIdx := -1;
        if baseRec >= REC_UCLASS_BASE then
          fIdx := FindUField(baseRec - REC_UCLASS_BASE, fieldName);
        if fIdx >= 0 then
          Result := UFldPtrElemRec[fIdx]
        else
          Result := REC_NONE;
      end
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
  else if ASTKind[node] = AN_METACLASS_NEW then
    { `classRefVar.Create` yields an instance of the metaclass's base class;
      the record id is stashed in ASTSLen at parse time. }
    Result := ASTSLen[node]
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
  else if ASTKind[node] = AN_TERNARY then
  begin
    { A record-valued conditional (`cond ? recA : recB`) has the arms' record
      type. Without this a NESTED struct ternary resolved REC_NONE -> the outer
      arm's hidden temp got no RecName -> wrong RecSize -> garbage copy. }
    Result := ResolveNodeRec(ASTLeft[ASTRight[node]]);
    if Result = REC_NONE then Result := ResolveNodeRec(ASTRight[ASTRight[node]]);
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
  i, ci, targetAlias: Integer;
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
        if AliasPtrDepth[i] = 1 then
        begin
          AliasPtrBaseTk[i] := AliasElemTk[i];
          AliasPtrBaseRec[i] := AliasElemRec[i];
        end;
      end
      else
      begin
        targetAlias := FindTypeAlias(targetName);
        if (targetAlias >= 0) and (AliasTk[targetAlias] = Ord(tyPointer)) and
           (AliasPtrDepth[targetAlias] > 0) and (AliasElemTk[i] = Ord(tyPointer)) then
        begin
          AliasPtrBaseTk[i] := AliasPtrBaseTk[targetAlias];
          AliasPtrBaseRec[i] := AliasPtrBaseRec[targetAlias];
        end;
      end;
    end;
  end;
end;

{ ===== Expression parser ===== }
