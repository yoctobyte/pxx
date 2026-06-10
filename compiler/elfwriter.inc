{ ===== ELF writer ===== }

procedure PatchAddr8(pos: Integer; addr: Int64);
begin
  Code[pos+0] := Byte(addr and $FF);
  Code[pos+1] := Byte((addr shr 8) and $FF);
  Code[pos+2] := Byte((addr shr 16) and $FF);
  Code[pos+3] := Byte((addr shr 24) and $FF);
  Code[pos+4] := Byte((addr shr 32) and $FF);
  Code[pos+5] := Byte((addr shr 40) and $FF);
  Code[pos+6] := Byte((addr shr 48) and $FF);
  Code[pos+7] := Byte((addr shr 56) and $FF);
end;

procedure DataPutB(v: Byte);
begin
  if DataLen >= MAX_DATA then Error('data overflow');
  Data[DataLen] := v;
  Inc(DataLen);
end;

procedure DataPutU16(v: Integer);
begin
  DataPutB(Byte(v and $FF));
  DataPutB(Byte((v shr 8) and $FF));
end;

procedure DataPutU32(v: Int64);
begin
  DataPutB(Byte(v and $FF));
  DataPutB(Byte((v shr 8) and $FF));
  DataPutB(Byte((v shr 16) and $FF));
  DataPutB(Byte((v shr 24) and $FF));
end;

procedure DataPutU64(v: Int64);
begin
  DataPutU32(v and $FFFFFFFF);
  DataPutU32((v shr 32) and $FFFFFFFF);
end;

procedure PatchDataU64(pos: Integer; v: Int64);
begin
  Data[pos+0] := Byte(v and $FF);
  Data[pos+1] := Byte((v shr 8) and $FF);
  Data[pos+2] := Byte((v shr 16) and $FF);
  Data[pos+3] := Byte((v shr 24) and $FF);
  Data[pos+4] := Byte((v shr 32) and $FF);
  Data[pos+5] := Byte((v shr 40) and $FF);
  Data[pos+6] := Byte((v shr 48) and $FF);
  Data[pos+7] := Byte((v shr 56) and $FF);
end;

procedure AddDataPtrFix(dataPos, targetOff: Integer);
{ Record a data->data 8-byte pointer relocation: the slot at dataPos is patched
  at link time to (dataBase + targetOff). Used by RTTI blob emission. }
begin
  if DataPtrFixCount >= MAX_DATAPTRFIX then Error('data ptr fixup overflow');
  DataPtrFix[DataPtrFixCount].DataPos   := dataPos;
  DataPtrFix[DataPtrFixCount].TargetOff := targetOff;
  Inc(DataPtrFixCount);
end;

procedure DataPutZ(const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do DataPutB(Ord(s[i]));
  DataPutB(0);
end;

procedure DataPutDyn(tag, value: Int64);
begin
  DataPutU64(tag);
  DataPutU64(value);
end;

procedure PrepareDynamicData;
var
  i, j, libIdx: Integer;
  found: Boolean;
  nameOff: array[0..MAX_EXTERNAL-1] of Integer;
  neededLibStr : array[0..MAX_EXTERNAL-1] of Integer; { distinct Strs[] indices }
  neededLibOff : array[0..MAX_EXTERNAL-1] of Integer; { their dynstr offsets }
begin
  DynamicInterpOff := DataLen;
  DataPutZ('/lib64/ld-linux-x86-64.so.2');
  DynamicInterpSize := DataLen - DynamicInterpOff;

  DynamicStrOff := DataLen;
  DataPutB(0);
  { Emit each distinct library soname once (one DT_NEEDED per library, not
    per imported symbol). InternStr dedups library names, so identical
    libraries share a Strs[] index — compare by index. }
  DynamicNeededCount := 0;
  for i := 0 to ExternalCount-1 do
  begin
    libIdx := ProcLibrary[ExternalProc[i]];
    found := False;
    for j := 0 to DynamicNeededCount-1 do
      if neededLibStr[j] = libIdx then begin found := True; break; end;
    if not found then
    begin
      neededLibStr[DynamicNeededCount] := libIdx;
      neededLibOff[DynamicNeededCount] := DataLen - DynamicStrOff;
      DataPutZ(Strs[libIdx].Text);
      Inc(DynamicNeededCount);
    end;
  end;
  { Symbol names (one per imported symbol) }
  for i := 0 to ExternalCount-1 do
  begin
    nameOff[i] := DataLen - DynamicStrOff;
    DataPutZ(Procs[ExternalProc[i]].Name);
  end;
  DynamicStrSize := DataLen - DynamicStrOff;
  while (DataLen mod 8) <> 0 do DataPutB(0);

  DynamicSymOff := DataLen;
  for i := 1 to 24 do DataPutB(0);
  for i := 0 to ExternalCount-1 do
  begin
    DataPutU32(nameOff[i]);
    DataPutB($12); { STB_GLOBAL, STT_FUNC }
    DataPutB(0);
    DataPutU16(0);
    DataPutU64(0);
    DataPutU64(0);
  end;

  DynamicHashOff := DataLen;
  DataPutU32(1); { one hash bucket }
  DataPutU32(ExternalCount + 1);
  if ExternalCount > 0 then DataPutU32(1) else DataPutU32(0);
  DataPutU32(0); { null symbol chain }
  for i := 1 to ExternalCount do
  begin
    if i < ExternalCount then DataPutU32(i + 1) else DataPutU32(0);
  end;

  DynamicRelaOff := DataLen;
  for i := 0 to ExternalCount-1 do
  begin
    DataPutU64(0); { patched to the GOT slot address below }
    DataPutU64(((i + 1) * 4294967296) + 6); { R_X86_64_GLOB_DAT }
    DataPutU64(0);
  end;

  DynamicOff := DataLen;
  for i := 0 to DynamicNeededCount-1 do DataPutDyn(1, neededLibOff[i]); { DT_NEEDED }
  DataPutDyn(5, 0);                         { DT_STRTAB }
  DataPutDyn(10, DynamicStrSize);           { DT_STRSZ }
  DataPutDyn(6, 0);                         { DT_SYMTAB }
  DataPutDyn(11, 24);                       { DT_SYMENT }
  DataPutDyn(4, 0);                         { DT_HASH }
  DataPutDyn(7, 0);                         { DT_RELA }
  DataPutDyn(8, ExternalCount * 24);        { DT_RELASZ }
  DataPutDyn(9, 24);                        { DT_RELAENT }
  DataPutDyn(0, 0);                         { DT_NULL }
  DynamicSize := DataLen - DynamicOff;
end;

procedure PatchDynamicData(dataBase: Int64);
var i, p: Integer;
begin
  for i := 0 to ExternalCount-1 do
    PatchDataU64(DynamicRelaOff + (i * 24), dataBase + ExternalGotOff[i]);
  p := DynamicOff + (DynamicNeededCount * 16);
  PatchDataU64(p + 8, dataBase + DynamicStrOff);
  Inc(p, 32);
  PatchDataU64(p + 8, dataBase + DynamicSymOff);
  Inc(p, 32);
  PatchDataU64(p + 8, dataBase + DynamicHashOff);
  Inc(p, 16);
  PatchDataU64(p + 8, dataBase + DynamicRelaOff);
end;

function IntToHexStr(val: Int64; digits: Integer): AnsiString;
var
  i, temp: Integer;
  ch: Char;
  v: Int64;
begin
  Result := '';
  v := val;
  for i := 1 to digits do
  begin
    temp := v and $F;
    if temp < 10 then
      ch := Chr(Ord('0') + temp)
    else
      ch := Chr(Ord('a') + temp - 10);
    Result := ch + Result;
    v := v shr 4;
  end;
end;

procedure WriteMapFile(const outPath: AnsiString; codeOffset: Int64);
var
  mapPath, mapContent: AnsiString;
  f, i, j, len: Integer;
  addr: Int64;
begin
  mapPath := outPath + '.map';
  mapContent := '# Frankonpiler Map File' + #10;
  mapContent := mapContent + '# Executable: ' + outPath + #10;
  mapContent := mapContent + '# Base Address: 0x' + IntToHexStr(LOAD_ADDR, 8) + #10;
  mapContent := mapContent + '# Code Offset: 0x' + IntToHexStr(codeOffset, 8) + #10 + #10;
  
  { Entry / _start }
  addr := LOAD_ADDR + codeOffset;
  mapContent := mapContent + '0x' + IntToHexStr(addr, 16) + ' _start' + #10;
  
  for i := 0 to ProcCount - 1 do
  begin
    if Procs[i].BodyAddr >= 0 then
    begin
      addr := LOAD_ADDR + codeOffset + Procs[i].BodyAddr;
      mapContent := mapContent + '0x' + IntToHexStr(addr, 16) + ' ' + Procs[i].Name + #10;
    end;
  end;
  
  len := Length(mapContent);
  if len > STRING_CAP then
    len := STRING_CAP;
    
  for j := 0 to len - 1 do
    TokChars[j] := mapContent[j + 1];
  
  f := sysopen(mapPath, 577); { O_WRONLY | O_CREAT | O_TRUNC }
  if f >= 0 then
  begin
    AssignPath := mapPath;
    sysfchmod(f, 420); { chmod 644 }
    if len > 0 then
      syswrite(f, TokChars, len);
    sysclose(f);
  end;
end;

{$ifdef FPC}
procedure writeU8(var f:File;v:Byte);   begin Blockwrite(f,v,1); end;
procedure writeU16(var f:File;v:Word);
var b:array[0..1]of Byte;
begin b[0]:=v and $FF;b[1]:=(v shr 8)and $FF;Blockwrite(f,b,2);end;
procedure writeU32(var f:File;v:LongWord);
var b:array[0..3]of Byte;
begin b[0]:=v and $FF;b[1]:=(v shr 8)and $FF;b[2]:=(v shr 16)and $FF;b[3]:=(v shr 24)and $FF;Blockwrite(f,b,4);end;
procedure writeU64(var f:File;v:Int64);
begin writeU32(f,LongWord(v and $FFFFFFFF));writeU32(f,LongWord((v shr 32)and $FFFFFFFF));end;
{$else}
procedure writeU8(f: Integer; v: Byte);
begin
  sysbuf[0] := v;
  syswrite(f, sysbuf, 1);
end;
procedure writeU16(f: Integer; v: Integer);
begin
  sysbuf[0] := v and 255;
  sysbuf[1] := (v shr 8) and 255;
  syswrite(f, sysbuf, 2);
end;
procedure writeU32(f: Integer; v: Integer);
begin
  sysbuf[0] := v and 255;
  sysbuf[1] := (v shr 8) and 255;
  sysbuf[2] := (v shr 16) and 255;
  sysbuf[3] := (v shr 24) and 255;
  syswrite(f, sysbuf, 4);
end;
procedure writeU64(f: Integer; v: Int64);
begin
  sysbuf[0] := v and 255;
  sysbuf[1] := (v shr 8) and 255;
  sysbuf[2] := (v shr 16) and 255;
  sysbuf[3] := (v shr 24) and 255;
  sysbuf[4] := (v shr 32) and 255;
  sysbuf[5] := (v shr 40) and 255;
  sysbuf[6] := (v shr 48) and 255;
  sysbuf[7] := (v shr 56) and 255;
  syswrite(f, sysbuf, 8);
end;
{$endif}

{$ifdef FPC}
procedure writeELF(const outPath: AnsiString);
var f: File; i: Integer;
    phCount, codeOffset: Integer;
    dataBase, bssBase, entry, filesz, memsz, addr: Int64;
begin
  phCount := 1;
  codeOffset := CODE_OFFSET;
  if ExternalCount > 0 then
  begin
    PrepareDynamicData;
    phCount := 3;
    codeOffset := DYNAMIC_CODE_OFFSET;
  end;
  dataBase := LOAD_ADDR + codeOffset + CodeLen;
  bssBase  := dataBase + DataLen;
  entry    := LOAD_ADDR + codeOffset;
  filesz   := codeOffset + CodeLen + DataLen;
  memsz    := filesz + BSSSize;

  { Apply data fixups (8-byte absolute) }
  for i := 0 to FixCount-1 do
  begin
    addr := dataBase + Fixups[i].DataOff;
    PatchAddr8(Fixups[i].CodePos, addr);
  end;

  { Apply global fixups (4-byte absolute) }
  for i := 0 to GlobFixCount-1 do
  begin
    addr := bssBase + GlobFix[i].BSSoff;
    Patch32(GlobFix[i].CodePos, addr);
  end;
  if ExternalCount > 0 then
  begin
    for i := 0 to DynCallCount-1 do
      Patch32(DynCallCodePos[i], dataBase + ExternalGotOff[DynCallExtIdx[i]]);
    PatchDynamicData(dataBase);
  end;

  for i := 0 to MethodFixCount-1 do
  begin
    addr := entry + Procs[MethodFixups[i].ProcIdx].BodyAddr;
    PatchDataU64(MethodFixups[i].DataPos, addr);
  end;

  { @proc: patch each `mov rax, imm64` with the routine's absolute code address }
  for i := 0 to ProcAddrFixCount-1 do
  begin
    addr := entry + Procs[ProcAddrFix[i].ProcIdx].BodyAddr;
    PatchAddr8(ProcAddrFix[i].CodePos, addr);
  end;

  for i := 0 to DataPtrFixCount-1 do
    PatchDataU64(DataPtrFix[i].DataPos, dataBase + DataPtrFix[i].TargetOff);

  Assign(f, outPath); Rewrite(f, 1);

  writeU8(f,$7F);writeU8(f,$45);writeU8(f,$4C);writeU8(f,$46);
  writeU8(f,2);writeU8(f,1);writeU8(f,1);writeU8(f,0);
  writeU8(f,0);writeU8(f,0);writeU8(f,0);writeU8(f,0);
  writeU8(f,0);writeU8(f,0);writeU8(f,0);writeU8(f,0);
  writeU16(f,2);writeU16(f,62);writeU32(f,1);
  writeU64(f,entry);writeU64(f,64);writeU64(f,0);
  writeU32(f,0);writeU16(f,64);writeU16(f,56);
  writeU16(f,phCount);writeU16(f,64);writeU16(f,0);writeU16(f,0);

  writeU32(f,1);writeU32(f,7);  { PT_LOAD, RWX }
  writeU64(f,0);writeU64(f,LOAD_ADDR);writeU64(f,LOAD_ADDR);
  writeU64(f,filesz);writeU64(f,memsz);writeU64(f,$200000);
  if ExternalCount > 0 then
  begin
    writeU32(f,3);writeU32(f,4); { PT_INTERP, R }
    writeU64(f,codeOffset + CodeLen + DynamicInterpOff);
    writeU64(f,dataBase + DynamicInterpOff);writeU64(f,dataBase + DynamicInterpOff);
    writeU64(f,DynamicInterpSize);writeU64(f,DynamicInterpSize);writeU64(f,1);
    writeU32(f,2);writeU32(f,6); { PT_DYNAMIC, RW }
    writeU64(f,codeOffset + CodeLen + DynamicOff);
    writeU64(f,dataBase + DynamicOff);writeU64(f,dataBase + DynamicOff);
    writeU64(f,DynamicSize);writeU64(f,DynamicSize);writeU64(f,8);
  end;

  if CodeLen > 0 then Blockwrite(f,Code[0],CodeLen);
  if DataLen > 0 then Blockwrite(f,Data[0],DataLen);
  Close(f);
  FpChmod(outPath,&755);
  WriteMapFile(outPath, codeOffset);
end;
{$else}
procedure writeELF(const outPath: AnsiString);
var f: Integer; i: Integer;
    phCount, codeOffset: Integer;
    dataBase, bssBase, entry, filesz, memsz, addr: Int64;
begin
  phCount := 1;
  codeOffset := CODE_OFFSET;
  if ExternalCount > 0 then
  begin
    PrepareDynamicData;
    phCount := 3;
    codeOffset := DYNAMIC_CODE_OFFSET;
  end;
  dataBase := LOAD_ADDR + codeOffset + CodeLen;
  bssBase  := dataBase + DataLen;
  entry    := LOAD_ADDR + codeOffset;
  filesz   := codeOffset + CodeLen + DataLen;
  memsz    := filesz + BSSSize;

  { Apply data fixups (8-byte absolute) }
  for i := 0 to FixCount-1 do
  begin
    addr := dataBase + Fixups[i].DataOff;
    PatchAddr8(Fixups[i].CodePos, addr);
  end;

  { Apply global fixups (4-byte absolute) }
  for i := 0 to GlobFixCount-1 do
  begin
    addr := bssBase + GlobFix[i].BSSoff;
    Patch32(GlobFix[i].CodePos, addr);
  end;
  if ExternalCount > 0 then
  begin
    for i := 0 to DynCallCount-1 do
      Patch32(DynCallCodePos[i], dataBase + ExternalGotOff[DynCallExtIdx[i]]);
    PatchDynamicData(dataBase);
  end;

  for i := 0 to MethodFixCount-1 do
  begin
    addr := entry + Procs[MethodFixups[i].ProcIdx].BodyAddr;
    PatchDataU64(MethodFixups[i].DataPos, addr);
  end;

  { @proc: patch each `mov rax, imm64` with the routine's absolute code address }
  for i := 0 to ProcAddrFixCount-1 do
  begin
    addr := entry + Procs[ProcAddrFix[i].ProcIdx].BodyAddr;
    PatchAddr8(ProcAddrFix[i].CodePos, addr);
  end;

  for i := 0 to DataPtrFixCount-1 do
    PatchDataU64(DataPtrFix[i].DataPos, dataBase + DataPtrFix[i].TargetOff);

  AssignPath := outPath;
  f := sysopen(AssignPath, 577); { O_WRONLY | O_CREAT | O_TRUNC }

  writeU8(f,$7F);writeU8(f,$45);writeU8(f,$4C);writeU8(f,$46);
  writeU8(f,2);writeU8(f,1);writeU8(f,1);writeU8(f,0);
  writeU8(f,0);writeU8(f,0);writeU8(f,0);writeU8(f,0);
  writeU8(f,0);writeU8(f,0);writeU8(f,0);writeU8(f,0);
  writeU16(f,2);writeU16(f,62);writeU32(f,1);
  writeU64(f,entry);writeU64(f,64);writeU64(f,0);
  writeU32(f,0);writeU16(f,64);writeU16(f,56);
  writeU16(f,phCount);writeU16(f,64);writeU16(f,0);writeU16(f,0);

  writeU32(f,1);writeU32(f,7);  { PT_LOAD, RWX }
  writeU64(f,0);writeU64(f,LOAD_ADDR);writeU64(f,LOAD_ADDR);
  writeU64(f,filesz);writeU64(f,memsz);writeU64(f,$200000);
  if ExternalCount > 0 then
  begin
    writeU32(f,3);writeU32(f,4); { PT_INTERP, R }
    writeU64(f,codeOffset + CodeLen + DynamicInterpOff);
    writeU64(f,dataBase + DynamicInterpOff);writeU64(f,dataBase + DynamicInterpOff);
    writeU64(f,DynamicInterpSize);writeU64(f,DynamicInterpSize);writeU64(f,1);
    writeU32(f,2);writeU32(f,6); { PT_DYNAMIC, RW }
    writeU64(f,codeOffset + CodeLen + DynamicOff);
    writeU64(f,dataBase + DynamicOff);writeU64(f,dataBase + DynamicOff);
    writeU64(f,DynamicSize);writeU64(f,DynamicSize);writeU64(f,8);
  end;

  if CodeLen > 0 then syswrite(f,Code,CodeLen);
  if DataLen > 0 then syswrite(f,Data,DataLen);
  sysfchmod(f, 493); { chmod 755 }
  sysclose(f);
  WriteMapFile(outPath, codeOffset);
end;
{$endif}

procedure LoadFile(const path: AnsiString; var dst: AnsiString);
var f, n: Integer;
begin
  LoadPath := path;
  SetLength(dst, STRING_CAP);
  f := sysopen(LoadPath, 0);
  if f >= 0 then
  begin
    n := sysread(f, dst[1], STRING_CAP);
    if n < 0 then n := 0;
    sysclose(f);
    SetLength(dst, n);
  end
  else
    SetLength(dst, 0);
end;

function GetFilePath(const path: AnsiString): AnsiString;
var i, lastSlash: Integer;
begin
  lastSlash := 0;
  for i := 1 to Length(path) do
  begin
    if path[i] = '/' then
      lastSlash := i;
  end;
  Result := '';
  if lastSlash > 0 then
  begin
    SetLength(Result, lastSlash);
    for i := 1 to lastSlash do
      Result[i] := path[i];
  end;
end;

function GetFileBaseName(const path: AnsiString): AnsiString;
{ Strip directory and extension: 'test/gui/helloworld/main.lpr' -> 'main'.
  Used to resolve the `*` in $R *.lfm / $R *.res to the current unit. }
var i, lastSlash, lastDot: Integer; s: AnsiString;
begin
  lastSlash := 0; lastDot := 0;
  for i := 1 to Length(path) do
  begin
    if path[i] = '/' then lastSlash := i;
    if path[i] = '.' then lastDot := i;
  end;
  if lastDot <= lastSlash then lastDot := Length(path) + 1;
  s := '';
  for i := lastSlash + 1 to lastDot - 1 do
    AppendChar(s, path[i]);
  Result := s;
end;

procedure NormalizePath(var p: AnsiString);
{ Collapse '.' and '..' segments so resolved unit/include paths are canonical
  in diagnostics and dedup keys. Leading '..' segments of a relative path are
  preserved; '..' at the root of an absolute path stays at the root. Segment
  bounds are tracked as integer offsets into the input, so no string tables. }
var
  keptStart, keptLen: array[0..127] of Integer;
  depth, i, k, segStart, segLen: Integer;
  res: AnsiString;
  isAbs, isDot, isDotDot, popPrev: Boolean;
begin
  isAbs := (Length(p) > 0) and (p[1] = '/');
  depth := 0;
  segStart := 1;
  for i := 1 to Length(p) + 1 do
  begin
    if (i > Length(p)) or (p[i] = '/') then
    begin
      segLen := i - segStart;
      isDot := False; isDotDot := False;
      if segLen = 1 then isDot := p[segStart] = '.';
      if segLen = 2 then
        isDotDot := (p[segStart] = '.') and (p[segStart + 1] = '.');
      if (segLen > 0) and not isDot then
      begin
        if isDotDot then
        begin
          popPrev := False;
          if depth > 0 then
            popPrev := not ((keptLen[depth - 1] = 2) and
                            (p[keptStart[depth - 1]] = '.') and
                            (p[keptStart[depth - 1] + 1] = '.'));
          if popPrev then
            Dec(depth)
          else if not isAbs then
          begin
            { relative path climbing above its start: keep the '..' }
            if depth >= 128 then Error('NormalizePath: path too deep');
            keptStart[depth] := segStart; keptLen[depth] := segLen;
            Inc(depth);
          end;
          { absolute path: '..' at the root is dropped }
        end
        else
        begin
          if depth >= 128 then Error('NormalizePath: path too deep');
          keptStart[depth] := segStart; keptLen[depth] := segLen;
          Inc(depth);
        end;
      end;
      segStart := i + 1;
    end;
  end;
  res := '';
  if isAbs then AppendChar(res, '/');
  for k := 0 to depth - 1 do
  begin
    if k > 0 then AppendChar(res, '/');
    for i := keptStart[k] to keptStart[k] + keptLen[k] - 1 do
      AppendChar(res, p[i]);
  end;
  p := res;
end;

procedure ExpandIncludes(var src: AnsiString; const baseDir: AnsiString);
{ Replace active dollar-include directives with file contents, one level deep.
  Conditional directives remain in the text for the real lexer pass; this
  pre-pass only simulates enough state to avoid loading includes from inactive
  branches. }
var
  i, j, k, closePos, condCount, savedDefineCount, savedDefineCharLen: Integer;
  fname, command, name, exprSource: AnsiString;
  cond, active: Boolean;
  condParent, condActive, condTaken: array[0..MAX_PAS_CONDS-1] of Boolean;
  savedDefineActive: array[0..MAX_PAS_DEFINES-1] of Boolean;
{$ifdef FPC}
  c: Char;
{$else}
  c: Integer;
{$endif}
  fullPath: AnsiString;
begin
  savedDefineCount := PasDefineCount;
  savedDefineCharLen := PasDefineCharLen;
  for k := 0 to MAX_PAS_DEFINES - 1 do
    savedDefineActive[k] := PasDefineActive[k];
  condCount := 0;
  active := True;
  SetLength(IncExpanded, 0);
  i := 1;
  while i <= Length(src) do
  begin
    if (i < Length(src)) and (src[i] = '{') and (src[i + 1] = '$') then
    begin
      j := i + 2;
      while (j <= Length(src)) and (src[j] in [' ', #9, #13, #10]) do Inc(j);
      command := '';
      while (j <= Length(src)) and
            (src[j] in ['a'..'z', 'A'..'Z', '0'..'9', '_']) do
      begin
        AppendChar(command, src[j]);
        Inc(j);
      end;
      while (j <= Length(src)) and (src[j] in [' ', #9, #13, #10]) do Inc(j);
      name := '';
      k := j;
      while (k <= Length(src)) and
            (src[k] in ['a'..'z', 'A'..'Z', '0'..'9', '_']) do
      begin
        AppendChar(name, src[k]);
        Inc(k);
      end;
      closePos := j;
      while (closePos <= Length(src)) and (src[closePos] <> '}') do Inc(closePos);
      if closePos > Length(src) then Error('unterminated Pascal directive during include expansion');

      if CaseEqual(command, 'ifdef') or CaseEqual(command, 'ifndef') or
         CaseEqual(command, 'if') or CaseEqual(command, 'ifopt') then
      begin
        if condCount >= MAX_PAS_CONDS then Error('include conditional nesting overflow');
        cond := False;
        if CaseEqual(command, 'ifopt') then
          cond := False { compiler option switches are not modelled; branch off }
        else if CaseEqual(command, 'if') then
        begin
          { Inactive branches need only nesting bookkeeping (FPC semantics):
            don't evaluate $IF expressions inside a dead region. }
          if active then
          begin
            exprSource := '';
            for k := j to closePos - 1 do AppendChar(exprSource, src[k]);
            cond := EvalPasCondExprText(exprSource);
          end;
        end
        else
        begin
          cond := PasDefineExists(name);
          if CaseEqual(command, 'ifndef') then cond := not cond;
        end;
        condParent[condCount] := active;
        condActive[condCount] := active and cond;
        condTaken[condCount] := active and cond;
        active := condActive[condCount];
        Inc(condCount);
      end
      else if CaseEqual(command, 'elseif') then
      begin
        if condCount = 0 then Error('unexpected elseif directive during include expansion');
        k := condCount - 1;
        cond := False;
        { Evaluate only when this branch could fire (parent active, no branch
          taken yet) — a dead $ELSEIF may use syntax we cannot evaluate. }
        if condParent[k] and not condTaken[k] then
        begin
          exprSource := '';
          for k := j to closePos - 1 do AppendChar(exprSource, src[k]);
          cond := EvalPasCondExprText(exprSource);
          k := condCount - 1;
        end;
        condActive[k] := condParent[k] and not condTaken[k] and cond;
        if condActive[k] then condTaken[k] := True;
        active := condActive[k];
      end
      else if CaseEqual(command, 'else') then
      begin
        if condCount = 0 then Error('unexpected else directive during include expansion');
        k := condCount - 1;
        condActive[k] := condParent[k] and not condTaken[k];
        condTaken[k] := True;
        active := condActive[k];
      end
      else if CaseEqual(command, 'endif') or CaseEqual(command, 'ifend') then
      begin
        if condCount = 0 then Error('unexpected endif directive during include expansion');
        Dec(condCount);
        if condCount = 0 then active := True
        else active := condActive[condCount - 1];
      end
      else if active and CaseEqual(command, 'define') then
        PasDefine(name)
      else if active and CaseEqual(command, 'undef') then
        PasUndefine(name);

      if active and (CaseEqual(command, 'include') or CaseEqual(command, 'i')) then
      begin
        fname := '';
        while (j <= Length(src)) and (src[j] <> '}') and (src[j] <> #10) do
        begin
          c := src[j];
{$ifdef FPC}
          if (c <> '''') and (c <> '"') and (c <> ' ') then AppendChar(fname, c);
{$else}
          if (c <> 39) and (c <> 34) and (c <> 32) then AppendChar(fname, Chr(c));
{$endif}
          Inc(j);
        end;
        if (Length(fname) > 0) and (j <= Length(src)) then
        begin
          if fname[1] = '/' then
            fullPath := fname
          else
          begin
            fullPath := baseDir;
            for k := 1 to Length(fname) do AppendChar(fullPath, fname[k]);
          end;
          NormalizePath(fullPath);
          LoadFile(fullPath, IncIncluded);
          for k := 1 to Length(IncIncluded) do AppendChar(IncExpanded, IncIncluded[k]);
          i := j + 1;
        end
        else
        begin
          AppendChar(IncExpanded, src[i]);
          Inc(i);
        end;
      end
      else
      begin
        AppendChar(IncExpanded, src[i]);
        Inc(i);
      end;
    end
    else
    begin
      AppendChar(IncExpanded, src[i]);
      Inc(i);
    end;
  end;
  if condCount <> 0 then Error('unterminated conditional directive during include expansion');
  PasDefineCount := savedDefineCount;
  PasDefineCharLen := savedDefineCharLen;
  for k := 0 to MAX_PAS_DEFINES - 1 do
    PasDefineActive[k] := savedDefineActive[k];
  src := IncExpanded;
end;
