{ ===== RTTI emission (Phase 1: published-only, streaming-grade) =====

  Emits, for every class with >=1 published member, a compile-time RTTI blob
  into Data[], plus a name->RTTI registry. Layout is OUR own (see defs.inc
  RTTI_* constants); the public reflection API (Phase 2) puts TypInfo names on
  top of it. Cross-references between blobs use AddDataPtrFix (data->data);
  method/proc code addresses use MethodFixups (patched to runtime addresses at
  link time), exactly as the VMT does.

  proto-unit shape:
    needs:  UCls*/UFld*/UMth*/UProp* tables, UClsVMTOffset, UClsSize_,
            Find*/InternStr/Strs/DataPut*/AddDataPtrFix/MethodFixups
    provides: EmitRTTI, DumpRTTITables

  This file is included after elfwriter.inc (DataPut*/PatchDataU64 live there)
  and is driven once from the main program after parsing. }

procedure EmitLayoutRTTI; forward;

function FieldIsManaged(fi: Integer): Boolean;
begin
  FieldIsManaged := False;
  if UFldTk[fi] = Ord(tyAnsiString) then FieldIsManaged := True
  else if UFldIsArray[fi] and (UFldArrLen[fi] = -1) then FieldIsManaged := True
  else if (UFldTk[fi] = Ord(tyRecord)) and RecordHasManagedFields(UFldRec_[fi]) then FieldIsManaged := True;
end;

function RecordManagedFieldCount(ci: Integer): Integer;
var base, cnt, i, managed: Integer;
begin
  managed := 0;
  base := UClsFBase[ci];
  cnt := UClsFCount[ci];
  for i := 0 to cnt - 1 do
  begin
    if FieldIsManaged(base + i) then Inc(managed);
  end;
  RecordManagedFieldCount := managed;
end;

function TokSliceStr(off, len: Integer): AnsiString;
{ Build a real string from a name slice in TokChars (self-host safe: AppendChar). }
var s: AnsiString; i: Integer;
begin
  s := '';
  i := 0;
  while i < len do
  begin
    AppendChar(s, TokChars[off + i]);
    Inc(i);
  end;
  TokSliceStr := s;
end;

function ClassHasPublished(ci: Integer): Boolean;
{ True if this class OR any ancestor declares a published member. A class that
  only inherits published members is still streamable (GetClass must find it),
  so it needs an RTTI header too. }
var base, cnt, i, curr: Integer;
begin
  ClassHasPublished := False;
  curr := ci;
  while curr >= 0 do
  begin
    base := UClsFBase[curr]; cnt := UClsFCount[curr];
    for i := 0 to cnt - 1 do
      if UFldPub[base + i] = 1 then begin ClassHasPublished := True; Exit; end;
    base := UClsMBase[curr]; cnt := UClsMCount[curr];
    for i := 0 to cnt - 1 do
      if UMthPub[base + i] = 1 then begin ClassHasPublished := True; Exit; end;
    base := UClsPBase[curr]; cnt := UClsPCount[curr];
    for i := 0 to cnt - 1 do
      if UPropPub[base + i] = 1 then begin ClassHasPublished := True; Exit; end;
    curr := UClsParent[curr];
  end;
end;

procedure DataPutZeros(n: Integer);
var i: Integer;
begin
  i := 0;
  while i < n do begin DataPutB(0); Inc(i); end;
end;

procedure QueueMethCodeFixup(dataPos, procIdx: Integer);
begin
  if MethodFixCount >= MAX_METHFIX then Error('too many method fixups (RTTI)');
  MethodFixups[MethodFixCount].DataPos := dataPos;
  MethodFixups[MethodFixCount].ProcIdx := procIdx;
  Inc(MethodFixCount);
end;

{ Emit an enum type RTTI blob: name ptr, value count, ptr to array of name ptrs.
  Returns the Data[] offset of the header. }
function EmitEnumRTTI(etid: Integer): Integer;
var hdr, arrOff, base, cnt, i, strIdx: Integer;
    nm: AnsiString;
begin
  base := EnumTypeValBase[etid];
  cnt := EnumTypeValCount[etid];
  arrOff := DataLen;
  DataPutZeros(cnt * 8);
  for i := 0 to cnt - 1 do
  begin
    nm := TokSliceStr(EnumValNOff[base + i], EnumValNLen[base + i]);
    strIdx := InternStr(nm);
    AddDataPtrFix(arrOff + i * 8, Strs[strIdx].Offset);
  end;
  hdr := DataLen;
  DataPutZeros(24);
  nm := TokSliceStr(EnumTypeNOff[etid], EnumTypeNLen[etid]);
  strIdx := InternStr(nm);
  AddDataPtrFix(hdr + 0, Strs[strIdx].Offset);
  PatchDataU64(hdr + 8, cnt);
  if cnt > 0 then AddDataPtrFix(hdr + 16, arrOff);
  EmitEnumRTTI := hdr;
end;

{ Fill a PropInfo record at the already-reserved offset piPos for property pri
  belonging to ci. The record (RTTI_PROP_SIZE bytes) must be reserved by the
  caller BEFORE calling this: InternStr appends string data to Data[], so any
  interning done here would otherwise land between consecutive records and
  break the runtime's fixed-stride props[i] indexing. }
procedure EmitPropInfo(ci, pri, piPos: Integer);
var tk, kind, tci, eid, strIdx, fIdx, mIdx, procIdx: Integer;
    nm: AnsiString;
begin
  { name }
  nm := TokSliceStr(UPropNOff[pri], UPropNLen[pri]);
  strIdx := InternStr(nm);
  AddDataPtrFix(piPos + 0, Strs[strIdx].Offset);

  { kind from declared type (enum identity overrides the integer fallback) }
  tk := UPropTk[pri];
  if UPropEnumId[pri] >= 0 then kind := RTTI_KIND_ENUM
  else if tk = Ord(tyString) then kind := RTTI_KIND_STRING
  else if tk = Ord(tyClass) then kind := RTTI_KIND_CLASS
  else if tk = Ord(tySet) then kind := RTTI_KIND_SET
  else if tk = Ord(tyRecord) then
  begin
    tci := UPropRec[pri] - REC_UCLASS_BASE;
    if (tci >= 0) and (tci < UClsCount) and 
       (LowerCase(TokSliceStr(UClsNOff[tci], UClsNLen[tci])) = 'tmethod') then
      kind := RTTI_KIND_METHOD
    else
      kind := RTTI_KIND_INT;
  end
  else kind := RTTI_KIND_INT;
  PatchDataU64(piPos + 8, kind);

  { typeRef: class props -> class RTTI; enum props -> enum RTTI }
  if kind = RTTI_KIND_CLASS then
  begin
    tci := UPropRec[pri] - REC_UCLASS_BASE;
    if (tci >= 0) and (tci < UClsCount) and (UClsRTTIOff[tci] >= 0) then
      AddDataPtrFix(piPos + 16, UClsRTTIOff[tci]);
  end
  else if kind = RTTI_KIND_ENUM then
  begin
    eid := UPropEnumId[pri];
    if (eid >= 0) and (EnumTypeRTTIOff[eid] >= 0) then
      AddDataPtrFix(piPos + 16, EnumTypeRTTIOff[eid]);
  end
  else if kind = RTTI_KIND_SET then
  begin
    { typeRef -> element enum RTTI, so streaming can map member names to bits }
    eid := UPropSetEnumId[pri];
    if (eid >= 0) and (EnumTypeRTTIOff[eid] >= 0) then
      AddDataPtrFix(piPos + 16, EnumTypeRTTIOff[eid]);
  end;

  { getter: field (getKind=0, getRef=byte offset) or method (getKind=1, getRef=code) }
  if UPropReadFLen[pri] > 0 then
  begin
    nm := TokSliceStr(UPropReadFOff[pri], UPropReadFLen[pri]);
    fIdx := FindUField(ci, nm);
    PatchDataU64(piPos + 24, 0);
    if fIdx >= 0 then PatchDataU64(piPos + 32, UFldOff_[fIdx]);
  end
  else if UPropReadMLen[pri] > 0 then
  begin
    nm := TokSliceStr(UPropReadMOff[pri], UPropReadMLen[pri]);
    mIdx := FindUMeth(ci, nm);
    PatchDataU64(piPos + 24, 1);
    if mIdx >= 0 then
    begin
      procIdx := UMthProc_[mIdx];
      if procIdx >= 0 then QueueMethCodeFixup(piPos + 32, procIdx);
    end;
  end;

  { setter }
  if UPropWriteFLen[pri] > 0 then
  begin
    nm := TokSliceStr(UPropWriteFOff[pri], UPropWriteFLen[pri]);
    fIdx := FindUField(ci, nm);
    PatchDataU64(piPos + 40, 0);
    if fIdx >= 0 then PatchDataU64(piPos + 48, UFldOff_[fIdx]);
  end
  else if UPropWriteMLen[pri] > 0 then
  begin
    nm := TokSliceStr(UPropWriteMOff[pri], UPropWriteMLen[pri]);
    mIdx := FindUMeth(ci, nm);
    PatchDataU64(piPos + 40, 1);
    if mIdx >= 0 then
    begin
      procIdx := UMthProc_[mIdx];
      if procIdx >= 0 then QueueMethCodeFixup(piPos + 48, procIdx);
    end;
  end;

  { ordType: type-kind hint (size/sign for ordinals) }
  PatchDataU64(piPos + 56, tk);
end;

{ Fill a MethInfo record (RTTI_METH_SIZE bytes) at the already-reserved offset
  miPos for published method mi. Record must be reserved by the caller first
  (see EmitPropInfo: InternStr appends and would otherwise split the array). }
procedure EmitMethInfo(mi, miPos: Integer);
var strIdx, procIdx: Integer;
    nm: AnsiString;
begin
  nm := TokSliceStr(UMthNOff[mi], UMthNLen[mi]);
  strIdx := InternStr(nm);
  AddDataPtrFix(miPos + 0, Strs[strIdx].Offset);
  procIdx := UMthProc_[mi];
  if procIdx >= 0 then QueueMethCodeFixup(miPos + 8, procIdx);
end;

{ Fill a FieldInfo record (RTTI_FIELD_SIZE bytes) at fiPos for published field
  fi: name ptr + byte offset. Lets the streamer wire a named child component into
  its matching published field (e.g. a .lfm Button1 child -> TForm1.Button1).
  Record must be reserved by the caller first (InternStr appends to Data[]). }
procedure EmitFieldInfo(fi, fiPos: Integer);
var strIdx: Integer; nm: AnsiString;
begin
  nm := TokSliceStr(UFldNOff[fi], UFldNLen[fi]);
  strIdx := InternStr(nm);
  AddDataPtrFix(fiPos + 0, Strs[strIdx].Offset);
  PatchDataU64(fiPos + 8, UFldOff_[fi]);
end;

procedure EmitRTTI;
var ci, i, k, base, cnt, hdr, strIdx, etid: Integer;
    propCount, methCount, fieldCount, firstOff: Integer;
    regEntries, entryPos: Integer;
    nm: AnsiString;
begin
  RTTIRegistryOff := -1;
  RTTIRegistryCount := 0;
  for ci := 0 to MAX_UCLASS - 1 do UClsRTTIOff[ci] := -1;

  { Enum type RTTI first, so prop typeRefs can point at it. }
  for etid := 0 to EnumTypeCount - 1 do
    EnumTypeRTTIOff[etid] := EmitEnumRTTI(etid);

  if UClsCount > 0 then
  begin
    { Pass 1: reserve a header per published class so forward type refs resolve. }
    for ci := 0 to UClsCount - 1 do
    begin
      if (not UClsIsRecord[ci]) and ClassHasPublished(ci) then
      begin
        UClsRTTIOff[ci] := DataLen;
        DataPutZeros(RTTI_CLS_SIZE);
      end;
    end;

    { Pass 2: fill headers + emit prop/meth arrays. }
    for ci := 0 to UClsCount - 1 do
    begin
      if UClsRTTIOff[ci] < 0 then continue;
      hdr := UClsRTTIOff[ci];

      { name }
      nm := TokSliceStr(UClsNOff[ci], UClsNLen[ci]);
      strIdx := InternStr(nm);
      AddDataPtrFix(hdr + 0, Strs[strIdx].Offset);

      { parent RTTI }
      if (UClsParent[ci] >= 0) and (UClsRTTIOff[UClsParent[ci]] >= 0) then
        AddDataPtrFix(hdr + 8, UClsRTTIOff[UClsParent[ci]]);

      { instance size }
      PatchDataU64(hdr + 16, UClsSize_[ci]);

      { VMT pointer }
      if UClsVMTOffset[ci] >= 0 then
        AddDataPtrFix(hdr + 24, UClsVMTOffset[ci]);

      { published properties (own). Reserve the whole array contiguously BEFORE
        filling: EmitPropInfo interns names (which append to Data[]), so records
        must be laid out first or the runtime's props[i] stride breaks. }
      base := UClsPBase[ci]; cnt := UClsPCount[ci];
      propCount := 0;
      for i := 0 to cnt - 1 do
        if UPropPub[base + i] = 1 then Inc(propCount);
      firstOff := -1;
      if propCount > 0 then
      begin
        firstOff := DataLen;
        DataPutZeros(propCount * RTTI_PROP_SIZE);
        k := 0;
        for i := 0 to cnt - 1 do
          if UPropPub[base + i] = 1 then
          begin
            EmitPropInfo(ci, base + i, firstOff + k * RTTI_PROP_SIZE);
            Inc(k);
          end;
      end;
      PatchDataU64(hdr + 32, propCount);
      if propCount > 0 then AddDataPtrFix(hdr + 40, firstOff);

      { published methods (own) — same contiguous-reserve-then-fill rule. }
      base := UClsMBase[ci]; cnt := UClsMCount[ci];
      methCount := 0;
      for i := 0 to cnt - 1 do
        if UMthPub[base + i] = 1 then Inc(methCount);
      firstOff := -1;
      if methCount > 0 then
      begin
        firstOff := DataLen;
        DataPutZeros(methCount * RTTI_METH_SIZE);
        k := 0;
        for i := 0 to cnt - 1 do
          if UMthPub[base + i] = 1 then
          begin
            EmitMethInfo(base + i, firstOff + k * RTTI_METH_SIZE);
            Inc(k);
          end;
      end;
      PatchDataU64(hdr + 48, methCount);
      if methCount > 0 then AddDataPtrFix(hdr + 56, firstOff);

      { published fields (own) — same contiguous-reserve-then-fill rule. Used to
        wire streamed child components into their matching published field. }
      base := UClsFBase[ci]; cnt := UClsFCount[ci];
      fieldCount := 0;
      for i := 0 to cnt - 1 do
        if UFldPub[base + i] = 1 then Inc(fieldCount);
      firstOff := -1;
      if fieldCount > 0 then
      begin
        firstOff := DataLen;
        DataPutZeros(fieldCount * RTTI_FIELD_SIZE);
        k := 0;
        for i := 0 to cnt - 1 do
          if UFldPub[base + i] = 1 then
          begin
            EmitFieldInfo(base + i, firstOff + k * RTTI_FIELD_SIZE);
            Inc(k);
          end;
      end;
      PatchDataU64(hdr + 64, fieldCount);
      if fieldCount > 0 then AddDataPtrFix(hdr + 72, firstOff);
    end;
  end;

  EmitLayoutRTTI;

  if UClsCount > 0 then
  begin
    { Registry: count slot followed by (name ptr, rtti ptr) pairs }
    regEntries := 0;
    for ci := 0 to UClsCount - 1 do
      if UClsRTTIOff[ci] >= 0 then Inc(regEntries);
    if regEntries > 0 then
    begin
      RTTIRegistryOff := DataLen;
      RTTIRegistryCount := regEntries;
      DataPutZeros(8);                       { count slot }
      PatchDataU64(RTTIRegistryOff, regEntries);
      for ci := 0 to UClsCount - 1 do
      begin
        if UClsRTTIOff[ci] < 0 then continue;
        entryPos := DataLen;
        DataPutZeros(16);
        nm := TokSliceStr(UClsNOff[ci], UClsNLen[ci]);
        strIdx := InternStr(nm);
        AddDataPtrFix(entryPos + 0, Strs[strIdx].Offset);
        AddDataPtrFix(entryPos + 8, UClsRTTIOff[ci]);
      end;
    end;
  end;
end;

procedure EmitLayoutRTTI;
var
  ci, i, fi, base, cnt, mCount, dCount, mHdr, dynDescOff: Integer;
  hdr, subCi, arrCount, mKind, typeRef: Integer;
  depth, baseKind, elSize, baseTypeRef, k, dynIdx: Integer;
  targetPtrSize: Integer;



begin
  targetPtrSize := TARGET_PTR_SIZE;

  { Pass 1: pre-allocate RTTI offsets in Data[] }
  for ci := 0 to UClsCount - 1 do
  begin
    if UClsIsRecord[ci] and RecordHasManagedFields(ci + REC_UCLASS_BASE) then
    begin
      UClsRTTIOff[ci] := DataLen;
      mCount := 0;
      dCount := 0;
      base := UClsFBase[ci];
      cnt := UClsFCount[ci];
      for i := 0 to cnt - 1 do
      begin
        fi := base + i;
        if FieldIsManaged(fi) then
        begin
          Inc(mCount);
          if UFldIsArray[fi] and (UFldArrLen[fi] = -1) then
            Inc(dCount);
        end;
      end;
      DataPutZeros(12 + mCount * 16 + dCount * 20);
    end;
  end;



  { Pass 2: fill descriptors }
  for ci := 0 to UClsCount - 1 do
  begin
    if UClsIsRecord[ci] and RecordHasManagedFields(ci + REC_UCLASS_BASE) then
    begin
      hdr := UClsRTTIOff[ci];
      PatchDataI32(hdr + 0, 1); { Kind = 1 (Record) }
      PatchDataI32(hdr + 4, UClsSize_[ci]); { Size }

      base := UClsFBase[ci];
      cnt := UClsFCount[ci];
      mCount := RecordManagedFieldCount(ci);

      k := 0;
      dynIdx := 0;
      for i := 0 to cnt - 1 do
      begin
        fi := base + i;
        if FieldIsManaged(fi) then
        begin
          mHdr := hdr + 12 + k * 16;
          PatchDataI32(mHdr + 0, UFldOff_[fi]); { Offset }

          if UFldTk[fi] = Ord(tyAnsiString) then
            mKind := 1
          else if UFldIsArray[fi] and (UFldArrLen[fi] = -1) then
            mKind := 2
          else
            mKind := 3;
          PatchDataI32(mHdr + 4, mKind);

          if UFldIsArray[fi] then
          begin
            if UFldArrLen[fi] = -1 then
              arrCount := 1
            else
              arrCount := UFldArrLen[fi];
          end
          else
            arrCount := 1;
          PatchDataI32(mHdr + 8, arrCount);

          typeRef := 0;
          if mKind = 2 then
          begin
            dynDescOff := hdr + 12 + mCount * 16 + dynIdx * 20;
            typeRef := dynDescOff - (mHdr + 12);

            PatchDataI32(dynDescOff + 0, 2); { Kind = 2 (DynArray) }

            depth := UFldDynDepth[fi];
            if UFldTk[fi] = Ord(tyAnsiString) then
              baseKind := 1
            else if (UFldTk[fi] = Ord(tyRecord)) and RecordHasManagedFields(UFldRec_[fi]) then
              baseKind := 3
            else
              baseKind := 0;

            if depth > 1 then
              elSize := targetPtrSize
            else
            begin
              if baseKind = 1 then
                elSize := targetPtrSize
              else if baseKind = 3 then
                elSize := UClsSize_[UFldRec_[fi] - REC_UCLASS_BASE]
              else
                elSize := TypeSize(IntToTypeKind(UFldTk[fi]));
            end;
            PatchDataI32(dynDescOff + 4, elSize);
            PatchDataI32(dynDescOff + 8, depth);
            PatchDataI32(dynDescOff + 12, baseKind);

            baseTypeRef := 0;
            if baseKind = 3 then
            begin
              subCi := UFldRec_[fi] - REC_UCLASS_BASE;
              if (subCi >= 0) and (subCi < UClsCount) and (UClsRTTIOff[subCi] >= 0) then
                baseTypeRef := UClsRTTIOff[subCi] - (dynDescOff + 16);
            end;
            PatchDataI32(dynDescOff + 16, baseTypeRef);

            Inc(dynIdx);
          end
          else if mKind = 3 then
          begin
            subCi := UFldRec_[fi] - REC_UCLASS_BASE;
            if (subCi >= 0) and (subCi < UClsCount) and (UClsRTTIOff[subCi] >= 0) then
              typeRef := UClsRTTIOff[subCi] - (mHdr + 12);
          end;
          PatchDataI32(mHdr + 12, typeRef);

          Inc(k);
        end;
      end;
      PatchDataI32(hdr + 8, k); { MemberCount }
    end;
  end;



  for i := 0 to AnonDynArrayCount - 1 do
  begin
    hdr := AnonDynArrayOff[i];
    PatchDataI32(hdr + 0, 2); { Kind = 2 (DynArray) }

    depth := AnonDynArrayDepth[i];
    if AnonDynArrayBaseTk[i] = Ord(tyAnsiString) then
      baseKind := 1
    else if (AnonDynArrayBaseTk[i] = Ord(tyRecord)) and RecordHasManagedFields(AnonDynArrayBaseRec[i]) then
      baseKind := 3
    else
      baseKind := 0;

    if depth > 1 then
      elSize := targetPtrSize
    else
    begin
      if baseKind = 1 then
        elSize := targetPtrSize
      else if baseKind = 3 then
        elSize := UClsSize_[AnonDynArrayBaseRec[i] - REC_UCLASS_BASE]
      else
        elSize := AnonDynArrayElSize[i];
    end;
    PatchDataI32(hdr + 4, elSize);
    PatchDataI32(hdr + 8, depth);
    PatchDataI32(hdr + 12, baseKind);

    baseTypeRef := 0;
    if baseKind = 3 then
    begin
      subCi := AnonDynArrayBaseRec[i] - REC_UCLASS_BASE;
      if (subCi >= 0) and (subCi < UClsCount) and (UClsRTTIOff[subCi] >= 0) then
        baseTypeRef := UClsRTTIOff[subCi] - (hdr + 16);
    end;
    PatchDataI32(hdr + 16, baseTypeRef);
  end;
end;

{ Compile-time structural dump (--dump-rtti). Proves names/kinds/offsets and
  resolved proc indices; runtime method *addresses* are validated in Phase 2. }
procedure DumpRTTITables;
var ci, i, base, cnt, pri, tk, mi, fIdx, procIdx, etid, vb: Integer;
    nm: AnsiString;
begin
  writeln('RTTI: registryOff=', RTTIRegistryOff, ' classes=', RTTIRegistryCount);
  for etid := 0 to EnumTypeCount - 1 do
  begin
    nm := TokSliceStr(EnumTypeNOff[etid], EnumTypeNLen[etid]);
    write('enum ', nm, ' count=', EnumTypeValCount[etid], ' rttiOff=', EnumTypeRTTIOff[etid]);
    vb := EnumTypeValBase[etid];
    for i := 0 to EnumTypeValCount[etid] - 1 do
      write(' ', TokSliceStr(EnumValNOff[vb + i], EnumValNLen[vb + i]));
    writeln;
  end;
  for ci := 0 to UClsCount - 1 do
  begin
    if UClsRTTIOff[ci] < 0 then continue;
    nm := TokSliceStr(UClsNOff[ci], UClsNLen[ci]);
    writeln('class ', nm, ' rttiOff=', UClsRTTIOff[ci],
            ' size=', UClsSize_[ci], ' vmtOff=', UClsVMTOffset[ci]);
    base := UClsPBase[ci]; cnt := UClsPCount[ci];
    for i := 0 to cnt - 1 do
    begin
      pri := base + i;
      if UPropPub[pri] <> 1 then continue;
      nm := TokSliceStr(UPropNOff[pri], UPropNLen[pri]);
      tk := UPropTk[pri];
      write('  prop ', nm, ' tk=', tk);
      if UPropEnumId[pri] >= 0 then
        write(' enum=', TokSliceStr(EnumTypeNOff[UPropEnumId[pri]], EnumTypeNLen[UPropEnumId[pri]]));
      if UPropReadFLen[pri] > 0 then
      begin
        fIdx := FindUField(ci, TokSliceStr(UPropReadFOff[pri], UPropReadFLen[pri]));
        if fIdx >= 0 then write(' getField@', UFldOff_[fIdx]);
      end
      else if UPropReadMLen[pri] > 0 then
      begin
        mi := FindUMeth(ci, TokSliceStr(UPropReadMOff[pri], UPropReadMLen[pri]));
        if mi >= 0 then write(' getMethProc=', UMthProc_[mi]);
      end;
      if UPropWriteFLen[pri] > 0 then
      begin
        fIdx := FindUField(ci, TokSliceStr(UPropWriteFOff[pri], UPropWriteFLen[pri]));
        if fIdx >= 0 then write(' setField@', UFldOff_[fIdx]);
      end
      else if UPropWriteMLen[pri] > 0 then
      begin
        mi := FindUMeth(ci, TokSliceStr(UPropWriteMOff[pri], UPropWriteMLen[pri]));
        if mi >= 0 then write(' setMethProc=', UMthProc_[mi]);
      end;
      writeln;
    end;
    base := UClsMBase[ci]; cnt := UClsMCount[ci];
    for i := 0 to cnt - 1 do
    begin
      mi := base + i;
      if UMthPub[mi] <> 1 then continue;
      nm := TokSliceStr(UMthNOff[mi], UMthNLen[mi]);
      procIdx := UMthProc_[mi];
      writeln('  meth ', nm, ' proc=', procIdx);
    end;
  end;
end;
