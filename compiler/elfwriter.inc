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
  i: Integer;
  nameOff: array[0..MAX_EXTERNAL-1] of Integer;
  libOff : array[0..MAX_EXTERNAL-1] of Integer;
begin
  DynamicInterpOff := DataLen;
  DataPutZ('/lib64/ld-linux-x86-64.so.2');
  DynamicInterpSize := DataLen - DynamicInterpOff;

  DynamicStrOff := DataLen;
  DataPutB(0);
  for i := 0 to ExternalCount-1 do
  begin
    libOff[i] := DataLen - DynamicStrOff;
    DataPutZ(Strs[ProcLibrary[ExternalProc[i]]].Text);
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
  for i := 0 to ExternalCount-1 do DataPutDyn(1, libOff[i]); { DT_NEEDED }
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
  p := DynamicOff + (ExternalCount * 16);
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

procedure ExpandIncludes(var src: AnsiString; const baseDir: AnsiString);
{ Replace dollar-include directives with file contents, one level deep }
var
  i, j, k: Integer;
  fname: AnsiString;
{$ifdef FPC}
  c: Char;
{$else}
  c: Integer;
{$endif}
  fullPath: AnsiString;
begin
  SetLength(IncExpanded, 0);
  i := 1;
  while i <= Length(src) do
  begin
    if (i <= Length(src) - 9) and
       (src[i] = '{') and (src[i+1] = '$') and
       ((src[i+2] = 'i') or (src[i+2] = 'I')) and
       ((src[i+3] = 'n') or (src[i+3] = 'N')) and
       ((src[i+4] = 'c') or (src[i+4] = 'C')) and
       ((src[i+5] = 'l') or (src[i+5] = 'L')) and
       ((src[i+6] = 'u') or (src[i+6] = 'U')) and
       ((src[i+7] = 'd') or (src[i+7] = 'D')) and
       ((src[i+8] = 'e') or (src[i+8] = 'E')) and
       (src[i+9] = ' ') then
    begin
      j := i + 10;
      fname := '';
      while (j <= Length(src)) and (src[j] <> '}') and (src[j] <> #10) do
      begin
        c := src[j];
{$ifdef FPC}
        if (c <> '''') and (c <> '"') and (c <> ' ') then
          AppendChar(fname, c);
{$else}
        if (c <> 39) and (c <> 34) and (c <> 32) then
          AppendChar(fname, Chr(c));
{$endif}
        Inc(j);
      end;
      if (Length(fname) > 0) and (j <= Length(src)) then
      begin
        fullPath := baseDir;
        for k := 1 to Length(fname) do
          AppendChar(fullPath, fname[k]);
        LoadFile(fullPath, IncIncluded);
        { Append all characters of included to dst }
        for k := 1 to Length(IncIncluded) do
          AppendChar(IncExpanded, IncIncluded[k]);
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
  end;
  src := IncExpanded;
end;
