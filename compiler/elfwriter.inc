{ ===== ELF writer ===== }

procedure PatchAddr8(pos: Integer; addr: Int64);
begin
  Code[pos+0] := Byte(addr and $FF);
  Code[pos+1] := Byte((addr shr 8) and $FF);
  Code[pos+2] := Byte((addr shr 16) and $FF);
  Code[pos+3] := Byte((addr shr 24) and $FF);
  if (addr >= 0) and (addr <= 2147483647) then
  begin
    Code[pos+4] := 0;
    Code[pos+5] := 0;
    Code[pos+6] := 0;
    Code[pos+7] := 0;
  end
  else if (addr < 0) and (addr >= -2147483648) then
  begin
    Code[pos+4] := 255;
    Code[pos+5] := 255;
    Code[pos+6] := 255;
    Code[pos+7] := 255;
  end
  else
  begin
    Code[pos+4] := Byte((addr shr 32) and $FF);
    Code[pos+5] := Byte((addr shr 40) and $FF);
    Code[pos+6] := Byte((addr shr 48) and $FF);
    Code[pos+7] := Byte((addr shr 56) and $FF);
  end;
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
  if (v >= 0) and (v <= 2147483647) then
    DataPutU32(0)
  else if (v < 0) and (v >= -2147483648) then
    DataPutU32($FFFFFFFF)
  else
    DataPutU32((v shr 32) and $FFFFFFFF);
end;

procedure PatchDataU64(pos: Integer; v: Int64);
begin
  Data[pos+0] := Byte(v and $FF);
  Data[pos+1] := Byte((v shr 8) and $FF);
  Data[pos+2] := Byte((v shr 16) and $FF);
  Data[pos+3] := Byte((v shr 24) and $FF);
  if (v >= 0) and (v <= 2147483647) then
  begin
    Data[pos+4] := 0;
    Data[pos+5] := 0;
    Data[pos+6] := 0;
    Data[pos+7] := 0;
  end
  else if (v < 0) and (v >= -2147483648) then
  begin
    Data[pos+4] := 255;
    Data[pos+5] := 255;
    Data[pos+6] := 255;
    Data[pos+7] := 255;
  end
  else
  begin
    Data[pos+4] := Byte((v shr 32) and $FF);
    Data[pos+5] := Byte((v shr 40) and $FF);
    Data[pos+6] := Byte((v shr 48) and $FF);
    Data[pos+7] := Byte((v shr 56) and $FF);
  end;
end;

procedure PatchDataI32(pos: Integer; v: Integer);
begin
  Data[pos+0] := Byte(v and $FF);
  Data[pos+1] := Byte((v shr 8) and $FF);
  Data[pos+2] := Byte((v shr 16) and $FF);
  Data[pos+3] := Byte((v shr 24) and $FF);
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
  i, j, libIdx, relType: Integer;
  found: Boolean;
  nameOff: array[0..MAX_EXTERNAL-1] of Integer;
  neededLibStr : array[0..MAX_EXTERNAL-1] of Integer; { distinct Strs[] indices }
  neededLibOff : array[0..MAX_EXTERNAL-1] of Integer; { their dynstr offsets }
begin
  DynamicInterpOff := DataLen;
  if TargetArch = TARGET_AARCH64 then
    DataPutZ('/lib/ld-linux-aarch64.so.1')
  else
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

  { RELA r_info = (sym << 32) | type. GLOB_DAT: x86-64=6, aarch64=1025. }
  if TargetArch = TARGET_AARCH64 then relType := 1025 else relType := 6;
  DynamicRelaOff := DataLen;
  for i := 0 to ExternalCount-1 do
  begin
    DataPutU64(0); { patched to the GOT slot address below }
    DataPutU64(((i + 1) * 4294967296) + relType); { GLOB_DAT }
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

{ ELF32 dynamic-link tables (i386). Mirrors PrepareDynamicData but with 32-bit
  structures: Elf32_Sym=16B, REL (not RELA, 8B) with R_386_GLOB_DAT=6, and
  Elf32_Dyn=8B. The dynamic linker resolves each imported symbol and writes its
  address into the 4-byte GOT slot the call indirects through. Reuses the shared
  Dynamic* globals (only one writer runs per compile); DynamicRelaOff holds the
  REL table offset here. }
procedure PrepareDynamicData32;
var
  i, j, libIdx, relType: Integer;
  found: Boolean;
  nameOff: array[0..MAX_EXTERNAL-1] of Integer;
  neededLibStr : array[0..MAX_EXTERNAL-1] of Integer;
  neededLibOff : array[0..MAX_EXTERNAL-1] of Integer;
begin
  DynamicInterpOff := DataLen;
  if TargetArch = TARGET_ARM32 then
    DataPutZ('/lib/ld-linux.so.3')          { arm EABI (armel) loader }
  else
    DataPutZ('/lib/ld-linux.so.2');         { i386 loader }
  DynamicInterpSize := DataLen - DynamicInterpOff;

  DynamicStrOff := DataLen;
  DataPutB(0);
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
  for i := 0 to ExternalCount-1 do
  begin
    nameOff[i] := DataLen - DynamicStrOff;
    DataPutZ(Procs[ExternalProc[i]].Name);
  end;
  DynamicStrSize := DataLen - DynamicStrOff;
  while (DataLen mod 4) <> 0 do DataPutB(0);

  { dynsym: Elf32_Sym = name(4) value(4) size(4) info(1) other(1) shndx(2). }
  DynamicSymOff := DataLen;
  for i := 1 to 16 do DataPutB(0);              { null symbol }
  for i := 0 to ExternalCount-1 do
  begin
    DataPutU32(nameOff[i]);
    DataPutU32(0);                              { value }
    DataPutU32(0);                              { size }
    DataPutB($12);                              { STB_GLOBAL, STT_FUNC }
    DataPutB(0);                                { other }
    DataPutU16(0);                              { shndx = SHN_UNDEF }
  end;

  DynamicHashOff := DataLen;
  DataPutU32(1);                                { nbucket }
  DataPutU32(ExternalCount + 1);                { nchain }
  if ExternalCount > 0 then DataPutU32(1) else DataPutU32(0);
  DataPutU32(0);                                { chain[0] }
  for i := 1 to ExternalCount do
  begin
    if i < ExternalCount then DataPutU32(i + 1) else DataPutU32(0);
  end;

  { REL table: Elf32_Rel = offset(4) info(4). info = (sym<<8) | type.
    GLOB_DAT: i386=R_386_GLOB_DAT(6), arm32=R_ARM_GLOB_DAT(21). }
  if TargetArch = TARGET_ARM32 then relType := 21 else relType := 6;
  DynamicRelaOff := DataLen;
  for i := 0 to ExternalCount-1 do
  begin
    DataPutU32(0);                              { patched to the GOT slot VA }
    DataPutU32(((i + 1) * 256) + relType);      { (sym<<8) | GLOB_DAT }
  end;

  { Elf32_Dyn = tag(4) val(4). }
  DynamicOff := DataLen;
  for i := 0 to DynamicNeededCount-1 do
  begin
    DataPutU32(1); DataPutU32(neededLibOff[i]); { DT_NEEDED }
  end;
  DataPutU32(5);  DataPutU32(0);                { DT_STRTAB }
  DataPutU32(10); DataPutU32(DynamicStrSize);   { DT_STRSZ }
  DataPutU32(6);  DataPutU32(0);                { DT_SYMTAB }
  DataPutU32(11); DataPutU32(16);               { DT_SYMENT }
  DataPutU32(4);  DataPutU32(0);                { DT_HASH }
  DataPutU32(17); DataPutU32(0);                { DT_REL }
  DataPutU32(18); DataPutU32(ExternalCount * 8);{ DT_RELSZ }
  DataPutU32(19); DataPutU32(8);                { DT_RELENT }
  DataPutU32(0);  DataPutU32(0);                { DT_NULL }
  DynamicSize := DataLen - DynamicOff;
end;

procedure PatchDynamicData32(dataBase: Int64);
var i, p: Integer;
begin
  for i := 0 to ExternalCount-1 do
    PatchDataI32(DynamicRelaOff + (i * 8), Integer(dataBase + ExternalGotOff[i]));
  p := DynamicOff + (DynamicNeededCount * 8);
  PatchDataI32(p + 4, Integer(dataBase + DynamicStrOff));   { DT_STRTAB }
  Inc(p, 16);
  PatchDataI32(p + 4, Integer(dataBase + DynamicSymOff));   { DT_SYMTAB }
  Inc(p, 16);
  PatchDataI32(p + 4, Integer(dataBase + DynamicHashOff));  { DT_HASH }
  Inc(p, 8);
  PatchDataI32(p + 4, Integer(dataBase + DynamicRelaOff));  { DT_REL }
end;

{ Point each external indirect call at its resolved GOT slot. x86-64 uses a
  `call qword [abs32]`, so the 32-bit operand is the slot VA. aarch64 builds the
  slot VA into x16 via movz/movk (the slot VA is < 2^32 under ET_EXEC), so patch
  both imm16 fields; the following ldr/blr are emitted at codegen time. }
procedure PatchDynCallSites(dataBase: Int64);
var i: Integer; slotVA: Int64;
begin
  for i := 0 to DynCallCount-1 do
  begin
    slotVA := dataBase + ExternalGotOff[DynCallExtIdx[i]];
    if TargetArch = TARGET_AARCH64 then
    begin
      Patch32(DynCallCodePos[i],     $D2800010 or ((slotVA and $FFFF) shl 5));
      Patch32(DynCallCodePos[i] + 4, $F2A00010 or (((slotVA shr 16) and $FFFF) shl 5));
    end
    else
      Patch32(DynCallCodePos[i], slotVA);
  end;
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
procedure writeStrZ(var f: File; const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do writeU8(f, Ord(s[i]));
  writeU8(f, 0);
end;
procedure writePad(var f: File; n: Integer);
var i: Integer;
begin
  for i := 1 to n do writeU8(f, 0);
end;
procedure writeSym32(var f: File; name, value, size, info, shndx: Integer);
begin
  writeU32(f, name); writeU32(f, value); writeU32(f, size);
  writeU8(f, info); writeU8(f, 0); writeU16(f, shndx);
end;
procedure writeRela32(var f: File; offset, symIdx, rtype, addend: Integer);
begin
  writeU32(f, offset); writeU32(f, (symIdx shl 8) or rtype); writeU32(f, addend);
end;
{ One Elf32_Shdr = writeShdrA (name..size) + writeShdrB (link..entsize).
  Split in two: calls with more than ~6 parameters are miscompiled by the
  self-hosted backend (see bug-many-param-call-corruption). }
procedure writeShdrA(var f: File; name, typ, flags, off, size: Integer);
begin
  writeU32(f, name); writeU32(f, typ); writeU32(f, flags);
  writeU32(f, 0);   { sh_addr = 0 in ET_REL }
  writeU32(f, off); writeU32(f, size);
end;
procedure writeShdrB(var f: File; link, info, alignv, entsize: Integer);
begin
  writeU32(f, link); writeU32(f, info);
  writeU32(f, alignv); writeU32(f, entsize);
end;
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
  { Avoid `v shr 32` for small values: i386 self-host duplicated the low dword. }
  if (v >= 0) and (v <= 2147483647) then
  begin
    sysbuf[4] := 0;
    sysbuf[5] := 0;
    sysbuf[6] := 0;
    sysbuf[7] := 0;
  end
  else if (v < 0) and (v >= -2147483648) then
  begin
    sysbuf[4] := 255;
    sysbuf[5] := 255;
    sysbuf[6] := 255;
    sysbuf[7] := 255;
  end
  else
  begin
    sysbuf[4] := (v shr 32) and 255;
    sysbuf[5] := (v shr 40) and 255;
    sysbuf[6] := (v shr 48) and 255;
    sysbuf[7] := (v shr 56) and 255;
  end;
  syswrite(f, sysbuf, 8);
end;
procedure writeStrZ(f: Integer; const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do writeU8(f, Ord(s[i]));
  writeU8(f, 0);
end;
procedure writePad(f: Integer; n: Integer);
var i: Integer;
begin
  for i := 1 to n do writeU8(f, 0);
end;
procedure writeSym32(f: Integer; name, value, size, info, shndx: Integer);
begin
  writeU32(f, name); writeU32(f, value); writeU32(f, size);
  writeU8(f, info); writeU8(f, 0); writeU16(f, shndx);
end;
procedure writeRela32(f: Integer; offset, symIdx, rtype, addend: Integer);
begin
  writeU32(f, offset); writeU32(f, (symIdx shl 8) or rtype); writeU32(f, addend);
end;
{ One Elf32_Shdr = writeShdrA (name..size) + writeShdrB (link..entsize).
  Split in two: calls with more than ~6 parameters are miscompiled by the
  self-hosted backend (see bug-many-param-call-corruption). }
procedure writeShdrA(f: Integer; name, typ, flags, off, size: Integer);
begin
  writeU32(f, name); writeU32(f, typ); writeU32(f, flags);
  writeU32(f, 0);   { sh_addr = 0 in ET_REL }
  writeU32(f, off); writeU32(f, size);
end;
procedure writeShdrB(f: Integer; link, info, alignv, entsize: Integer);
begin
  writeU32(f, link); writeU32(f, info);
  writeU32(f, alignv); writeU32(f, entsize);
end;
{$endif}

{$ifdef FPC}
procedure writeELF(const outPath: AnsiString);
var f: File; i: Integer;
    phCount, codeOffset, machine: Integer;
    dataBase, bssBase, entry, filesz, memsz, addr: Int64;
begin
  if TargetArch = TARGET_AARCH64 then
    machine := 183
  else
    machine := 62;
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
    PatchDynCallSites(dataBase);
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
  writeU16(f,2);writeU16(f,machine);writeU32(f,1);
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
    phCount, codeOffset, machine: Integer;
    dataBase, bssBase, entry, filesz, memsz, addr: Int64;
begin
  if TargetArch = TARGET_AARCH64 then
    machine := 183
  else
    machine := 62;
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
    PatchDynCallSites(dataBase);
    PatchDynamicData(dataBase);
  end;

  for i := 0 to MethodFixCount-1 do
  begin
    addr := entry + Procs[MethodFixups[i].ProcIdx].BodyAddr;
    PatchDataU64(MethodFixups[i].DataPos, addr);
  end;

  { @proc: patch each `mov rax, imm64` (x86-64) / 8-byte literal (aarch64) with
    the routine's absolute code address. }
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
  writeU16(f,2);writeU16(f,machine);writeU32(f,1);
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

procedure writeELF32(const outPath: AnsiString);
{ Static i386 ET_EXEC writer (feature-target-i386). One PT_LOAD mapping the
  whole file at LOAD_ADDR32 — p_offset must equal p_vaddr mod pagesize, so
  offset 0 (the gen_arch_probe.py lesson). v1 constraints are enforced, not
  assumed: anything needing 64-bit-only fixup machinery is a hard error. }
var
  i, codeOffset, phnum: Integer;
  isDyn: Boolean;
  dataBase, bssBase, entry, filesz, memsz, addr: Int64;
{$ifdef FPC}
  f: File;
{$else}
  f: Integer;
{$endif}
begin
  isDyn := False;
  if (TargetArch = TARGET_I386) or (TargetArch = TARGET_ARM32) then
  begin
    if ExternalCount > 0 then isDyn := True;
  end;
  if (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32) then
  begin
    if ExternalCount > 0 then
      Error('target esp32: external (dynamic) symbols not yet supported');
    if (MethodFixCount > 0) or (ProcAddrFixCount > 0) then
      Error('target esp32: method/proc-address fixups not yet supported');
  end;

  phnum := 1;
  codeOffset := CODE_OFFSET32;
  if isDyn then
  begin
    PrepareDynamicData32;          { appends interp/dynstr/dynsym/hash/rel/dynamic }
    phnum := 3;
    codeOffset := DYNAMIC_CODE_OFFSET32;
  end;
  dataBase := LOAD_ADDR32 + codeOffset + CodeLen;
  { BSS holds word-sized globals laid out with AlignTo offsets, so the base
    itself must be aligned — Xtensa s32i/l32i (and strict RV32 cores) trap on
    misaligned word access. Code+data lengths are byte-granular, so pad. }
  bssBase  := AlignTo(dataBase + DataLen, 8);
  entry    := LOAD_ADDR32 + codeOffset;
  filesz   := codeOffset + CodeLen + DataLen;
  memsz    := (bssBase - LOAD_ADDR32) + BSSSize;

  { Data fixups: 4-byte absolute on this target (EmitDataRef emitted 4 bytes). }
  for i := 0 to FixCount-1 do
  begin
    addr := dataBase + Fixups[i].DataOff;
    Patch32(Fixups[i].CodePos, addr);
  end;

  { Global (BSS) fixups: 4-byte absolute, same as x86-64. }
  for i := 0 to GlobFixCount-1 do
  begin
    addr := bssBase + GlobFix[i].BSSoff;
    Patch32(GlobFix[i].CodePos, addr);
  end;

  { @proc: 32-bit absolute code address (i386 `mov eax,imm32` / arm32 literal
    word) patched in place. }
  for i := 0 to ProcAddrFixCount-1 do
  begin
    addr := entry + Procs[ProcAddrFix[i].ProcIdx].BodyAddr;
    Patch32(ProcAddrFix[i].CodePos, addr);
  end;

  { Method-pointer fixups: patch the 32-bit code address into each VMT slot
    (data blob). Slots are 8 bytes; the address fits in the low dword, the high
    dword stays zero (PatchDataU64 writes the full Int64 and addr < 2^32). The
    esp32 targets are still rejected by the guard above. }
  for i := 0 to MethodFixCount-1 do
    PatchDataU64(MethodFixups[i].DataPos, entry + Procs[MethodFixups[i].ProcIdx].BodyAddr);

  { Data->data pointer relocations (RTTI/layout blobs). Slots are 8 bytes; the
    32-bit absolute target fits in the low dword, high dword stays zero. }
  for i := 0 to DataPtrFixCount-1 do
    PatchDataU64(DataPtrFix[i].DataPos, dataBase + DataPtrFix[i].TargetOff);

  { Dynamic externals: point each FF/14/25 indirect call at its GOT slot VA, and
    fill the dynamic-section absolute pointers (STRTAB/SYMTAB/HASH/REL). }
  if isDyn then
  begin
    for i := 0 to DynCallCount-1 do
    begin
      addr := dataBase + ExternalGotOff[DynCallExtIdx[i]];
      if TargetArch = TARGET_ARM32 then
      begin
        { movw ip,#lo16 ; movt ip,#hi16 — A2 encoding imm4:imm12 fields. }
        Patch32(DynCallCodePos[i],
          $E300C000 or (((addr and $F000) shl 4) or (addr and $FFF)));
        Patch32(DynCallCodePos[i] + 4,
          $E340C000 or ((((addr shr 16) and $F000) shl 4) or ((addr shr 16) and $FFF)));
      end
      else
        Patch32(DynCallCodePos[i], addr);   { i386 call dword [abs32] operand }
    end;
    PatchDynamicData32(dataBase);
  end;

{$ifdef FPC}
  Assign(f, outPath); Rewrite(f, 1);
{$else}
  AssignPath := outPath;
  f := sysopen(AssignPath, 577); { O_WRONLY | O_CREAT | O_TRUNC }
{$endif}

  { ELF32 ehdr (52 bytes) }
  writeU8(f,$7F);writeU8(f,$45);writeU8(f,$4C);writeU8(f,$46);
  writeU8(f,1);writeU8(f,1);writeU8(f,1);writeU8(f,0);  { class 32, LE, v1 }
  writeU8(f,0);writeU8(f,0);writeU8(f,0);writeU8(f,0);
  writeU8(f,0);writeU8(f,0);writeU8(f,0);writeU8(f,0);
  writeU16(f,2);
  if TargetArch = TARGET_ARM32 then writeU16(f,40)
  else if TargetArch = TARGET_RISCV32 then writeU16(f,243)
  else if TargetArch = TARGET_XTENSA then writeU16(f,94)
  else writeU16(f,3);
  writeU32(f,1);            { ET_EXEC, EM_ARM/EM_386 }
  writeU32(f,entry);writeU32(f,ELF32_HEADER_SIZE);writeU32(f,0);
  if TargetArch = TARGET_ARM32 then writeU32(f,$05000000) else writeU32(f,0);
  writeU16(f,ELF32_HEADER_SIZE);writeU16(f,PROG32_HEADER_SIZE);
  writeU16(f,phnum);writeU16(f,0);writeU16(f,0);writeU16(f,0);

  { phdr32 (32 bytes): PT_LOAD RWX, whole file at LOAD_ADDR32 }
  writeU32(f,1);writeU32(f,0);                          { type, offset }
  writeU32(f,LOAD_ADDR32);writeU32(f,LOAD_ADDR32);
  writeU32(f,filesz);writeU32(f,memsz);
  writeU32(f,7);writeU32(f,$1000);                      { flags, align }
  if isDyn then
  begin
    { PT_INTERP (R): the dynamic loader path. }
    writeU32(f,3);                                      { p_type = PT_INTERP }
    writeU32(f,codeOffset + CodeLen + DynamicInterpOff);{ p_offset }
    writeU32(f,dataBase + DynamicInterpOff);            { p_vaddr }
    writeU32(f,dataBase + DynamicInterpOff);            { p_paddr }
    writeU32(f,DynamicInterpSize);                      { p_filesz }
    writeU32(f,DynamicInterpSize);                      { p_memsz }
    writeU32(f,4);writeU32(f,1);                        { flags=R, align }
    { PT_DYNAMIC (RW). }
    writeU32(f,2);                                      { p_type = PT_DYNAMIC }
    writeU32(f,codeOffset + CodeLen + DynamicOff);      { p_offset }
    writeU32(f,dataBase + DynamicOff);                  { p_vaddr }
    writeU32(f,dataBase + DynamicOff);                  { p_paddr }
    writeU32(f,DynamicSize);                            { p_filesz }
    writeU32(f,DynamicSize);                            { p_memsz }
    writeU32(f,6);writeU32(f,4);                        { flags=RW, align }
  end;

{$ifdef FPC}
  if CodeLen > 0 then Blockwrite(f,Code[0],CodeLen);
  if DataLen > 0 then Blockwrite(f,Data[0],DataLen);
  Close(f);
  FpChmod(outPath,&755);
{$else}
  if CodeLen > 0 then syswrite(f,Code,CodeLen);
  if DataLen > 0 then syswrite(f,Data,DataLen);
  sysfchmod(f, 493); { chmod 755 }
  sysclose(f);
{$endif}
end;

procedure writeELF32Rel(const outPath: AnsiString);
{ Relocatable ELF32 object writer (feature-elf-rel-writer): ET_REL .o for the
  esp32-idf profile. Both ESP backends route every absolute address through a
  32-bit literal slot and resolve intra-object calls at emit time, so every
  relocation is a plain data-word R_XTENSA_32 / R_RISCV_32 (type 1 on both) —
  no code relocations, no linker-relaxation interaction.
  File layout (written sequentially; the self-hosted writer cannot seek):
  ehdr, .text, .data, .symtab, .strtab, .rela.text, .rela.data, .shstrtab,
  section headers. Symbols: section syms, every proc as LOCAL FUNC (debug
  visibility without link-time name collisions), the program entry exported
  GLOBAL as app_main, externals as UNDEF GLOBAL. }
var
  i, machine: Integer;
  numProcSyms, numSyms, firstGlobal: Integer;
  textOff, dataOff, symOff, strOff, relaTextOff, relaDataOff: Integer;
  shstrOff, shOff, strSize: Integer;
  relaTextCount, relaDataCount, appMainOff: Integer;
{$ifdef FPC}
  f: File;
{$else}
  f: Integer;
{$endif}
begin
  if (TargetArch <> TARGET_XTENSA) and (TargetArch <> TARGET_RISCV32) then
    Error('--emit-obj: only xtensa/riscv32 targets are supported');
  if ProcAddrFixCount > 0 then
    Error('--emit-obj: proc-address fixups not yet supported');
  if TargetArch = TARGET_XTENSA then machine := 94 else machine := 243;

  { .strtab layout: 0 = empty, then proc names, app_main, external names }
  strSize := 1;
  numProcSyms := 0;
  for i := 0 to ProcCount-1 do
    if (Procs[i].BodyAddr >= 0) and (not ProcExternal[i]) then
    begin
      ObjProcStrOff[i] := strSize;
      strSize := strSize + Length(Procs[i].Name) + 1;
      Inc(numProcSyms);
    end
    else
      ObjProcStrOff[i] := -1;
  appMainOff := strSize;
  strSize := strSize + 9;  { 'app_main' + NUL }
  for i := 0 to ExternalCount-1 do
  begin
    ObjExtStrOff[i] := strSize;
    strSize := strSize + Length(Procs[ExternalProc[i]].Name) + 1;
  end;

  firstGlobal := 4 + numProcSyms;  { null + .text/.data/.bss section syms + procs }
  numSyms := firstGlobal + 1 + ExternalCount;
  relaTextCount := FixCount + GlobFixCount + DynCallCount;
  relaDataCount := DataPtrFixCount + MethodFixCount;

  textOff := ELF32_HEADER_SIZE;                  { 52, already 4-aligned }
  dataOff := AlignTo(textOff + CodeLen, 8);
  symOff  := AlignTo(dataOff + DataLen, 4);
  strOff  := symOff + numSyms * 16;
  relaTextOff := AlignTo(strOff + strSize, 4);
  relaDataOff := relaTextOff + relaTextCount * 12;
  shstrOff := relaDataOff + relaDataCount * 12;
  shOff := AlignTo(shstrOff + 66, 4);            { 66 = .shstrtab blob size }

{$ifdef FPC}
  Assign(f, outPath); Rewrite(f, 1);
{$else}
  AssignPath := outPath;
  f := sysopen(AssignPath, 577); { O_WRONLY | O_CREAT | O_TRUNC }
{$endif}

  { ELF32 ehdr (52 bytes), ET_REL }
  writeU8(f,$7F);writeU8(f,$45);writeU8(f,$4C);writeU8(f,$46);
  writeU8(f,1);writeU8(f,1);writeU8(f,1);writeU8(f,0);  { class 32, LE, v1 }
  writeU8(f,0);writeU8(f,0);writeU8(f,0);writeU8(f,0);
  writeU8(f,0);writeU8(f,0);writeU8(f,0);writeU8(f,0);
  writeU16(f,1);writeU16(f,machine);writeU32(f,1);      { ET_REL }
  writeU32(f,0);writeU32(f,0);writeU32(f,shOff);        { entry, phoff, shoff }
  writeU32(f,0);                                        { e_flags }
  writeU16(f,ELF32_HEADER_SIZE);writeU16(f,0);writeU16(f,0);
  writeU16(f,40);writeU16(f,9);writeU16(f,8);   { shentsize, shnum, shstrndx }

{$ifdef FPC}
  if CodeLen > 0 then Blockwrite(f,Code[0],CodeLen);
  writePad(f, dataOff - (textOff + CodeLen));
  if DataLen > 0 then Blockwrite(f,Data[0],DataLen);
{$else}
  if CodeLen > 0 then syswrite(f,Code,CodeLen);
  writePad(f, dataOff - (textOff + CodeLen));
  if DataLen > 0 then syswrite(f,Data,DataLen);
{$endif}
  writePad(f, symOff - (dataOff + DataLen));

  { .symtab; sh_info below = firstGlobal (locals first, per the ELF spec) }
  writeSym32(f, 0, 0, 0, 0, 0);
  writeSym32(f, 0, 0, 0, 3, 1);   { STT_SECTION .text }
  writeSym32(f, 0, 0, 0, 3, 3);   { STT_SECTION .data }
  writeSym32(f, 0, 0, 0, 3, 5);   { STT_SECTION .bss }
  for i := 0 to ProcCount-1 do
    if ObjProcStrOff[i] >= 0 then
      writeSym32(f, ObjProcStrOff[i], Procs[i].BodyAddr, 0, 2, 1); { LOCAL FUNC }
  writeSym32(f, appMainOff, 0, 0, $12, 1);  { GLOBAL FUNC app_main = entry }
  for i := 0 to ExternalCount-1 do
    writeSym32(f, ObjExtStrOff[i], 0, 0, $10, 0); { GLOBAL NOTYPE UNDEF }

  { .strtab }
  writeU8(f, 0);
  for i := 0 to ProcCount-1 do
    if ObjProcStrOff[i] >= 0 then writeStrZ(f, Procs[i].Name);
  writeStrZ(f, 'app_main');
  for i := 0 to ExternalCount-1 do
    writeStrZ(f, Procs[ExternalProc[i]].Name);
  writePad(f, relaTextOff - (strOff + strSize));

  { .rela.text: literal slots -> .data / .bss / undefined externals.
    Symbol indices: 1 = .text section sym, 2 = .data, 3 = .bss. }
  for i := 0 to FixCount-1 do
    writeRela32(f, Fixups[i].CodePos, 2, 1, Fixups[i].DataOff);
  for i := 0 to GlobFixCount-1 do
    writeRela32(f, GlobFix[i].CodePos, 3, 1, GlobFix[i].BSSoff);
  for i := 0 to DynCallCount-1 do
    writeRela32(f, DynCallCodePos[i], firstGlobal + 1 + DynCallExtIdx[i], 1, 0);

  { .rela.data: data->data pointers and data->code method slots. Slots are 8
    bytes wide (layout shared with 64-bit targets); the reloc patches the low
    word, the high word stays zero. }
  for i := 0 to DataPtrFixCount-1 do
    writeRela32(f, DataPtrFix[i].DataPos, 2, 1, DataPtrFix[i].TargetOff);
  for i := 0 to MethodFixCount-1 do
    writeRela32(f, MethodFixups[i].DataPos, 1, 1,
                Procs[MethodFixups[i].ProcIdx].BodyAddr);

  { .shstrtab: fixed 66-byte blob; name offsets hardcoded in the shdrs below }
  writeU8(f, 0);
  writeStrZ(f, '.text');        { 1 }
  writeStrZ(f, '.rela.text');   { 7 }
  writeStrZ(f, '.data');        { 18 }
  writeStrZ(f, '.rela.data');   { 24 }
  writeStrZ(f, '.bss');         { 35 }
  writeStrZ(f, '.symtab');      { 40 }
  writeStrZ(f, '.strtab');      { 48 }
  writeStrZ(f, '.shstrtab');    { 56 }
  writePad(f, shOff - (shstrOff + 66));

  { shdrs: 0 null, 1 .text, 2 .rela.text, 3 .data, 4 .rela.data, 5 .bss,
    6 .symtab, 7 .strtab, 8 .shstrtab. $40 = SHF_INFO_LINK on rela sections. }
  writeShdrA(f, 0, 0, 0, 0, 0);
  writeShdrB(f, 0, 0, 0, 0);
  writeShdrA(f, 1, 1, 6, textOff, CodeLen);
  writeShdrB(f, 0, 0, 4, 0);
  writeShdrA(f, 7, 4, $40, relaTextOff, relaTextCount*12);
  writeShdrB(f, 6, 1, 4, 12);
  writeShdrA(f, 18, 1, 3, dataOff, DataLen);
  writeShdrB(f, 0, 0, 8, 0);
  writeShdrA(f, 24, 4, $40, relaDataOff, relaDataCount*12);
  writeShdrB(f, 6, 3, 4, 12);
  writeShdrA(f, 35, 8, 3, dataOff + DataLen, BSSSize);
  writeShdrB(f, 0, 0, 8, 0);
  writeShdrA(f, 40, 2, 0, symOff, numSyms*16);
  writeShdrB(f, 7, firstGlobal, 4, 16);
  writeShdrA(f, 48, 3, 0, strOff, strSize);
  writeShdrB(f, 0, 0, 1, 0);
  writeShdrA(f, 56, 3, 0, shstrOff, 66);
  writeShdrB(f, 0, 0, 1, 0);

{$ifdef FPC}
  Close(f);
{$else}
  sysfchmod(f, 420); { chmod 644 — a .o is not executable }
  sysclose(f);
{$endif}
end;

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
          AppendString(IncExpanded, IncIncluded);
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
      k := i;
      while k <= Length(src) do
      begin
        if (k < Length(src)) and (src[k] = '{') and (src[k + 1] = '$') then
          Break;                            { real directive boundary }
        if src[k] = '{' then
        begin
          { Brace comment: skip to its matching close-brace, nesting on an inner
            directive-looking open-brace-dollar so its close-brace does not end
            the comment early and its directive text is not taken for a real one.
            The comment is still copied through for the real lexer pass. }
          j := 1;
          Inc(k);
          while (k <= Length(src)) and (j > 0) do
          begin
            if (src[k] = '{') and (k < Length(src)) and (src[k + 1] = '$') then Inc(j)
            else if src[k] = '}' then Dec(j);
            Inc(k);
          end;
        end
        else
          Inc(k);
      end;
      AppendRange(IncExpanded, src, i, k - 1);
      i := k;
    end;
  end;
  if condCount <> 0 then Error('unterminated conditional directive during include expansion');
  PasDefineCount := savedDefineCount;
  PasDefineCharLen := savedDefineCharLen;
  for k := 0 to MAX_PAS_DEFINES - 1 do
    PasDefineActive[k] := savedDefineActive[k];
  src := IncExpanded;
end;
