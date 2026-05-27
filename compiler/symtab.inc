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
var i, base, cnt: Integer; lo, name2: AnsiString;
begin
  Result := -1;
  name2 := name;
  lo := ULower(name2);
  base := UClsFBase[ci];
  cnt  := UClsFCount[ci];
  i := 0;
  while i < cnt do
  begin
    if UNameMatch(UFldNOff[base + i], UFldNLen[base + i], lo) then begin Result := base + i; Exit; end;
    Inc(i);
  end;
end;

function FindUMeth(ci: Integer; const name: AnsiString): Integer;
var i, base, cnt: Integer; lo, name2: AnsiString;
begin
  Result := -1;
  name2 := name;
  lo := ULower(name2);
  base := UClsMBase[ci];
  cnt  := UClsMCount[ci];
  i := 0;
  while i < cnt do
  begin
    if UNameMatch(UMthNOff[base + i], UMthNLen[base + i], lo) then begin Result := base + i; Exit; end;
    Inc(i);
  end;
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
  UClsCount := UClsCount + 1;
end;

procedure AddUField(ci, noff, nlen, byteOff, tk, recId: Integer);
var fi: Integer;
begin
  fi := UFldCount;
  UFldNOff[fi] := noff;  UFldNLen[fi] := nlen;
  UFldOff_[fi] := byteOff; UFldTk[fi] := tk; UFldRec_[fi] := recId;
  UFldCount := UFldCount + 1;
  UClsFCount[ci] := UClsFCount[ci] + 1;
end;

procedure AddUMeth(ci, noff, nlen, pi: Integer);
var mi: Integer;
begin
  mi := UMthCount;
  UMthNOff[mi] := noff; UMthNLen[mi] := nlen; UMthProc_[mi] := pi;
  UMthCount := UMthCount + 1;
  UClsMCount[ci] := UClsMCount[ci] + 1;
end;

{ ===== Record Helper Functions ===== }

const
  REC_NONE = 0;
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
  else if lo = 'TPendingGFSpec' then Result := REC_TPENDINGGFSPEC;
  if Result = REC_NONE then
  begin
    lo2 := lo;
    ci := FindUClass(lo2);
    if ci >= 0 then Result := REC_UCLASS_BASE + ci;
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
    if ci >= 0 then Result := True;
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
  else if rec = REC_TSYMBOL then Result := 344
  else if rec = REC_TPARAM then Result := 296
  else if rec = REC_TPROC then Result := 2688
  else if rec = REC_TRAWTOKEN then Result := 40
  else if rec = REC_TMYCLASS then Result := 16
  else if rec = REC_TTEMPLATE then Result := 544
  else if rec = REC_TSPECIALIZATION then Result := 800
  else if rec = REC_TGENERICFUNC then Result := 552
  else if rec = REC_TPENDINGGFSPEC then Result := 544
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
    else if field = 'IsRef' then Result := 336;
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
    if field = 'SVal' then Result := tyString;
  end
  else if rec = REC_TSTRENTRY then
  begin
    if field = 'Text' then Result := tyString;
  end
  else if rec = REC_TSYMBOL then
  begin
    if field = 'Name' then Result := tyString
    else if (field = 'IsArray') or (field = 'IsRef') then Result := tyBoolean;
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
    if StrEqual(Syms[i].Name, lo) then begin Result := i; Exit; end;

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
var sz: Integer;
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

  sz := 8;
  if tk = tyString then
  begin
    if CurProc < 0 then sz := STRING_CAP + 8
    else sz := LOCAL_STR_CAP + 8;
  end
  else if tk = tyRecord then sz := RecSize(LastTypeRecId);

  if CurProc < 0 then
  begin
    Syms[SymCount].Kind   := skGlobal;
    Syms[SymCount].Offset := BSSSize;
    Inc(BSSSize, sz);
  end
  else
  begin
    Inc(FrameSize, sz);
    Syms[SymCount].Kind   := skLocal;
    Syms[SymCount].Offset := -FrameSize;
  end;
  Result := SymCount; Inc(SymCount);
end;

function AllocArray(const name: AnsiString; elemType: TTypeKind; lo, hi: Integer): Integer;
var elemSize, totalSize: Integer;
begin
  if SymCount >= MAX_SYMS then Error('too many symbols');
  elemSize := 1;
  if elemType in [tyInteger, tyBoolean, tyClass] then elemSize := 8
  else if elemType = tyChar then elemSize := 1
  else if elemType = tyString then
  begin
    if CurProc < 0 then elemSize := STRING_CAP + 8
    else elemSize := LOCAL_STR_CAP + 8;
  end
  else if elemType = tyRecord then elemSize := RecSize(LastTypeRecId);

  totalSize := (hi - lo + 1) * elemSize;
  Syms[SymCount].Name     := name;
  Syms[SymCount].TypeKind := elemType;
  Syms[SymCount].ConstVal := lo;   { lo bound stored in ConstVal }
  Syms[SymCount].IsArray  := True;
  Syms[SymCount].ArrLen   := hi - lo + 1;
  Syms[SymCount].ElemType := elemType;
  Syms[SymCount].ElemRecName := LastTypeRecId;
  Syms[SymCount].IsRef    := False;

  if CurProc < 0 then
  begin
    Syms[SymCount].Kind   := skGlobal;
    Syms[SymCount].Offset := BSSSize;
    Inc(BSSSize, totalSize);
  end
  else
  begin
    Inc(FrameSize, totalSize);
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
begin
  if (Syms[idx].Kind = skParam) and Syms[idx].IsRef and
     (Syms[idx].TypeKind <> tyString) then
  begin
    { by-reference scalar: load pointer from slot, then load pointed value }
    EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[idx].Offset);
    if Syms[idx].TypeKind = tyChar then
      begin EmitB($48); EmitB($0F); EmitB($B6); EmitB($00); end
    else
      begin EmitB($48); EmitB($8B); EmitB($00); end;
  end
  else if (Syms[idx].Kind = skParam) and (Syms[idx].TypeKind = tyString) then
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
          if Syms[idx].TypeKind = tyChar then
            begin EmitB($48); EmitB($0F); EmitB($B6); EmitB($85); EmitI32(Syms[idx].Offset); end
          else
            begin EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[idx].Offset); end;
        end;
      skGlobal:
        begin
          if Syms[idx].TypeKind = tyChar then
            begin EmitB($48); EmitB($0F); EmitB($B6); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end
          else
            begin EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end;
        end;
      skConst:
        MovRaxImm(Syms[idx].ConstVal);
    end;
  end;
end;

procedure EmitStoreVar(idx: Integer);
begin
  if (Syms[idx].Kind = skParam) and Syms[idx].IsRef then
  begin
    EmitB($48); EmitB($8B); EmitB($8D); EmitI32(Syms[idx].Offset);
    if Syms[idx].TypeKind = tyChar then
      begin EmitB($88); EmitB($01); end
    else
      begin EmitB($48); EmitB($89); EmitB($01); end;
  end
  else case Syms[idx].Kind of
    skLocal, skParam:
      begin
        if Syms[idx].TypeKind = tyChar then
          begin EmitB($88); EmitB($85); EmitI32(Syms[idx].Offset); end
        else
          begin EmitB($48); EmitB($89); EmitB($85); EmitI32(Syms[idx].Offset); end;
      end;
    skGlobal:
      begin
        if Syms[idx].TypeKind = tyChar then
          begin EmitB($88); EmitB($04); EmitB($25); EmitGlobRef(Syms[idx].Offset); end
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

procedure EmitArrElemAddr(arrIdx: Integer);
{ On entry: rax = array index. On exit: rax = element address. }
var elemSize: Integer;
begin
  elemSize := 1;
  if Syms[arrIdx].ElemType in [tyInteger, tyBoolean, tyClass] then elemSize := 8
  else if Syms[arrIdx].ElemType = tyString then
  begin
    if Syms[arrIdx].Kind = skGlobal then elemSize := STRING_CAP + 8
    else elemSize := LOCAL_STR_CAP + 8;
  end
  else if Syms[arrIdx].ElemType = tyRecord then elemSize := RecSize(Syms[arrIdx].ElemRecName);
  
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
begin
  EmitArrElemAddr(arrIdx);
  if Syms[arrIdx].ElemType in [tyInteger, tyBoolean, tyClass] then
    begin EmitB($48); EmitB($8B); EmitB($00); end  { mov rax, [rax] }
  else
    begin EmitB($48); EmitB($0F); EmitB($B6); EmitB($00); end; { movzx rax, byte [rax] }
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
begin
  { addr was pushed before RHS eval }
  EmitB($59);                   { pop rcx -- element address }
  if Syms[arrIdx].ElemType in [tyInteger, tyBoolean, tyClass] then
    begin EmitB($48); EmitB($89); EmitB($01); end  { mov [rcx], rax }
  else
    begin EmitB($88); EmitB($01); end;              { mov [rcx], al }
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
  if (pType in [tyInteger, tyBoolean, tyChar]) and
     (aType in [tyInteger, tyBoolean, tyChar]) then
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

procedure EmitwriteChar;
{ rax = char byte value → write 1 byte to stdout }
begin
  { Store byte to INTBUF[0] in data section }
  EmitB($48); EmitB($BE); EmitDataRef(INTBUF_OFFSET);  { mov rsi, &intbuf }
  EmitB($88); EmitB($06);                               { mov [rsi], al }
  MovRaxImm(SYS_WRITE); MovRdiImm(STDOUT); MovRdxImm(1); EmitSyscall;
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
      if Syms[retSymIdx].Kind = skGlobal then
      begin
        EmitB($48); EmitB($8B); EmitB($04); EmitB($25); EmitGlobRef(Syms[retSymIdx].Offset);
      end
      else
      begin
        { Return contents of integer/char/boolean }
        EmitB($48); EmitB($8B); EmitB($85); EmitI32(Syms[retSymIdx].Offset);
      end;
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
    EmitB($FF); EmitB($14); EmitB($25); { call qword ptr [absolute address] }
    DynCallCodePos[DynCallCount] := CodeLen;
    DynCallExtIdx[DynCallCount] := extIdx;
    Inc(DynCallCount);
    EmitI32(0);
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

{ ===== Expression parser ===== }
