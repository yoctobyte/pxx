{ SPDX-License-Identifier: MPL-2.0 }
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
  { Symbol names (one per imported symbol). An `external 'lib' name 'sym'` clause
    overrides the emitted link symbol (ProcExtName); else the Pascal name. }
  for i := 0 to ExternalCount-1 do
  begin
    nameOff[i] := DataLen - DynamicStrOff;
    if ProcExtName[ExternalProc[i]] >= 0 then
      DataPutZ(Strs[ProcExtName[ExternalProc[i]]].Text)
    else
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
    if ProcExtName[ExternalProc[i]] >= 0 then
      DataPutZ(Strs[ProcExtName[ExternalProc[i]]].Text)
    else
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
{ Elf64_Sym (24 bytes) / Elf64_Rela (24 bytes) / Elf64_Shdr (64 bytes, split
  A/B for the same >6-param reason as writeShdrA/B) for writeELFRelX64. }
procedure writeSym64(var f: File; name: Integer; info, shndx: Integer; value, size: Int64);
begin
  writeU32(f, name); writeU8(f, info); writeU8(f, 0); writeU16(f, shndx);
  writeU64(f, value); writeU64(f, size);
end;
procedure writeRela64(var f: File; offset: Int64; symIdx, rtype: Integer; addend: Int64);
begin
  writeU64(f, offset);
  writeU64(f, (Int64(symIdx) shl 32) or Int64(rtype));
  writeU64(f, addend);
end;
procedure writeShdrA64(var f: File; name, typ: Integer; flags, off, size: Int64);
begin
  writeU32(f, name); writeU32(f, typ);
  writeU64(f, flags); writeU64(f, 0);   { sh_addr = 0 in ET_REL }
  writeU64(f, off); writeU64(f, size);
end;
procedure writeShdrB64(var f: File; link, info: Integer; alignv, entsize: Int64);
begin
  writeU32(f, link); writeU32(f, info);
  writeU64(f, alignv); writeU64(f, entsize);
end;
{ One Elf64_Shdr (64 bytes) for the -g debug sections. All share flags/addr/link/
  info/entsize = 0 and addralign = 1, so only name/type/offset/size vary. }
procedure writeShdr64(var f: File; name, typ: Integer; off, size: Int64);
begin
  writeU32(f, name); writeU32(f, typ);
  writeU64(f, DbgShFlags); writeU64(f, DbgShAddr);
  writeU64(f, off); writeU64(f, size);
  writeU32(f, 0); writeU32(f, 0);     { sh_link, sh_info }
  writeU64(f, DbgShAlign); writeU64(f, 0);  { sh_addralign, sh_entsize }
end;
{ -g section header table: NULL, .text, .data, .bss (allocated — so gdb's
  find_pc_section maps code/data/bss addresses; without .text a subprogram DIE's
  low_pc resolves to no section and gdb segfaults), then the 4 debug sections. }
procedure DbgWriteShdrTable(var f: File; entry, dataBase, bssBase: Int64; codeOffset: Integer; dbgFileBase: Int64);
begin
  writePad(f, 64);   { NULL shdr (index 0) }
  DbgShFlags := 6; DbgShAddr := entry;    DbgShAlign := 16;
  writeShdr64(f, DbgNmText, 1, codeOffset, CodeLen);                  { .text PROGBITS }
  DbgShFlags := 3; DbgShAddr := dataBase; DbgShAlign := 8;
  writeShdr64(f, DbgNmData, 1, codeOffset + CodeLen, DataLen);        { .data PROGBITS }
  DbgShFlags := 3; DbgShAddr := bssBase;  DbgShAlign := 8;
  writeShdr64(f, DbgNmBss, 8, codeOffset + CodeLen + DataLen, BSSSize); { .bss NOBITS }
  DbgShFlags := 0; DbgShAddr := 0;        DbgShAlign := 1;
  writeShdr64(f, DbgNmLine,   1, dbgFileBase + DbgLineSecOff,   DbgLineSecSize);
  writeShdr64(f, DbgNmInfo,   1, dbgFileBase + DbgInfoSecOff,   DbgInfoSecSize);
  writeShdr64(f, DbgNmAbbrev, 1, dbgFileBase + DbgAbbrevSecOff, DbgAbbrevSecSize);
  writeShdr64(f, DbgNmFrame,  1, dbgFileBase + DbgFrameSecOff,  DbgFrameSecSize);
  writeShdr64(f, DbgNmShStr,  3, dbgFileBase + DbgShStrSecOff,  DbgShStrSecSize);
end;
{ Elf32_Shdr (40 bytes) for the -g ELF32 targets (i386/arm32). }
procedure writeShdr32(var f: File; name, typ, off, size: Integer);
begin
  writeU32(f, name); writeU32(f, typ);
  writeU32(f, DbgShFlags); writeU32(f, DbgShAddr);
  writeU32(f, off); writeU32(f, size);
  writeU32(f, 0); writeU32(f, 0);     { sh_link, sh_info }
  writeU32(f, DbgShAlign); writeU32(f, 0);  { sh_addralign, sh_entsize }
end;
procedure DbgWriteShdrTable32(var f: File; entry, dataBase, bssBase, codeOffset, dbgFileBase: Integer);
begin
  writePad(f, 40);   { NULL shdr (index 0) }
  DbgShFlags := 6; DbgShAddr := entry;    DbgShAlign := 16;
  writeShdr32(f, DbgNmText, 1, codeOffset, CodeLen);
  DbgShFlags := 3; DbgShAddr := dataBase; DbgShAlign := 8;
  writeShdr32(f, DbgNmData, 1, codeOffset + CodeLen, DataLen);
  DbgShFlags := 3; DbgShAddr := bssBase;  DbgShAlign := 8;
  writeShdr32(f, DbgNmBss, 8, codeOffset + CodeLen + DataLen, BSSSize);
  DbgShFlags := 0; DbgShAddr := 0;        DbgShAlign := 1;
  writeShdr32(f, DbgNmLine,   1, dbgFileBase + DbgLineSecOff,   DbgLineSecSize);
  writeShdr32(f, DbgNmInfo,   1, dbgFileBase + DbgInfoSecOff,   DbgInfoSecSize);
  writeShdr32(f, DbgNmAbbrev, 1, dbgFileBase + DbgAbbrevSecOff, DbgAbbrevSecSize);
  writeShdr32(f, DbgNmFrame,  1, dbgFileBase + DbgFrameSecOff,  DbgFrameSecSize);
  writeShdr32(f, DbgNmShStr,  3, dbgFileBase + DbgShStrSecOff,  DbgShStrSecSize);
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
{ Elf64_Sym (24 bytes) / Elf64_Rela (24 bytes) / Elf64_Shdr (64 bytes, split
  A/B for the same >6-param reason as writeShdrA/B) for writeELFRelX64. }
procedure writeSym64(f: Integer; name: Integer; info, shndx: Integer; value, size: Int64);
begin
  writeU32(f, name); writeU8(f, info); writeU8(f, 0); writeU16(f, shndx);
  writeU64(f, value); writeU64(f, size);
end;
procedure writeRela64(f: Integer; offset: Int64; symIdx, rtype: Integer; addend: Int64);
begin
  writeU64(f, offset);
  writeU64(f, (Int64(symIdx) shl 32) or Int64(rtype));
  writeU64(f, addend);
end;
procedure writeShdrA64(f: Integer; name, typ: Integer; flags, off, size: Int64);
begin
  writeU32(f, name); writeU32(f, typ);
  writeU64(f, flags); writeU64(f, 0);   { sh_addr = 0 in ET_REL }
  writeU64(f, off); writeU64(f, size);
end;
procedure writeShdrB64(f: Integer; link, info: Integer; alignv, entsize: Int64);
begin
  writeU32(f, link); writeU32(f, info);
  writeU64(f, alignv); writeU64(f, entsize);
end;
{ One Elf64_Shdr (64 bytes) for the -g debug sections. All share flags/addr/link/
  info/entsize = 0 and addralign = 1, so only name/type/offset/size vary. }
procedure writeShdr64(f: Integer; name, typ: Integer; off, size: Int64);
begin
  writeU32(f, name); writeU32(f, typ);
  writeU64(f, DbgShFlags); writeU64(f, DbgShAddr);
  writeU64(f, off); writeU64(f, size);
  writeU32(f, 0); writeU32(f, 0);     { sh_link, sh_info }
  writeU64(f, DbgShAlign); writeU64(f, 0);  { sh_addralign, sh_entsize }
end;
{ -g section header table: NULL, .text, .data, .bss (allocated — so gdb's
  find_pc_section maps code/data/bss addresses; without .text a subprogram DIE's
  low_pc resolves to no section and gdb segfaults), then the 4 debug sections. }
procedure DbgWriteShdrTable(f: Integer; entry, dataBase, bssBase: Int64; codeOffset: Integer; dbgFileBase: Int64);
var i: Integer;
begin
  for i := 1 to 64 do writeU8(f, 0);   { NULL shdr (index 0) }
  DbgShFlags := 6; DbgShAddr := entry;    DbgShAlign := 16;
  writeShdr64(f, DbgNmText, 1, codeOffset, CodeLen);                  { .text PROGBITS }
  DbgShFlags := 3; DbgShAddr := dataBase; DbgShAlign := 8;
  writeShdr64(f, DbgNmData, 1, codeOffset + CodeLen, DataLen);        { .data PROGBITS }
  DbgShFlags := 3; DbgShAddr := bssBase;  DbgShAlign := 8;
  writeShdr64(f, DbgNmBss, 8, codeOffset + CodeLen + DataLen, BSSSize); { .bss NOBITS }
  DbgShFlags := 0; DbgShAddr := 0;        DbgShAlign := 1;
  writeShdr64(f, DbgNmLine,   1, dbgFileBase + DbgLineSecOff,   DbgLineSecSize);
  writeShdr64(f, DbgNmInfo,   1, dbgFileBase + DbgInfoSecOff,   DbgInfoSecSize);
  writeShdr64(f, DbgNmAbbrev, 1, dbgFileBase + DbgAbbrevSecOff, DbgAbbrevSecSize);
  writeShdr64(f, DbgNmFrame,  1, dbgFileBase + DbgFrameSecOff,  DbgFrameSecSize);
  writeShdr64(f, DbgNmShStr,  3, dbgFileBase + DbgShStrSecOff,  DbgShStrSecSize);
end;
{ Elf32_Shdr (40 bytes) for the -g ELF32 targets (i386/arm32). }
procedure writeShdr32(f: Integer; name, typ, off, size: Integer);
begin
  writeU32(f, name); writeU32(f, typ);
  writeU32(f, DbgShFlags); writeU32(f, DbgShAddr);
  writeU32(f, off); writeU32(f, size);
  writeU32(f, 0); writeU32(f, 0);     { sh_link, sh_info }
  writeU32(f, DbgShAlign); writeU32(f, 0);  { sh_addralign, sh_entsize }
end;
procedure DbgWriteShdrTable32(f: Integer; entry, dataBase, bssBase, codeOffset, dbgFileBase: Integer);
var i: Integer;
begin
  for i := 1 to 40 do writeU8(f, 0);   { NULL shdr (index 0) }
  DbgShFlags := 6; DbgShAddr := entry;    DbgShAlign := 16;
  writeShdr32(f, DbgNmText, 1, codeOffset, CodeLen);
  DbgShFlags := 3; DbgShAddr := dataBase; DbgShAlign := 8;
  writeShdr32(f, DbgNmData, 1, codeOffset + CodeLen, DataLen);
  DbgShFlags := 3; DbgShAddr := bssBase;  DbgShAlign := 8;
  writeShdr32(f, DbgNmBss, 8, codeOffset + CodeLen + DataLen, BSSSize);
  DbgShFlags := 0; DbgShAddr := 0;        DbgShAlign := 1;
  writeShdr32(f, DbgNmLine,   1, dbgFileBase + DbgLineSecOff,   DbgLineSecSize);
  writeShdr32(f, DbgNmInfo,   1, dbgFileBase + DbgInfoSecOff,   DbgInfoSecSize);
  writeShdr32(f, DbgNmAbbrev, 1, dbgFileBase + DbgAbbrevSecOff, DbgAbbrevSecSize);
  writeShdr32(f, DbgNmFrame,  1, dbgFileBase + DbgFrameSecOff,  DbgFrameSecSize);
  writeShdr32(f, DbgNmShStr,  3, dbgFileBase + DbgShStrSecOff,  DbgShStrSecSize);
end;
{$endif}

{ ===== DWARF Tier 1 (-g): .debug_line + minimal CU stub =====================
  PXX is its own linker, so it writes every .debug_* byte itself. Everything
  below builds the section content into the shared DbgBuf byte buffer (no file
  IO, no $ifdef — pure byte math) so both writeELF variants can append it with
  their own primitives. x86-64 only for Tier 1. }

procedure DbgPutB(v: Integer);
begin
  if DbgLen >= MAX_DWARF then Error('DWARF buffer overflow (-g)');
  DbgBuf[DbgLen] := v and 255;
  Inc(DbgLen);
end;

procedure DbgPutU16(v: Integer);
begin
  DbgPutB(v and 255); DbgPutB((v shr 8) and 255);
end;

procedure DbgPutU32(v: Integer);
begin
  DbgPutB(v and 255); DbgPutB((v shr 8) and 255);
  DbgPutB((v shr 16) and 255); DbgPutB((v shr 24) and 255);
end;

procedure DbgPutU64(v: Int64);
begin
  DbgPutU32(Integer(v and $FFFFFFFF));
  { Match writeU64's small-value path so we never rely on `v shr 32` for values
    that fit in 32 bits (the i386 self-host duplicated-low-dword landmine). }
  if (v >= 0) and (v <= 2147483647) then DbgPutU32(0)
  else if (v < 0) and (v >= -2147483648) then DbgPutU32(-1)
  else DbgPutU32(Integer((v shr 32) and $FFFFFFFF));
end;

{ A target-width address (4 on i386/arm32, 8 on x86-64/aarch64). }
procedure DbgPutAddr(v: Int64);
begin
  if DbgPtrSize = 8 then DbgPutU64(v) else DbgPutU32(Integer(v and $FFFFFFFF));
end;

{ True for the four targets that get DWARF -g (esp xtensa/riscv32 excluded:
  windowed/no-frame-pointer ABI, no gdb-over-qemu line path). }
function DbgArchSupported: Boolean;
begin
  DbgArchSupported := (TargetArch = TARGET_X86_64) or (TargetArch = TARGET_AARCH64)
    or (TargetArch = TARGET_I386) or (TargetArch = TARGET_ARM32);
end;

{ Fill the per-target DWARF parameter globals. }
procedure DbgSetArchParams;
begin
  DbgFrameSavesLR := False; DbgRegLR := 0;
  if TargetArch = TARGET_I386 then
  begin
    DbgPtrSize := 4; DbgRegFrame := 5; DbgRegRA := 8; DbgRegSP := 4;
    DbgPrologAdv1 := 1; DbgPrologAdv2 := 2;       { push ebp; mov ebp,esp }
  end
  else if TargetArch = TARGET_ARM32 then
  begin
    DbgPtrSize := 4; DbgRegFrame := 11; DbgRegRA := 14; DbgRegSP := 13;
    DbgRegLR := 14; DbgFrameSavesLR := True;
    DbgPrologAdv1 := 4; DbgPrologAdv2 := 4;       { push {fp,lr}; mov fp,sp }
  end
  else if TargetArch = TARGET_AARCH64 then
  begin
    DbgPtrSize := 8; DbgRegFrame := 29; DbgRegRA := 30; DbgRegSP := 31;
    DbgRegLR := 30; DbgFrameSavesLR := True;
    DbgPrologAdv1 := 4; DbgPrologAdv2 := 4;       { stp x29,x30,[sp,#-16]!; mov x29,sp }
  end
  else
  begin   { x86-64 }
    DbgPtrSize := 8; DbgRegFrame := 6; DbgRegRA := 16; DbgRegSP := 7;
    DbgPrologAdv1 := 1; DbgPrologAdv2 := 3;       { push rbp; mov rbp,rsp }
  end;
end;

{ Overwrite a 4-byte little-endian value already placed in DbgBuf (back-patch). }
procedure DbgPatchU32(pos, v: Integer);
begin
  DbgBuf[pos]   := v and 255;
  DbgBuf[pos+1] := (v shr 8) and 255;
  DbgBuf[pos+2] := (v shr 16) and 255;
  DbgBuf[pos+3] := (v shr 24) and 255;
end;

procedure DbgPutULEB(v: Integer);
var b: Integer;
begin
  repeat
    b := v and $7F;
    v := v shr 7;
    if v <> 0 then b := b or $80;
    DbgPutB(b);
  until v = 0;
end;

procedure DbgPutSLEB(v: Integer);
var b: Integer; more: Boolean;
begin
  more := True;
  while more do
  begin
    b := v and $7F;
    { Arithmetic shift right by 7. Pascal `div` truncates toward zero and `shr`
      is logical, so neither alone gives floor() for negatives — bias first. }
    if v < 0 then v := (v - 127) div 128
    else v := v div 128;
    if ((v = 0) and ((b and $40) = 0)) or ((v = -1) and ((b and $40) <> 0)) then
      more := False
    else
      b := b or $80;
    DbgPutB(b);
  end;
end;

procedure DbgPutStrZ(const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do DbgPutB(Ord(s[i]));
  DbgPutB(0);
end;

{ Overwrite a single byte already in DbgBuf (back-patch a block1 length). }
procedure DbgPatchB(pos, v: Integer);
begin
  DbgBuf[pos] := v and 255;
end;

{ Build a string from a name slice in TokChars (local copy — TokSliceStr in
  rtti_emit.inc is included after this file). }
function DbgTokSlice(off, len: Integer): AnsiString;
var s: AnsiString; i: Integer;
begin
  s := ''; i := 0;
  while i < len do begin AppendChar(s, TokChars[off + i]); Inc(i); end;
  DbgTokSlice := s;
end;

{ Base-type props for a TTypeKind ordinal. Returns True + sets name/enc/size for
  the scalar kinds that map to DW_TAG_base_type; False for record/class/string/
  pointer/etc (handled as structure_type or the pointer cheat). }
function DbgBaseTypeProps(tkOrd: Integer; var nm: AnsiString; var enc, sz: Integer): Boolean;
begin
  DbgBaseTypeProps := True;
  case tkOrd of
    1:  begin nm := 'Integer';    enc := 5; sz := 4; end;  { tyInteger, signed }
    2:  begin nm := 'Boolean';    enc := 2; sz := 1; end;  { boolean }
    3:  begin nm := 'Char';       enc := 8; sz := 1; end;  { unsigned_char }
    7:  begin nm := 'ShortInt';   enc := 5; sz := 1; end;
    8:  begin nm := 'Byte';       enc := 7; sz := 1; end;
    9:  begin nm := 'SmallInt';   enc := 5; sz := 2; end;
    10: begin nm := 'Word';       enc := 7; sz := 2; end;
    11: begin nm := 'LongInt';    enc := 5; sz := 4; end;
    12: begin nm := 'Cardinal';   enc := 7; sz := 4; end;
    13: begin nm := 'Int64';      enc := 5; sz := 8; end;
    14: begin nm := 'QWord';      enc := 7; sz := 8; end;
    15: begin nm := 'NativeInt';  enc := 5; sz := 8; end;
    16: begin nm := 'NativeUInt'; enc := 7; sz := 8; end;
    18: begin nm := 'Single';     enc := 4; sz := 4; end;
    19: begin nm := 'Double';     enc := 4; sz := 8; end;
    20: begin nm := 'Extended';   enc := 4; sz := 10; end;
  else
    DbgBaseTypeProps := False;
  end;
end;

{ Human label for a type, used for the pointer-cheat name and array-of-<T>. }
function DbgTypeDisplayName(tkOrd, recId: Integer): AnsiString;
var nm: AnsiString; enc, sz: Integer;
begin
  if DbgBaseTypeProps(tkOrd, nm, enc, sz) then begin DbgTypeDisplayName := nm; Exit; end;
  case tkOrd of
    4, 23, 25, 26: DbgTypeDisplayName := 'string';
    17: DbgTypeDisplayName := 'Pointer';
    21: DbgTypeDisplayName := 'set';
    22: DbgTypeDisplayName := 'Variant';
    5, 6:  { record / class: use the declared type name if known }
      if (recId >= REC_UCLASS_BASE) and ((recId - REC_UCLASS_BASE) < UClsCount) then
        DbgTypeDisplayName := DbgTokSlice(UClsNOff[recId - REC_UCLASS_BASE], UClsNLen[recId - REC_UCLASS_BASE])
      else if tkOrd = 6 then DbgTypeDisplayName := 'object'
      else DbgTypeDisplayName := 'record';
  else
    DbgTypeDisplayName := 'unknown';
  end;
end;

function DbgTypeLookup(cat, recId, aux: Integer): Integer;
var i: Integer;
begin
  for i := 0 to DbgTypeCount - 1 do
    if (DbgTypeCat[i] = cat) and (DbgTypeRecId[i] = recId) and (DbgTypeAux[i] = aux) then
    begin DbgTypeLookup := DbgTypeOff[i]; Exit; end;
  DbgTypeLookup := -1;
end;

procedure DbgTypeRegister(cat, recId, aux, off: Integer);
begin
  if DbgTypeCount >= MAX_DBG_TYPES then Exit;
  DbgTypeCat[DbgTypeCount] := cat;
  DbgTypeRecId[DbgTypeCount] := recId;
  DbgTypeAux[DbgTypeCount] := aux;
  DbgTypeOff[DbgTypeCount] := off;
  Inc(DbgTypeCount);
end;

function DbgEnsureType(tkOrd, recId, isArr, arrLen, elemTkOrd, elemRec: Integer): Integer; forward;

{ Shared anonymous "pointer to void" DIE — the base every cheat typedef wraps. }
function DbgEnsureVoidPtr: Integer;
var off: Integer;
begin
  off := DbgTypeLookup(9000, 0, 0);
  if off >= 0 then begin DbgEnsureVoidPtr := off; Exit; end;
  off := DbgLen - DbgInfoSecOff;
  DbgTypeRegister(9000, 0, 0, off);
  DbgPutULEB(12); DbgPutB(DbgPtrSize);   { anonymous pointer_type, target ptr width }
  DbgEnsureVoidPtr := off;
end;

{ A runtime-layout type that gets a labeled typedef over the void pointer, so gdb
  shows the Pascal name (`string`, `array of Integer`, …) instead of `void *`,
  while `x/s` / handle inspection still work. }
function DbgEmitNamedCheat(const nm: AnsiString): Integer;
var vp, off: Integer;
begin
  vp := DbgEnsureVoidPtr;
  off := DbgLen - DbgInfoSecOff;
  DbgPutULEB(11); DbgPutStrZ(nm); DbgPutU32(vp);   { typedef nm -> void* }
  DbgEmitNamedCheat := off;
end;

{ Emit a DW_TAG_base_type / pointer-cheat / structure_type for a non-array type,
  returning its .debug_info offset (cached). Records emit their members from the
  existing UFld* tables (no field metadata rebuild); class/string/pointer/variant
  degrade to a named typedef over a void pointer. }
function DbgEnsureScalar(tkOrd, recId: Integer): Integer;
var off, i, ci, fb, fc, memOff, fldTk, fldRec, fldArr, fldArrLen, fldDyn: Integer;
    nm: AnsiString; enc, sz: Integer;
begin
  off := DbgTypeLookup(tkOrd, recId, 0);
  if off >= 0 then begin DbgEnsureScalar := off; Exit; end;

  if DbgBaseTypeProps(tkOrd, nm, enc, sz) then
  begin
    off := DbgLen - DbgInfoSecOff;
    DbgTypeRegister(tkOrd, recId, 0, off);
    DbgPutULEB(5); DbgPutStrZ(nm); DbgPutB(enc); DbgPutB(sz);
    DbgEnsureScalar := off; Exit;
  end;

  if (tkOrd = 5) and (recId >= REC_UCLASS_BASE) and ((recId - REC_UCLASS_BASE) < UClsCount)
     and not UClsIsInterface[recId - REC_UCLASS_BASE] then
  begin
    { record by value → structure_type. Ensure each field's type first so member
      ref4s point backward. }
    ci := recId - REC_UCLASS_BASE;
    fb := UClsFBase[ci]; fc := UClsFCount[ci];
    for i := 0 to fc - 1 do
    begin
      fldTk := UFldTk[fb + i]; fldRec := UFldRec_[fb + i];
      fldArr := 0; if UFldIsArray[fb + i] then fldArr := 1;
      fldArrLen := UFldArrLen[fb + i]; fldDyn := UFldDynDepth[fb + i];
      if fldDyn > 0 then DbgEnsureType(fldTk, fldRec, 1, -1, fldTk, fldRec)
      else if fldArr <> 0 then DbgEnsureType(fldTk, fldRec, 1, fldArrLen, fldTk, fldRec)
      else DbgEnsureScalar(fldTk, fldRec);
    end;
    off := DbgLen - DbgInfoSecOff;
    DbgTypeRegister(tkOrd, recId, 0, off);
    DbgPutULEB(7);                                  { structure_type }
    DbgPutStrZ(DbgTokSlice(UClsNOff[ci], UClsNLen[ci]));
    DbgPutU16(RecSize(recId));                      { byte_size }
    for i := 0 to fc - 1 do
    begin
      fldTk := UFldTk[fb + i]; fldRec := UFldRec_[fb + i];
      fldArr := 0; if UFldIsArray[fb + i] then fldArr := 1;
      fldArrLen := UFldArrLen[fb + i]; fldDyn := UFldDynDepth[fb + i];
      if fldDyn > 0 then memOff := DbgEnsureType(fldTk, fldRec, 1, -1, fldTk, fldRec)
      else if fldArr <> 0 then memOff := DbgEnsureType(fldTk, fldRec, 1, fldArrLen, fldTk, fldRec)
      else memOff := DbgEnsureScalar(fldTk, fldRec);
      DbgPutULEB(8);                                { member }
      DbgPutStrZ(DbgTokSlice(UFldNOff[fb + i], UFldNLen[fb + i]));
      DbgPutU32(memOff);                            { ref4 type }
      DbgPutU16(UFldOff_[fb + i]);                  { data_member_location }
    end;
    DbgPutB(0);                                     { end members }
    DbgEnsureScalar := off; Exit;
  end;

  { Everything with runtime/heap layout → named typedef over a void pointer. }
  off := DbgEmitNamedCheat(DbgTypeDisplayName(tkOrd, recId));
  DbgTypeRegister(tkOrd, recId, 0, off);
  DbgEnsureScalar := off;
end;

function DbgEnsureType(tkOrd, recId, isArr, arrLen, elemTkOrd, elemRec: Integer): Integer;
var off, elemOff, cat, aux: Integer;
begin
  if (isArr <> 0) and (arrLen >= 0) then
  begin
    cat := 2000; aux := arrLen * 64 + elemTkOrd;
    off := DbgTypeLookup(cat, elemRec, aux);
    if off >= 0 then begin DbgEnsureType := off; Exit; end;
    elemOff := DbgEnsureScalar(elemTkOrd, elemRec);
    off := DbgLen - DbgInfoSecOff;
    DbgTypeRegister(cat, elemRec, aux, off);
    DbgPutULEB(9);                 { array_type }
    DbgPutU32(elemOff);           { ref4 DW_AT_type }
    DbgPutULEB(10);               { subrange_type }
    if arrLen > 0 then DbgPutU16(arrLen - 1) else DbgPutU16(0);  { upper_bound }
    DbgPutB(0);                   { end children }
    DbgEnsureType := off; Exit;
  end;
  if isArr <> 0 then
  begin
    { dynamic array → pointer-cheat "array of <elem>" }
    cat := 3000; aux := elemTkOrd;
    off := DbgTypeLookup(cat, elemRec, aux);
    if off >= 0 then begin DbgEnsureType := off; Exit; end;
    off := DbgEmitNamedCheat('array of ' + DbgTypeDisplayName(elemTkOrd, elemRec));
    DbgTypeRegister(cat, elemRec, aux, off);
    DbgEnsureType := off; Exit;
  end;
  DbgEnsureType := DbgEnsureScalar(tkOrd, recId);
end;

{ The type offset for one DbgVar entry. }
function DbgVarTypeOff(vi: Integer): Integer;
var isArr: Integer;
begin
  isArr := 0; if DbgVarIsArray[vi] then isArr := 1;
  DbgVarTypeOff := DbgEnsureType(DbgVarTk[vi], DbgVarRec[vi], isArr,
                                 DbgVarArrLen[vi], DbgVarElemTk[vi], DbgVarElemRec[vi]);
end;

{ Pass 1 of .debug_info children: emit every type DIE referenced by a captured
  var, so the param/var DIEs that follow can ref4 backward. }
procedure DbgEmitTypeDIEs;
var i: Integer;
begin
  DbgTypeCount := 0;
  for i := 0 to DbgVarCount - 1 do DbgVarTypeOff(i);
end;

{ Emit a formal_parameter / variable DIE (location: globals = DW_OP_addr abs;
  locals/params = DW_OP_fbreg off, +DW_OP_deref for by-ref). }
procedure DbgEmitOneVar(vi: Integer);
var typeOff, lenPos: Integer;
begin
  typeOff := DbgVarTypeOff(vi);   { cached }
  if DbgVarIsParam[vi] then DbgPutULEB(3) else DbgPutULEB(4);
  DbgPutStrZ(DbgVarName[vi]);
  DbgPutU32(typeOff);             { ref4 DW_AT_type }
  { DW_AT_location, block1 }
  lenPos := DbgLen; DbgPutB(0);   { length placeholder }
  if DbgVarIsGlobal[vi] then
  begin
    DbgPutB($03);                 { DW_OP_addr }
    DbgPutAddr(DbgBssBase + DbgVarOff[vi]);
  end
  else
  begin
    DbgPutB($91);                 { DW_OP_fbreg }
    DbgPutSLEB(DbgVarOff[vi]);
    if DbgVarIsRef[vi] then DbgPutB($06);  { DW_OP_deref (by-ref param) }
  end;
  DbgPatchB(lenPos, DbgLen - (lenPos + 1));
end;

{ Pass 2: one DW_TAG_subprogram per main-file proc + the program body, each with
  its captured params/locals (globals hang under the main-body subprogram). }
procedure DbgEmitSubprograms(entry: Int64);
var p, i, lenPos: Integer;
begin
  for p := 0 to ProcCount - 1 do
  begin
    if ProcDbgMain[p] and (Procs[p].BodyAddr >= 0) and (not ProcExternal[p]) then
    begin
      DbgPutULEB(2);                              { subprogram }
      DbgPutStrZ(Procs[p].Name);
      DbgPutAddr(entry + Procs[p].BodyAddr);      { low_pc }
      DbgPutAddr(entry + ProcBodyEnd[p]);         { high_pc (absolute) }
      DbgPutB(1); DbgPutB($50 + DbgRegFrame);     { frame_base = DW_OP_reg<frame> }
      for i := 0 to DbgVarCount - 1 do
        if DbgVarProc[i] = p then DbgEmitOneVar(i);
      DbgPutB(0);                                 { end subprogram children }
    end;
  end;
  { Program body as a subprogram named after the program; its vars are globals. }
  if DbgMainBodyEnd > DbgMainBodyStart then
  begin
    DbgPutULEB(2);
    if DbgProgName <> '' then DbgPutStrZ(DbgProgName) else DbgPutStrZ('main');
    DbgPutAddr(entry + DbgMainBodyStart);
    DbgPutAddr(entry + DbgMainBodyEnd);
    DbgPutB(1); DbgPutB($50 + DbgRegFrame);
    DbgPutB(0);   { no children: program globals are CU-level (DbgEmitGlobals) }
  end;
end;

{ Program globals as CU-level variable DIEs (siblings of the subprograms), so gdb
  treats them as true globals visible from every frame — not locals of `main`. }
procedure DbgEmitGlobals;
var i: Integer;
begin
  for i := 0 to DbgVarCount - 1 do
    if DbgVarProc[i] = -1 then DbgEmitOneVar(i);
end;

{ Pad the in-progress .debug_frame entry with DW_CFA_nop to the next pointer-size
  boundary (relative to the section start), as CIE/FDE require. }
procedure DbgFramePad;
begin
  while ((DbgLen - DbgFrameSecOff) mod DbgPtrSize) <> 0 do DbgPutB(0);
end;

{ .debug_frame: one CIE (standard frame-pointer frame for the target) + one FDE
  per main-file proc, plus a program-body FDE with the return address marked
  undefined so the unwinder terminates cleanly (no junk outermost frame).
  Absolute addresses; all regs/offsets come from DbgSetArchParams. }
procedure DbgEmitFrame(entry: Int64);
var lenPos, p: Integer;
begin
  DbgFrameSecOff := DbgLen;
  { ---- CIE ---- }
  lenPos := DbgLen; DbgPutU32(0);
  DbgPutU32(-1);                 { CIE_id = 0xFFFFFFFF (.debug_frame) }
  DbgPutB(1);                    { version }
  DbgPutB(0);                    { augmentation = "" }
  DbgPutULEB(1);                 { code_alignment_factor }
  DbgPutSLEB(-DbgPtrSize);       { data_alignment_factor }
  DbgPutB(DbgRegRA);             { return_address_register }
  DbgPutB($0c); DbgPutULEB(DbgRegSP); DbgPutULEB(DbgPtrSize);  { def_cfa sp, ptr }
  DbgPutB($80 + DbgRegRA); DbgPutULEB(1);                       { offset RA at cfa-ptr }
  DbgFramePad;
  DbgPatchU32(lenPos, DbgLen - (lenPos + 4));

  { ---- one FDE per main-file proc (standard frame-pointer prologue) ---- }
  for p := 0 to ProcCount - 1 do
    if ProcDbgMain[p] and (Procs[p].BodyAddr >= 0) and (not ProcExternal[p]) then
    begin
      lenPos := DbgLen; DbgPutU32(0);
      DbgPutU32(0);                                   { CIE_pointer }
      DbgPutAddr(entry + Procs[p].BodyAddr);          { initial_location }
      DbgPutAddr(ProcBodyEnd[p] - Procs[p].BodyAddr); { address_range }
      DbgPutB($40 + DbgPrologAdv1);                   { advance_loc (frame-setup store) }
      DbgPutB($0e); DbgPutULEB(2 * DbgPtrSize);       { def_cfa_offset }
      DbgPutB($80 + DbgRegFrame); DbgPutULEB(2);      { offset frame-reg at cfa-2*ptr }
      if DbgFrameSavesLR then begin DbgPutB($80 + DbgRegLR); DbgPutULEB(1); end; { offset LR at cfa-ptr }
      DbgPutB($40 + DbgPrologAdv2);                   { advance_loc (mov fp,sp) }
      DbgPutB($0d); DbgPutULEB(DbgRegFrame);          { def_cfa_register frame-reg }
      DbgFramePad;
      DbgPatchU32(lenPos, DbgLen - (lenPos + 4));
    end;

  { ---- program body FDE: RA undefined → unwinder stops here ---- }
  if DbgMainBodyEnd > DbgMainBodyStart then
  begin
    lenPos := DbgLen; DbgPutU32(0);
    DbgPutU32(0);
    DbgPutAddr(entry + DbgMainBodyStart);
    DbgPutAddr(DbgMainBodyEnd - DbgMainBodyStart);
    DbgPutB($07); DbgPutULEB(DbgRegRA);             { DW_CFA_undefined RA }
    DbgFramePad;
    DbgPatchU32(lenPos, DbgLen - (lenPos + 4));
  end;
  DbgFrameSecSize := DbgLen - DbgFrameSecOff;
end;

{ Build all .debug_* section bytes into DbgBuf. entry = runtime VA of code start
  (LOAD_ADDR+codeOffset); codeBytes = CodeLen. DWARF version 3, DWARF32. }
procedure BuildDwarfSections(entry: Int64; codeBytes: Integer);
var i, lenPos, hdrPos, progStart, curLine, curAddr, dLine, dAddr: Integer;
    nm: AnsiString;
begin
  DbgSetArchParams;
  DbgLen := 0;
  nm := DbgSrcName;
  if nm = '' then nm := 'source.pas';

  { ---- .debug_line ---- }
  DbgLineSecOff := DbgLen;
  lenPos := DbgLen; DbgPutU32(0);   { unit_length — patched }
  DbgPutU16(3);                     { version = DWARF 3 }
  hdrPos := DbgLen; DbgPutU32(0);   { header_length — patched }
  DbgPutB(1);                       { minimum_instruction_length }
  DbgPutB(1);                       { default_is_stmt }
  DbgPutB(256 - 5);                 { line_base = -5 (as unsigned byte) }
  DbgPutB(14);                      { line_range }
  DbgPutB(13);                      { opcode_base }
  { standard_opcode_lengths for opcodes 1..12 }
  DbgPutB(0); DbgPutB(1); DbgPutB(1); DbgPutB(1); DbgPutB(1); DbgPutB(0);
  DbgPutB(0); DbgPutB(0); DbgPutB(1); DbgPutB(0); DbgPutB(0); DbgPutB(1);
  { include_directories: none → just the terminating NUL }
  DbgPutB(0);
  { file_names: one entry, then terminating NUL }
  DbgPutStrZ(nm); DbgPutULEB(0); DbgPutULEB(0); DbgPutULEB(0);
  DbgPutB(0);
  { header_length = distance from the byte after header_length to here }
  progStart := DbgLen;
  DbgPatchU32(hdrPos, progStart - (hdrPos + 4));

  { line number program }
  { DW_LNE_set_address(entry + first row addr) }
  if DwarfRowCount > 0 then curAddr := DwarfRowAddr[0] else curAddr := 0;
  DbgPutB(0); DbgPutULEB(1 + DbgPtrSize); DbgPutB(2); DbgPutAddr(entry + curAddr); { extended set_address }
  curLine := 1;
  for i := 0 to DwarfRowCount - 1 do
  begin
    dAddr := DwarfRowAddr[i] - curAddr;
    if dAddr <> 0 then
    begin
      DbgPutB(2); DbgPutULEB(dAddr);    { DW_LNS_advance_pc }
      curAddr := DwarfRowAddr[i];
    end;
    dLine := DwarfRowLine[i] - curLine;
    if dLine <> 0 then
    begin
      DbgPutB(3); DbgPutSLEB(dLine);    { DW_LNS_advance_line }
      curLine := DwarfRowLine[i];
    end;
    if DwarfRowPrologueEnd[i] then DbgPutB(10);  { DW_LNS_set_prologue_end }
    DbgPutB(1);                          { DW_LNS_copy → append row }
  end;
  { advance to end of code, then end_sequence }
  dAddr := codeBytes - curAddr;
  if dAddr > 0 then begin DbgPutB(2); DbgPutULEB(dAddr); end;
  DbgPutB(0); DbgPutULEB(1); DbgPutB(1); { DW_LNE_end_sequence }
  DbgLineSecSize := DbgLen - DbgLineSecOff;
  DbgPatchU32(lenPos, DbgLineSecSize - 4);

  { ---- .debug_abbrev ---- }
  DbgAbbrevSecOff := DbgLen;
  { abbrev 1: compile_unit (has children: the subprograms + type DIEs) }
  DbgPutULEB(1); DbgPutULEB($11); DbgPutB(1);   { DW_TAG_compile_unit, children=yes }
  DbgPutULEB($25); DbgPutULEB($08);  { DW_AT_producer, DW_FORM_string }
  DbgPutULEB($13); DbgPutULEB($0b);  { DW_AT_language, DW_FORM_data1 }
  DbgPutULEB($03); DbgPutULEB($08);  { DW_AT_name, DW_FORM_string }
  DbgPutULEB($1b); DbgPutULEB($08);  { DW_AT_comp_dir, DW_FORM_string }
  DbgPutULEB($11); DbgPutULEB($01);  { DW_AT_low_pc, DW_FORM_addr }
  DbgPutULEB($12); DbgPutULEB($01);  { DW_AT_high_pc, DW_FORM_addr }
  DbgPutULEB($10); DbgPutULEB($06);  { DW_AT_stmt_list, DW_FORM_data4 }
  DbgPutULEB(0); DbgPutULEB(0);
  { abbrev 2: subprogram (children: params + locals) }
  DbgPutULEB(2); DbgPutULEB($2e); DbgPutB(1);   { DW_TAG_subprogram, children=yes }
  DbgPutULEB($03); DbgPutULEB($08);  { DW_AT_name, DW_FORM_string }
  DbgPutULEB($11); DbgPutULEB($01);  { DW_AT_low_pc, DW_FORM_addr }
  DbgPutULEB($12); DbgPutULEB($01);  { DW_AT_high_pc, DW_FORM_addr }
  DbgPutULEB($40); DbgPutULEB($0a);  { DW_AT_frame_base, DW_FORM_block1 }
  DbgPutULEB(0); DbgPutULEB(0);
  { abbrev 3: formal_parameter }
  DbgPutULEB(3); DbgPutULEB($05); DbgPutB(0);   { DW_TAG_formal_parameter, no children }
  DbgPutULEB($03); DbgPutULEB($08);  { DW_AT_name, DW_FORM_string }
  DbgPutULEB($49); DbgPutULEB($13);  { DW_AT_type, DW_FORM_ref4 }
  DbgPutULEB($02); DbgPutULEB($0a);  { DW_AT_location, DW_FORM_block1 }
  DbgPutULEB(0); DbgPutULEB(0);
  { abbrev 4: variable }
  DbgPutULEB(4); DbgPutULEB($34); DbgPutB(0);   { DW_TAG_variable, no children }
  DbgPutULEB($03); DbgPutULEB($08);  { DW_AT_name, DW_FORM_string }
  DbgPutULEB($49); DbgPutULEB($13);  { DW_AT_type, DW_FORM_ref4 }
  DbgPutULEB($02); DbgPutULEB($0a);  { DW_AT_location, DW_FORM_block1 }
  DbgPutULEB(0); DbgPutULEB(0);
  { abbrev 5: base_type }
  DbgPutULEB(5); DbgPutULEB($24); DbgPutB(0);   { DW_TAG_base_type }
  DbgPutULEB($03); DbgPutULEB($08);  { DW_AT_name, DW_FORM_string }
  DbgPutULEB($3e); DbgPutULEB($0b);  { DW_AT_encoding, DW_FORM_data1 }
  DbgPutULEB($0b); DbgPutULEB($0b);  { DW_AT_byte_size, DW_FORM_data1 }
  DbgPutULEB(0); DbgPutULEB(0);
  { abbrev 6: pointer_type (the runtime-layout cheat: a named 8-byte pointer) }
  DbgPutULEB(6); DbgPutULEB($0f); DbgPutB(0);   { DW_TAG_pointer_type }
  DbgPutULEB($03); DbgPutULEB($08);  { DW_AT_name, DW_FORM_string }
  DbgPutULEB($0b); DbgPutULEB($0b);  { DW_AT_byte_size, DW_FORM_data1 }
  DbgPutULEB(0); DbgPutULEB(0);
  { abbrev 7: structure_type (record/class-by-value; members follow) }
  DbgPutULEB(7); DbgPutULEB($13); DbgPutB(1);   { DW_TAG_structure_type, children=yes }
  DbgPutULEB($03); DbgPutULEB($08);  { DW_AT_name, DW_FORM_string }
  DbgPutULEB($0b); DbgPutULEB($05);  { DW_AT_byte_size, DW_FORM_data2 }
  DbgPutULEB(0); DbgPutULEB(0);
  { abbrev 8: member }
  DbgPutULEB(8); DbgPutULEB($0d); DbgPutB(0);   { DW_TAG_member }
  DbgPutULEB($03); DbgPutULEB($08);  { DW_AT_name, DW_FORM_string }
  DbgPutULEB($49); DbgPutULEB($13);  { DW_AT_type, DW_FORM_ref4 }
  DbgPutULEB($38); DbgPutULEB($05);  { DW_AT_data_member_location, DW_FORM_data2 }
  DbgPutULEB(0); DbgPutULEB(0);
  { abbrev 9: array_type (fixed array; subrange child gives the count) }
  DbgPutULEB(9); DbgPutULEB($01); DbgPutB(1);   { DW_TAG_array_type, children=yes }
  DbgPutULEB($49); DbgPutULEB($13);  { DW_AT_type, DW_FORM_ref4 }
  DbgPutULEB(0); DbgPutULEB(0);
  { abbrev 10: subrange_type }
  DbgPutULEB(10); DbgPutULEB($21); DbgPutB(0);  { DW_TAG_subrange_type }
  DbgPutULEB($2f); DbgPutULEB($05);  { DW_AT_upper_bound, DW_FORM_data2 }
  DbgPutULEB(0); DbgPutULEB(0);
  { abbrev 11: typedef (gives the pointer-cheat a real Pascal type name) }
  DbgPutULEB(11); DbgPutULEB($16); DbgPutB(0);  { DW_TAG_typedef }
  DbgPutULEB($03); DbgPutULEB($08);  { DW_AT_name, DW_FORM_string }
  DbgPutULEB($49); DbgPutULEB($13);  { DW_AT_type, DW_FORM_ref4 }
  DbgPutULEB(0); DbgPutULEB(0);
  { abbrev 12: anonymous pointer_type (pointer to void — the cheat's base) }
  DbgPutULEB(12); DbgPutULEB($0f); DbgPutB(0);  { DW_TAG_pointer_type }
  DbgPutULEB($0b); DbgPutULEB($0b);  { DW_AT_byte_size, DW_FORM_data1 }
  DbgPutULEB(0); DbgPutULEB(0);
  DbgPutULEB(0);                     { end of abbrev table }
  DbgAbbrevSecSize := DbgLen - DbgAbbrevSecOff;

  { ---- .debug_info ---- }
  DbgInfoSecOff := DbgLen;
  lenPos := DbgLen; DbgPutU32(0);   { unit_length — patched }
  DbgPutU16(3);                     { version }
  DbgPutU32(0);                     { debug_abbrev_offset = 0 }
  DbgPutB(DbgPtrSize);              { address_size }
  DbgPutULEB(1);                    { DIE: abbrev code 1 (compile_unit) }
  DbgPutStrZ('frankonpiler');       { DW_AT_producer }
  DbgPutB($09);                     { DW_AT_language = DW_LANG_Pascal83 }
  DbgPutStrZ(nm);                   { DW_AT_name }
  DbgPutStrZ('.');                  { DW_AT_comp_dir }
  DbgPutAddr(entry);               { DW_AT_low_pc }
  DbgPutAddr(entry + codeBytes);   { DW_AT_high_pc }
  DbgPutU32(0);                     { DW_AT_stmt_list → .debug_line offset 0 }

  { Type DIEs first (so param/var ref4s resolve backward), then CU-level globals,
    then the subprograms with their locals as children. }
  DbgEmitTypeDIEs;
  DbgEmitGlobals;
  DbgEmitSubprograms(entry);

  DbgPutB(0);                       { end of compile_unit children }
  DbgInfoSecSize := DbgLen - DbgInfoSecOff;
  DbgPatchU32(lenPos, DbgInfoSecSize - 4);

  { ---- .debug_frame (CFI: robust unwinding + clean bt termination) ---- }
  DbgEmitFrame(entry);

  { ---- .shstrtab ---- }
  DbgShStrSecOff := DbgLen;
  DbgPutB(0);                       { index 0 = empty name }
  DbgNmText := DbgLen - DbgShStrSecOff;   DbgPutStrZ('.text');
  DbgNmData := DbgLen - DbgShStrSecOff;   DbgPutStrZ('.data');
  DbgNmBss := DbgLen - DbgShStrSecOff;    DbgPutStrZ('.bss');
  DbgNmLine := DbgLen - DbgShStrSecOff;   DbgPutStrZ('.debug_line');
  DbgNmInfo := DbgLen - DbgShStrSecOff;   DbgPutStrZ('.debug_info');
  DbgNmAbbrev := DbgLen - DbgShStrSecOff; DbgPutStrZ('.debug_abbrev');
  DbgNmFrame := DbgLen - DbgShStrSecOff;  DbgPutStrZ('.debug_frame');
  DbgNmShStr := DbgLen - DbgShStrSecOff;  DbgPutStrZ('.shstrtab');
  DbgShStrSecSize := DbgLen - DbgShStrSecOff;
end;

{$ifdef FPC}
procedure writeELF(const outPath: AnsiString);
var f: File; i: Integer;
    phCount, codeOffset, machine: Integer;
    dataBase, bssBase, entry, filesz, memsz, addr: Int64;
    doDebug: Boolean; dbgFileBase, shoff: Int64; padN: Integer;
    zb: Byte;
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
  entry    := LOAD_ADDR + codeOffset + AsmEntryOff;
  filesz   := codeOffset + CodeLen + DataLen;
  memsz    := filesz + BSSSize;

  doDebug := DebugInfo and ((TargetArch = TARGET_X86_64) or (TargetArch = TARGET_AARCH64));
  shoff := 0;
  if doDebug then
  begin
    DbgBssBase := bssBase;
    BuildDwarfSections(entry, CodeLen);
    dbgFileBase := filesz;
    shoff := dbgFileBase + DbgLen;
    padN := (8 - (shoff mod 8)) mod 8;
    shoff := shoff + padN;
  end;

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
  writeU64(f,entry);writeU64(f,64);writeU64(f,shoff);
  writeU32(f,0);writeU16(f,64);writeU16(f,56);
  if doDebug then
  begin
    writeU16(f,phCount);writeU16(f,64);writeU16(f,9);writeU16(f,8); { e_shnum=9, e_shstrndx=8 }
  end
  else
  begin
    writeU16(f,phCount);writeU16(f,64);writeU16(f,0);writeU16(f,0);
  end;

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
  if doDebug then
  begin
    if DbgLen > 0 then Blockwrite(f,DbgBuf[0],DbgLen);
    zb := 0;
    for i := 1 to padN do Blockwrite(f,zb,1);
    DbgWriteShdrTable(f, entry, dataBase, bssBase, codeOffset, dbgFileBase);
  end;
  Close(f);
  FpChmod(outPath,&755);
  WriteMapFile(outPath, codeOffset);
end;
{$else}
procedure writeELF(const outPath: AnsiString);
var f: Integer; i: Integer;
    phCount, codeOffset, machine: Integer;
    dataBase, bssBase, entry, filesz, memsz, addr: Int64;
    doDebug: Boolean; dbgFileBase, shoff: Int64; padN: Integer;
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
  entry    := LOAD_ADDR + codeOffset + AsmEntryOff;
  filesz   := codeOffset + CodeLen + DataLen;
  memsz    := filesz + BSSSize;

  { DWARF -g: Tier 1 is x86-64 only. Build the .debug_* bytes, then place a
    section-header table after them (the load image is unchanged — debug sections
    live past p_filesz, unmapped). }
  doDebug := DebugInfo and ((TargetArch = TARGET_X86_64) or (TargetArch = TARGET_AARCH64));
  shoff := 0;
  if doDebug then
  begin
    DbgBssBase := bssBase;
    BuildDwarfSections(entry, CodeLen);
    dbgFileBase := filesz;
    shoff := dbgFileBase + DbgLen;
    padN := (8 - (shoff mod 8)) mod 8;
    shoff := shoff + padN;
  end;

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
  writeU64(f,entry);writeU64(f,64);writeU64(f,shoff);
  writeU32(f,0);writeU16(f,64);writeU16(f,56);
  if doDebug then
  begin
    writeU16(f,phCount);writeU16(f,64);writeU16(f,9);writeU16(f,8); { e_shnum=9, e_shstrndx=8 }
  end
  else
  begin
    writeU16(f,phCount);writeU16(f,64);writeU16(f,0);writeU16(f,0);
  end;

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
  if doDebug then
  begin
    if DbgLen > 0 then syswrite(f,DbgBuf,DbgLen);
    for i := 1 to padN do writeU8(f,0);
    DbgWriteShdrTable(f, entry, dataBase, bssBase, codeOffset, dbgFileBase);
  end;
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
  loadBase, dataBase, bssBase, entry, filesz, memsz, addr: Int64;
  doDebug: Boolean; dbgFileBase, shoff32, padN: Integer;
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
    { @proc address fixups (ProcAddrFix) are 32-bit-absolute patched in place
      below and work for the bare ET_EXEC image on both riscv32 (auipc +
      inline literal) and xtensa (L32R inline literal) — each IR_PROCADDR
      emits a Patch32-friendly word. Method fixups remain unsupported. }
    { Method-address fixups (VMT slots in the data blob) use the generic
      PatchDataU64 loop below — 8-byte slots, 32-bit address in the low dword,
      same as i386/arm32. Nothing esp-specific remains. }
  end;

  phnum := 1;
  codeOffset := CODE_OFFSET32;
  if isDyn then
  begin
    PrepareDynamicData32;          { appends interp/dynstr/dynsym/hash/rel/dynamic }
    phnum := 3;
    codeOffset := DYNAMIC_CODE_OFFSET32;
  end;
  { Bare-metal ESP image loads into the SoC SRAM (one RWX region under qemu);
    everything else uses the classic i386 ET_EXEC base. }
  if EspBareBoot then
  begin
    if TargetArch = TARGET_XTENSA then loadBase := ESP_BARE_IRAM_BASE_XT
    else loadBase := ESP_BARE_IRAM_BASE;
  end
  else loadBase := LOAD_ADDR32;
  dataBase := loadBase + codeOffset + CodeLen;
  { BSS holds word-sized globals laid out with AlignTo offsets, so the base
    itself must be aligned — Xtensa s32i/l32i (and strict RV32 cores) trap on
    misaligned word access. Code+data lengths are byte-granular, so pad. }
  bssBase  := AlignTo(dataBase + DataLen, 8);
  { AsmEntryOff: .asm frontend `global <label>` entry override — always 0
    (inert) for every non-.asm compile, same contract as the x86-64 writers. }
  entry    := loadBase + codeOffset + AsmEntryOff;
  filesz   := codeOffset + CodeLen + DataLen;
  memsz    := (bssBase - loadBase) + BSSSize;

  { DWARF -g for the 32-bit hosted targets (i386/arm32). esp (bare/xtensa/riscv32)
    is excluded. Section headers placed past p_filesz, like the 64-bit path. }
  doDebug := DebugInfo and ((TargetArch = TARGET_I386) or (TargetArch = TARGET_ARM32))
             and (not EspBareBoot);
  shoff32 := 0;
  if doDebug then
  begin
    DbgBssBase := bssBase;
    BuildDwarfSections(entry, CodeLen);
    dbgFileBase := filesz;
    shoff32 := dbgFileBase + DbgLen;
    padN := (4 - (shoff32 mod 4)) mod 4;
    shoff32 := shoff32 + padN;
  end;

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
  writeU32(f,entry);writeU32(f,ELF32_HEADER_SIZE);writeU32(f,shoff32);
  if TargetArch = TARGET_ARM32 then writeU32(f,$05000000) else writeU32(f,0);
  writeU16(f,ELF32_HEADER_SIZE);writeU16(f,PROG32_HEADER_SIZE);
  if doDebug then
  begin
    writeU16(f,phnum);writeU16(f,40);writeU16(f,9);writeU16(f,8); { shentsize=40, shnum=9, shstrndx=8 }
  end
  else
  begin
    writeU16(f,phnum);writeU16(f,0);writeU16(f,0);writeU16(f,0);
  end;

  { phdr32 (32 bytes): PT_LOAD RWX, whole file at loadBase }
  writeU32(f,1);writeU32(f,0);                          { type, offset }
  writeU32(f,loadBase);writeU32(f,loadBase);
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
  if doDebug then
  begin
    if DbgLen > 0 then Blockwrite(f,DbgBuf[0],DbgLen);
    for i := 1 to padN do writeU8(f,0);
    DbgWriteShdrTable32(f, entry, dataBase, bssBase, codeOffset, dbgFileBase);
  end;
  Close(f);
  FpChmod(outPath,&755);
{$else}
  if CodeLen > 0 then syswrite(f,Code,CodeLen);
  if DataLen > 0 then syswrite(f,Data,DataLen);
  if doDebug then
  begin
    if DbgLen > 0 then syswrite(f,DbgBuf,DbgLen);
    for i := 1 to padN do writeU8(f,0);
    DbgWriteShdrTable32(f, entry, dataBase, bssBase, codeOffset, dbgFileBase);
  end;
  sysfchmod(f, 493); { chmod 755 }
  sysclose(f);
{$endif}
end;

function CodePosToIramOff(cp: Integer): Integer;
{ If cp falls inside an iram proc's body range, return its offset within
  .iram1.text; otherwise -1 (the position stays in flash .text). }
var i: Integer;
begin
  Result := -1;
  for i := 0 to ProcCount-1 do
    if ProcIram[i] and (Procs[i].BodyAddr >= 0) and
       (cp >= Procs[i].BodyAddr) and (cp < ProcBodyEnd[i]) then
    begin
      Result := ObjProcIramOff[i] + (cp - Procs[i].BodyAddr);
      Exit;
    end;
end;

procedure writeELF32RelIram(const outPath: AnsiString);
{ Extended ET_REL writer used when the program has `iram;` procedures: emits a
  second executable section `.iram1.text` (the IDF linker script routes it to
  internal IRAM). The byte image of each iram proc is duplicated out of the main
  Code[] buffer into .iram1.text (its dead twin stays in .text so flash
  PC-relative call offsets computed at emit time remain valid). Cross-section
  calls were emitted as indirect literal loads (IramCallFix) and are relocated
  here against the callee proc's own local symbol. Sections (11):
  0 null,1 .text,2 .rela.text,3 .iram1.text,4 .rela.iram1.text,5 .data,
  6 .rela.data,7 .bss,8 .symtab,9 .strtab,10 .shstrtab. }
var
  i, machine, iramSize, mapped: Integer;
  numProcSyms, numSyms, firstGlobal, symIdx: Integer;
  textOff, iramOff, dataOff, symOff, strOff: Integer;
  relaTextOff, relaIramOff, relaDataOff, shstrOff, shOff, strSize: Integer;
  relaTextCount, relaIramCount, relaDataCount, appMainOff: Integer;
{$ifdef FPC}
  f: File;
{$else}
  f: Integer;
{$endif}
begin
  if TargetArch = TARGET_XTENSA then machine := 94 else machine := 243;

  { Assign each iram proc a contiguous offset within .iram1.text. }
  iramSize := 0;
  for i := 0 to ProcCount-1 do
    if ProcIram[i] and (Procs[i].BodyAddr >= 0) and (not ProcExternal[i]) then
    begin
      ObjProcIramOff[i] := iramSize;
      iramSize := iramSize + (ProcBodyEnd[i] - Procs[i].BodyAddr);
    end;

  { .strtab: 0 empty, proc names, app_main, external names. Also assign each
    proc's .symtab index (section syms occupy 1..4). }
  strSize := 1;
  numProcSyms := 0;
  for i := 0 to ProcCount-1 do
    if (Procs[i].BodyAddr >= 0) and (not ProcExternal[i]) then
    begin
      ObjProcStrOff[i] := strSize;
      strSize := strSize + Length(Procs[i].Name) + 1;
      ObjProcSymIdx[i] := 5 + numProcSyms;
      Inc(numProcSyms);
    end
    else
      ObjProcStrOff[i] := -1;
  appMainOff := strSize;
  strSize := strSize + 9;
  for i := 0 to ExternalCount-1 do
  begin
    ObjExtStrOff[i] := strSize;
    strSize := strSize + Length(Procs[ExternalProc[i]].Name) + 1;
  end;

  firstGlobal := 5 + numProcSyms;        { null + 4 section syms + procs }
  numSyms := firstGlobal + 1 + ExternalCount;

  { Partition relocation counts by which text section their CodePos lands in. }
  relaTextCount := 0; relaIramCount := 0;
  for i := 0 to FixCount-1 do
    if CodePosToIramOff(Fixups[i].CodePos) >= 0 then Inc(relaIramCount) else Inc(relaTextCount);
  for i := 0 to GlobFixCount-1 do
    if CodePosToIramOff(GlobFix[i].CodePos) >= 0 then Inc(relaIramCount) else Inc(relaTextCount);
  for i := 0 to DynCallCount-1 do
    if CodePosToIramOff(DynCallCodePos[i]) >= 0 then Inc(relaIramCount) else Inc(relaTextCount);
  for i := 0 to IramCallFixCount-1 do
    if CodePosToIramOff(IramCallFix[i].CodePos) >= 0 then Inc(relaIramCount) else Inc(relaTextCount);
  { @proc: each IR_PROCADDR literal word gets an absolute (R_*_32) reloc against
    the target proc's symbol — the @isr address for esp_intr_alloc. }
  for i := 0 to ProcAddrFixCount-1 do
    if CodePosToIramOff(ProcAddrFix[i].CodePos) >= 0 then Inc(relaIramCount) else Inc(relaTextCount);
  relaDataCount := DataPtrFixCount + MethodFixCount;

  textOff := ELF32_HEADER_SIZE;
  iramOff := AlignTo(textOff + CodeLen, 4);
  dataOff := AlignTo(iramOff + iramSize, 8);
  symOff  := AlignTo(dataOff + DataLen, 4);
  strOff  := symOff + numSyms * 16;
  relaTextOff := AlignTo(strOff + strSize, 4);
  relaIramOff := relaTextOff + relaTextCount * 12;
  relaDataOff := relaIramOff + relaIramCount * 12;
  shstrOff := relaDataOff + relaDataCount * 12;
  shOff := AlignTo(shstrOff + 95, 4);    { 95 = .shstrtab blob size }

{$ifdef FPC}
  Assign(f, outPath); Rewrite(f, 1);
{$else}
  AssignPath := outPath;
  f := sysopen(AssignPath, 577);
{$endif}

  { ehdr (ET_REL), 11 sections, shstrndx 10 }
  writeU8(f,$7F);writeU8(f,$45);writeU8(f,$4C);writeU8(f,$46);
  writeU8(f,1);writeU8(f,1);writeU8(f,1);writeU8(f,0);
  writeU8(f,0);writeU8(f,0);writeU8(f,0);writeU8(f,0);
  writeU8(f,0);writeU8(f,0);writeU8(f,0);writeU8(f,0);
  writeU16(f,1);writeU16(f,machine);writeU32(f,1);
  writeU32(f,0);writeU32(f,0);writeU32(f,shOff);
  writeU32(f,0);
  writeU16(f,ELF32_HEADER_SIZE);writeU16(f,0);writeU16(f,0);
  writeU16(f,40);writeU16(f,11);writeU16(f,10);

  { .text = full Code[] (iram procs keep a dead twin here so flash PC-relative
    offsets stay valid); .iram1.text = the live copy of each iram proc body. }
{$ifdef FPC}
  if CodeLen > 0 then Blockwrite(f,Code[0],CodeLen);
  writePad(f, iramOff - (textOff + CodeLen));
  for i := 0 to ProcCount-1 do
    if ProcIram[i] and (Procs[i].BodyAddr >= 0) and (not ProcExternal[i]) then
      Blockwrite(f, Code[Procs[i].BodyAddr], ProcBodyEnd[i] - Procs[i].BodyAddr);
  writePad(f, dataOff - (iramOff + iramSize));
  if DataLen > 0 then Blockwrite(f,Data[0],DataLen);
{$else}
  if CodeLen > 0 then syswrite(f,Code,CodeLen);
  writePad(f, iramOff - (textOff + CodeLen));
  for i := 0 to ProcCount-1 do
    if ProcIram[i] and (Procs[i].BodyAddr >= 0) and (not ProcExternal[i]) then
      syswrite(f, Code[Procs[i].BodyAddr], ProcBodyEnd[i] - Procs[i].BodyAddr);
  writePad(f, dataOff - (iramOff + iramSize));
  if DataLen > 0 then syswrite(f,Data,DataLen);
{$endif}
  writePad(f, symOff - (dataOff + DataLen));

  { .symtab: null, 4 section syms (.text/.iram1.text/.data/.bss), procs, app_main, externals. }
  writeSym32(f, 0, 0, 0, 0, 0);
  writeSym32(f, 0, 0, 0, 3, 1);   { .text }
  writeSym32(f, 0, 0, 0, 3, 3);   { .iram1.text }
  writeSym32(f, 0, 0, 0, 3, 5);   { .data }
  writeSym32(f, 0, 0, 0, 3, 7);   { .bss }
  for i := 0 to ProcCount-1 do
    if ObjProcStrOff[i] >= 0 then
    begin
      if ProcIram[i] then
        writeSym32(f, ObjProcStrOff[i], ObjProcIramOff[i], 0, 2, 3)  { LOCAL FUNC in .iram1.text }
      else
        writeSym32(f, ObjProcStrOff[i], Procs[i].BodyAddr, 0, 2, 1); { LOCAL FUNC in .text }
    end;
  writeSym32(f, appMainOff, 0, 0, $12, 1);
  for i := 0 to ExternalCount-1 do
    writeSym32(f, ObjExtStrOff[i], 0, 0, $10, 0);

  { .strtab }
  writeU8(f, 0);
  for i := 0 to ProcCount-1 do
    if ObjProcStrOff[i] >= 0 then writeStrZ(f, Procs[i].Name);
  writeStrZ(f, 'app_main');
  for i := 0 to ExternalCount-1 do
    writeStrZ(f, Procs[ExternalProc[i]].Name);
  writePad(f, relaTextOff - (strOff + strSize));

  { .rela.text — only relocs whose CodePos stays in flash .text.
    Section syms: 3 = .data, 4 = .bss. }
  for i := 0 to FixCount-1 do
    if CodePosToIramOff(Fixups[i].CodePos) < 0 then
      writeRela32(f, Fixups[i].CodePos, 3, 1, Fixups[i].DataOff);
  for i := 0 to GlobFixCount-1 do
    if CodePosToIramOff(GlobFix[i].CodePos) < 0 then
      writeRela32(f, GlobFix[i].CodePos, 4, 1, GlobFix[i].BSSoff);
  for i := 0 to DynCallCount-1 do
    if CodePosToIramOff(DynCallCodePos[i]) < 0 then
      writeRela32(f, DynCallCodePos[i], firstGlobal + 1 + DynCallExtIdx[i], 1, 0);
  for i := 0 to IramCallFixCount-1 do
    if CodePosToIramOff(IramCallFix[i].CodePos) < 0 then
      writeRela32(f, IramCallFix[i].CodePos, ObjProcSymIdx[IramCallFix[i].ProcIdx], 1, 0);
  for i := 0 to ProcAddrFixCount-1 do
    if CodePosToIramOff(ProcAddrFix[i].CodePos) < 0 then
      writeRela32(f, ProcAddrFix[i].CodePos, ObjProcSymIdx[ProcAddrFix[i].ProcIdx], 1, 0);

  { .rela.iram1.text — relocs whose CodePos was duplicated into .iram1.text;
    offsets remapped to the section-local position. }
  for i := 0 to FixCount-1 do
  begin
    mapped := CodePosToIramOff(Fixups[i].CodePos);
    if mapped >= 0 then writeRela32(f, mapped, 3, 1, Fixups[i].DataOff);
  end;
  for i := 0 to GlobFixCount-1 do
  begin
    mapped := CodePosToIramOff(GlobFix[i].CodePos);
    if mapped >= 0 then writeRela32(f, mapped, 4, 1, GlobFix[i].BSSoff);
  end;
  for i := 0 to DynCallCount-1 do
  begin
    mapped := CodePosToIramOff(DynCallCodePos[i]);
    if mapped >= 0 then writeRela32(f, mapped, firstGlobal + 1 + DynCallExtIdx[i], 1, 0);
  end;
  for i := 0 to IramCallFixCount-1 do
  begin
    mapped := CodePosToIramOff(IramCallFix[i].CodePos);
    if mapped >= 0 then writeRela32(f, mapped, ObjProcSymIdx[IramCallFix[i].ProcIdx], 1, 0);
  end;
  for i := 0 to ProcAddrFixCount-1 do
  begin
    mapped := CodePosToIramOff(ProcAddrFix[i].CodePos);
    if mapped >= 0 then writeRela32(f, mapped, ObjProcSymIdx[ProcAddrFix[i].ProcIdx], 1, 0);
  end;

  { .rela.data (unchanged from the base writer; iram method targets use the
    .iram1.text section sym). }
  for i := 0 to DataPtrFixCount-1 do
    writeRela32(f, DataPtrFix[i].DataPos, 3, 1, DataPtrFix[i].TargetOff);
  for i := 0 to MethodFixCount-1 do
    if ProcIram[MethodFixups[i].ProcIdx] then
      writeRela32(f, MethodFixups[i].DataPos, 2, 1, ObjProcIramOff[MethodFixups[i].ProcIdx])
    else
      writeRela32(f, MethodFixups[i].DataPos, 1, 1, Procs[MethodFixups[i].ProcIdx].BodyAddr);

  { .shstrtab: 95-byte blob }
  writeU8(f, 0);
  writeStrZ(f, '.text');            { 1 }
  writeStrZ(f, '.rela.text');       { 7 }
  writeStrZ(f, '.iram1.text');      { 18 }
  writeStrZ(f, '.rela.iram1.text'); { 30 }
  writeStrZ(f, '.data');            { 47 }
  writeStrZ(f, '.rela.data');       { 53 }
  writeStrZ(f, '.bss');             { 64 }
  writeStrZ(f, '.symtab');          { 69 }
  writeStrZ(f, '.strtab');          { 77 }
  writeStrZ(f, '.shstrtab');        { 85 }
  writePad(f, shOff - (shstrOff + 95));

  { Section headers. $40 = SHF_INFO_LINK on rela sections. }
  writeShdrA(f, 0, 0, 0, 0, 0);                              writeShdrB(f, 0, 0, 0, 0);
  writeShdrA(f, 1, 1, 6, textOff, CodeLen);                  writeShdrB(f, 0, 0, 4, 0);
  writeShdrA(f, 7, 4, $40, relaTextOff, relaTextCount*12);   writeShdrB(f, 8, 1, 4, 12);
  writeShdrA(f, 18, 1, 6, iramOff, iramSize);                writeShdrB(f, 0, 0, 4, 0);
  writeShdrA(f, 30, 4, $40, relaIramOff, relaIramCount*12);  writeShdrB(f, 8, 3, 4, 12);
  writeShdrA(f, 47, 1, 3, dataOff, DataLen);                 writeShdrB(f, 0, 0, 8, 0);
  writeShdrA(f, 53, 4, $40, relaDataOff, relaDataCount*12);  writeShdrB(f, 8, 5, 4, 12);
  writeShdrA(f, 64, 8, 3, dataOff + DataLen, BSSSize);       writeShdrB(f, 0, 0, 8, 0);
  writeShdrA(f, 69, 2, 0, symOff, numSyms*16);               writeShdrB(f, 9, firstGlobal, 4, 16);
  writeShdrA(f, 77, 3, 0, strOff, strSize);                  writeShdrB(f, 0, 0, 1, 0);
  writeShdrA(f, 85, 3, 0, shstrOff, 95);                     writeShdrB(f, 0, 0, 1, 0);

{$ifdef FPC}
  Close(f);
{$else}
  sysfchmod(f, 420);
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
  { Programs with `iram;` procedures need the two-text-section writer, which also
    handles @proc (ProcAddrFix) relocs — dispatch BEFORE the guard below. }
  for i := 0 to ProcCount-1 do
    if ProcIram[i] and (Procs[i].BodyAddr >= 0) then
    begin
      writeELF32RelIram(outPath);
      Exit;
    end;
  { Non-iram .o: @proc relocs aren't wired here yet (the iram writer above is).
    An ISR/@isr program always has an iram proc, so it takes that path. }
  if ProcAddrFixCount > 0 then
    Error('--emit-obj: @proc fixups need an iram/interrupt routine present (non-iram .o path not wired)');
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

{ Relocatable ELF64 object writer for the .asm frontend's `-c`/--emit-obj
  mode (feature-asm-source-frontend task #5), x86-64 only. Everything the
  .asm frontend assembles -- code, the inline `section .data` bytes, even a
  data label's own bytes -- lives in ONE combined Code[]/CodeLen blob (see
  the comments in asmfront.inc's ParseAsmProgram): there is no separate data
  segment to emit, so this writer has just one content section, `.text`,
  covering the whole blob. `global <label>` symbols and `extern` UND symbols
  both index into that single section. Internal jmp/jcc/[rel] references are
  already fully resolved by ParseAsmProgram (Patch32) before this runs --
  the only relocations this object needs are `call <extern>` sites
  (AsmObjCallPos/AsmObjCallExtIdx), each an R_X86_64_PLT32 against the
  extern's UND symbol, exactly what `nasm -f elf64` + `extern foo` + `call
  foo` produces.
  File layout (written sequentially; the self-hosted writer cannot seek):
  ehdr, .text, .symtab, .strtab, .rela.text, .shstrtab, section headers. }
procedure writeELFRelX64(const outPath: AnsiString);
var
  i, machine: Integer;
  numSyms, firstGlobal, relaTextCount: Integer;
  textOff, symOff, strOff, relaTextOff, shstrOff, shOff, strSize: Integer;
{$ifdef FPC}
  f: File;
{$else}
  f: Integer;
{$endif}
begin
  if TargetArch <> TARGET_X86_64 then
    Error('--emit-obj: .asm frontend object output is x86-64 only');
  machine := 62;   { EM_X86_64 }

  { .strtab layout: 0 = empty, then global-label names, then extern names }
  strSize := 1;
  for i := 0 to AsmGlobalSymCount - 1 do
  begin
    AsmGlobalSymStrOff[i] := strSize;
    strSize := strSize + Length(AsmGlobalSymName[i]) + 1;
  end;
  for i := 0 to ExternalCount - 1 do
  begin
    ObjExtStrOff[i] := strSize;
    strSize := strSize + Length(Procs[ExternalProc[i]].Name) + 1;
  end;

  firstGlobal := 2;   { null sym + .text section sym }
  numSyms := firstGlobal + AsmGlobalSymCount + ExternalCount;
  relaTextCount := AsmObjCallCount;

  textOff := ELF_HEADER_SIZE;                       { 64, already 8-aligned }
  symOff  := AlignTo(textOff + CodeLen, 8);
  strOff  := symOff + numSyms * 24;
  relaTextOff := AlignTo(strOff + strSize, 8);
  shstrOff := relaTextOff + relaTextCount * 24;
  shOff := AlignTo(shstrOff + 44, 8);               { 44 = .shstrtab blob size }

{$ifdef FPC}
  Assign(f, outPath); Rewrite(f, 1);
{$else}
  AssignPath := outPath;
  f := sysopen(AssignPath, 577); { O_WRONLY | O_CREAT | O_TRUNC }
{$endif}

  { ELF64 ehdr (64 bytes), ET_REL }
  writeU8(f,$7F);writeU8(f,$45);writeU8(f,$4C);writeU8(f,$46);
  writeU8(f,2);writeU8(f,1);writeU8(f,1);writeU8(f,0);  { class 64, LE, v1 }
  writeU8(f,0);writeU8(f,0);writeU8(f,0);writeU8(f,0);
  writeU8(f,0);writeU8(f,0);writeU8(f,0);writeU8(f,0);
  writeU16(f,1);writeU16(f,machine);writeU32(f,1);      { ET_REL }
  writeU64(f,0);writeU64(f,0);writeU64(f,shOff);        { entry, phoff, shoff }
  writeU32(f,0);                                        { e_flags }
  writeU16(f,ELF_HEADER_SIZE);writeU16(f,0);writeU16(f,0);
  writeU16(f,64);writeU16(f,6);writeU16(f,5);   { shentsize, shnum=6, shstrndx=5 }

{$ifdef FPC}
  if CodeLen > 0 then Blockwrite(f,Code[0],CodeLen);
{$else}
  if CodeLen > 0 then syswrite(f,Code,CodeLen);
{$endif}
  writePad(f, symOff - (textOff + CodeLen));

  { .symtab; sh_info below = firstGlobal (locals first, per the ELF spec) }
  writeSym64(f, 0, 0, 0, 0, 0);
  writeSym64(f, 0, 3, 1, 0, 0);   { STT_SECTION .text }
  for i := 0 to AsmGlobalSymCount - 1 do
    writeSym64(f, AsmGlobalSymStrOff[i], $10, 1, AsmGlobalSymOff[i], 0); { GLOBAL NOTYPE, in .text }
  for i := 0 to ExternalCount - 1 do
    writeSym64(f, ObjExtStrOff[i], $10, 0, 0, 0);   { GLOBAL NOTYPE UNDEF }

  { .strtab }
  writeU8(f, 0);
  for i := 0 to AsmGlobalSymCount - 1 do writeStrZ(f, AsmGlobalSymName[i]);
  for i := 0 to ExternalCount - 1 do writeStrZ(f, Procs[ExternalProc[i]].Name);
  writePad(f, relaTextOff - (strOff + strSize));

  { .rela.text: one R_X86_64_PLT32 per `call <extern>` site. addend -4:
    the call encodes rel32 relative to the END of the 4-byte field (the
    next instruction), so S + A - P with A=-4 lands exactly there -- the
    same convention gas/nasm use for `call` to an undefined symbol. }
  for i := 0 to AsmObjCallCount - 1 do
    writeRela64(f, AsmObjCallPos[i], firstGlobal + AsmGlobalSymCount + AsmObjCallExtIdx[i], 4, -4);

  { .shstrtab: fixed 44-byte blob; name offsets hardcoded in the shdrs below }
  writeU8(f, 0);
  writeStrZ(f, '.text');        { 1 }
  writeStrZ(f, '.rela.text');   { 7 }
  writeStrZ(f, '.symtab');      { 18 }
  writeStrZ(f, '.strtab');      { 26 }
  writeStrZ(f, '.shstrtab');    { 34 }
  writePad(f, shOff - (shstrOff + 44));

  { shdrs: 0 null, 1 .text, 2 .rela.text, 3 .symtab, 4 .strtab, 5 .shstrtab.
    $40 = SHF_INFO_LINK on the rela section. }
  writeShdrA64(f, 0, 0, 0, 0, 0);
  writeShdrB64(f, 0, 0, 0, 0);
  writeShdrA64(f, 1, 1, 6, textOff, CodeLen);
  writeShdrB64(f, 0, 0, 16, 0);
  writeShdrA64(f, 7, 4, $40, relaTextOff, relaTextCount * 24);
  writeShdrB64(f, 3, 1, 8, 24);
  writeShdrA64(f, 18, 2, 0, symOff, numSyms * 24);
  writeShdrB64(f, 4, firstGlobal, 8, 24);
  writeShdrA64(f, 26, 3, 0, strOff, strSize);
  writeShdrB64(f, 0, 0, 1, 0);
  writeShdrA64(f, 34, 3, 0, shstrOff, 44);
  writeShdrB64(f, 0, 0, 1, 0);

{$ifdef FPC}
  Close(f);
{$else}
  sysfchmod(f, 420); { chmod 644 — a .o is not executable }
  sysclose(f);
{$endif}
end;

{ x86-64 ET_DYN shared-library writer for the .asm frontend's `--shared` mode
  (feature-asm-source-frontend task #6). No PIC codegen retrofit needed: the
  .asm frontend's own addressing is already position-independent by
  construction (labels/branches are rip-relative, `[base+disp]` is register-
  relative, immediates are immediates -- there is no absolute-address
  operand form in this frontend at all), and `call <extern>` in this mode
  uses a rip-relative GOT access (see the EmitSharedMode branch in
  ParseAsmProgram) whose displacement is fixed at assemble time regardless
  of where the .so eventually loads. So there are zero R_X86_64_RELATIVE
  relocations to emit for our own code/data -- the only relocations this .so
  needs are R_X86_64_GLOB_DAT entries filling each extern's GOT slot, which
  the dynamic linker processes via PT_DYNAMIC (the same mechanism
  PrepareDynamicData/PatchDynamicData already use for a linked ET_EXEC's
  dynamic imports).
  No section headers: the dynamic linker (and a real linker consuming this
  .so, e.g. `gcc -shared`/`ld -lfoo`) resolves everything through
  PT_DYNAMIC and its DT_SYMTAB/DT_STRTAB/DT_HASH -- section headers are
  supplementary, not required (the ET_EXEC writer already omits them too
  unless `-g`).
  Preferred load base = 0 (vaddr == file offset throughout): rip-relative
  code doesn't care what base the loader eventually picks, so there's no
  reason to reserve a nonzero preferred address.
  File layout (written sequentially; the self-hosted writer cannot seek):
  ehdr, 2 phdrs (PT_LOAD, PT_DYNAMIC), .text (Code[]), GOT (Data[]),
  .dynstr, .dynsym, .hash, .rela.dyn, dynamic entries. }
procedure writeELFSharedX64(const outPath: AnsiString);
var
  i, j, libIdx, dynCount, numDynSyms, neededCount: Integer;
  found: Boolean;
  textOff, dataOff, dynstrOff, dynsymOff, hashOff, relaDynOff, dynamicOff: Integer;
  dynstrSize, hashSize, dynamicSize, fileSize, phOff: Integer;
  strOffExport: array[0..MAX_ASM_GLOBALS-1] of Integer;
  strOffImport: array[0..MAX_EXTERNAL-1] of Integer;
  neededLibStr: array[0..MAX_EXTERNAL-1] of Integer;
  neededLibOff: array[0..MAX_EXTERNAL-1] of Integer;
{$ifdef FPC}
  f: File;
{$else}
  f: Integer;
{$endif}
begin
  if TargetArch <> TARGET_X86_64 then
    Error('--shared: .asm frontend shared-library output is x86-64 only');

  dynCount := AsmGlobalSymCount + ExternalCount;
  numDynSyms := dynCount + 1;   { + null symbol }

  { .dynstr: 0 = empty, then export names, then import (extern) names }
  dynstrSize := 1;
  for i := 0 to AsmGlobalSymCount - 1 do
  begin
    strOffExport[i] := dynstrSize;
    dynstrSize := dynstrSize + Length(AsmGlobalSymName[i]) + 1;
  end;
  for i := 0 to ExternalCount - 1 do
  begin
    strOffImport[i] := dynstrSize;
    dynstrSize := dynstrSize + Length(Procs[ExternalProc[i]].Name) + 1;
  end;

  { DT_NEEDED: one per distinct imported library (Strs[] index dedup, same
    as PrepareDynamicData). }
  neededCount := 0;
  for i := 0 to ExternalCount - 1 do
  begin
    libIdx := ProcLibrary[ExternalProc[i]];
    found := False;
    for j := 0 to neededCount - 1 do
      if neededLibStr[j] = libIdx then found := True;
    if not found then
    begin
      neededLibStr[neededCount] := libIdx;
      neededLibOff[neededCount] := dynstrSize;
      dynstrSize := dynstrSize + Length(Strs[libIdx].Text) + 1;
      Inc(neededCount);
    end;
  end;

  { .hash word count: nbucket + nchain (2) + bucket[0] (1) + chain[0..dynCount] (dynCount+1) = dynCount+4 words. }
  hashSize := (dynCount + 4) * 4;
  { DT_NEEDED*, DT_HASH, DT_STRTAB, DT_STRSZ, DT_SYMTAB, DT_SYMENT, DT_RELA,
    DT_RELASZ, DT_RELAENT, DT_NULL -- 9 fixed entries, Elf64_Dyn = 16 bytes. }
  dynamicSize := (neededCount + 9) * 16;

  phOff := ELF_HEADER_SIZE;
  textOff := phOff + 2 * PROG_HEADER_SIZE;
  dataOff := AlignTo(textOff + CodeLen, 8);
  dynstrOff := dataOff + DataLen;
  dynsymOff := AlignTo(dynstrOff + dynstrSize, 8);
  hashOff := dynsymOff + numDynSyms * 24;
  relaDynOff := AlignTo(hashOff + hashSize, 8);
  dynamicOff := relaDynOff + ExternalCount * 24;
  fileSize := dynamicOff + dynamicSize;

  { resolve each --shared extern call's rip-relative GOT displacement, now
    that dataOff (the GOT region's vaddr, base 0 == file offset) is known --
    same target-(patch_pos+4) formula every other rip-relative site in this
    compiler uses. AsmSoCallPos[i] is a Code[]-internal (0-based) offset,
    same as CodeLen always is; the *vaddr* of that patch site is textOff +
    AsmSoCallPos[i] (textOff = start of Code[] within the file/address
    space), which is what the CPU's actual rip-relative arithmetic runs
    from at runtime -- using the bare Code[]-relative position here (missing
    the +textOff) produced a displacement too large by exactly textOff.
    Must happen before Code[] is written out below. }
  for i := 0 to AsmSoCallCount - 1 do
    Patch32(AsmSoCallPos[i], (dataOff + ExternalGotOff[AsmSoCallExtIdx[i]]) - (textOff + AsmSoCallPos[i] + 4));

{$ifdef FPC}
  Assign(f, outPath); Rewrite(f, 1);
{$else}
  AssignPath := outPath;
  f := sysopen(AssignPath, 577); { O_WRONLY | O_CREAT | O_TRUNC }
{$endif}

  { ELF64 ehdr, ET_DYN, no section headers }
  writeU8(f,$7F);writeU8(f,$45);writeU8(f,$4C);writeU8(f,$46);
  writeU8(f,2);writeU8(f,1);writeU8(f,1);writeU8(f,0);  { class 64, LE, v1 }
  writeU8(f,0);writeU8(f,0);writeU8(f,0);writeU8(f,0);
  writeU8(f,0);writeU8(f,0);writeU8(f,0);writeU8(f,0);
  writeU16(f,3);writeU16(f,62);writeU32(f,1);           { ET_DYN, EM_X86_64 }
  writeU64(f,0);writeU64(f,phOff);writeU64(f,0);        { entry=0, phoff, shoff=0 }
  writeU32(f,0);                                        { e_flags }
  writeU16(f,ELF_HEADER_SIZE);writeU16(f,PROG_HEADER_SIZE);writeU16(f,2);
  writeU16(f,0);writeU16(f,0);writeU16(f,0);   { shentsize/shnum/shstrndx = 0 }

  { PT_LOAD: whole file, RWX (same single-segment simplification the ET_EXEC
    writer already uses). }
  writeU32(f,1);writeU32(f,7);
  writeU64(f,0);writeU64(f,0);writeU64(f,0);
  writeU64(f,fileSize);writeU64(f,fileSize);writeU64(f,$200000);

  { PT_DYNAMIC }
  writeU32(f,2);writeU32(f,6);
  writeU64(f,dynamicOff);writeU64(f,dynamicOff);writeU64(f,dynamicOff);
  writeU64(f,dynamicSize);writeU64(f,dynamicSize);writeU64(f,8);

{$ifdef FPC}
  if CodeLen > 0 then Blockwrite(f,Code[0],CodeLen);
{$else}
  if CodeLen > 0 then syswrite(f,Code,CodeLen);
{$endif}
  writePad(f, dataOff - (textOff + CodeLen));

{$ifdef FPC}
  if DataLen > 0 then Blockwrite(f,Data[0],DataLen);
{$else}
  if DataLen > 0 then syswrite(f,Data,DataLen);
{$endif}
  writePad(f, dynstrOff - (dataOff + DataLen));

  { .dynstr }
  writeU8(f, 0);
  for i := 0 to AsmGlobalSymCount - 1 do writeStrZ(f, AsmGlobalSymName[i]);
  for i := 0 to ExternalCount - 1 do writeStrZ(f, Procs[ExternalProc[i]].Name);
  for i := 0 to neededCount - 1 do writeStrZ(f, Strs[neededLibStr[i]].Text);
  writePad(f, dynsymOff - (dynstrOff + dynstrSize));

  { .dynsym: null, then export syms (defined -- st_value is a real virtual
    address here, base 0 so textOff+offset-into-Code[]; shndx=1 is a
    placeholder, there is no real section header table to match it against
    -- what matters for dynamic symbol resolution is shndx<>SHN_UNDEF and
    st_value), then import syms (UND). }
  writeSym64(f, 0, 0, 0, 0, 0);
  for i := 0 to AsmGlobalSymCount - 1 do
    writeSym64(f, strOffExport[i], $10, 1, textOff + AsmGlobalSymOff[i], 0);
  for i := 0 to ExternalCount - 1 do
    writeSym64(f, strOffImport[i], $10, 0, 0, 0);

  { .hash: SysV DT_HASH, single bucket (same naive-but-correct scheme
    PrepareDynamicData already uses for the ET_EXEC path). }
  writeU32(f, 1); writeU32(f, numDynSyms);
  if dynCount > 0 then writeU32(f, 1) else writeU32(f, 0);
  writeU32(f, 0);
  for i := 1 to dynCount do
  begin
    if i < dynCount then writeU32(f, i + 1) else writeU32(f, 0);
  end;
  writePad(f, relaDynOff - (hashOff + hashSize));

  { .rela.dyn: one R_X86_64_GLOB_DAT per extern, filling its GOT slot
    (already allocated by RegisterExternal in Data[]/ExternalGotOff) with
    the dynamic linker's resolved runtime address at load time. Import
    symbol index = 1 (null) + AsmGlobalSymCount (exports) + i. }
  for i := 0 to ExternalCount - 1 do
    writeRela64(f, dataOff + ExternalGotOff[i], 1 + AsmGlobalSymCount + i, 6, 0);

  { PT_DYNAMIC entries }
  for i := 0 to neededCount - 1 do
  begin
    writeU64(f, 1); writeU64(f, neededLibOff[i]);   { DT_NEEDED }
  end;
  writeU64(f, 4); writeU64(f, hashOff);              { DT_HASH }
  writeU64(f, 5); writeU64(f, dynstrOff);            { DT_STRTAB }
  writeU64(f, 10); writeU64(f, dynstrSize);          { DT_STRSZ }
  writeU64(f, 6); writeU64(f, dynsymOff);            { DT_SYMTAB }
  writeU64(f, 11); writeU64(f, 24);                  { DT_SYMENT }
  writeU64(f, 7); writeU64(f, relaDynOff);           { DT_RELA }
  writeU64(f, 8); writeU64(f, ExternalCount * 24);   { DT_RELASZ }
  writeU64(f, 9); writeU64(f, 24);                   { DT_RELAENT }
  writeU64(f, 0); writeU64(f, 0);                    { DT_NULL }

{$ifdef FPC}
  Close(f);
{$else}
  sysfchmod(f, 420); { chmod 644 — a .so is not executable }
  sysclose(f);
{$endif}
end;

{$ifndef FPC}
function sysgetdents64(fd: Integer; var buf; count: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(217, fd, Int64(@buf), count, 0, 0, 0));
end;
{$endif}

function ResolveCaseInsensitivePath(const path: AnsiString; var resolved: AnsiString): Boolean;
var dir, scanDir, want, entry, candidate: AnsiString;
    matches, fd, n, off, reclen: Integer;
{$ifdef FPC}
    sr: TSearchRec;
{$else}
    buf: array[0..4095] of Byte;
    b: Byte;
{$endif}
begin
  Result := False;
  resolved := path;
  dir := GetFilePath(path);
  want := '';
  if Length(path) = 0 then Exit;
  for off := Length(dir) + 1 to Length(path) do
    AppendChar(want, path[off]);
  if Length(want) = 0 then Exit;

  scanDir := dir;
  if Length(scanDir) = 0 then scanDir := '.';
  matches := 0;

{$ifdef FPC}
  if FindFirst(scanDir + '/*', faAnyFile, sr) = 0 then
  begin
    repeat
      if (sr.Name <> '.') and (sr.Name <> '..') and CaseEqual(sr.Name, want) then
      begin
        Inc(matches);
        if Length(dir) = 0 then
          candidate := sr.Name
        else
          ConcatThree(dir, sr.Name, '', candidate);
      end;
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
{$else}
  fd := sysopen(scanDir, 65536); { O_DIRECTORY }
  if fd < 0 then Exit;
  n := sysgetdents64(fd, buf, 4096);
  while n > 0 do
  begin
    off := 0;
    while off < n do
    begin
      reclen := Integer(buf[off + 16]) + Integer(buf[off + 17]) * 256;
      if reclen <= 0 then
        off := n
      else
      begin
        entry := '';
        b := buf[off + 19];
        while b <> 0 do
        begin
          AppendChar(entry, Chr(b));
          off := off + 1;
          b := buf[off + 19];
        end;
        off := off - Length(entry);
        if (entry <> '.') and (entry <> '..') and CaseEqual(entry, want) then
        begin
          Inc(matches);
          if Length(dir) = 0 then
            candidate := entry
          else
            ConcatThree(dir, entry, '', candidate);
        end;
        off := off + reclen;
      end;
    end;
    if matches > 1 then Break;
    n := sysgetdents64(fd, buf, 4096);
  end;
  sysclose(fd);
{$endif}

  if matches = 1 then
  begin
    resolved := candidate;
    Result := True;
  end;
end;

procedure LoadFile(const path: AnsiString; var dst: AnsiString);
var f, n, i: Integer;
begin
  { Staging buffer is the global LoadFileBuf (8 MB) — an 8 MB stack local here
    overflows a default 8 MB stack (FPC cold-bootstrap segfaulted in this
    prologue). Single-use, never re-entered, so a shared global is safe. }
  LoadPath := path;
  SetLength(dst, 0);
  f := sysopen(LoadPath, 0);
  if f >= 0 then
  begin
    n := sysread(f, LoadFileBuf, STRING_CAP);
    if n < 0 then n := 0;
    sysclose(f);
    SetLength(dst, n);
    for i := 0 to n - 1 do
      dst[i + 1] := Chr(LoadFileBuf[i]);
  end
  else
    SetLength(dst, 0);
end;

procedure LoadFileCI(const path: AnsiString; var dst: AnsiString);
var realPath: AnsiString;
begin
  LoadFile(path, dst);
  if Length(dst) = 0 then
  begin
    if ResolveCaseInsensitivePath(path, realPath) then
      LoadFile(realPath, dst);
  end;
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
  i, j, k, incDi, closePos, condCount, savedDefineCount, savedDefineCharLen: Integer;
  fname, command, name, exprSource: AnsiString;
  cond, active: Boolean;
  condParent, condActive, condTaken: array[0..MAX_PAS_CONDS-1] of Boolean;
  savedDefineActive: array[0..MAX_PAS_DEFINES-1] of Boolean;
  savedDefineHasValue: array[0..MAX_PAS_DEFINES-1] of Boolean;
  savedDefineValue: array[0..MAX_PAS_DEFINES-1] of Int64;
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
  begin
    savedDefineActive[k] := PasDefineActive[k];
    savedDefineHasValue[k] := PasDefineHasValue[k];
    savedDefineValue[k] := PasDefineValue[k];
  end;
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
          { Windows-style separators in include paths ({$I inc\foo.inc} —
            rtl-generics writes them) resolve on unix like FPC does:
            translate to '/'. }
{$ifdef FPC}
          if c = '\' then c := '/';
          if (c <> '''') and (c <> '"') and (c <> ' ') then AppendChar(fname, c);
{$else}
          if c = 92 then c := 47;
          if (c <> 39) and (c <> 34) and (c <> 32) then AppendChar(fname, Chr(c));
{$endif}
          Inc(j);
        end;
        if (Length(fname) = 1) and ((fname[1] = '+') or (fname[1] = '-')) or
           ((Length(fname) > 0) and (fname[1] = '%')) then
        begin
          { NOT an include: `{$I+}` / `{$I-}` IO-checking switches and
            `{$I %MACRO%}` compile-time info macros — leave them in the text
            for the lexer (the hard miss-error below must not fire on them). }
          AppendChar(IncExpanded, src[i]);
          Inc(i);
        end
        else if (Length(fname) > 0) and (j <= Length(src)) then
        begin
          if fname[1] = '/' then
            fullPath := fname
          else
          begin
            fullPath := baseDir;
            for k := 1 to Length(fname) do AppendChar(fullPath, fname[k]);
          end;
          NormalizePath(fullPath);
          LoadFileCI(fullPath, IncIncluded);
          { Search the -Fi include roots after the including file's dir
            (FPC order). A miss everywhere is a hard error — the old silent
            drop compiled with silently different configuration
            (bug-pascal-include-search-silent-miss). Empty content doubles as
            the miss signal, so a genuinely empty include file also errors;
            an empty include is a no-op, put a comment in it if one is real. }
          if (Length(IncIncluded) = 0) and (fname[1] <> '/') then
            for incDi := 0 to PasIncDirCount - 1 do
            begin
              fullPath := PasIncDirs[incDi];
              for k := 1 to Length(fname) do AppendChar(fullPath, fname[k]);
              NormalizePath(fullPath);
              LoadFileCI(fullPath, IncIncluded);
              if Length(IncIncluded) > 0 then Break;
            end;
          if Length(IncIncluded) = 0 then
          begin
            ErrorIdent := fname;
            Error('cannot open include file');
          end;
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
        if src[k] = #39 then
        begin
          { String literal: a "{$...}" inside it is text, not a directive (an
            unterminated literal ends at the newline, like the lexer). }
          Inc(k);
          while (k <= Length(src)) and (src[k] <> #39) and (src[k] <> #10) do Inc(k);
          if k <= Length(src) then Inc(k);   { the closing quote / the newline }
        end
        else if (src[k] = '/') and (k < Length(src)) and (src[k + 1] = '/') then
        begin
          { Line comment: inert to the end of the line. }
          while (k <= Length(src)) and (src[k] <> #10) do Inc(k);
        end
        else if (src[k] = '(') and (k < Length(src)) and (src[k + 1] = '*') then
        begin
          { Paren-star comment: EVERYTHING inside — including {$...} directives
            — is comment text, mirroring the lexer's paren-star scanner (same-type
            nesting per NestedComments; braces are delimiter-inert). Without
            this, commented-out directive examples were expanded: ZenGL's
            zgl_gltypeconst C-junk block and Synapse jedi.inc's doc comment
            killed every unit (bug-pascal-directive-inside-paren-star-comment). }
          j := 1;
          Inc(k, 2);
          while (k <= Length(src)) and (j > 0) do
          begin
            if (src[k] = '*') and (k < Length(src)) and (src[k + 1] = ')') then
            begin Dec(j); Inc(k, 2); end
            else if NestedComments and (src[k] = '(') and (k < Length(src)) and
                    (src[k + 1] = '*') then
            begin Inc(j); Inc(k, 2); end
            else
              Inc(k);
          end;
        end
        else if src[k] = '{' then
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
  begin
    PasDefineActive[k] := savedDefineActive[k];
    PasDefineHasValue[k] := savedDefineHasValue[k];
    PasDefineValue[k] := savedDefineValue[k];
  end;
  src := IncExpanded;
end;
