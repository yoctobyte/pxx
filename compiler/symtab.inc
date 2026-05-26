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

function FieldNameEqual(const f1, f2: AnsiString): Boolean;
var len, i: Integer; c1, c2: Char;
begin
  Result := False;
  len := Length(f1);
  if len = Length(f2) then
  begin
    Result := True;
    for i := 1 to len do
    begin
      c1 := f1[i]; c2 := f2[i];
      if (c1 >= 'a') and (c1 <= 'z') then Dec(c1, 32);
      if (c2 >= 'a') and (c2 <= 'z') then Dec(c2, 32);
      if c1 <> c2 then Result := False;
    end;
  end;
end;

function GetFieldSize(tk: TTypeKind; recId: Integer): Integer;
begin
  if tk = tyString then
    Result := 264
  else if tk = tyRecord then
    Result := Records[recId].Size
  else
    Result := 8;
end;

function AddRecord(const name: AnsiString; size: Integer; isClass: Boolean): Integer;
begin
  Inc(RecordCount);
  Records[RecordCount].Name := name;
  Records[RecordCount].Size := size;
  Records[RecordCount].IsClass := isClass;
  Records[RecordCount].FieldCount := 0;
  Result := RecordCount;
end;

procedure AddField(recId: Integer; const name: AnsiString; tk: TTypeKind; elemRec: Integer; isArray: Boolean; arrLo, arrHi: Integer);
var
  fSize, fc: Integer;
begin
  fc := Records[recId].FieldCount;
  Records[recId].Fields[fc].Name := name;
  Records[recId].Fields[fc].TypeKind := tk;
  Records[recId].Fields[fc].RecId := elemRec;
  Records[recId].Fields[fc].IsArray := isArray;
  
  if isArray then
  begin
    Records[recId].Fields[fc].ArrLen := arrHi - arrLo + 1;
    fSize := Records[recId].Fields[fc].ArrLen * GetFieldSize(tk, elemRec);
  end
  else
  begin
    Records[recId].Fields[fc].ArrLen := 0;
    fSize := GetFieldSize(tk, elemRec);
  end;
  
  Records[recId].Fields[fc].Offset := Records[recId].Size;
  Inc(Records[recId].Size, fSize);
  Inc(Records[recId].FieldCount);
end;

function AddRecordManual(const name: AnsiString; size: Integer; isClass: Boolean): Integer;
begin
  Inc(RecordCount);
  Records[RecordCount].Name := name;
  Records[RecordCount].Size := size;
  Records[RecordCount].IsClass := isClass;
  Records[RecordCount].FieldCount := 0;
  Result := RecordCount;
end;

procedure AddFieldManual(rec: Integer; const name: AnsiString; offset: Integer; tk: TTypeKind; elemRec: Integer; isArray: Boolean; arrLen: Integer);
var fc: Integer;
begin
  fc := Records[rec].FieldCount;
  Records[rec].Fields[fc].Name := name;
  Records[rec].Fields[fc].Offset := offset;
  Records[rec].Fields[fc].TypeKind := tk;
  Records[rec].Fields[fc].RecId := elemRec;
  Records[rec].Fields[fc].IsArray := isArray;
  Records[rec].Fields[fc].ArrLen := arrLen;
  Inc(Records[rec].FieldCount);
end;

procedure InitRecords;
begin
  RecordCount := 0;
  
  { 1. TToken }
  AddRecordManual('TToken', 288, False);
  AddFieldManual(REC_TTOKEN, 'Kind', 0, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TTOKEN, 'SVal', 8, tyString, REC_NONE, False, 0);
  AddFieldManual(REC_TTOKEN, 'IVal', 272, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TTOKEN, 'Line', 280, tyInteger, REC_NONE, False, 0);

  { 2. TStrEntry }
  AddRecordManual('TStrEntry', 280, False);
  AddFieldManual(REC_TSTRENTRY, 'Text', 0, tyString, REC_NONE, False, 0);
  AddFieldManual(REC_TSTRENTRY, 'Offset', 264, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TSTRENTRY, 'Len', 272, tyInteger, REC_NONE, False, 0);

  { 3. TFixup }
  AddRecordManual('TFixup', 16, False);
  AddFieldManual(REC_TFIXUP, 'CodePos', 0, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TFIXUP, 'DataOff', 8, tyInteger, REC_NONE, False, 0);

  { 4. TGlobFix }
  AddRecordManual('TGlobFix', 16, False);
  AddFieldManual(REC_TGLOBFIX, 'CodePos', 0, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TGLOBFIX, 'BSSoff', 8, tyInteger, REC_NONE, False, 0);

  { 5. TCallFix }
  AddRecordManual('TCallFix', 16, False);
  AddFieldManual(REC_TCALLFIX, 'CodePos', 0, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TCALLFIX, 'ProcIdx', 8, tyInteger, REC_NONE, False, 0);

  { 6. TSymbol }
  AddRecordManual('TSymbol', 344, False);
  AddFieldManual(REC_TSYMBOL, 'Name', 0, tyString, REC_NONE, False, 0);
  AddFieldManual(REC_TSYMBOL, 'TypeKind', 264, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TSYMBOL, 'Kind', 272, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TSYMBOL, 'Offset', 280, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TSYMBOL, 'ConstVal', 288, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TSYMBOL, 'IsArray', 296, tyBoolean, REC_NONE, False, 0);
  AddFieldManual(REC_TSYMBOL, 'ArrLen', 304, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TSYMBOL, 'ElemType', 312, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TSYMBOL, 'RecName', 320, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TSYMBOL, 'ElemRecName', 328, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TSYMBOL, 'IsRef', 336, tyBoolean, REC_NONE, False, 0);

  { 7. TParam }
  AddRecordManual('TParam', 296, False);
  AddFieldManual(REC_TPARAM, 'Name', 0, tyString, REC_NONE, False, 0);
  AddFieldManual(REC_TPARAM, 'TypeKind', 264, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TPARAM, 'SymIdx', 272, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TPARAM, 'IsRef', 280, tyBoolean, REC_NONE, False, 0);
  AddFieldManual(REC_TPARAM, 'IsArray', 288, tyBoolean, REC_NONE, False, 0);

  { 8. TProc }
  AddRecordManual('TProc', 2688, False);
  AddFieldManual(REC_TPROC, 'Name', 0, tyString, REC_NONE, False, 0);
  AddFieldManual(REC_TPROC, 'IsFunc', 264, tyBoolean, REC_NONE, False, 0);
  AddFieldManual(REC_TPROC, 'RetType', 272, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TPROC, 'ParamCount', 280, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TPROC, 'Params', 288, tyRecord, REC_TPARAM, True, 8);
  AddFieldManual(REC_TPROC, 'BodyAddr', 2656, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TPROC, 'FramePatch', 2664, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TPROC, 'RetSymIdx', 2672, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TPROC, 'ScopeBase', 2680, tyInteger, REC_NONE, False, 0);

  { 9. TRawToken }
  AddRecordManual('TRawToken', 40, False);
  AddFieldManual(REC_TRAWTOKEN, 'Kind', 0, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TRAWTOKEN, 'IVal', 8, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TRAWTOKEN, 'Line', 16, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TRAWTOKEN, 'SOffset', 24, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TRAWTOKEN, 'SLen', 32, tyInteger, REC_NONE, False, 0);

  { 10. TMyClass }
  AddRecordManual('TMyClass', 16, True);
  AddFieldManual(REC_TMYCLASS, 'x', 0, tyInteger, REC_NONE, False, 0);
  AddFieldManual(REC_TMYCLASS, 'y', 8, tyInteger, REC_NONE, False, 0);
end;

function IsRecordType(const lo: AnsiString): Integer;
var i: Integer;
begin
  Result := REC_NONE;
  for i := 1 to RecordCount do
  begin
    if FieldNameEqual(Records[i].Name, lo) then
    begin
      Result := i;
      Exit;
    end;
  end;
end;

function IsClassType(const lo: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 1 to RecordCount do
  begin
    if FieldNameEqual(Records[i].Name, lo) then
    begin
      Result := Records[i].IsClass;
      Exit;
    end;
  end;
end;

function RecSize(rec: Integer): Integer;
begin
  if (rec > 0) and (rec <= RecordCount) then
    Result := Records[rec].Size
  else
    Result := 8;
end;

function RecFieldOffset(rec: Integer; const field: AnsiString): Integer;
var i: Integer;
begin
  Result := 0;
  if (rec > 0) and (rec <= RecordCount) then
  begin
    for i := 0 to Records[rec].FieldCount-1 do
    begin
      if FieldNameEqual(Records[rec].Fields[i].Name, field) then
      begin
        Result := Records[rec].Fields[i].Offset;
        Exit;
      end;
    end;
  end;
end;

function RecFieldType(rec: Integer; const field: AnsiString): TTypeKind;
var i: Integer;
begin
  Result := tyInteger;
  if (rec > 0) and (rec <= RecordCount) then
  begin
    for i := 0 to Records[rec].FieldCount-1 do
    begin
      if FieldNameEqual(Records[rec].Fields[i].Name, field) then
      begin
        Result := Records[rec].Fields[i].TypeKind;
        Exit;
      end;
    end;
  end;
end;

function RecFieldRecId(rec: Integer; const field: AnsiString): Integer;
var i: Integer;
begin
  Result := REC_NONE;
  if (rec > 0) and (rec <= RecordCount) then
  begin
    for i := 0 to Records[rec].FieldCount-1 do
    begin
      if FieldNameEqual(Records[rec].Fields[i].Name, field) then
      begin
        Result := Records[rec].Fields[i].RecId;
        Exit;
      end;
    end;
  end;
end;

function RecFieldIsArray(rec: Integer; const field: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  if (rec > 0) and (rec <= RecordCount) then
  begin
    for i := 0 to Records[rec].FieldCount-1 do
    begin
      if FieldNameEqual(Records[rec].Fields[i].Name, field) then
      begin
        Result := Records[rec].Fields[i].IsArray;
        Exit;
      end;
    end;
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

  if VERBOSE and StrEqual(lo, 'ELF_HEADER_SIZE') then
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

{ ===== Procedure table ===== }

function FindProc(const name: AnsiString): Integer;
var i: Integer; lo: AnsiString;
begin
  lo := name;
  for i := 0 to ProcCount-1 do
    if Procs[i].Name = lo then begin Result := i; Exit; end;
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
begin
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
  for i := 0 to ProcCount-1 do
  begin
    writeln('Proc ', i, ': ', Procs[i].Name, ' at CodePos ', Procs[i].BodyAddr);
  end;
  for i := 0 to CallFixCount-1 do
  begin
    pi := CallFix[i].ProcIdx;
    if Procs[pi].BodyAddr < 0 then
      Error('unresolved forward');
    Patch32(CallFix[i].CodePos, Procs[pi].BodyAddr - (CallFix[i].CodePos + 4));
  end;
end;

{ ===== Expression parser ===== }
