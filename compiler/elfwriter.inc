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
  if DataLen >= MAX_DATA then ErrorNoPos('data overflow');
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

{ AddDataPtrFix moved to emit.inc (2026-08-25) — next to the other relocation
  recorders, and included early enough that AddMethodFix, its sibling, is
  visible to the frontends that append VMT slots. }

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


{ The LINK symbol for external index `extIdx`: the `external name 'sym'` alias
  when the declaration carried one, else the Pascal identifier. EVERY writer
  that names an undefined symbol must go through here. The dynamic-import paths
  resolved the alias and the three --emit-obj writers did not, which is
  `bug-a-emit-obj-ignores-external-name`; sizing a string table and writing it
  are two separate callers of this, so they cannot drift apart either. }
function ExternalLinkName(extIdx: Integer): AnsiString;
begin
  if ProcExtName[ExternalProc[extIdx]] >= 0 then
    Result := Strs[ProcExtName[ExternalProc[extIdx]]].Text
  else
    Result := Procs[ExternalProc[extIdx]].Name;
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
    DataPutZ(ExternalLinkName(i));
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
    DataPutZ(ExternalLinkName(i));
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
procedure PatchDynCallSites(dataBase, codeVA: Int64);
{ codeVA is the virtual address of Code[0]. Only x86-64 needs it: its external
  call is `call qword ptr [rip+disp32]` through the GOT slot, so the field holds
  a distance rather than the slot's address. Every other target still patches
  the absolute VA. }
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
    else if TargetArch = TARGET_X86_64 then
      Patch32(DynCallCodePos[i], slotVA - (codeVA + DynCallCodePos[i] + 4))
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

{ Append a short line into the TokChars bounce buffer at pos (clamped to
  STRING_CAP). WriteMapFile used to build the whole map by AnsiString
  concatenation — one `mapContent := mapContent + line` per proc — which is a
  quadratic copy AND drove the allocator's large-block first-fit walk into
  O(n^2): on the 12000-proc token-growth stress test the map writer, not the
  compile, was most of the wall time (bug-a-token-growth-test-is-slow-and-
  times-out; sampled PCs sat in PXXStrConcat/PXXAlloc). Building straight into
  the fixed buffer is a single linear pass. }
procedure MapAppendLine(const s: AnsiString; var pos: Integer);
var k: Integer;
begin
  for k := 1 to Length(s) do
  begin
    if pos >= STRING_CAP then Exit;
    TokChars[pos] := s[k];
    pos := pos + 1;
  end;
end;

procedure WriteMapFile(const outPath: AnsiString; loadBase, codeOffset: Int64);
{ loadBase is a PARAMETER rather than LOAD_ADDR, because writeELF32 loads at
  LOAD_ADDR32 / ESP_LOAD_ADDR32 / the dynamic base, and a map keyed on the
  64-bit constant would be wrong at every line while looking right. }
var
  mapPath: AnsiString;
  f, i, len: Integer;
  addr: Int64;
begin
  mapPath := outPath + '.map';
  len := 0;
  MapAppendLine('# Frankonpiler Map File' + #10, len);
  MapAppendLine('# Executable: ' + outPath + #10, len);
  MapAppendLine('# Base Address: 0x' + IntToHexStr(loadBase, 8) + #10, len);
  MapAppendLine('# Code Offset: 0x' + IntToHexStr(codeOffset, 8) + #10 + #10, len);

  { Entry / _start }
  addr := loadBase + codeOffset;
  MapAppendLine('0x' + IntToHexStr(addr, 16) + ' _start' + #10, len);

  for i := 0 to ProcCount - 1 do
  begin
    if Procs[i].BodyAddr >= 0 then
    begin
      addr := loadBase + codeOffset + Procs[i].BodyAddr;
      MapAppendLine('0x' + IntToHexStr(addr, 16) + ' ' + Procs[i].Name + #10, len);
    end;
  end;

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
{ Elf32_Rel (8 bytes) -- no addend field: the addend lives IN the section bytes
  being relocated. That is not a style choice, it is the i386 psABI: gcc, clang
  and tcc all emit `.rel.text` for -m32, and the SHT_RELA form xtensa and
  riscv32 use is not what an i386 linker expects. So writeELFRel386General
  patches each addend into Code[]/Data[] before writing them.
  feature-a-object-output-for-i386-arm32-and-aarch64 }
procedure writeRel32(var f: File; offset, symIdx, rtype: Integer);
begin
  writeU32(f, offset); writeU32(f, (symIdx shl 8) or rtype);
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
{ Elf32_Rel (8 bytes) -- addend in the section bytes; see the FPC twin above. }
procedure writeRel32(f: Integer; offset, symIdx, rtype: Integer);
begin
  writeU32(f, offset); writeU32(f, (symIdx shl 8) or rtype);
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
  their own primitives. Tier 1 covers x86-64, aarch64, i386 and arm32 -- the set
  DbgArchSupported names below; esp xtensa/riscv32 are excluded (windowed /
  no-frame-pointer ABI, no gdb-over-qemu line path). Corrected 2026-08-30: read
  "x86-64 only for Tier 1". }

{ DbgBuf grows on demand, exactly as Code does through GrowCode -- same doubling,
  same "MAX_ is a ceiling, not an allocation" split. It was a fixed 1 MiB array,
  and the fixed size was not a safety property: `-g -O2` on compiler.pas simply
  exceeded it and died, so the compiler could not be built with debug info at any
  optimisation level above the default. Debug info scales with the program and
  with how much the optimiser has to say about it; a constant chosen once cannot
  track that.
  bug-a-g-with-o2-or-o3-overflows-the-dwarf-buffer-on-compiler-pas }
procedure GrowDbg;
var n: Integer;
begin
  { Name the numbers. The bare 'DWARF buffer overflow (-g)' this replaced said
    nothing about how much was wanted or what the limit was, so establishing that
    the old 1 MiB cap was being missed by 2,339 bytes -- not by an order of
    magnitude -- took a measurement pass instead of a read. }
  if DbgLen >= MAX_DWARF then
    ErrorNoPos('DWARF buffer overflow (-g): emitted ' + AIntToStr(DbgLen) +
          ' bytes of .debug_* content, ceiling MAX_DWARF is ' + AIntToStr(MAX_DWARF) +
          '. Debug info scales with program size; raise MAX_DWARF in defs.inc.');
  if DbgCapacity = 0 then n := 65536 else n := DbgCapacity * 2;
  if n > MAX_DWARF then n := MAX_DWARF;
  SetLength(DbgBuf, n + 16);
  DbgCapacity := n;
end;

procedure DbgPutB(v: Integer);
begin
  if DbgLen >= DbgCapacity then GrowDbg;
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

function DbgEnsureScalar(tkOrd, recId: Integer): Integer; forward;

{ Shared `^Char` DIE. A managed string HANDLE points straight at the character
  data and PXXStrFromLit NUL-terminates it (the length and refcount live BELOW
  the handle), so "pointer to char" is not a cheat here — it is the literal
  truth, and it is what makes gdb print

      $1 = 0x7fffe7e00018 "point"

  instead of the bare pointer a void* typedef produced. Strings are everywhere
  in this codebase, so this one DIE is most of the practical difference between
  a usable and an unusable `print`. }
function DbgEnsureCharPtr: Integer;
var off, chOff: Integer;
begin
  off := DbgTypeLookup(9001, 0, 0);
  if off >= 0 then begin DbgEnsureCharPtr := off; Exit; end;
  chOff := DbgEnsureScalar(3, 0);          { Char base_type }
  off := DbgLen - DbgInfoSecOff;
  DbgTypeRegister(9001, 0, 0, off);
  DbgPutULEB(13); DbgPutB(DbgPtrSize); DbgPutU32(chOff);   { pointer_type -> Char }
  DbgEnsureCharPtr := off;
end;

{ TRUE for the kinds whose runtime value is a managed-string handle. }
function DbgIsStringKind(tkOrd: Integer): Boolean;
begin
  DbgIsStringKind := (tkOrd = 4) or (tkOrd = 23) or (tkOrd = 25) or (tkOrd = 26);
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

  { A record is a structure_type by value; a CLASS variable holds a POINTER to
    the same structure, so it gets the identical body wrapped in a pointer DIE.
    Without the class case every object was a typedef over void*, and gdb
    answered `Type void is not a structure or union type` to `print n.name` —
    which is most of what you want a debugger for in a NilPy program. }
  if ((tkOrd = 5) or (tkOrd = 6)) and (recId >= REC_UCLASS_BASE) and
     ((recId - REC_UCLASS_BASE) < UClsCount)
     and not UClsIsInterface[recId - REC_UCLASS_BASE] then
  begin
    if tkOrd = 6 then
    begin
      { The pointer DIE is emitted and REGISTERED FIRST, with its target ref4
        left blank and patched once the body exists. A type graph may be
        CYCLIC — `TB = class;` forward, TA holding a TB, TB holding a TA, which
        is what the forward declaration exists to allow — and registering only
        after the body was walked meant the walk re-entered itself and ran the
        compiler's stack out. The pointer is where the cycle is legal, so it is
        where it must be cut. }
      off := DbgLen - DbgInfoSecOff;
      DbgTypeRegister(tkOrd, recId, 0, off);
      DbgPutULEB(13); DbgPutB(DbgPtrSize);
      i := DbgLen; DbgPutU32(0);                  { target ref4 — patched below }
      DbgPatchU32(i, DbgEnsureScalar(5, recId));
      DbgEnsureScalar := off; Exit;
    end;
    { Second cut, for a cycle that reaches a struct BODY while that same body is
      still being emitted (a by-value shape a pointer never breaks). The DIE
      cannot nest inside itself, so the inner reference degrades to the named
      void* cheat rather than recursing. }
    if DbgTypeLookup(9500, recId, 0) >= 0 then
    begin
      DbgEnsureScalar := DbgEmitNamedCheat(DbgTypeDisplayName(tkOrd, recId));
      Exit;
    end;
    DbgTypeRegister(9500, recId, 0, 0);
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

  { A VARIANT is a real two-word record {VType, Payload} — the layout pylib's
    TPyVarRec declares and every NilPy value rides in. As a void* typedef gdb
    printed the TAG as a pointer (`$1 = 0x6` for a variant holding a string),
    which is worse than useless: it looks like an address. Emitted as a
    structure_type it reads as {VType = 6, Payload = 0x7fff...}, and the tag
    tells you how to read the payload (see devdocs/dev/debug-heap.md and
    pylib's PyVarSlot* for the tag values). }
  if tkOrd = 22 then
  begin
    i := DbgEnsureScalar(13, 0);                 { Int64 members }
    off := DbgLen - DbgInfoSecOff;
    DbgTypeRegister(tkOrd, recId, 0, off);
    DbgPutULEB(7);                               { structure_type }
    DbgPutStrZ('Variant');
    DbgPutU16(2 * DbgPtrSize);
    DbgPutULEB(8); DbgPutStrZ('VType');   DbgPutU32(i); DbgPutU16(0);
    DbgPutULEB(8); DbgPutStrZ('Payload'); DbgPutU32(i); DbgPutU16(DbgPtrSize);
    DbgPutB(0);
    DbgEnsureScalar := off; Exit;
  end;

  { A managed string is a real ^Char (see DbgEnsureCharPtr), so it gets a
    typedef over THAT rather than over void* — gdb then prints the text. }
  if DbgIsStringKind(tkOrd) then
  begin
    i := DbgEnsureCharPtr;
    off := DbgLen - DbgInfoSecOff;
    DbgTypeRegister(tkOrd, recId, 0, off);
    DbgPutULEB(11); DbgPutStrZ(DbgTypeDisplayName(tkOrd, recId)); DbgPutU32(i);
    DbgEnsureScalar := off; Exit;
  end;

  { Everything else with runtime/heap layout → named typedef over a void pointer. }
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
    if SymOffIsData(DbgVarOff[vi]) then
      DbgPutAddr(DbgDataBase + SymOffDataPart(DbgVarOff[vi]))
    else
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
var i, lenPos, hdrPos, progStart, curLine, curAddr, dLine, dAddr, curFile: Integer;
    j, sortAddr, sortLine, sortFile: Integer;
    sortProl: Boolean;
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
  { file_names: the main file is entry 1, then every source registered with
    DbgMarkTokFile (imported `.py` modules, C headers). DWARF numbers these from 1, which
    is why DbgFileOfTok returns i+2 for registered range i. }
  DbgPutStrZ(nm); DbgPutULEB(0); DbgPutULEB(0); DbgPutULEB(0);
  for i := 0 to DbgFileCount - 1 do
  begin
    DbgPutStrZ(DbgFileName[i]); DbgPutULEB(0); DbgPutULEB(0); DbgPutULEB(0);
  end;
  DbgPutB(0);
  { header_length = distance from the byte after header_length to here }
  progStart := DbgLen;
  DbgPatchU32(hdrPos, progStart - (hdrPos + 4));

  { The rows arrive in EMISSION order, which is not address order: codegen places
    out-of-line chunks (and a proc's first-row backfill) away from the main flow,
    so ~104 rows in the compiler's own -g build sit below their predecessor.
    DW_LNS_advance_pc's operand is an UNSIGNED LEB128, so a negative delta was
    emitted as its 32-bit two's complement and the consumer's address register
    carried into bit 32 — permanently. 34% of the rows described addresses that
    do not exist, which is why `info line` on anything in the top fifth of the
    binary answered "no line number information" or named a wrong file.

    Sorting by address is what DWARF wants (a line program maps address -> line,
    so address order IS the correct order) and costs nothing here: the rows are
    already sorted apart from those inversions, and the deepest one displaces
    ~5 KB of code, so this insertion sort is linear in practice. It must be
    STABLE — several rows legitimately share an address, and the first of them
    is the one carrying prologue_end. Shifting rather than swapping gives that.
    See bug-a-dwarf-line-program-emits-backward-address-steps. }
  for i := 1 to DwarfRowCount - 1 do
    if DwarfRowAddr[i] < DwarfRowAddr[i - 1] then
    begin
      sortAddr := DwarfRowAddr[i];
      sortLine := DwarfRowLine[i];
      sortFile := DwarfRowFile[i];
      sortProl := DwarfRowPrologueEnd[i];
      j := i - 1;
      while (j >= 0) and (DwarfRowAddr[j] > sortAddr) do
      begin
        DwarfRowAddr[j + 1] := DwarfRowAddr[j];
        DwarfRowLine[j + 1] := DwarfRowLine[j];
        DwarfRowFile[j + 1] := DwarfRowFile[j];
        DwarfRowPrologueEnd[j + 1] := DwarfRowPrologueEnd[j];
        Dec(j);
      end;
      DwarfRowAddr[j + 1] := sortAddr;
      DwarfRowLine[j + 1] := sortLine;
      DwarfRowFile[j + 1] := sortFile;
      DwarfRowPrologueEnd[j + 1] := sortProl;
    end;

  { line number program }
  { DW_LNE_set_address(entry + first row addr) }
  if DwarfRowCount > 0 then curAddr := DwarfRowAddr[0] else curAddr := 0;
  DbgPutB(0); DbgPutULEB(1 + DbgPtrSize); DbgPutB(2); DbgPutAddr(entry + curAddr); { extended set_address }
  curLine := 1;
  curFile := 1;                          { the line program starts in file 1 }
  for i := 0 to DwarfRowCount - 1 do
  begin
    dAddr := DwarfRowAddr[i] - curAddr;
    if dAddr <> 0 then
    begin
      DbgPutB(2); DbgPutULEB(dAddr);    { DW_LNS_advance_pc }
      curAddr := DwarfRowAddr[i];
    end;
    { A row from another source: switch files before the line delta, since the
      line number is relative to whichever file is current. }
    if DwarfRowFile[i] <> curFile then
    begin
      curFile := DwarfRowFile[i];
      if curFile < 1 then curFile := 1;
      DbgPutB(4); DbgPutULEB(curFile);  { DW_LNS_set_file }
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
  { abbrev 13: TYPED pointer_type — the ^Char a managed string really is, so
    gdb prints the text rather than the handle (see DbgEnsureCharPtr) }
  DbgPutULEB(13); DbgPutULEB($0f); DbgPutB(0);  { DW_TAG_pointer_type }
  DbgPutULEB($0b); DbgPutULEB($0b);  { DW_AT_byte_size, DW_FORM_data1 }
  DbgPutULEB($49); DbgPutULEB($13);  { DW_AT_type, DW_FORM_ref4 }
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

{ ---- page-separate CODE from DATA ------------------------------------------
  Pad Code[] until the data section starts on a page of its own.

  THE PADDING GOES INTO Code[], NOT INTO dataBase, and that distinction is the
  whole correctness of this. There is ONE PT_LOAD with p_offset 0, so a virtual
  address IS `LOAD_ADDR + a file offset` — `dataBase := LOAD_ADDR + codeOffset +
  CodeLen`, and the data's file offset is `codeOffset + CodeLen`. Aligning
  dataBase on its own would desynchronise the two and every emitted data
  reference would read 0..4095 bytes early. That version would also pass the
  self-host fixedpoint, because a uniformly-wrong compiler reproduces itself
  perfectly — the gate proves reproduction, not correctness.

  Why it is worth up to 4 KiB per binary: with code and data adjacent, the
  boundary page holds both, and a hot write to a mutable word on that page makes
  a qemu-user-style emulator invalidate the translations it made from that page,
  on every store. Measured 83x on aarch64 and, for the SAME binary that runs in
  0.009s natively, 1600x on x86-64 under qemu-x86_64. The controls that make it
  a mechanism: removing the mutable word removes it, and so does moving the word
  off the shared page while keeping everything else.
  bug-a-a-hot-write-to-a-data-page-that-shares-with-code-costs-1600x-under-qemu

  Fixed HERE rather than in the pass that first put a mutable word beside code
  (a string literal's refcount, feature-opt-o3-static-string-literals), because
  the hazard belongs to the layout and not to that pass: it is any mutable word
  beside code, and the next one would be found the same expensive way.

  4096 IS WHAT THE MEASURED CASES NEED, NOT A PROOF. An emulator's granularity
  follows the target page size, and a host configured for 16 KiB pages would
  still leave a residual shared page. Stated rather than left for a reader to
  take "page-aligned" as "solved everywhere".

  The padding is APPENDED and never inserted: the out-of-line import thunk is
  placed just before this dispatch and its rel32 call sites are already patched
  against its position, so anything but a tail append moves every one of them.
  Appending at the tail is also the one growth that cannot arm the rel8
  truncation of bug-a-a-rel8-jump-patch-truncates-silently-when-its-span-grows,
  since it lengthens no span between a patch site and its target.

  Zero-filled and unreachable: the bytes sit past the last emitted instruction
  and nothing falls through to them, and zero is `udf #0` on aarch64 and faults
  on x86-64 — so a stray jump into the padding dies loudly instead of running.

  EMIT THE BYTES WITH EmitB. `Code` is a DYNAMIC array grown on demand by
  GrowCode, so `Code[CodeLen] := 0; Inc(CodeLen)` writes past CodeCapacity the
  moment the padding crosses it — out of bounds, into whatever heap block
  follows. The first version did exactly that and the symptom was nowhere near
  the cause: it landed in GlobFix, whose entries came back ZEROED, so the ELF
  writer then patched every 4-byte global reference with `bssBase + 0` at code
  offset 0 instead of at its own site. The binary died with SIGILL on its first
  instruction, with a fixup array that had been correct 200 lines earlier
  (measured: gf0.pos 1 before the loop, 0 after). MAX_CODE (32 MiB) is NOT the
  bound that matters here — CodeCapacity is, and it starts at 64 KiB. }
const
  ELF_DATA_PAGE = 4096;
  { aarch64 kernels ship with 4, 16 or 64 KiB pages; 64 KiB covers all three.
    See ElfSegAlign below for why the loader's page and not ours decides this. }
  ELF_AARCH64_PAGE = 65536;

{ THE DATA SECTION MUST BE WORD-ALIGNED, AND FOR YEARS IT ONLY WAS BY LUCK.

  Every executable writer here places data immediately after code --
  `dataBase := LOAD_ADDR + codeOffset + CodeLen` -- so the data section began
  wherever the last instruction happened to end. Code lengths are byte-granular,
  so that is an arbitrary residue: measured across a 129-source differential,
  EVERY program sampled started its data three bytes past a word boundary.

  x86-64 and riscv32 absorb an unaligned word load. Xtensa's l32i/s32i does not
  -- it raises an alignment fault, which surfaces under qemu as
  `uncaught target signal 7 (Bus error)`. So whether a given program died came
  down to whether it happened to dereference a word that landed misaligned: 41
  of 94 windowed-ABI programs did. The other 53 were never safe, only untested.

  The one line that has been holding this up since 75d2ba662 is
  PadCodeToPageBoundary below, which pads to 4096 and therefore to 8 as a side
  effect -- a constant introduced for an unrelated qemu translation-cache
  reason, in a writer under active edit, propping up a correctness property
  nothing asserts. Four routes take it away with no diagnostic: a second
  PT_LOAD, a 16 KiB-page host, `--emit-obj`, and any bare-metal ESP image
  (which skips the page pad outright and so has been misaligned all along).

  Hence this: an explicit, unconditional, stated invariant, and an Error rather
  than a silent miscompile if it is ever violated. Diagnosed by frankS,
  bug-a-a-perf-commit-silently-fixed-41-xtensa-windowed-divergences-and-nobody-knows-why.

  8 and not 4: the same width bssBase has always used two lines below, for the
  same reason plus aarch64's 64-bit exclusives, and a typed constant can be a
  qword. There is no target on which 4 is enough and 8 is too much. }
const
  ELF_DATA_ALIGN = 8;

procedure AlignCodeForData(codeOffset: Int64);
begin
  { Record where filler starts so `-S` can stop there -- see CodePadStart in
    defs.inc. First padder wins: this runs before the page pad, so the listing
    stops at the first byte that is not an instruction, not at the last. }
  if CodePadStart < 0 then CodePadStart := CodeLen;
  while ((codeOffset + CodeLen) mod ELF_DATA_ALIGN) <> 0 do
    EmitB(0);   { EmitB, never `Code[CodeLen] := 0` -- see the note below }
end;

{ The invariant checked where it is USED, not where it is established -- the
  loop above cannot fail, but a writer that computes dataBase without calling
  AlignCodeForData can, and so can a load base that is not itself aligned
  (SocIramBase is a per-chip constant, not something this file controls). An
  Error here is a build that stops; the alternative is a program that faults on
  xtensa and runs everywhere else. }
procedure CheckDataBaseAligned(dataBase: Int64);
begin
  if (dataBase mod ELF_DATA_ALIGN) <> 0 then
    ErrorNoPos('internal: data section base is not 8-byte aligned -- xtensa l32i '
          + 'will fault on it');
end;

{ THE PAD IS NOW A SEGMENT BOUNDARY, AND ITS SIZE IS THE LOADER'S PAGE, NOT OURS.

  With code and data in separate PT_LOADs the loader maps each one from
  PAGE_START(p_vaddr) at the HARDWARE page size, whatever that is -- p_align is
  a congruence requirement, not a promise about granularity. If the boundary
  between the two segments is not aligned to the loader's page, the data
  segment's mapping starts BELOW the end of the code segment and re-maps that
  overlap R+W. The content stays correct (our p_vaddr = LOAD_ADDR + p_offset
  identity guarantees the same file bytes land at the same addresses either
  way); the PERMISSIONS do not. Real code in the overlap becomes
  non-executable and the program dies on its first call into it.

  4096 is right for x86-64, i386, arm32, riscv32 and hosted xtensa: their Linux
  base page is 4 KiB. It is NOT right for aarch64, whose kernel may be built
  for 4, 16 or 64 KiB -- so aarch64 gets 65536, which is exactly why GNU ld
  defaults `max-page-size` to 0x10000 on that architecture. The cost is up to
  64 KiB of zero padding in an aarch64 image and it buys the property that the
  image is correct on a kernel we have never run it on.

  This is the same lesson as AlignCodeForData above, one level up: the data
  section was word-aligned for years by a coincidence nobody tested, and 41
  xtensa programs were the bill. Sizing this pad to the page size we happen to
  test on would be the identical mistake with a bigger blast radius, because a
  wrong answer here is a SIGSEGV on the first instruction of the overlap rather
  than on one unlucky load. }
function ElfSegAlign: Int64;
begin
  if TargetArch = TARGET_AARCH64 then
    ElfSegAlign := ELF_AARCH64_PAGE
  else
    ElfSegAlign := ELF_DATA_PAGE;
end;

procedure PadCodeToPageBoundary(codeOffset: Int64);
var segAlign: Int64;
begin
  if CodePadStart < 0 then CodePadStart := CodeLen;
  segAlign := ElfSegAlign;
  while ((codeOffset + CodeLen) mod segAlign) <> 0 do
    EmitB(0);   { EmitB, never `Code[CodeLen] := 0` -- see the note above }
end;

procedure ApplyImageFixups(codeVA, dataBase, bssBase, entry: Int64);
{ Resolve every code and data fixup against the addresses an IMAGE will have.
  One copy, because there were two and they had already drifted: writeELF is
  written twice ({$ifdef FPC} / self-hosted, for the file handle type alone)
  and the two patch passes differed only in the COMMENT above the @proc loop --
  which is the half that goes stale silently. Both said `mov rax, imm64` after
  x86-64 started emitting a lea.

  Every rip-relative field here is a DISPLACEMENT measured from the address
  after it, so each needs codeVA -- the virtual address of Code[0]. `entry` is
  separate and is NOT the same number: it carries AsmEntryOff.

  Callers pass absolute VAs for an ET_EXEC and base-relative ones (codeVA =
  file offset, load base 0) for an ET_DYN, where the loader adds the base. }
var
  i: Integer;
  addr: Int64;
begin
  { Apply data fixups (8-byte absolute) }
  for i := 0 to FixCount-1 do
  begin
    addr := dataBase + Fixups[i].DataOff;
    { A rewritten `movabs r64, imm64` is now `lea r64, [rip+disp32]`: four
      bytes measured from the end of the instruction, not eight absolute. }
    if FixupPCRel[i] then
      Patch32(Fixups[i].CodePos,
              addr - (codeVA + Fixups[i].CodePos + 4))
    else
      PatchAddr8(Fixups[i].CodePos, addr);
  end;

  { Apply global fixups (4-byte absolute) }
  for i := 0 to GlobFixCount-1 do
  begin
    { A data-resident global (a typed const array baked into .data) carries a
      BIASED offset -- the one decode point for all of them, because every
      backend reaches a global through the same EmitGlobRef. See DATA_SYM_BIAS. }
    if SymOffIsData(GlobFix[i].BSSoff) then
      addr := dataBase + SymOffDataPart(GlobFix[i].BSSoff)
    else
      addr := bssBase + GlobFix[i].BSSoff;
    { PCRel: EmitGlobRef rewrote the operand to [rip+disp32], so the field holds
      the distance from the address AFTER it (rip at execution) to the target,
      not the target. }
    if GlobFixPCRel[i] then
      Patch32(GlobFix[i].CodePos,
              addr - (codeVA + GlobFix[i].CodePos + 4
                      + GlobFixTrail[i]))
    else
      Patch32(GlobFix[i].CodePos, addr);
  end;
  if ExternalCount > 0 then
  begin
    PatchDynCallSites(dataBase, codeVA);
    PatchDynamicData(dataBase);
  end;

  for i := 0 to MethodFixCount-1 do
  begin
    addr := entry + Procs[MethodFixups[i].ProcIdx].BodyAddr;
    PatchDataU64(MethodFixups[i].DataPos, addr);
  end;

  { @proc: the routine's own code address -- `lea rax,[rip+disp32]` on x86-64,
    an 8-byte absolute literal elsewhere. }
  for i := 0 to ProcAddrFixCount-1 do
  begin
    { A routine with NO BODY has BodyAddr = -1, and `entry + (-1)` is a
      perfectly plausible-looking address one byte below the entry point. The
      program then jumps there the first time the value is called — a crash
      with no diagnostic, arbitrarily far from the cause (songformatter reached
      it through a Tk callback registered 500 widgets earlier). Say so at LINK
      time instead. }
    if Procs[ProcAddrFix[i].ProcIdx].BodyAddr < 0 then
      ErrorNoPos('@' + Procs[ProcAddrFix[i].ProcIdx].Name +
            ': the address of a routine with no body was taken');
    addr := entry + Procs[ProcAddrFix[i].ProcIdx].BodyAddr;
    { x86-64 emits `lea rax, [rip+disp32]`, so the field is the distance from
      the address AFTER it, four bytes wide. aarch64/arm32/xtensa store an
      8-byte absolute literal and keep PatchAddr8. }
    if TargetArch = TARGET_X86_64 then
      Patch32(ProcAddrFix[i].CodePos,
              addr - (codeVA + ProcAddrFix[i].CodePos + 4))
    else
      PatchAddr8(ProcAddrFix[i].CodePos, addr);
  end;

  for i := 0 to DataPtrFixCount-1 do
    PatchDataU64(DataPtrFix[i].DataPos, dataBase + DataPtrFix[i].TargetOff);
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
  phCount := 3;   { PT_LOAD code + PT_LOAD data + PT_GNU_STACK }
  codeOffset := CODE_OFFSET;
  if ExternalCount > 0 then
  begin
    PrepareDynamicData;
    phCount := 5;   { + PT_INTERP + PT_DYNAMIC }
    codeOffset := DYNAMIC_CODE_OFFSET;
  end;
  { Code starts immediately after the program headers, so the constant and the
    header count are one fact spelled twice and drift silently: the image still
    loads, every address it reports is off by 56, and nothing fails. Checked
    here because this file keeps two parallel copies of this writer. }
  if codeOffset <> ELF_HEADER_SIZE + phCount * PROG_HEADER_SIZE then
    ErrorNoPos('internal: CODE_OFFSET disagrees with the program-header count');
  AlignCodeForData(codeOffset);   { the invariant; the page pad below only implies it }
  PadCodeToPageBoundary(codeOffset);
  dataBase := LOAD_ADDR + codeOffset + CodeLen;
  CheckDataBaseAligned(dataBase);
  { bssBase must be 8-aligned: aarch64 64-bit exclusives (ldaxr/stlxr in the
    --threadsafe I/O + atomic stubs) SIGBUS on a 4-aligned qword. CodeLen varies
    per program, so an unaligned dataBase+DataLen would randomly misalign BSS. }
  bssBase  := AlignTo(dataBase + DataLen, 8);
  entry    := LOAD_ADDR + codeOffset + AsmEntryOff;
  filesz   := codeOffset + CodeLen + DataLen;
  memsz    := (bssBase - LOAD_ADDR) + BSSSize;

  { DbgArchSupported, not a fourth copy of the target list. This line said
    "x86_64 or aarch64" in BOTH writeELF variants and "i386 or arm32" in
    writeELF32, so the DWARF Tier-1 set was written down three times as live
    code while the one function that states it correctly had ZERO call sites.
    Anyone who grepped DbgArchSupported found the right answer and reasonably
    concluded it was enforced; it was not.
    bug-a-the-dwarf-target-set-is-written-down-three-times-and-the-authority-is-dead-code }
  doDebug := DebugInfo and DbgArchSupported;
  shoff := 0;
  if doDebug then
  begin
    DbgBssBase := bssBase;
    DbgDataBase := dataBase;   { a data-resident global's DWARF location — DATA_SYM_BIAS }
    BuildDwarfSections(entry, CodeLen);
    dbgFileBase := filesz;
    shoff := dbgFileBase + DbgLen;
    padN := (8 - (shoff mod 8)) mod 8;
    shoff := shoff + padN;
  end;

  ApplyImageFixups(LOAD_ADDR + codeOffset, dataBase, bssBase, entry);

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

  { PT_LOAD #1 -- headers + code, R+X. p_filesz = p_memsz: nothing in this
    segment is zero-filled at load, the page pad is real bytes in the file. }
  writeU32(f,1);writeU32(f,5);  { PT_LOAD, R+X }
  writeU64(f,0);writeU64(f,LOAD_ADDR);writeU64(f,LOAD_ADDR);
  writeU64(f,codeOffset + CodeLen);writeU64(f,codeOffset + CodeLen);
  writeU64(f,ElfSegAlign);
  { PT_LOAD #2 -- data + bss, R+W and NO X. p_memsz runs to the end of bss,
    which the kernel zero-fills past p_filesz. bssBase is dataBase + DataLen
    rounded up to 8, so the gap is inside this segment and is zeroed too. }
  writeU32(f,1);writeU32(f,6);  { PT_LOAD, R+W }
  writeU64(f,codeOffset + CodeLen);writeU64(f,dataBase);writeU64(f,dataBase);
  writeU64(f,DataLen);writeU64(f,(bssBase - dataBase) + BSSSize);
  writeU64(f,ElfSegAlign);
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
  writeU32(f,$6474E551);writeU32(f,6); { PT_GNU_STACK, RW (no X): no executable
    stack request, else newer kernels refuse to load the image entirely
    (bug-elf-missing-pt-gnu-stack) }
  writeU64(f,0);writeU64(f,0);writeU64(f,0);
  writeU64(f,0);writeU64(f,0);writeU64(f,$10);

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
  if EmitMapFile then WriteMapFile(outPath, LOAD_ADDR, codeOffset);
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
  phCount := 3;   { PT_LOAD code + PT_LOAD data + PT_GNU_STACK }
  codeOffset := CODE_OFFSET;
  if ExternalCount > 0 then
  begin
    PrepareDynamicData;
    phCount := 5;   { + PT_INTERP + PT_DYNAMIC }
    codeOffset := DYNAMIC_CODE_OFFSET;
  end;
  { Code starts immediately after the program headers, so the constant and the
    header count are one fact spelled twice and drift silently: the image still
    loads, every address it reports is off by 56, and nothing fails. Checked
    here because this file keeps two parallel copies of this writer. }
  if codeOffset <> ELF_HEADER_SIZE + phCount * PROG_HEADER_SIZE then
    ErrorNoPos('internal: CODE_OFFSET disagrees with the program-header count');
  AlignCodeForData(codeOffset);   { the invariant; the page pad below only implies it }
  PadCodeToPageBoundary(codeOffset);
  dataBase := LOAD_ADDR + codeOffset + CodeLen;
  CheckDataBaseAligned(dataBase);
  { bssBase must be 8-aligned: aarch64 64-bit exclusives (ldaxr/stlxr in the
    --threadsafe I/O + atomic stubs) SIGBUS on a 4-aligned qword. CodeLen varies
    per program, so an unaligned dataBase+DataLen would randomly misalign BSS. }
  bssBase  := AlignTo(dataBase + DataLen, 8);
  entry    := LOAD_ADDR + codeOffset + AsmEntryOff;
  filesz   := codeOffset + CodeLen + DataLen;
  memsz    := (bssBase - LOAD_ADDR) + BSSSize;

  { DWARF -g. Build the .debug_* bytes, then place a section-header table after
    them (the load image is unchanged — debug sections live past p_filesz,
    unmapped).

    Corrected 2026-08-30: this said "Tier 1 is x86-64 only", ONE LINE above a
    condition that also tests aarch64, and Tier 1 in fact covers FOUR targets --
    the 32-bit writer below (~line 1895) gates i386 and arm32 the same way.
    Measured, not read: `-g` on all four emits 4 .debug sections. Reading only
    the condition under this comment gives the answer "two", which is what makes
    this worth a note rather than a silent edit. }
  { DbgArchSupported, not a fourth copy of the target list. This line said
    "x86_64 or aarch64" in BOTH writeELF variants and "i386 or arm32" in
    writeELF32, so the DWARF Tier-1 set was written down three times as live
    code while the one function that states it correctly had ZERO call sites.
    Anyone who grepped DbgArchSupported found the right answer and reasonably
    concluded it was enforced; it was not.
    bug-a-the-dwarf-target-set-is-written-down-three-times-and-the-authority-is-dead-code }
  doDebug := DebugInfo and DbgArchSupported;
  shoff := 0;
  if doDebug then
  begin
    DbgBssBase := bssBase;
    DbgDataBase := dataBase;   { a data-resident global's DWARF location — DATA_SYM_BIAS }
    BuildDwarfSections(entry, CodeLen);
    dbgFileBase := filesz;
    shoff := dbgFileBase + DbgLen;
    padN := (8 - (shoff mod 8)) mod 8;
    shoff := shoff + padN;
  end;

  ApplyImageFixups(LOAD_ADDR + codeOffset, dataBase, bssBase, entry);

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

  { PT_LOAD #1 -- headers + code, R+X. p_filesz = p_memsz: nothing in this
    segment is zero-filled at load, the page pad is real bytes in the file. }
  writeU32(f,1);writeU32(f,5);  { PT_LOAD, R+X }
  writeU64(f,0);writeU64(f,LOAD_ADDR);writeU64(f,LOAD_ADDR);
  writeU64(f,codeOffset + CodeLen);writeU64(f,codeOffset + CodeLen);
  writeU64(f,ElfSegAlign);
  { PT_LOAD #2 -- data + bss, R+W and NO X. p_memsz runs to the end of bss,
    which the kernel zero-fills past p_filesz. bssBase is dataBase + DataLen
    rounded up to 8, so the gap is inside this segment and is zeroed too. }
  writeU32(f,1);writeU32(f,6);  { PT_LOAD, R+W }
  writeU64(f,codeOffset + CodeLen);writeU64(f,dataBase);writeU64(f,dataBase);
  writeU64(f,DataLen);writeU64(f,(bssBase - dataBase) + BSSSize);
  writeU64(f,ElfSegAlign);
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
  writeU32(f,$6474E551);writeU32(f,6); { PT_GNU_STACK, RW (no X): no executable
    stack request, else newer kernels refuse to load the image entirely
    (bug-elf-missing-pt-gnu-stack) }
  writeU64(f,0);writeU64(f,0);writeU64(f,0);
  writeU64(f,0);writeU64(f,0);writeU64(f,$10);

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
  if EmitMapFile then WriteMapFile(outPath, LOAD_ADDR, codeOffset);
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
    { Neither backend emits a dynamic segment, so a `cdecl external` cannot be
      resolved — the restriction is real. Three things were wrong with SAYING
      so: it named esp32 for BOTH architectures, so `--target=riscv32` was told
      about a chip it was not targeting; it named no symbol, so the `in:` line
      pointed at whichever RTL unit happened to hold the first external
      (softfloat.pas) with nothing to grep for; and it did not say what to do.
      bug-a-a-riscv32-diagnostic-names-the-wrong-target }
    if ExternalCount > 0 then
      ErrorNoPos('target ' + TargetDisplayName + ': external (dynamic) symbols are '
            + 'not supported on this target (first one: '
            + Procs[ExternalProc[0]].Name + '); this backend emits no dynamic '
            + 'segment, so link the dependency in statically or build for a '
            + 'target that has one (x86-64, i386, arm32, aarch64)');
    { @proc address fixups (ProcAddrFix) are 32-bit-absolute patched in place
      below and work for the bare ET_EXEC image on both riscv32 (auipc +
      inline literal) and xtensa (L32R inline literal) — each IR_PROCADDR
      emits a Patch32-friendly word. Method fixups remain unsupported. }
    { Method-address fixups (VMT slots in the data blob) use the generic
      PatchDataU64 loop below — 8-byte slots, 32-bit address in the low dword,
      same as i386/arm32. Nothing esp-specific remains. }
  end;

  { A bare-metal ESP image keeps the original SINGLE RWX PT_LOAD: it loads into
    SoC SRAM as one region, no loader enforces a second segment's permissions,
    and the split would cost a page of padding in a memory measured in hundreds
    of KB to buy nothing. Everything hosted gets code and data separated. }
  if EspBareBoot then
  begin
    phnum := 2;   { PT_LOAD (RWX) + PT_GNU_STACK }
    codeOffset := ESP_CODE_OFFSET32;
  end
  else
  begin
    phnum := 3;   { PT_LOAD code + PT_LOAD data + PT_GNU_STACK }
    codeOffset := CODE_OFFSET32;
  end;
  if isDyn then
  begin
    PrepareDynamicData32;          { appends interp/dynstr/dynsym/hash/rel/dynamic }
    phnum := 5;   { + PT_INTERP + PT_DYNAMIC }
    codeOffset := DYNAMIC_CODE_OFFSET32;
  end;
  { See the same check in writeELF: the constant and the header count are one
    fact spelled twice, and drift produces an image that loads and lies. }
  if codeOffset <> ELF32_HEADER_SIZE + phnum * PROG32_HEADER_SIZE then
    ErrorNoPos('internal: CODE_OFFSET32 disagrees with the program-header count');
  { Bare-metal ESP image loads into the SoC SRAM (one RWX region under qemu);
    everything else uses the classic i386 ET_EXEC base. }
  if EspBareBoot then
  begin
    { the CHIP owns its load org, not the ISA — same values for the two chips
      the generic targets default to, so this is byte-identical for them.
      decide-esp-soc-axis-and-capability-table }
    loadBase := SocIramBase(TargetSoc);
  end
  else loadBase := LOAD_ADDR32;
  { NOT for a bare-metal ESP image: it loads into SoC SRAM measured in
    hundreds of KB, where 4 KiB is a real cost — and nothing is translating
    from that page there, so the hazard does not exist to be avoided. }
  { Unconditional, ESP included: the bare image skips the page pad, so this is
    the ONLY thing aligning its data -- and xtensa is the target that faults. }
  AlignCodeForData(codeOffset);
  if not EspBareBoot then PadCodeToPageBoundary(codeOffset);
  dataBase := loadBase + codeOffset + CodeLen;
  CheckDataBaseAligned(dataBase);
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
  { Same one authority as the two 64-bit writers -- see the note there.
    `not EspBareBoot` STAYS. It is redundant today (compiler.pas:1702 halts
    unless the target is xtensa or riscv32, neither of which DbgArchSupported
    accepts), but "redundant" is a claim about a validation elsewhere, and
    deleting a live condition on the strength of one is a separate change
    needing its own proof. It costs a boolean.
    bug-a-the-dwarf-target-set-is-written-down-three-times-and-the-authority-is-dead-code }
  doDebug := DebugInfo and DbgArchSupported and (not EspBareBoot);
  shoff32 := 0;
  if doDebug then
  begin
    DbgBssBase := bssBase;
    DbgDataBase := dataBase;   { a data-resident global's DWARF location — DATA_SYM_BIAS }
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
    { A data-resident global (a typed const array baked into .data) carries a
      BIASED offset -- the one decode point for all of them, because every
      backend reaches a global through the same EmitGlobRef. See DATA_SYM_BIAS. }
    if SymOffIsData(GlobFix[i].BSSoff) then
      addr := dataBase + SymOffDataPart(GlobFix[i].BSSoff)
    else
      addr := bssBase + GlobFix[i].BSSoff;
    { PCRel is never set on this path today -- EmitGlobRef's rewrite is guarded
      on TARGET_X86_64 and this writer serves i386 and arm32. Kept identical to
      the two 64-bit loops on purpose: three copies of one decision that differ
      is the shape that let a record-field elSize sit wrong for 2.5 months
      (eb3b51755). If a 32-bit PC-relative form is ever added, this loop is
      already the same shape and does not need finding. }
    if GlobFixPCRel[i] then
      Patch32(GlobFix[i].CodePos,
              addr - (LOAD_ADDR + codeOffset + GlobFix[i].CodePos + 4
                      + GlobFixTrail[i]))
    else
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

  { phdr32 (32 bytes each). The ESP bare image is one RWX segment covering the
    whole file, as it has always been; every hosted image is code R+X then
    data+bss R+W. }
  if EspBareBoot then
  begin
    writeU32(f,1);writeU32(f,0);                        { PT_LOAD, offset 0 }
    writeU32(f,loadBase);writeU32(f,loadBase);
    writeU32(f,filesz);writeU32(f,memsz);
    writeU32(f,7);writeU32(f,$1000);                    { flags RWX, align }
  end
  else
  begin
    writeU32(f,1);writeU32(f,0);                        { PT_LOAD, offset 0 }
    writeU32(f,loadBase);writeU32(f,loadBase);
    writeU32(f,codeOffset + CodeLen);writeU32(f,codeOffset + CodeLen);
    writeU32(f,5);writeU32(f,ElfSegAlign);              { flags R+X }
    writeU32(f,1);writeU32(f,codeOffset + CodeLen);     { PT_LOAD, data offset }
    writeU32(f,dataBase);writeU32(f,dataBase);
    writeU32(f,DataLen);writeU32(f,(bssBase - dataBase) + BSSSize);
    writeU32(f,6);writeU32(f,ElfSegAlign);              { flags R+W, no X }
  end;
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
  { PT_GNU_STACK (RW, no X): see bug-elf-missing-pt-gnu-stack. }
  writeU32(f,$6474E551);                                { p_type }
  writeU32(f,0);writeU32(f,0);writeU32(f,0);            { offset, vaddr, paddr }
  writeU32(f,0);writeU32(f,0);                          { filesz, memsz }
  writeU32(f,6);writeU32(f,$10);                        { flags=RW, align }

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
  { The 32-bit writer emitted no map at all, so `--map` was silently a no-op for
    i386, arm32, riscv32 and xtensa -- the four targets with NO other route to a
    symbol, since --emit-obj refuses on three of them. A guest core's PC was
    therefore unresolvable by construction
    (bug-a-no-cross-target-can-build-the-compiler-itself). }
  if EmitMapFile then WriteMapFile(outPath, loadBase, codeOffset);
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

{ Bodies below, after the Obj*Is* predicates they call -- pxx prescans headers
  and the FPC seed does not, so a body placed here would build fine and fail
  only in the seed canary. }
procedure ObjPlanEspSymbols(numSectionSyms: Integer;
                            var strSize, numLocalProcs, numExportProcs,
                                numExportData, appMainOff, firstGlobal,
                                extSym0: Integer); forward;
{ The .symtab index of every defined proc, in the layout the HOSTED writers
  emit (writeELFRelX64General and its i386 sibling): null, three section syms,
  local procs, local data, then firstGlobal onward for the exported ones. The
  ESP writer has its own version of this inside ObjPlanEspSymbols because its
  symbol table is laid out differently; the two must not be merged by someone
  who notices they look alike.

  Split into a second pass for the same reason that one is: an exported proc's
  index depends on numLocalProcs AND numLocalData, neither of which is known
  until the first pass has counted them. Getting it wrong aims a call at the
  wrong symbol, which the linker resolves happily -- a wild jump, not an
  error -- so ObjCallFixIsRelocatable refuses anything it cannot index. }
procedure ObjRefuseEspDataImports; forward;
function ObjEspProcIsExported(procIdx: Integer): Boolean; forward;

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
  numLocalProcs, numExportProcs, numExportData, extSym0: Integer;
  numSyms, firstGlobal, symIdx: Integer;
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

  ObjRefuseEspDataImports;
  ObjPlanEspSymbols(4, strSize, numLocalProcs, numExportProcs, numExportData,
                    appMainOff, firstGlobal, extSym0);
  numSyms := extSym0 + ExternalCount;

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
    if (ObjProcStrOff[i] >= 0) and (not ObjEspProcIsExported(i)) then
    begin
      if ProcIram[i] then
        writeSym32(f, ObjProcStrOff[i], ObjProcIramOff[i], 0, 2, 3)  { LOCAL FUNC in .iram1.text }
      else
        writeSym32(f, ObjProcStrOff[i], Procs[i].BodyAddr, 0, 2, 1); { LOCAL FUNC in .text }
    end;
  writeSym32(f, appMainOff, 0, 0, $12, 1);
  { The MARKED surface, and only it: a cdecl routine keeps its section -- an
    iram proc stays in .iram1.text -- so exporting it does not move its code. }
  for i := 0 to ProcCount-1 do
    if (ObjProcStrOff[i] >= 0) and ObjEspProcIsExported(i) then
    begin
      if ProcIram[i] then
        writeSym32(f, ObjProcStrOff[i], ObjProcIramOff[i], 0, $12, 3)
      else
        writeSym32(f, ObjProcStrOff[i], Procs[i].BodyAddr, 0, $12, 1);
    end;
  for i := 0 to SymCount-1 do
    if ObjDataStrOff[i] >= 0 then
      writeSym32(f, ObjDataStrOff[i], Syms[i].Offset, SymAllocSize[i], $11, 7);
  for i := 0 to ExternalCount-1 do
    writeSym32(f, ObjExtStrOff[i], 0, 0, $10, 0);

  { .strtab -- proc names in INDEX order, not symbol order (see the planner). }
  writeU8(f, 0);
  for i := 0 to ProcCount-1 do
    if ObjProcStrOff[i] >= 0 then writeStrZ(f, Procs[i].Name);
  writeStrZ(f, 'app_main');
  for i := 0 to SymCount-1 do
    if ObjDataStrOff[i] >= 0 then writeStrZ(f, Syms[i].Name);
  for i := 0 to ExternalCount-1 do
    writeStrZ(f, ExternalLinkName(i));
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
      writeRela32(f, DynCallCodePos[i], extSym0 + DynCallExtIdx[i], 1, 0);
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
    if mapped >= 0 then writeRela32(f, mapped, extSym0 + DynCallExtIdx[i], 1, 0);
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
  numLocalProcs, numExportProcs, numExportData, extSym0: Integer;
  numSyms, firstGlobal: Integer;
  textOff, dataOff, symOff, strOff, relaTextOff, relaDataOff: Integer;
  shstrOff, shOff, strSize: Integer;
  relaTextCount, relaDataCount, appMainOff: Integer;
{$ifdef FPC}
  f: File;
{$else}
  f: Integer;
{$endif}
begin
  { An INTERNAL invariant, not the user-facing refusal. Naming the whole
    supported set from in here is what went stale twice: this writer serves two
    targets and cannot see who else has a writer, so every sentence it wrote
    about the others was a copy that nothing updated. The set now lives in
    TargetHasObjectWriter and the refusal is at compiler.pas's dispatch, which
    is the code that reads the predicate.

    Kept rather than deleted because it is reachable: it fires the moment a new
    dispatch route sends an unrelated target here, which is exactly the change
    that would otherwise emit a silently wrong ELF32 object.
    bug-a-the-emit-obj-refusal-names-a-target-set-that-excludes-x86-64 }
  if (TargetArch <> TARGET_XTENSA) and (TargetArch <> TARGET_RISCV32) then
    ErrorNoPos('internal: writeELF32Rel serves --target=xtensa and --target=riscv32 '
        + 'only, but was dispatched for --target=' + TargetArchName(TargetArch));
  { Programs with `iram;` procedures need the two-text-section writer, which also
    handles @proc (ProcAddrFix) relocs — dispatch BEFORE the guard below. }
  for i := 0 to ProcCount-1 do
    if ProcIram[i] and (Procs[i].BodyAddr >= 0) then
    begin
      writeELF32RelIram(outPath);
      Exit;
    end;
  { @proc / proc-type values (ProcAddrFix): the extended writer above already
    relocates them against the proc's LOCAL symbol — route through it; with no
    iram procs its .iram1.text section is simply empty. This is what lets a
    PLAIN (task-context) routine's address be registered as an SDK callback
    without the iram; mislabel (bug-esp-emit-obj-proc-fixup-non-iram). }
  if ProcAddrFixCount > 0 then
  begin
    writeELF32RelIram(outPath);
    Exit;
  end;
  if TargetArch = TARGET_XTENSA then machine := 94 else machine := 243;

  ObjRefuseEspDataImports;
  ObjPlanEspSymbols(3, strSize, numLocalProcs, numExportProcs, numExportData,
                    appMainOff, firstGlobal, extSym0);
  numSyms := extSym0 + ExternalCount;
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
    if (ObjProcStrOff[i] >= 0) and (not ObjEspProcIsExported(i)) then
      writeSym32(f, ObjProcStrOff[i], Procs[i].BodyAddr, 0, 2, 1); { LOCAL FUNC }
  writeSym32(f, appMainOff, 0, 0, $12, 1);  { GLOBAL FUNC app_main = entry }
  for i := 0 to ProcCount-1 do
    if (ObjProcStrOff[i] >= 0) and ObjEspProcIsExported(i) then
      writeSym32(f, ObjProcStrOff[i], Procs[i].BodyAddr, 0, $12, 1); { GLOBAL FUNC }
  for i := 0 to SymCount-1 do
    if ObjDataStrOff[i] >= 0 then
      writeSym32(f, ObjDataStrOff[i], Syms[i].Offset, SymAllocSize[i], $11, 5);
  for i := 0 to ExternalCount-1 do
    writeSym32(f, ObjExtStrOff[i], 0, 0, $10, 0); { GLOBAL NOTYPE UNDEF }

  { .strtab -- proc names in INDEX order, not symbol order (see the planner). }
  writeU8(f, 0);
  for i := 0 to ProcCount-1 do
    if ObjProcStrOff[i] >= 0 then writeStrZ(f, Procs[i].Name);
  writeStrZ(f, 'app_main');
  for i := 0 to SymCount-1 do
    if ObjDataStrOff[i] >= 0 then writeStrZ(f, Syms[i].Name);
  for i := 0 to ExternalCount-1 do
    writeStrZ(f, ExternalLinkName(i));
  writePad(f, relaTextOff - (strOff + strSize));

  { .rela.text: literal slots -> .data / .bss / undefined externals.
    Symbol indices: 1 = .text section sym, 2 = .data, 3 = .bss. }
  for i := 0 to FixCount-1 do
    writeRela32(f, Fixups[i].CodePos, 2, 1, Fixups[i].DataOff);
  for i := 0 to GlobFixCount-1 do
    writeRela32(f, GlobFix[i].CodePos, 3, 1, GlobFix[i].BSSoff);
  for i := 0 to DynCallCount-1 do
    writeRela32(f, DynCallCodePos[i], extSym0 + DynCallExtIdx[i], 1, 0);

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

{ ===== General x86-64 relocatable object writer =====
  feature-a-a-general-x86-64-relocatable-object-writer, under
  meta-a-pxx-produces-linkable-code.

  The ELF64 sibling of writeELF32Rel: everything a compiler BACKEND produces --
  procedures as symbols, .data, .bss, and the backend relocation kinds -- as an
  ET_REL object a real linker consumes.

  WHY THIS IS NOT writeELFRelX64. That one is the .asm FRONTEND's writer: its
  symbols are `global` labels (AsmGlobalSym*) and its only relocations are
  `call <extern>` sites (AsmObjCall*), which is complete for a .asm source,
  where data is appended into Code[] and addressed as part of .text. compiler.pas
  dispatched --emit-obj by ARCHITECTURE, so every Pascal, C and NilPy program on
  x86-64 -- the DEFAULT target -- landed there and got an object describing none
  of itself. The dispatch now asks what the object has to CARRY.

  RELOCATION MODEL: absolute, so a link needs -no-pie. The x86-64 backend
  reaches .data through an 8-byte absolute operand (EmitDataRef) and a global
  through a 4-byte sign-extended displacement (EmitGlobRef -- every x86-64 site
  is a `[disp32]` SIB form), which are R_X86_64_64 and R_X86_64_32S. A linker
  can satisfy those only in a non-PIE link with everything below 2 GiB, and
  modern toolchains default to PIE, so `gcc -no-pie` is part of the contract
  rather than a detail. Lifting it means teaching the backend a rip-relative
  global-reference form under --emit-obj (R_X86_64_PC32) -- backend work, not
  writer work, and a separate ticket
  (feature-a-x86-64-object-output-is-position-dependent).

  EXTERNAL CALLS NEED NO BACKEND CHANGE, which is what kept this writer small.
  An external call on x86-64 is already `call qword ptr [abs32]` through a GOT
  slot the compiler allocates in its OWN .data (RegisterExternal). In an object
  that is two ordinary relocations -- the operand is R_X86_64_32S against .data,
  and the 8-byte slot is R_X86_64_64 against the extern's UND symbol -- and the
  LINKER fills the slot. No PLT, no rewriting of the call site, no new emit
  mode. @extern (EmitExternalProcAddr) rides the same pair.

  EXPORT SURFACE: the routines declared with the C convention -- ProcCdecl, i.e.
  Pascal `cdecl` and every function of a C translation unit -- under their own
  names, GLOBAL FUNC. Everything else defined is a LOCAL FUNC: visible to a
  debugger, invisible to the linker, so an object cannot collide with its host
  over an RTL name. Nothing exported means nothing linkable, and we say so
  rather than write it (the failure otherwise surfaces at someone else's link
  step with no cause attached --
  bug-a-emit-obj-on-x86-64-produces-an-object-with-no-symbols-data-or-relocations).

  NOT EXPORTED: the program entry at .text+0. It is the
  set-up-globals-run-the-body-and-exit path, so a C caller invoking it would
  terminate the process rather than return. The consequence is real and belongs
  in the ticket, not hidden here: a pxx object linked into a foreign program
  runs NO global/unit initialisation, so an exported routine must not depend on
  any.

  File layout (written sequentially; the self-hosted writer cannot seek):
  ehdr, .text, .data, .symtab, .strtab, .rela.text, .rela.data,
  [.init_array, .rela.init_array], [.fini_array, .rela.fini_array], .shstrtab,
  section headers. Sections: 0 null, 1 .text, 2 .rela.text, 3 .data,
  4 .rela.data, 5 .bss, 6 .symtab, 7 .strtab, 8 .shstrtab, then the array
  sections if this object HAS initialisers.

  THE ARRAY SECTIONS ARE APPENDED AFTER .shstrtab's INDEX, not inserted in file
  order, and that is deliberate: every existing section keeps the index it had,
  so e_shstrndx stays 8 and no link/info field in the eight headers below has to
  move. Their CONTENT still lands before .shstrtab because the self-hosted
  writer cannot seek and must write sequentially -- index order and file order
  are independent, and only one of them was expensive to change.

  The .shstrtab blob stays the 66-byte one writeELF32Rel uses when there are no
  array sections, and grows 29 bytes per pair that exists.

  WHAT THAT BUYS, SCOPED TO WHAT WAS ACTUALLY MEASURED -- an object whose
  frontend emits no thunk is byte-identical to what this writer produced before
  the feature, verified against the pre-feature compiler with the two compiler
  shas asserted to differ. Today that means every PASCAL object, because the
  Pascal frontend does not emit the thunks yet. It does NOT mean "any object with
  no initialisers": a C object always carries a finalizer runner, so it gains
  .fini_array either way, and gains .init_array only when it has pre-main work.
  The first version of this comment said the wider thing and the control that
  "confirmed" it was a Pascal object -- a population that cannot contain the C
  thunk at all, so it agreed without ever having been able to disagree.
  bug-a-c-an-emit-obj-object-linked-into-a-non-pxx-program-never-runs-its-initialisers }

function ObjProcIsDefined(procIdx: Integer): Boolean;
{ Has this proc entry a body in Code[]? False for an `external` declaration and
  for a bare signature (a `cdecl` PROC TYPE registers a Procs[] entry too, and
  ProcCdecl is True on it -- BodyAddr is what tells the two apart). }
begin
  Result := (Procs[procIdx].BodyAddr >= 0) and (not ProcExternal[procIdx]);
end;

function ObjProcIsExported(procIdx: Integer): Boolean;
{ Does this routine belong in the object's link-visible surface? Only if its
  NAME and its CONVENTION both mean something outside this compilation, which
  is exactly the C-convention set. An internal-convention routine exported
  under its Pascal name would be callable and wrong.

  `static` REMOVES a C function from that surface, and it is not an
  optimisation: C 6.2.2p3 gives it internal linkage, so the name means nothing
  outside this translation unit and two objects that both define it are not in
  conflict. Emitted GLOBAL, they are -- busybox puts `static ALWAYS_INLINE`
  helpers in libbb.h (bb_ascii_isalnum, bb_strtoi32, is_tty_secure,
  new_tls_state, ...), every translation unit that includes it defined them,
  and the 82-object link died on `multiple definition of' before reaching
  anything else. Nothing here needs a new symbol group: a defined-but-not-
  exported proc already lands in the LOCAL block ahead of firstGlobal, which
  is where every non-cdecl Pascal routine has always gone.

  The DATA side has said this since the linkage work landed (ObjDataIsLocal
  reads SymCStaticLink) -- functions were the arm that never got the sibling.
  Measured: for `static int helper(int)` in a shared header, gcc emits `t' and
  we emitted `T'.
  bug-a-static-c-functions-are-emitted-as-global-symbols }
begin
  Result := ProcCdecl[procIdx] and (not ProcCStaticLink[procIdx]);
end;

{ numExtraLocal: LOCAL symbols emitted after the local data block and before
  the first global -- today the init/fini thunk symbols under
  --function-sections. It only has to move firstGlobal; the thunks are not in
  Procs[] and have no ObjProcSymIdx row. }
procedure ObjPlanHostedProcSymIdx(numLocalProcs, numLocalData, numExtraLocal: Integer);
var i, n, firstGlobal: Integer;
begin
  for i := 0 to ProcCount-1 do ObjProcSymIdx[i] := -1;
  n := 0;
  for i := 0 to ProcCount-1 do
    if ObjProcIsDefined(i) and (not ObjProcIsExported(i)) then
    begin
      ObjProcSymIdx[i] := 4 + n;
      Inc(n);
    end;
  firstGlobal := 4 + numLocalProcs + numLocalData + numExtraLocal;
  n := 0;
  for i := 0 to ProcCount-1 do
    if ObjProcIsDefined(i) and ObjProcIsExported(i) then
    begin
      ObjProcSymIdx[i] := firstGlobal + n;
      Inc(n);
    end;
end;

{ May a reference that names a PROC BY INDEX -- @proc's address, a VMT slot --
  become a relocation against that proc's own symbol, instead of `.text` plus a
  baked body offset?

  The same substitution ObjCallFixIsRelocatable makes for calls, and needed for
  the same reason: a `.text + <offset>` addend is computed for THIS object's
  copy of the callee, so a linker that drops or replaces that copy leaves the
  slot pointing at whatever moved in. It is also STRICTLY WORSE than a baked
  call displacement, because a VMT slot is data the program dereferences rather
  than a jump the linker could at least be told about.

  Simpler than the call predicate by exactly one clause: there is no target
  snapshot to disagree with. CallFixTarget exists because a call site records
  which body it was aimed at and a later same-named static can overwrite the
  row; ProcAddrFix and MethodFixups carry no such snapshot, so there is nothing
  here to compare and nothing to refuse on. That is a difference in the DATA,
  not a relaxation -- if either grows a target snapshot, this predicate needs
  the clause too. }
{ Names for the init/fini thunk symbols. LOCAL, so they cannot collide across
  objects and cannot join the export surface -- both properties the COMDAT
  group-signature question will need again. }
const
  OBJ_INIT_THUNK_NAME = '__pxx_init_thunk';
  OBJ_FINI_THUNK_NAME = '__pxx_fini_thunk';

function ObjProcRefIsRelocatable(p: Integer): Boolean;
begin
  ObjProcRefIsRelocatable := False;
  if not FunctionSections then Exit;
  if not EmitObjMode then Exit;
  if (p < 0) or (p >= ProcCount) then Exit;
  if not ObjProcIsDefined(p) then Exit;
  if ObjProcSymIdx[p] < 0 then Exit;
  ObjProcRefIsRelocatable := True;
end;

function ObjCallFixIsRelocatable(i: Integer): Boolean;
var p: Integer;
begin
  ObjCallFixIsRelocatable := False;
  if not FunctionSections then Exit;
  if not EmitObjMode then Exit;
  p := CallFix[i].ProcIdx;
  if (p < 0) or (p >= ProcCount) then Exit;
  if (CallFixTarget[i] >= 0) and (CallFixTarget[i] <> Procs[p].BodyAddr) then Exit;
  if not ObjProcIsDefined(p) then Exit;
  if ObjProcSymIdx[p] < 0 then Exit;
  ObjCallFixIsRelocatable := True;
end;

{ May this call site become a relocation against the callee's symbol?

  Refuses exactly one shape, and getting the test right mattered. CallFixTarget
  is an unconditional SNAPSHOT of Procs[procIdx].BodyAddr taken when the site was
  recorded (symtab.inc), so it is -1 only for a FORWARD reference. Reading
  ">= 0" as "pinned to a specific body" therefore refused every BACKWARD call --
  measured, 1004 of 1084 sites in a C object against 80 accepted. The report
  below is what caught that; the predicate looked obviously right.

  The real hazard is narrower: the snapshot DISAGREEING with the row. A C file
  with two same-named file-scope statics compiles both and the later body
  overwrites the row, so a site aimed at the first body would be silently
  re-aimed at the second -- links cleanly, runs the wrong function, which is how
  test/cstatic_same_module_dup.c once went from "2 11" to "11 11". Those stay
  baked, and because they stay baked they are also what will block per-function
  sections later, so they are COUNTED rather than assumed absent. }
{ What this flag did and, more usefully, what it could NOT do. The count that
  matters is not how many calls were relocated but how many call sites remain
  BAKED, because per-function sections cannot land while any of them do: a baked
  displacement is computed for this object's own copy of the callee, so a linker
  that drops or replaces that copy leaves the jump pointing into whatever moves
  in. Printed rather than inferred -- the first reading of this feature counted
  80 relocations against 1124 call instructions in .text and no amount of
  reasoning about EmitCallProc would have said which of the four reasons
  accounted for the other 1044. }
procedure ObjReportFunctionSections;
var i, reloc, tgtPinned, undef, noSym: Integer;
    firstBaked, pinnedNames: AnsiString;
begin
  if not FunctionSections then Exit;
  reloc := 0; tgtPinned := 0; undef := 0; noSym := 0;
  pinnedNames := '';
  for i := 0 to CallFixCount-1 do
    if ObjCallFixIsRelocatable(i) then Inc(reloc)
    else if (CallFix[i].ProcIdx >= 0) and (CallFix[i].ProcIdx < ProcCount) and
            (CallFixTarget[i] >= 0) and
            (CallFixTarget[i] <> Procs[CallFix[i].ProcIdx].BodyAddr) then
    begin
      Inc(tgtPinned);
      { NAMED, not just counted. This number is the one thing left blocking
        per-function sections, and driving it to zero means knowing WHICH
        callee's snapshot disagrees with its row. The count alone is actively
        misleading: it sent its first reader looking for duplicate file-scope
        statics in the translation unit under compilation, which has none --
        the six in a plain C object are all `sysret', and both definitions are
        in CRTL (fcntl.c and unistd.c), pulled into the same buffer behind a
        program whose only libc reference is printf.
        ONE NAME PER SITE, NOT PER CALLEE, so a repeated name is the finding
        rather than a printing bug: six sites, one callee. Capped at 8 with the
        cap stated in the output, so a pathological object prints a line and
        not a megabyte, and nobody reads a truncation as a total. }
      if tgtPinned <= 8 then
        pinnedNames := pinnedNames + ' ' + Procs[CallFix[i].ProcIdx].Name
      else if tgtPinned = 9 then
        pinnedNames := pinnedNames + ' ...(first 8 only)';
    end
    else if (CallFix[i].ProcIdx < 0) or (CallFix[i].ProcIdx >= ProcCount) or
            (not ObjProcIsDefined(CallFix[i].ProcIdx)) then Inc(undef)
    else Inc(noSym);
  write(StdErr, 'function-sections: CallFix ', CallFixCount,
          '  relocated ', reloc,
          '  pinned-target ', tgtPinned,
          '  undefined ', undef,
          '  no-symbol ', noSym);
  if tgtPinned > 0 then write(StdErr, '  (pinned:', pinnedNames, ')');
  writeln(StdErr, '');
  { The other two families that name a proc by index, counted for the same
    reason: what blocks per-function sections is the number still BAKED, and
    a VMT slot left baked is worse than a baked call because the program
    dereferences it. Reported even when both are zero -- a zero here means
    "this program has no @proc and no virtual method", which is a fact about
    the PROGRAM, and reading a silent line as "nothing left to do" is how a
    census of one shape gets mistaken for a census of all of them. }
  reloc := 0; noSym := 0;
  for i := 0 to ProcAddrFixCount-1 do
    if ObjProcRefIsRelocatable(ProcAddrFix[i].ProcIdx) then Inc(reloc) else Inc(noSym);
  writeln(StdErr, 'function-sections: ProcAddrFix ', ProcAddrFixCount,
          '  relocated ', reloc, '  baked ', noSym);
  reloc := 0; noSym := 0; firstBaked := '';
  for i := 0 to MethodFixCount-1 do
    if ObjProcRefIsRelocatable(MethodFixups[i].ProcIdx) then Inc(reloc)
    else
    begin
      Inc(noSym);
      { NAME the first one. A bare count says work remains and gives nothing to
        grep for, and these are precisely the entries that will block
        per-function sections -- the reader's next question is always "which",
        and answering it costs one string. }
      if (firstBaked = '') and (MethodFixups[i].ProcIdx >= 0)
         and (MethodFixups[i].ProcIdx < ProcCount) then
        firstBaked := Procs[MethodFixups[i].ProcIdx].Name;
    end;
  write(StdErr, 'function-sections: MethodFix ', MethodFixCount,
        '  relocated ', reloc, '  baked ', noSym);
  if noSym > 0 then write(StdErr, '  (first: ', firstBaked, ')');
  writeln(StdErr, '');
end;


function ObjProcBind(procIdx: Integer): Byte;
{ The st_info BINDING NIBBLE, already shifted: $10 GLOBAL, $20 WEAK.

  WHY THE RUNTIME IS WEAK AND THE PROGRAM IS NOT. crtl is pulled into every
  --emit-obj object WHOLESALE -- a two-line .c comes out with 117 global
  definitions, 116 of them crtl -- so any two pxx objects collide on all 116 and
  ld refuses the link outright. WEAK makes the linker keep one definition and
  discard the rest, which is what every C runtime does for the same reason.

  NOT LOCAL, and the difference matters. A self-contained runtime per object
  looks like the tidier answer and is wrong: object A's `malloc` would take from
  A's heap and object B's `free` would return to B's, so a pointer crossing a
  translation unit corrupts rather than collides. Weak keeps ONE copy of the
  code, and that copy carries its own state's addresses, so every caller reaches
  the same allocator AND the same heap.

  THAT ARGUMENT COVERS STATE REACHED THROUGH CODE AND NOTHING ELSE, which is why
  the data half of this change exists. A program that reads `errno` or `optind`
  BY NAME never goes through a crtl routine, so no surviving copy funnels it --
  and those had no linkage at all, so two objects kept separate copies in
  silence. Measured by frankD against gcc: `errno=0 strerror=[]` where gcc says
  `errno=2 strerror=[No such file or directory]`, and busybox's `cat` losing its
  reason string and taking `-u` as a filename, one bug each. So the state is
  exported weak alongside the code; see ObjDataIsRuntime.
  bug-a-every-object-defines-the-whole-of-crtl-globally-so-no-two-objects-link }
begin
  if ProcObjRuntimeCopy[procIdx] then ObjProcBind := $20 else ObjProcBind := $10;
end;

function ObjProcSize(procIdx: Integer): Int64;
begin
  if ProcBodyEnd[procIdx] > Procs[procIdx].BodyAddr then
    Result := ProcBodyEnd[procIdx] - Procs[procIdx].BodyAddr
  else
    Result := 0;
end;

function ObjDataIsCandidate(i: Integer): Boolean;
{ Is symbol `i` a C file-scope variable that took global storage?

  SymObjDataScope is MEMBERSHIP and the linkage flags are not: SymObjDataExternOnly and
  SymCStaticLink both default to False, and False is a meaningful answer for
  each, so neither can separate a C global from the several thousand RTL globals
  that share Syms. Asking the linkage first is how an export pass ends up
  exporting the whole runtime. }
begin
  ObjDataIsCandidate := (i >= 0) and (i < SymCount) and
                        (SymObjDataScope[i] or SymObjRuntimeCopy[i]) and
                        (Syms[i].Kind = skGlobal) and (Syms[i].Name <> '');
end;

function ObjDataIsRuntime(i: Integer): Boolean;
{ Is this one of pxx's OWN C runtime's variables, rather than the user's?

  RUNTIME WINS OVER SCOPE WHEN BOTH ARE SET, and that combination is the common
  case rather than a corner: `#include <stdio.h>` puts `extern FILE *stdin;` in
  the USER's translation unit, so the user's file really does declare it, while
  crtl holds the DEFINITION. Asking only "did the user's file mention this name"
  therefore called `stdin` and `stdout` the program's own, and two objects that
  both included stdio.h collided on them -- before reaching the 116 code
  symbols, and for a different reason.

  The question that answers correctly is WHOSE DEFINITION, not whose mention. A
  crtl definition makes it runtime state however many user files declare it.
  bug-a-every-object-defines-the-whole-of-crtl-globally-so-no-two-objects-link }
begin
  ObjDataIsRuntime := ObjDataIsCandidate(i) and SymObjRuntimeCopy[i];
end;

function ObjDataIsImport(i: Integer): Boolean;
{ Every declaration of this NAME said `extern` and none defined it. Rule 3 of
  C 6.9.2 as the ticket states it -- and note `static` wins outright, because an
  internal-linkage name is never undefined-elsewhere.

  A NAME OUR OWN RUNTIME OWNS IS NEVER IMPORTED, whatever the fold says. We
  ship a C runtime; asking the host's libc for a piece of its state is how a
  non-TLS reference to `errno` meets glibc's TLS one, and ld does not warn --
  it refuses libc.so outright with "bad value". A translation unit that pulls
  crtl's declaration of errno without pulling the module that defines it is
  the shape that reaches here, and it is a real one: test_shared_lib.c does it.
  The answer is a private slot, which is what it had before this ticket, not an
  UND that the linker will resolve into a different runtime. }
begin
  ObjDataIsImport := ObjDataIsCandidate(i) and SymObjDataExternOnly[i] and
                     (not SymCStaticLink[i]) and (not SymObjRuntimeCopy[i]);
end;

function ObjDataIsLocal(i: Integer): Boolean;
begin
  ObjDataIsLocal := ObjDataIsCandidate(i) and SymCStaticLink[i];
end;

function ObjDataExportInfo(i: Integer): Byte;
{ st_info for an exported data symbol: $11 GLOBAL OBJECT, $21 WEAK OBJECT.
  The runtime's state is weak for the same reason its code is -- see
  ObjProcBind, which carries the argument and the measurement. }
begin
  if SymObjRuntimeCopy[i] then ObjDataExportInfo := $21 else ObjDataExportInfo := $11;
end;

function ObjDataIsExport(i: Integer): Boolean;
{ A definition with external linkage: not static, and not extern-only. Covers
  both an initialised definition and a tentative one, which is deliberate --
  `extern T n;` then a bare `T n;` is a DEFINITION and SymObjDataExternOnly has
  already been folded back to False for it. }
begin
  ObjDataIsExport := ObjDataIsCandidate(i) and (not SymCStaticLink[i]) and
                     (not SymObjDataExternOnly[i]);
end;

function ObjDataIsReferenced(i: Integer): Boolean;
{ Does any relocation actually reach this symbol's own slot?

  gcc emits UND only for an imported name the translation unit USES, and an
  unreferenced UND would be a name this object asks the linker to find for no
  reason. The reference test is an exact match on the symbol's base, which is
  what every measured C shape produces: a constant index and a field offset are
  computed after the LEA, so `ia[5]`, `st.c` and `ta[4].y` all relocate to the
  bare base. }
var k: Integer;
begin
  ObjDataIsReferenced := False;
  for k := 0 to GlobFixCount-1 do
    if (not SymOffIsData(GlobFix[k].BSSoff)) and
       (GlobFix[k].BSSoff = Syms[i].Offset) then
    begin
      ObjDataIsReferenced := True;
      Exit;
    end;
end;

function ObjDataSymIndexForOff(bssOff: Integer): Integer;
{ The IMPORT whose slot starts exactly at `bssOff`, or -1.

  Exact match, not range containment, and that is a measured choice rather than
  a simplification: the design this replaces assumed element and field offsets
  were folded into the relocation addend, and for C they are not (see the
  ticket's table). A range test would additionally have to decide how far an
  import extends, and an incomplete array reserves a single element -- so a
  range keyed on the reservation would be too SMALL for any folded reference
  while a range keyed on the next symbol's base would silently swallow one. }
var k: Integer;
begin
  ObjDataSymIndexForOff := -1;
  for k := 0 to SymCount-1 do
    if ObjDataIsImport(k) and (Syms[k].Offset = bssOff) then
    begin
      ObjDataSymIndexForOff := k;
      Exit;
    end;
end;

function ObjDataExportSymForOff(bssOff: Integer): Integer;
{ The EXPORTED definition whose slot starts exactly at `bssOff`, or -1.

  The twin of ObjDataSymIndexForOff, and it exists for the same reason with the
  arrow reversed. An import must name its symbol or it reads a private slot; an
  EXPORT must name its symbol or it *is* the private slot -- every reference
  inside this object resolves to its own .bss and the linker's choice between
  two definitions of the name reaches nobody. Measured: two objects that both
  used errno linked cleanly and each read its own copy, so `errno` came back 0
  where gcc says 2. Sharing a definition is a two-sided contract and only the
  import side was wired.

  .bss only, because the export loop declares section 5 for every data symbol
  it writes. Accepting a .data-encoded offset here would name a symbol whose
  own st_shndx says .bss -- a wrong address that still links. }
var k: Integer;
begin
  ObjDataExportSymForOff := -1;
  if SymOffIsData(bssOff) then Exit;
  for k := 0 to SymCount-1 do
    if ObjDataIsExport(k) and (not SymOffIsData(Syms[k].Offset)) and
       (Syms[k].Offset = bssOff) then
    begin
      ObjDataExportSymForOff := k;
      Exit;
    end;
end;

function ObjDataExportOrdinal(symIdx: Integer): Integer;
{ Position within the EXPORT group, counted with the predicate the planner and
  both writers walk -- see ObjDataImportOrdinal for why it is recomputed. }
var k, n: Integer;
begin
  n := 0;
  for k := 0 to SymCount-1 do
  begin
    if ObjDataIsExport(k) then
    begin
      if k = symIdx then
      begin
        ObjDataExportOrdinal := n;
        Exit;
      end;
      n := n + 1;
    end;
  end;
  ObjDataExportOrdinal := -1;
end;

function ObjDataRelocIsSymbolic(bssOff: Integer): Boolean;
{ Does this reference name a data SYMBOL rather than a section? Import or
  export -- the i386 writer needs the question without needing the index. }
begin
  ObjDataRelocIsSymbolic := (ObjDataSymIndexForOff(bssOff) >= 0) or
                            (ObjDataExportSymForOff(bssOff) >= 0);
end;

function ObjEspProcIsExported(procIdx: Integer): Boolean;
{ ObjProcIsExported, minus the one name this writer already owns.

  The entry symbol is emitted as GLOBAL `app_main` at the program entry,
  because that is the name the IDF calls. A C source that DEFINES `app_main`
  therefore has a proc of that name too -- pxx's entry stub runs the
  initialisers and calls it -- and exporting that proc as well puts two GLOBAL
  definitions of `app_main` in one object, at different values. Measured when
  the export loop was first written: symbol 8 at 0 and symbol 10 at 0x134.
  The entry symbol wins; the user's own stays LOCAL, exactly as it was before
  any of this. }
begin
  Result := ObjProcIsExported(procIdx) and
            (not CaseEqual(Procs[procIdx].Name, 'app_main'));
end;

procedure ObjPlanEspSymbols(numSectionSyms: Integer;
                            var strSize, numLocalProcs, numExportProcs,
                                numExportData, appMainOff, firstGlobal,
                                extSym0: Integer);
{ One symbol plan for both ELF32 object writers.

  WHY THE ESP OBJECT EXPORTED ONLY `app_main` until now, and why widening it is
  not a policy change: the writer was built for the ESP-IDF component shape --
  the SDK calls one entry point -- and every proc was LOCAL FUNC deliberately,
  as a guard against name collisions inside an IDF build. That guard is worth
  keeping, and it is kept: what appears in the global group is exactly what the
  programmer MARKED. A `cdecl` routine and a `cvar`/`public` global are explicit
  requests to be linkable by name; an unmarked program's object is unchanged
  byte for byte, which the test asserts rather than assumes.

  So the divergence being removed is not "ESP objects become chatty". It is that
  the SAME source exported on x86-64 and i386 and silently did not here -- the
  marker meant something on four targets and nothing on two.

  STRTAB ORDER IS DELIBERATELY NOT THE SYMBOL ORDER. Proc names stay in index
  order, exactly where they were, so an unmarked object's .strtab is unchanged;
  only the symbol SLOT a name is referenced from moves. Data names go after
  app_main and before the externals.

  ObjProcSymIdx is computed in a second pass because a proc's index depends on
  how many procs stayed local, which the first pass is still counting. The Iram
  writer relocates @proc literals against it, so getting this wrong is a wild
  code pointer rather than a link error. }
var i, n: Integer;
begin
  strSize := 1;
  numLocalProcs := 0;
  numExportProcs := 0;
  for i := 0 to ProcCount-1 do
    if ObjProcIsDefined(i) then
    begin
      ObjProcStrOff[i] := strSize;
      strSize := strSize + Length(Procs[i].Name) + 1;
      if ObjEspProcIsExported(i) then Inc(numExportProcs) else Inc(numLocalProcs);
    end
    else
      ObjProcStrOff[i] := -1;

  appMainOff := strSize;
  strSize := strSize + 9;                   { 'app_main' + NUL }

  numExportData := 0;
  for i := 0 to SymCount-1 do
    if ObjDataIsExport(i) then
    begin
      ObjDataStrOff[i] := strSize;
      strSize := strSize + Length(Syms[i].Name) + 1;
      Inc(numExportData);
    end
    else
      ObjDataStrOff[i] := -1;

  for i := 0 to ExternalCount-1 do
  begin
    ObjExtStrOff[i] := strSize;
    strSize := strSize + Length(ExternalLinkName(i)) + 1;
  end;

  firstGlobal := 1 + numSectionSyms + numLocalProcs;
  extSym0 := firstGlobal + 1 + numExportProcs + numExportData;

  n := 0;
  for i := 0 to ProcCount-1 do
    if ObjProcIsDefined(i) and (not ObjEspProcIsExported(i)) then
    begin
      ObjProcSymIdx[i] := 1 + numSectionSyms + n;
      Inc(n);
    end;
  n := 0;
  for i := 0 to ProcCount-1 do
    if ObjProcIsDefined(i) and ObjEspProcIsExported(i) then
    begin
      ObjProcSymIdx[i] := firstGlobal + 1 + n;
      Inc(n);
    end;
end;

procedure ObjRefuseEspDataImports;
{ An IMPORT has no route through these writers -- every GlobFix relocates
  against the .bss section sym -- so an `external` variable would take local
  storage and read zero, which is the silent-wrong-value shape the whole data
  work exists to prevent. Refused rather than emitted, until someone needs it.
  bug-a-the-esp-object-writer-exports-only-app-main-so-no-cdecl-routine-or-global-is-linkable }
var i: Integer;
begin
  for i := 0 to SymCount-1 do
    if ObjDataIsImport(i) then
      ErrorNoPos('--emit-obj: an imported variable (' + Syms[i].Name
        + ') is not supported for xtensa/riscv32 objects: the reference would '
        + 'relocate into this object''s own .bss and read zero. Export an '
        + 'accessor from the defining side instead');
end;

function ObjDataImportOrdinal(symIdx: Integer): Integer;
{ The position of `symIdx` within the IMPORT group, counted with exactly the
  predicate the planner and the writers walk. Recomputed rather than stored so
  there is one definition of the order: a stored ordinal would be a second copy
  free to disagree with the emission loop, and a wrong symbol index still
  links. }
var k, n: Integer;
begin
  n := 0;
  for k := 0 to SymCount-1 do
    if ObjDataIsImport(k) and ObjDataIsReferenced(k) then
    begin
      if k = symIdx then
      begin
        ObjDataImportOrdinal := n;
        Exit;
      end;
      Inc(n);
    end;
  ObjDataImportOrdinal := -1;
end;

function ObjDataOffIsInsideAnImport(bssOff: Integer): Integer;
{ The import whose reserved extent STRICTLY CONTAINS `bssOff` without starting
  at it, or -1. This is the shape the exact-match lookup cannot serve, and the
  reason it exists is that relocating it against `.bss` is the original defect
  wearing a new hat: it would link cleanly and read this object's own memory.

  It is separate from the lookup so it can be MEASURED before it is trusted --
  see the `a.datareloc` channel. A guard whose case nobody has constructed is
  not obviously better than no guard: it reads as "handled" to the next person.
  Track B looked for one from the Pascal side (a global AnsiString indexed
  through EmitStringCharLoad) and found the +8 lands on the string HEADER after
  the pointer load, never on the symbol's own slot, so it does not reach here. }
var k: Integer;
begin
  ObjDataOffIsInsideAnImport := -1;
  for k := 0 to SymCount-1 do
    if ObjDataIsImport(k) and (bssOff > Syms[k].Offset) and
       (bssOff < Syms[k].Offset + SymAllocSize[k]) then
    begin
      ObjDataOffIsInsideAnImport := k;
      Exit;
    end;
end;


procedure ObjPlanHostedSymbols(var strSize, numLocalProcs, numExportProcs,
                               numLocalData, numExportData, numImportData: Integer);
{ The EXPORT POLICY of a hosted relocatable object, in one place because it is
  the half that must never drift between targets: if x86-64 and i386 disagreed
  about what an object exports, the i386 link that exists to MEASURE the C-ABI
  convention would be measuring the writer instead.

  Assigns every .strtab name offset in the order the symbol table emits them --
  local procs, local data, exported procs, exported data, externals, imported
  data -- and counts each group. The caller writes the symbols; it does not
  decide who is in them.

  The data groups arrived with
  bug-a-an-object-neither-exports-nor-imports-data-symbols-and-links-silently-wrong:
  before them an object emitted no OBJECT symbol at all, so a defined global was
  invisible to the linker and an `extern` one was relocated into this object's
  OWN .bss -- two objects sharing a global linked cleanly and read different
  memory. }
var i: Integer;
begin
  strSize := 1;                { index 0 is the empty name }
  numLocalProcs := 0;
  numExportProcs := 0;
  numLocalData := 0;
  numExportData := 0;
  numImportData := 0;
  for i := 0 to ProcCount-1 do
    ObjProcStrOff[i] := -1;
  for i := 0 to SymCount-1 do
    ObjDataStrOff[i] := -1;
  for i := 0 to ProcCount-1 do
    if ObjProcIsDefined(i) and (not ObjProcIsExported(i)) then
    begin
      ObjProcStrOff[i] := strSize;
      strSize := strSize + Length(Procs[i].Name) + 1;
      Inc(numLocalProcs);
    end;
  { DATA joins in the three groups the symbol table emits it in, and the order
    below IS that layout. ELF requires every LOCAL before every GLOBAL with
    sh_info naming the first global, so local (static) data sits with the local
    procs ahead of firstGlobal, and the two global groups follow the exported
    procs. Both writers walk these same predicates in this same order; the
    counts returned here are what their index arithmetic is built on. }
  for i := 0 to SymCount-1 do
    if ObjDataIsLocal(i) then
    begin
      ObjDataStrOff[i] := strSize;
      strSize := strSize + Length(Syms[i].Name) + 1;
      Inc(numLocalData);
    end;
  for i := 0 to ProcCount-1 do
    if ObjProcIsDefined(i) and ObjProcIsExported(i) then
    begin
      ObjProcStrOff[i] := strSize;
      strSize := strSize + Length(Procs[i].Name) + 1;
      Inc(numExportProcs);
    end;
  for i := 0 to SymCount-1 do
    if ObjDataIsExport(i) then
    begin
      ObjDataStrOff[i] := strSize;
      strSize := strSize + Length(Syms[i].Name) + 1;
      Inc(numExportData);
    end;
  for i := 0 to ExternalCount-1 do
  begin
    ObjExtStrOff[i] := strSize;
    strSize := strSize + Length(ExternalLinkName(i)) + 1;
  end;
  { Imports last, and only those a relocation actually reaches -- an
    unreferenced UND asks the linker to resolve a name this object never uses. }
  for i := 0 to SymCount-1 do
    if ObjDataIsImport(i) and ObjDataIsReferenced(i) then
    begin
      ObjDataStrOff[i] := strSize;
      strSize := strSize + Length(Syms[i].Name) + 1;
      Inc(numImportData);
    end;
  if (numExportProcs = 0) and (numExportData = 0) then
    ErrorNoPos('--emit-obj: this object would define no linkable symbol, so nothing '
        + 'could ever link against it. A pxx object exports the routines '
        + 'declared with the C convention -- Pascal `cdecl`, or any function of '
        + 'a .c translation unit -- plus any file-scope variable a .c '
        + 'translation unit defines and any Pascal global marked `cvar` or '
        + '`public`. Mark what the object is for, or build an executable '
        + 'instead');
end;

procedure ObjCheckProcAddrBodies;
{ @proc on a bodiless routine, refused at the same point the ET_EXEC writers
  refuse it. In an object it would otherwise become a relocation with addend
  -1: a valid-looking entry pointing one byte below .text. }
var i: Integer;
begin
  for i := 0 to ProcAddrFixCount-1 do
    if Procs[ProcAddrFix[i].ProcIdx].BodyAddr < 0 then
      ErrorNoPos('@' + Procs[ProcAddrFix[i].ProcIdx].Name +
            ': the address of a routine with no body was taken');
end;

procedure writeELFRelX64General(const outPath: AnsiString);
var
  i: Integer;
  numLocalProcs, numExportProcs, numSyms, firstGlobal, extSym0: Integer;
  numLocalData, numExportData, numImportData, impSym0, dsym: Integer;
  textOff, dataOff, symOff, strOff, relaTextOff, relaDataOff: Integer;
  shstrOff, shOff, strSize: Integer;
  relaTextCount, relaDataCount: Integer;
  initArrOff, relaInitArrOff, finiArrOff, relaFiniArrOff: Integer;
  initArrSec, finiArrSec, numSects, shstrSize: Integer;
  initArrNm, relaInitArrNm, finiArrNm, relaFiniArrNm: Integer;
  hasInitArr, hasFiniArr: Boolean;
    nThunkSym, initThunkSym, finiThunkSym: Integer;
    thunkInitStrOff, thunkFiniStrOff, thunkNext: Integer;
{$ifdef FPC}
  f: File;
{$else}
  f: Integer;
{$endif}
begin
  { An INTERNAL assertion, not a user-facing refusal: compiler.pas only reaches
    here with TargetArch = TARGET_X86_64, and the refusal a user sees is the
    TargetHasObjectWriter one beside that dispatch. It still has to name the
    right set, because the next reader of this line takes it for a statement of
    fact -- and it was one: it said "i386 [...] ha[s] no object writer yet"
    while writeELFRel386General had existed for a day. Enumerate, do not
    assert. }
  if TargetArch <> TARGET_X86_64 then
    ErrorNoPos('--emit-obj: internal -- the general ELF64 object writer was '
        + 'reached with --target=' + TargetArchName(TargetArch)
        + ', and it is x86-64 only. Targets with a writer of any kind: '
        + EmitObjTargetList + '; each of the others reaches its own, not this '
        + 'one, so arriving here is a dispatch bug rather than a missing '
        + 'writer.');

  ObjCheckProcAddrBodies;
  ObjPlanHostedSymbols(strSize, numLocalProcs, numExportProcs,
                       numLocalData, numExportData, numImportData);

  { null + 3 section syms + local procs + local data | exported procs +
    exported data + external funcs + imported data. extSym0 moves by
    numExportData and impSym0 is new; every relocation that names a symbol
    index is built from these three. }
  { --function-sections: the init and fini thunks get LOCAL FUNC symbols of
    their own, so .rela.init_array/.rela.fini_array can name THEM with addend 0
    instead of `.text` plus a baked offset. They were the last two code
    references in the object still bound to the section symbol, and they cannot
    be left that way for per-function sections: each thunk falls INSIDE the
    range of whatever proc precedes it -- a different proc in every program --
    so a `.text + off` addend is a promise about a layout the linker is about
    to change.

    Gated, so the DEFAULT object is byte-identical: without the flag no symbol
    is added, firstGlobal does not move, and every index built from it is what
    it was. }
  nThunkSym := 0;
  if FunctionSections then
  begin
    if InitThunkOff >= 0 then Inc(nThunkSym);
    if FiniThunkOff >= 0 then Inc(nThunkSym);
  end;
  initThunkSym := -1; finiThunkSym := -1;
  thunkInitStrOff := 0; thunkFiniStrOff := 0;
  if nThunkSym > 0 then
  begin
    thunkNext := 4 + numLocalProcs + numLocalData;
    if InitThunkOff >= 0 then begin initThunkSym := thunkNext; Inc(thunkNext); end;
    if FiniThunkOff >= 0 then finiThunkSym := thunkNext;
    { The two names go at the END of .strtab, not beside their symbols. A string
      table is a blob addressed by explicit per-symbol offsets, so the order is
      free -- and appending is the only placement whose offset is knowable here,
      because ObjPlanHostedSymbols returns a TOTAL and not a running position.
      The SYMBOLS still sit between the local data and the first global, which
      is the part firstGlobal cares about. }
    if InitThunkOff >= 0 then
    begin
      thunkInitStrOff := strSize;
      strSize := strSize + Length(OBJ_INIT_THUNK_NAME) + 1;
    end;
    if FiniThunkOff >= 0 then
    begin
      thunkFiniStrOff := strSize;
      strSize := strSize + Length(OBJ_FINI_THUNK_NAME) + 1;
    end;
  end;

  firstGlobal := 4 + numLocalProcs + numLocalData + nThunkSym;
  extSym0 := firstGlobal + numExportProcs + numExportData;
  impSym0 := extSym0 + ExternalCount;
  numSyms := impSym0 + numImportData;

  ObjPlanHostedProcSymIdx(numLocalProcs, numLocalData, nThunkSym);

  relaTextCount := FixCount + GlobFixCount + DynCallCount + ProcAddrFixCount;
  { --function-sections: one PC32 per internal call, against the callee's own
    FUNC symbol. Counted with the same predicate that emits them, so the header
    and the body cannot disagree about how many there are -- a mismatch here
    writes a section whose size does not match its contents, which readelf
    reports as a truncated file rather than as anything naming this feature. }
  for i := 0 to CallFixCount-1 do
    if ObjCallFixIsRelocatable(i) then Inc(relaTextCount);
  relaDataCount := DataPtrFixCount + MethodFixCount + ExternalCount;

  textOff := ELF_HEADER_SIZE;                    { 64, already 8-aligned }
  dataOff := AlignTo(textOff + CodeLen, 16);
  symOff  := AlignTo(dataOff + DataLen, 8);
  strOff  := symOff + numSyms * 24;
  relaTextOff := AlignTo(strOff + strSize, 8);
  relaDataOff := relaTextOff + relaTextCount * 24;

  { .init_array / .fini_array exist only when a frontend emitted the thunks --
    which today means --emit-obj on x86-64 through the C frontend, and --shared.
    See the header comment for the exact scope of "unchanged": it is narrower
    than it first reads, and the first control I ran for it was vacuous. }
  hasInitArr := InitThunkOff >= 0;
  hasFiniArr := FiniThunkOff >= 0;
  initArrSec := -1;
  finiArrSec := -1;
  numSects := 9;
  if hasInitArr then begin initArrSec := numSects; numSects := numSects + 2; end;
  if hasFiniArr then begin finiArrSec := numSects; numSects := numSects + 2; end;

  { Names are appended to the 66-byte base blob only for sections that EXIST, so
    an object without initialisers is byte-for-byte the file it was before this
    feature. That property is worth four conditional sums: the first version of
    this wrote all four names unconditionally to keep the offsets constant, and
    the A/B caught it -- every object grew 58 bytes and e_shoff moved, which is a
    change to every consumer of every object for the benefit of objects that do
    not use the feature. 12 = len('.init_array')+1, 17 = len('.rela.init_array')+1. }
  shstrSize := 66;
  initArrNm := 0; relaInitArrNm := 0; finiArrNm := 0; relaFiniArrNm := 0;
  if hasInitArr then
  begin
    initArrNm := shstrSize; relaInitArrNm := shstrSize + 12;
    shstrSize := shstrSize + 29;
  end;
  if hasFiniArr then
  begin
    finiArrNm := shstrSize; relaFiniArrNm := shstrSize + 12;
    shstrSize := shstrSize + 29;
  end;

  { Every offset here is already 8-aligned: relaDataOff is, 24 and 8 preserve
    it, so the array sections need no padding of their own. }
  initArrOff     := relaDataOff + relaDataCount * 24;
  relaInitArrOff := initArrOff;
  if hasInitArr then relaInitArrOff := initArrOff + 8;
  finiArrOff := relaInitArrOff;
  if hasInitArr then finiArrOff := relaInitArrOff + 24;
  relaFiniArrOff := finiArrOff;
  if hasFiniArr then relaFiniArrOff := finiArrOff + 8;
  shstrOff := relaFiniArrOff;
  if hasFiniArr then shstrOff := relaFiniArrOff + 24;
  shOff := AlignTo(shstrOff + shstrSize, 8);

{$ifdef FPC}
  Assign(f, outPath); Rewrite(f, 1);
{$else}
  AssignPath := outPath;
  f := sysopen(AssignPath, 577); { O_WRONLY | O_CREAT | O_TRUNC }
{$endif}

  { ELF64 ehdr (64 bytes), ET_REL, EM_X86_64 }
  writeU8(f,$7F);writeU8(f,$45);writeU8(f,$4C);writeU8(f,$46);
  writeU8(f,2);writeU8(f,1);writeU8(f,1);writeU8(f,0);  { class 64, LE, v1 }
  writeU8(f,0);writeU8(f,0);writeU8(f,0);writeU8(f,0);
  writeU8(f,0);writeU8(f,0);writeU8(f,0);writeU8(f,0);
  writeU16(f,1);writeU16(f,62);writeU32(f,1);           { ET_REL, EM_X86_64 }
  writeU64(f,0);writeU64(f,0);writeU64(f,shOff);        { entry, phoff, shoff }
  writeU32(f,0);                                        { e_flags }
  writeU16(f,ELF_HEADER_SIZE);writeU16(f,0);writeU16(f,0);
  writeU16(f,64);writeU16(f,numSects);writeU16(f,8); { shentsize, shnum, shstrndx }

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
  writeSym64(f, 0, 0, 0, 0, 0);
  writeSym64(f, 0, 3, 1, 0, 0);   { STT_SECTION .text }
  writeSym64(f, 0, 3, 3, 0, 0);   { STT_SECTION .data }
  writeSym64(f, 0, 3, 5, 0, 0);   { STT_SECTION .bss }
  for i := 0 to ProcCount-1 do
    if ObjProcIsDefined(i) and (not ObjProcIsExported(i)) then
      writeSym64(f, ObjProcStrOff[i], $02, 1, Procs[i].BodyAddr, ObjProcSize(i));
  { LOCAL data ($01 = LOCAL OBJECT), shndx 5 = .bss. A `static` file-scope
    variable must never become an export -- it is the control that catches a
    pass which simply exports everything. }
  for i := 0 to SymCount-1 do
    if ObjDataIsLocal(i) then
      writeSym64(f, ObjDataStrOff[i], $01, 5, Syms[i].Offset, SymAllocSize[i]);
  { The thunk symbols, if any: LOCAL FUNC ($02) in .text, between the local
    data and the first global so firstGlobal describes them. SIZE 0 ON PURPOSE
    -- a thunk is code no proc owns and its extent is recorded nowhere, so
    stating one would be inventing it. That is a real limit for a later
    --gc-sections, which wants a size; it is none for a relocation, which wants
    an address. }
  if initThunkSym >= 0 then
    writeSym64(f, thunkInitStrOff, $02, 1, InitThunkOff, 0);
  if finiThunkSym >= 0 then
    writeSym64(f, thunkFiniStrOff, $02, 1, FiniThunkOff, 0);
  for i := 0 to ProcCount-1 do
    if ObjProcIsDefined(i) and ObjProcIsExported(i) then
      writeSym64(f, ObjProcStrOff[i], Byte(ObjProcBind(i) or 2), 1, Procs[i].BodyAddr, ObjProcSize(i));
  { EXPORTED data ($11 = GLOBAL OBJECT). A tentative definition is a definition
    (C 6.9.2) and lands here with the rest -- and as a real .bss OBJECT, not
    SHN_COMMON, which is -fno-common semantics and matches gcc 10 and later. }
  for i := 0 to SymCount-1 do
    if ObjDataIsExport(i) then
      writeSym64(f, ObjDataStrOff[i], ObjDataExportInfo(i), 5, Syms[i].Offset, SymAllocSize[i]);
  for i := 0 to ExternalCount-1 do
    writeSym64(f, ObjExtStrOff[i], $10, 0, 0, 0);  { GLOBAL NOTYPE UNDEF }
  { IMPORTED data ($10 = GLOBAL NOTYPE, shndx 0 = UND, value 0, size 0). The
    size lives on the DEFINITION in another TU -- `extern char b[];` carries
    none -- so emitting anything but 0 here would be inventing it. }
  for i := 0 to SymCount-1 do
    if ObjDataIsImport(i) and ObjDataIsReferenced(i) then
      writeSym64(f, ObjDataStrOff[i], $10, 0, 0, 0);

  { .strtab, in the same order }
  writeU8(f, 0);
  for i := 0 to ProcCount-1 do
    if ObjProcIsDefined(i) and (not ObjProcIsExported(i)) then writeStrZ(f, Procs[i].Name);
  for i := 0 to SymCount-1 do
    if ObjDataIsLocal(i) then writeStrZ(f, Syms[i].Name);
  for i := 0 to ProcCount-1 do
    if ObjProcIsDefined(i) and ObjProcIsExported(i) then writeStrZ(f, Procs[i].Name);
  for i := 0 to SymCount-1 do
    if ObjDataIsExport(i) then writeStrZ(f, Syms[i].Name);
  for i := 0 to ExternalCount-1 do writeStrZ(f, ExternalLinkName(i));
  for i := 0 to SymCount-1 do
    if ObjDataIsImport(i) and ObjDataIsReferenced(i) then writeStrZ(f, Syms[i].Name);
  if initThunkSym >= 0 then writeStrZ(f, OBJ_INIT_THUNK_NAME);
  if finiThunkSym >= 0 then writeStrZ(f, OBJ_FINI_THUNK_NAME);
  writePad(f, relaTextOff - (strOff + strSize));

  { .rela.text. Section syms: 1 = .text, 2 = .data, 3 = .bss.
    R_X86_64_64 = 1, R_X86_64_32S = 11. }
  for i := 0 to FixCount-1 do
    { rtype 1 = R_X86_64_64 (absolute), 2 = R_X86_64_PC32 for the lea form }
    if FixupPCRel[i] then
      writeRela64(f, Fixups[i].CodePos, 2, 2, Fixups[i].DataOff - 4)
    else
      writeRela64(f, Fixups[i].CodePos, 2, 1, Fixups[i].DataOff);
  for i := 0 to GlobFixCount-1 do
  begin
    { A data-resident global (a typed const baked into .data) carries a BIASED
      offset; SymOffIsData is the one decode point for all of them.
      UNREACHABLE TODAY, DELIBERATELY, AND NOT DEAD: the promotion that creates
      such a global bails out under EmitObjMode (symtab.inc, `if EmitObjMode or
      EmitSharedMode then Exit`) precisely because an object writer must name a
      SECTION rather than patch an address, and no writer did. This arm is that
      missing half for x86-64 -- so lifting the refusal here is a symtab
      question, not a writer one. Do not "simplify" it away on the evidence
      that no object reaches it; that evidence is the refusal, not the shape of
      the data. (The ELF32 sibling still reads the offset raw, which is correct
      only while that refusal stands.) }
    { rtype 11 = R_X86_64_32S (absolute), 2 = R_X86_64_PC32. A PC32 addend is
      relative to the address AFTER the field, so it carries the -4 PLUS any
      instruction bytes that trail the displacement -- which is what
      GlobFixTrail[i] holds, per site.

      This comment used to say "measured across 1271 sites, no site on this
      path has bytes trailing the field, so the correction is -4 everywhere and
      never -8", three lines above the code that adds GlobFixTrail. That census
      was taken over objects built WITHOUT --threadsafe and the shape lives in
      lock code, so the population could not contain it; believing it cost a
      hang in test_multithreading. The same false claim was asserted in
      emit.inc (fixed in 3156ac887) -- this was its third copy. Do not restore
      it. }
    { An IMPORTED global must relocate against ITS OWN SYMBOL, not against this
      object's .bss. Relocating it section-relative is the defect this whole
      ticket is named for: the link succeeds, and the program reads a private
      slot in the importing object instead of the definition. dsym < 0 means
      "not an import", which is every reference in an executable and every
      reference to a global this TU defines, so the old paths below are
      unchanged for them.

      The addend is 0, not the slot offset: an UND symbol has no value yet, and
      the linker supplies it. The PC32 correction still applies. }
    dsym := ObjDataSymIndexForOff(GlobFix[i].BSSoff);
    if dsym >= 0 then
      dsym := impSym0 + ObjDataImportOrdinal(dsym)
    else
    begin
      { An EXPORTED definition names its own symbol for the mirror-image
        reason -- see ObjDataExportSymForOff. Addend 0 either way: an import's
        value comes from the linker, an export's from its own st_value, and
        adding this object's .bss offset on top of either is the same wrong
        address. }
      dsym := ObjDataExportSymForOff(GlobFix[i].BSSoff);
      if dsym >= 0 then
        dsym := firstGlobal + numExportProcs + ObjDataExportOrdinal(dsym);
    end;
    if dsym >= 0 then
    begin
      if GlobFixPCRel[i] then
        writeRela64(f, GlobFix[i].CodePos, dsym, 2, -4 - GlobFixTrail[i])
      else
        writeRela64(f, GlobFix[i].CodePos, dsym, 11, 0);
    end
    else if GlobFixPCRel[i] then
    begin
      if SymOffIsData(GlobFix[i].BSSoff) then
        writeRela64(f, GlobFix[i].CodePos, 2, 2,
                    SymOffDataPart(GlobFix[i].BSSoff) - 4 - GlobFixTrail[i])
      else
        writeRela64(f, GlobFix[i].CodePos, 3, 2,
                    GlobFix[i].BSSoff - 4 - GlobFixTrail[i]);
    end
    else if SymOffIsData(GlobFix[i].BSSoff) then
      writeRela64(f, GlobFix[i].CodePos, 2, 11, SymOffDataPart(GlobFix[i].BSSoff))
    else
      writeRela64(f, GlobFix[i].CodePos, 3, 11, GlobFix[i].BSSoff);
  end;
  { `call qword ptr [abs32]` / `mov rax,[abs32]`: the operand names OUR GOT
    slot in .data, not the callee. The slot's own relocation is in .rela.data. }
  for i := 0 to DynCallCount-1 do
    { `call qword ptr [rip+disp32]` naming our own GOT slot in .data: PC32, so
      the addend carries the -4 to the end of the instruction. }
    writeRela64(f, DynCallCodePos[i], 2, 2, ExternalGotOff[DynCallExtIdx[i]] - 4);
  { @proc: the `mov rax, imm64` operand, absolute against .text }
  { @proc: `lea rax,[rip+disp32]` against .text -- PC32 (rtype 2), addend
    carrying the -4 to the end of the instruction. It was R_X86_64_64 against
    an absolute code address, the last absolute relocation .text emitted. }
  { --function-sections names the CALLEE'S symbol with the standard rel32 bias
    instead, so the linker computes S + (-4) - P. RELA carries its addend
    explicitly and ignores the bytes already in .text, so both spellings resolve
    to the same address in a link that keeps this object's copy -- which is what
    makes the byte-identity check below a real test rather than a tautology. }
  for i := 0 to ProcAddrFixCount-1 do
    if ObjProcRefIsRelocatable(ProcAddrFix[i].ProcIdx) then
      writeRela64(f, ProcAddrFix[i].CodePos,
                  ObjProcSymIdx[ProcAddrFix[i].ProcIdx], 2, -4)
    else
      writeRela64(f, ProcAddrFix[i].CodePos, 1, 2,
                  Procs[ProcAddrFix[i].ProcIdx].BodyAddr - 4);

  { --function-sections: the internal calls, LAST in .rela.text so the entries
    above keep the file offsets they had. addend -4 is the standard rel32 bias,
    so the linker computes S + (-4) - P -- exactly the displacement
    ApplyCallFixups baked. RELA carries its addend explicitly and IGNORES the
    bytes already sitting in .text, so the two agree by construction and the
    LINKED binary must be byte-identical with the flag on and off. That identity
    is how this step is verified: on its own it has no observable effect, and a
    step with no observable effect can only be checked by proving it changed
    nothing. }
  for i := 0 to CallFixCount-1 do
    if ObjCallFixIsRelocatable(i) then
      writeRela64(f, CallFix[i].CodePos, ObjProcSymIdx[CallFix[i].ProcIdx], 2, -4);
  ObjReportFunctionSections;

  { .rela.data: data->data pointers, data->code method slots, and one
    R_X86_64_64 per external GOT slot against that extern's UND symbol. }
  for i := 0 to DataPtrFixCount-1 do
    writeRela64(f, DataPtrFix[i].DataPos, 2, 1, DataPtrFix[i].TargetOff);
  { A VMT slot is R_X86_64_64 -- an absolute address, addend 0 against the
    method's own symbol under --function-sections, where it was `.text` plus the
    body offset. }
  for i := 0 to MethodFixCount-1 do
    if ObjProcRefIsRelocatable(MethodFixups[i].ProcIdx) then
      writeRela64(f, MethodFixups[i].DataPos,
                  ObjProcSymIdx[MethodFixups[i].ProcIdx], 1, 0)
    else
      writeRela64(f, MethodFixups[i].DataPos, 1, 1,
                  Procs[MethodFixups[i].ProcIdx].BodyAddr);
  for i := 0 to ExternalCount-1 do
    writeRela64(f, ExternalGotOff[i], extSym0 + i, 1, 0);

  { .init_array / .fini_array: ONE 8-byte slot each, whose VALUE is supplied by
    the relocation rather than by these bytes. The slot is written as zero
    because an ET_REL object states addresses only through relocations -- .text
    has no address yet, so "the address of the init thunk" can only be
    (section .text) + InitThunkOff, which is exactly what an R_X86_64_64 against
    the .text section symbol says. Symbol 1 is that section symbol, the same one
    the method-slot fixups above relocate against. }
  if hasInitArr then
  begin
    writeU64(f, 0);
    if initThunkSym >= 0 then writeRela64(f, 0, initThunkSym, 1, 0)
    else writeRela64(f, 0, 1, 1, InitThunkOff);
  end;
  if hasFiniArr then
  begin
    writeU64(f, 0);
    if finiThunkSym >= 0 then writeRela64(f, 0, finiThunkSym, 1, 0)
    else writeRela64(f, 0, 1, 1, FiniThunkOff);
  end;

  { .shstrtab: 66-byte base blob, plus 29 bytes per array pair that exists. }
  writeU8(f, 0);
  writeStrZ(f, '.text');            { 1 }
  writeStrZ(f, '.rela.text');       { 7 }
  writeStrZ(f, '.data');            { 18 }
  writeStrZ(f, '.rela.data');       { 24 }
  writeStrZ(f, '.bss');             { 35 }
  writeStrZ(f, '.symtab');          { 40 }
  writeStrZ(f, '.strtab');          { 48 }
  writeStrZ(f, '.shstrtab');        { 56 }
  if hasInitArr then
  begin
    writeStrZ(f, '.init_array');
    writeStrZ(f, '.rela.init_array');
  end;
  if hasFiniArr then
  begin
    writeStrZ(f, '.fini_array');
    writeStrZ(f, '.rela.fini_array');
  end;
  writePad(f, shOff - (shstrOff + shstrSize));

  { shdrs. $40 = SHF_INFO_LINK on rela sections; 6 = ALLOC|EXEC, 3 = ALLOC|WRITE. }
  writeShdrA64(f, 0, 0, 0, 0, 0);
  writeShdrB64(f, 0, 0, 0, 0);
  writeShdrA64(f, 1, 1, 6, textOff, CodeLen);
  writeShdrB64(f, 0, 0, 16, 0);
  writeShdrA64(f, 7, 4, $40, relaTextOff, relaTextCount*24);
  writeShdrB64(f, 6, 1, 8, 24);
  writeShdrA64(f, 18, 1, 3, dataOff, DataLen);
  writeShdrB64(f, 0, 0, 16, 0);
  writeShdrA64(f, 24, 4, $40, relaDataOff, relaDataCount*24);
  writeShdrB64(f, 6, 3, 8, 24);
  writeShdrA64(f, 35, 8, 3, dataOff + DataLen, BSSSize);
  writeShdrB64(f, 0, 0, 16, 0);
  writeShdrA64(f, 40, 2, 0, symOff, numSyms*24);
  writeShdrB64(f, 7, firstGlobal, 8, 24);
  writeShdrA64(f, 48, 3, 0, strOff, strSize);
  writeShdrB64(f, 0, 0, 1, 0);
  writeShdrA64(f, 56, 3, 0, shstrOff, shstrSize);
  writeShdrB64(f, 0, 0, 1, 0);
  { 14 = SHT_INIT_ARRAY, 15 = SHT_FINI_ARRAY, flags 3 = ALLOC|WRITE. entsize 8
    because the linker concatenates these section-wise into one array. The rela
    sections link to .symtab (6) and INFO to the array section they patch. }
  if hasInitArr then
  begin
    writeShdrA64(f, initArrNm, 14, 3, initArrOff, 8);
    writeShdrB64(f, 0, 0, 8, 8);
    writeShdrA64(f, relaInitArrNm, 4, $40, relaInitArrOff, 24);
    writeShdrB64(f, 6, initArrSec, 8, 24);
  end;
  if hasFiniArr then
  begin
    writeShdrA64(f, finiArrNm, 15, 3, finiArrOff, 8);
    writeShdrB64(f, 0, 0, 8, 8);
    writeShdrA64(f, relaFiniArrNm, 4, $40, relaFiniArrOff, 24);
    writeShdrB64(f, 6, finiArrSec, 8, 24);
  end;

{$ifdef FPC}
  Close(f);
{$else}
  sysfchmod(f, 420); { chmod 644 -- a .o is not executable }
  sysclose(f);
{$endif}
end;


{ ===== General i386 relocatable object writer =====
  feature-a-object-output-for-i386-arm32-and-aarch64, under
  meta-a-pxx-produces-linkable-code.

  The ELF32/i386 twin of writeELFRelX64General, and it exists for a reason
  beyond symmetry: **i386 is the target that can settle the C-ABI convention.**
  x86-64 never diverged, so an x86-64 object proves the machinery and answers
  nothing; i386, arm32 and aarch64 did. A gcc -m32 caller linking one of these
  turns decide-does-a-c-function-always-use-the-c-abi from an argument into a
  measurement.

  IT SHARES THE POLICY AND NOT THE FORMAT. ObjPlanHostedSymbols decides the
  export surface for both, so the two cannot drift -- if they disagreed about
  what an object exports, the i386 link would be measuring the writer instead of
  the ABI. Everything below it is format, and the format genuinely differs.

  WHY THIS IS NOT writeELF32Rel WITH `machine := 3`. That writer serves
  freestanding ESP firmware, and two of its choices are wrong here:

    - it exports `app_main` and makes every proc LOCAL, which is the right
      surface for an IDF image and defines nothing a linker can use;
    - it relocates each external DIRECTLY at a .text literal slot, because both
      ESP backends reach an external through a literal holding its address.
      i386 does not: it emits `call dword [abs32]` through a GOT slot the
      compiler allocates in its OWN .data (RegisterExternal), exactly like
      x86-64. That needs TWO relocations -- the operand against .data with the
      slot offset as addend, and the slot itself against the extern -- and a
      writer that emits only the first produces an object that links cleanly and
      jumps to zero.

  RELOCATION FORM: SHT_REL, not SHT_RELA, and every type is R_386_32 (1). The
  i386 psABI has no addend field; gcc, clang and tcc all emit `.rel.text` for
  -m32. So each addend is patched into Code[]/Data[] BEFORE the sections are
  written -- the backend left zeros at every one of these sites, so patching
  them is a fill, not an overwrite.

  Absolute, therefore `-no-pie`, for the same reason as x86-64 and one more
  besides: on i386 even a PIE build of ordinary C uses a GOT, and none of our
  operands are PC-relative.

  File layout (written sequentially; the self-hosted writer cannot seek):
  ehdr, .text, .data, .symtab, .strtab, .rel.text, .rel.data, .shstrtab,
  section headers. Sections (9): 0 null, 1 .text, 2 .rel.text, 3 .data,
  4 .rel.data, 5 .bss, 6 .symtab, 7 .strtab, 8 .shstrtab. }

function Rel386Type(pcRel: Boolean): Integer;
{ R_386_PC32 (2) or R_386_32 (1). The whole difference between an object that
  takes `-Wl,-z,text` and one that forces a writable .text, in one place so the
  four fixup arrays cannot disagree. }
begin
  if pcRel then Rel386Type := 2 else Rel386Type := 1;
end;

procedure writeELFRel386General(const outPath: AnsiString);
var
  i: Integer;
  numLocalProcs, numExportProcs, numSyms, firstGlobal, extSym0: Integer;
  numLocalData, numExportData, numImportData, impSym0, dsym: Integer;
  textOff, dataOff, symOff, strOff, relTextOff, relDataOff: Integer;
  shstrOff, shOff, strSize: Integer;
  relTextCount, relDataCount: Integer;
  initArrOff, relInitArrOff, finiArrOff, relFiniArrOff: Integer;
  initArrSec, finiArrSec, numSects, shstrSize: Integer;
  initArrNm, relInitArrNm, finiArrNm, relFiniArrNm: Integer;
  hasInitArr, hasFiniArr: Boolean;
{$ifdef FPC}
  f: File;
{$else}
  f: Integer;
{$endif}
begin
  if TargetArch <> TARGET_I386 then
    ErrorNoPos('--emit-obj: the general ELF32/i386 object writer is i386 only');

  ObjCheckProcAddrBodies;
  ObjPlanHostedSymbols(strSize, numLocalProcs, numExportProcs,
                       numLocalData, numExportData, numImportData);

  { null + 3 section syms + local procs + local data | exported procs +
    exported data + external funcs + imported data. extSym0 moves by
    numExportData and impSym0 is new; every relocation that names a symbol
    index is built from these three. }
  firstGlobal := 4 + numLocalProcs + numLocalData;
  extSym0 := firstGlobal + numExportProcs + numExportData;
  impSym0 := extSym0 + ExternalCount;
  numSyms := impSym0 + numImportData;

  relTextCount := FixCount + GlobFixCount + DynCallCount + ProcAddrFixCount;
  relDataCount := DataPtrFixCount + MethodFixCount + ExternalCount;

  { SHT_REL addends, written into the bytes the relocation covers. Every site
    below holds zero from the backend, so this fills rather than overwrites --
    and the values are the SAME ones the ELF64 writer passes as explicit
    r_addend, which is the property to preserve if either side is ever
    changed. }
  { A PC-RELATIVE site needs a DIFFERENT addend from the absolute one beside it,
    and it is not a constant. The linker stores S + A - P; the instruction wants
    (S + symOffset) - anchorAddr, where anchorAddr is the address the body's
    `call/pop` pushed. P is the field's own address, so

        A = symOffset + (fieldPos - anchorPos)

    and the backend recorded (fieldPos - anchorPos) per site as *PicDelta when it
    rewrote the operand. It is per-SITE, not per-body: two references from the
    same body sit at different distances past the one anchor. PicDelta is 0 on
    every absolute site, so the two arms below could be one expression -- they
    are kept apart because reading `+ PicDelta` on a row typed R_386_32 would
    suggest the addend has a PC term there, and it must not. }
  for i := 0 to FixCount-1 do
    if FixupPCRel[i] then
      Patch32(Fixups[i].CodePos, Fixups[i].DataOff + FixupPicDelta[i])
    else
      Patch32(Fixups[i].CodePos, Fixups[i].DataOff);
  for i := 0 to GlobFixCount-1 do
  begin
    { REL carries no addend field, so the in-place code word IS the addend. For
      an IMPORT it must be 0 (plus the PC-relative correction), never this
      object's own .bss offset -- writing the offset here while naming the
      import's symbol in .rel.text would resolve to the definition PLUS a
      private offset, which is a wrong address that still links.
      The x86-64 twin puts the same 0 in the RELA addend field. }
    if ObjDataRelocIsSymbolic(GlobFix[i].BSSoff) then
    begin
      if GlobFixPCRel[i] then
        Patch32(GlobFix[i].CodePos, GlobFixPicDelta[i])
      else
        Patch32(GlobFix[i].CodePos, 0);
    end
    else if SymOffIsData(GlobFix[i].BSSoff) then
    begin
      if GlobFixPCRel[i] then
        Patch32(GlobFix[i].CodePos, SymOffDataPart(GlobFix[i].BSSoff) + GlobFixPicDelta[i])
      else
        Patch32(GlobFix[i].CodePos, SymOffDataPart(GlobFix[i].BSSoff));
    end
    else
    begin
      if GlobFixPCRel[i] then
        Patch32(GlobFix[i].CodePos, GlobFix[i].BSSoff + GlobFixPicDelta[i])
      else
        Patch32(GlobFix[i].CodePos, GlobFix[i].BSSoff);
    end;
  end;
  for i := 0 to DynCallCount-1 do
    if DynCallPCRel[i] then
      Patch32(DynCallCodePos[i], ExternalGotOff[DynCallExtIdx[i]] + DynCallPicDelta[i])
    else
      Patch32(DynCallCodePos[i], ExternalGotOff[DynCallExtIdx[i]]);
  for i := 0 to ProcAddrFixCount-1 do
    if ProcAddrPCRel[i] then
      Patch32(ProcAddrFix[i].CodePos, Procs[ProcAddrFix[i].ProcIdx].BodyAddr + ProcAddrPicDelta[i])
    else
      Patch32(ProcAddrFix[i].CodePos, Procs[ProcAddrFix[i].ProcIdx].BodyAddr);
  { The .data slots are 8 bytes wide (the layout is shared with the 64-bit
    targets); R_386_32 covers the low dword and the high dword stays zero,
    which is what a 32-bit pointer read of the slot sees. }
  for i := 0 to DataPtrFixCount-1 do
    PatchDataU64(DataPtrFix[i].DataPos, DataPtrFix[i].TargetOff);
  for i := 0 to MethodFixCount-1 do
    PatchDataU64(MethodFixups[i].DataPos, Procs[MethodFixups[i].ProcIdx].BodyAddr);
  for i := 0 to ExternalCount-1 do
    PatchDataU64(ExternalGotOff[i], 0);

  textOff := ELF32_HEADER_SIZE;                  { 52, already 4-aligned }
  dataOff := AlignTo(textOff + CodeLen, 8);
  symOff  := AlignTo(dataOff + DataLen, 4);
  strOff  := symOff + numSyms * 16;
  relTextOff := AlignTo(strOff + strSize, 4);
  relDataOff := relTextOff + relTextCount * 8;

  { .init_array / .fini_array, the i386 twin of the x86-64 writer's. Same shape,
    three differences that are all the psABI and none of them cosmetic: entries
    are 4 bytes not 8, the relocation is R_386_32 (1) against the .text section
    symbol, and SHT_REL carries NO addend field -- so the thunk offset is written
    into the section BYTES and the relocation only says "add .text here".
    bug-a-an-i386-emit-obj-object-still-never-runs-its-initialisers }
  hasInitArr := InitThunkOff >= 0;
  hasFiniArr := FiniThunkOff >= 0;
  initArrSec := -1;
  finiArrSec := -1;
  numSects := 9;
  if hasInitArr then begin initArrSec := numSects; numSects := numSects + 2; end;
  if hasFiniArr then begin finiArrSec := numSects; numSects := numSects + 2; end;

  { Names appended only for sections that exist, so an object without a thunk is
    byte-identical to what this writer produced before. 12 = len('.init_array')+1,
    16 = len('.rel.init_array')+1 -- REL, not RELA: one byte shorter than the
    x86-64 twin's, which is exactly the kind of constant that gets copied. }
  shstrSize := 64;
  initArrNm := 0; relInitArrNm := 0; finiArrNm := 0; relFiniArrNm := 0;
  if hasInitArr then
  begin
    initArrNm := shstrSize; relInitArrNm := shstrSize + 12;
    shstrSize := shstrSize + 28;
  end;
  if hasFiniArr then
  begin
    finiArrNm := shstrSize; relFiniArrNm := shstrSize + 12;
    shstrSize := shstrSize + 28;
  end;

  initArrOff    := relDataOff + relDataCount * 8;
  relInitArrOff := initArrOff;
  if hasInitArr then relInitArrOff := initArrOff + 4;
  finiArrOff := relInitArrOff;
  if hasInitArr then finiArrOff := relInitArrOff + 8;
  relFiniArrOff := finiArrOff;
  if hasFiniArr then relFiniArrOff := finiArrOff + 4;
  shstrOff := relFiniArrOff;
  if hasFiniArr then shstrOff := relFiniArrOff + 8;
  shOff := AlignTo(shstrOff + shstrSize, 4);

{$ifdef FPC}
  Assign(f, outPath); Rewrite(f, 1);
{$else}
  AssignPath := outPath;
  f := sysopen(AssignPath, 577); { O_WRONLY | O_CREAT | O_TRUNC }
{$endif}

  { ELF32 ehdr (52 bytes), ET_REL, EM_386 }
  writeU8(f,$7F);writeU8(f,$45);writeU8(f,$4C);writeU8(f,$46);
  writeU8(f,1);writeU8(f,1);writeU8(f,1);writeU8(f,0);  { class 32, LE, v1 }
  writeU8(f,0);writeU8(f,0);writeU8(f,0);writeU8(f,0);
  writeU8(f,0);writeU8(f,0);writeU8(f,0);writeU8(f,0);
  writeU16(f,1);writeU16(f,3);writeU32(f,1);            { ET_REL, EM_386 }
  writeU32(f,0);writeU32(f,0);writeU32(f,shOff);        { entry, phoff, shoff }
  writeU32(f,0);                                        { e_flags }
  writeU16(f,ELF32_HEADER_SIZE);writeU16(f,0);writeU16(f,0);
  writeU16(f,40);writeU16(f,numSects);writeU16(f,8); { shentsize, shnum, shstrndx }

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
    if ObjProcIsDefined(i) and (not ObjProcIsExported(i)) then
      writeSym32(f, ObjProcStrOff[i], Procs[i].BodyAddr, ObjProcSize(i), $02, 1);
  { The data groups, in the same order and by the same predicates as the x86-64
    writer -- the policy is shared, so these six loops are the FORMAT half of
    one decision taken in ObjPlanHostedSymbols. If only one writer emitted them
    the counts that writer returns would no longer describe the table it wrote,
    which is exactly the truncated object this loop was added to fix. }
  for i := 0 to SymCount-1 do
    if ObjDataIsLocal(i) then
      writeSym32(f, ObjDataStrOff[i], Syms[i].Offset, SymAllocSize[i], $01, 5);
  for i := 0 to ProcCount-1 do
    if ObjProcIsDefined(i) and ObjProcIsExported(i) then
      writeSym32(f, ObjProcStrOff[i], Procs[i].BodyAddr, ObjProcSize(i), Byte(ObjProcBind(i) or 2), 1);
  for i := 0 to SymCount-1 do
    if ObjDataIsExport(i) then
      writeSym32(f, ObjDataStrOff[i], Syms[i].Offset, SymAllocSize[i], ObjDataExportInfo(i), 5);
  for i := 0 to ExternalCount-1 do
    writeSym32(f, ObjExtStrOff[i], 0, 0, $10, 0);  { GLOBAL NOTYPE UNDEF }
  for i := 0 to SymCount-1 do
    if ObjDataIsImport(i) and ObjDataIsReferenced(i) then
      writeSym32(f, ObjDataStrOff[i], 0, 0, $10, 0);

  { .strtab, in the same order }
  writeU8(f, 0);
  for i := 0 to ProcCount-1 do
    if ObjProcIsDefined(i) and (not ObjProcIsExported(i)) then writeStrZ(f, Procs[i].Name);
  for i := 0 to SymCount-1 do
    if ObjDataIsLocal(i) then writeStrZ(f, Syms[i].Name);
  for i := 0 to ProcCount-1 do
    if ObjProcIsDefined(i) and ObjProcIsExported(i) then writeStrZ(f, Procs[i].Name);
  for i := 0 to SymCount-1 do
    if ObjDataIsExport(i) then writeStrZ(f, Syms[i].Name);
  for i := 0 to ExternalCount-1 do writeStrZ(f, ExternalLinkName(i));
  for i := 0 to SymCount-1 do
    if ObjDataIsImport(i) and ObjDataIsReferenced(i) then writeStrZ(f, Syms[i].Name);
  writePad(f, relTextOff - (strOff + strSize));

  { .rel.text. Section syms: 1 = .text, 2 = .data, 3 = .bss.

    TWO types now: R_386_32 = 1 (absolute) and R_386_PC32 = 2 (relative to the
    PC-anchored base in esi). A site is relative exactly when the emitter marked
    it so, which is the SAME flag pair x86-64 already uses for its rip form --
    reused rather than duplicated, because a second parallel notion of "this
    fixup is relative" is how the two x86-64 arms came to disagree once already.

    This reads False for every i386 site until the addressing conversion sets
    it, so landing it is inert.
    bug-a-an-i386-object-from-the-c-frontend-carries-text-relocations }
  { FOUR ARRAYS, ONE QUESTION. Each of Fixups/GlobFix/DynCall/ProcAddrFix carries
    its own PCRel flag, so the relocation TYPE is chosen in four places; Rel386Type
    is the one place that answers it. The arm added second is the one that stays
    wrong, and there are already four (frankA, 2026-09-01). }
  for i := 0 to FixCount-1 do
    writeRel32(f, Fixups[i].CodePos, 2, Rel386Type(FixupPCRel[i]));
  for i := 0 to GlobFixCount-1 do
  begin
    { An IMPORTED global relocates against its OWN symbol here too. REL (not
      RELA) carries no addend field, so the addend already sits in the code
      word: Patch32 below writes it, and for an import that must be 0 rather
      than this object's private .bss offset -- the linker supplies the address.
      Getting only one of the two right is the silent-wrong-read bug again. }
    dsym := ObjDataSymIndexForOff(GlobFix[i].BSSoff);
    if dsym >= 0 then dsym := impSym0 + ObjDataImportOrdinal(dsym)
    else
    begin
      dsym := ObjDataExportSymForOff(GlobFix[i].BSSoff);
      if dsym >= 0 then
        dsym := firstGlobal + numExportProcs + ObjDataExportOrdinal(dsym);
    end;
    if dsym >= 0 then
      writeRel32(f, GlobFix[i].CodePos, dsym, Rel386Type(GlobFixPCRel[i]))
    else if SymOffIsData(GlobFix[i].BSSoff) then
    begin
      writeRel32(f, GlobFix[i].CodePos, 2, Rel386Type(GlobFixPCRel[i]));
    end
    else
    begin
      writeRel32(f, GlobFix[i].CodePos, 3, Rel386Type(GlobFixPCRel[i]));
    end;
  end;
  { `call dword [abs32]`: the operand names OUR GOT slot in .data, not the
    callee. The slot's own relocation is in .rel.data below. }
  for i := 0 to DynCallCount-1 do
    writeRel32(f, DynCallCodePos[i], 2, Rel386Type(DynCallPCRel[i]));
  for i := 0 to ProcAddrFixCount-1 do
    writeRel32(f, ProcAddrFix[i].CodePos, 1, Rel386Type(ProcAddrPCRel[i]));

  { .rel.data: data->data pointers, data->code method slots, and one entry per
    external GOT slot against that extern's UND symbol. }
  for i := 0 to DataPtrFixCount-1 do
    writeRel32(f, DataPtrFix[i].DataPos, 2, 1);
  for i := 0 to MethodFixCount-1 do
    writeRel32(f, MethodFixups[i].DataPos, 1, 1);
  for i := 0 to ExternalCount-1 do
    writeRel32(f, ExternalGotOff[i], extSym0 + i, 1);

  { .init_array / .fini_array contents. Unlike the x86-64 twin, the slot is NOT
    zero: SHT_REL has no addend field, so the thunk's code offset lives in these
    four bytes and the relocation supplies only the .text base. Writing zero
    here -- the x86-64 habit -- yields a null pointer the C runtime calls. }
  if hasInitArr then
  begin
    writeU32(f, InitThunkOff);
    writeRel32(f, 0, 1, 1);          { R_386_32 vs the .text section symbol }
  end;
  if hasFiniArr then
  begin
    writeU32(f, FiniThunkOff);
    writeRel32(f, 0, 1, 1);
  end;

  { .shstrtab: 64-byte base blob, plus 28 bytes per array pair that exists. }
  writeU8(f, 0);
  writeStrZ(f, '.text');        { 1 }
  writeStrZ(f, '.rel.text');    { 7 }
  writeStrZ(f, '.data');        { 17 }
  writeStrZ(f, '.rel.data');    { 23 }
  writeStrZ(f, '.bss');         { 33 }
  writeStrZ(f, '.symtab');      { 38 }
  writeStrZ(f, '.strtab');      { 46 }
  writeStrZ(f, '.shstrtab');    { 54 }
  if hasInitArr then
  begin
    writeStrZ(f, '.init_array');
    writeStrZ(f, '.rel.init_array');
  end;
  if hasFiniArr then
  begin
    writeStrZ(f, '.fini_array');
    writeStrZ(f, '.rel.fini_array');
  end;
  writePad(f, shOff - (shstrOff + shstrSize));

  { shdrs. SHT_REL = 9, entsize 8. $40 = SHF_INFO_LINK; 6 = ALLOC|EXEC,
    3 = ALLOC|WRITE, 8 = SHT_NOBITS for .bss. }
  writeShdrA(f, 0, 0, 0, 0, 0);
  writeShdrB(f, 0, 0, 0, 0);
  writeShdrA(f, 1, 1, 6, textOff, CodeLen);
  writeShdrB(f, 0, 0, 16, 0);
  writeShdrA(f, 7, 9, $40, relTextOff, relTextCount*8);
  writeShdrB(f, 6, 1, 4, 8);
  writeShdrA(f, 17, 1, 3, dataOff, DataLen);
  writeShdrB(f, 0, 0, 8, 0);
  writeShdrA(f, 23, 9, $40, relDataOff, relDataCount*8);
  writeShdrB(f, 6, 3, 4, 8);
  writeShdrA(f, 33, 8, 3, dataOff + DataLen, BSSSize);
  writeShdrB(f, 0, 0, 8, 0);
  writeShdrA(f, 38, 2, 0, symOff, numSyms*16);
  writeShdrB(f, 7, firstGlobal, 4, 16);
  writeShdrA(f, 46, 3, 0, strOff, strSize);
  writeShdrB(f, 0, 0, 1, 0);
  writeShdrA(f, 54, 3, 0, shstrOff, shstrSize);
  writeShdrB(f, 0, 0, 1, 0);
  { 14 = SHT_INIT_ARRAY, 15 = SHT_FINI_ARRAY, flags 3 = ALLOC|WRITE, entsize 4.
    The rel sections link to .symtab (6) and INFO to the array they patch. }
  if hasInitArr then
  begin
    writeShdrA(f, initArrNm, 14, 3, initArrOff, 4);
    writeShdrB(f, 0, 0, 4, 4);
    writeShdrA(f, relInitArrNm, 9, $40, relInitArrOff, 8);
    writeShdrB(f, 6, initArrSec, 4, 8);
  end;
  if hasFiniArr then
  begin
    writeShdrA(f, finiArrNm, 15, 3, finiArrOff, 4);
    writeShdrB(f, 0, 0, 4, 4);
    writeShdrA(f, relFiniArrNm, 9, $40, relFiniArrOff, 8);
    writeShdrB(f, 6, finiArrSec, 4, 8);
  end;

{$ifdef FPC}
  Close(f);
{$else}
  sysfchmod(f, 420); { chmod 644 -- a .o is not executable }
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
    ErrorNoPos('--emit-obj: .asm frontend object output is x86-64 only');

  { THIS WRITER IS THE .asm FRONTEND'S, AND THE DISPATCH SENDS IT EVERYTHING.

    Read what it emits below: `.text`, a symbol per `global <label>` from the
    .asm frontend (AsmGlobalSym*), the UND externs, and one relocation per
    `call <extern>` (AsmObjCall*). There is no `.data`, no `.bss`, and no
    relocation kind for anything a compiler BACKEND produces. That is correct
    for a .asm source, where data is appended into Code[] and addressed as part
    of .text (`dataBase := CodeLen`, asmfront.inc) -- and it is why the guard
    below is about the program, not about the frontend.

    compiler.pas dispatches `--emit-obj` by ARCHITECTURE: x86-64 comes here,
    everything else to writeELF32Rel, which is the GENERAL object writer (procs
    as symbols, .data, .bss, .rela.data) and refuses anything but xtensa and
    riscv32. So a Pascal, C or NilPy program on x86-64 -- the DEFAULT target --
    landed here and this writer faithfully wrote everything it knew, which was
    nothing: 4 symbols, none of them defined, a zero-size .rela.text, no data
    and no bss, for a program with 132 procedures. The `ok:` line downstream
    then reported `data=2864B bss=42332B procs=132` about a file containing
    none of it.

    There is no general x86-64 relocatable writer to route those programs to.
    Until there is (feature-a-a-general-x86-64-relocatable-object-writer), REFUSE
    -- an unlinkable object reported as success is strictly worse than an error,
    because the failure surfaces at someone else's link step with no cause
    attached. The test is what the object would have to CARRY, so a .asm source
    that only needs text, globals and extern calls still works exactly as before.
    bug-a-emit-obj-on-x86-64-produces-an-object-with-no-symbols-data-or-relocations }
  if (BSSSize > 0) or (FixCount > 0) or (GlobFixCount > 0) or
     (DataPtrFixCount > 0) or (MethodFixCount > 0) or (ProcAddrFixCount > 0) then
    ErrorNoPos('--emit-obj: this program needs a general relocatable object (data, '
        + 'bss or backend relocations) and the x86-64 object writer only '
        + 'handles .asm-frontend output (text, global labels, extern calls). '
        + 'Emitting one would silently drop them. Build an executable instead, '
        + 'or use --target=xtensa/riscv32 --platform=esp for object output');
  if (AsmGlobalSymCount = 0) and (ProcCount > 0) then
    ErrorNoPos('--emit-obj: the x86-64 object writer exports symbols only for .asm '
        + '`global` labels, so this object would define nothing and could not '
        + 'be linked against');

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
    strSize := strSize + Length(ExternalLinkName(i)) + 1;
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
  for i := 0 to ExternalCount - 1 do writeStrZ(f, ExternalLinkName(i));
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
  fromAsm: Boolean;
  expCount, relCount, memSize, bssBase: Integer;
  shstrOff, shstrSize, shOff, sIdx: Integer;
  shName, shType, shFlags, shOffs, shSize, shLink, shInfo, shAlign, shEnt:
    array[0..9] of Int64;
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
    ErrorNoPos('--shared: shared-library output is x86-64 only');

  { WHICH FRONTEND PRODUCED THIS. AsmGlobalSymCount is nonzero only when
    ParseAsmProgram populated it, so it is the .asm shape's own signature --
    the same discriminator writeELFRelX64General uses to pick a writer, and
    deliberately not TargetArch, which sent every compiled program into a
    writer that could describe none of it.

    The two differ in exactly three things -- where the export list comes
    from, whether there is a .bss, and whether Data[] holds absolute pointers
    needing R_X86_64_RELATIVE. Everything after this is written once, over an
    export list built here, rather than branched at each use: the .asm and
    compiled paths disagreeing about their own symbol table is precisely the
    drift this writer cannot afford. }
  fromAsm := AsmGlobalSymCount > 0;

  { .dynstr: 0 = empty, then export names, then import (extern) names }
  dynstrSize := 1;
  expCount := 0;
  if fromAsm then
    for i := 0 to AsmGlobalSymCount - 1 do
    begin
      strOffExport[i] := dynstrSize;
      dynstrSize := dynstrSize + Length(AsmGlobalSymName[i]) + 1;
      Inc(expCount);
    end
  else
  begin
    { Same export surface as an object: the C-convention routines, under their
      own names. ObjProcStrOff is reused as the per-proc name offset, so a
      compiled .so and a compiled .o cannot disagree about who is exported. }
    for i := 0 to ProcCount-1 do
      ObjProcStrOff[i] := -1;
    for i := 0 to ProcCount-1 do
      if ObjProcIsDefined(i) and ObjProcIsExported(i) then
      begin
        ObjProcStrOff[i] := dynstrSize;
        dynstrSize := dynstrSize + Length(Procs[i].Name) + 1;
        Inc(expCount);
      end;
    if expCount = 0 then
      ErrorNoPos('--shared: this library would export no symbol, so nothing could '
          + 'ever link or dlopen against it. A pxx shared library exports the '
          + 'routines declared with the C convention -- Pascal `cdecl`, or any '
          + 'function of a .c translation unit. Mark what the library is for, '
          + 'or build an executable instead');
    ObjCheckProcAddrBodies;
  end;

  dynCount := expCount + ExternalCount;
  numDynSyms := dynCount + 1;   { + null symbol }

  { Absolute pointers that live IN .data: data->data (DataPtrFix) and the
    data->code method slots (MethodFixups). Code no longer contributes any --
    it is all rip-relative since
    feature-a-x86-64-object-output-is-position-dependent -- so these are the
    only things whose stored value depends on the load address, and each needs
    one R_X86_64_RELATIVE. The .asm frontend produces neither. }
  if fromAsm then relCount := 0 else relCount := DataPtrFixCount + MethodFixCount;
  for i := 0 to ExternalCount - 1 do
  begin
    strOffImport[i] := dynstrSize;
    dynstrSize := dynstrSize + Length(ExternalLinkName(i)) + 1;
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
    DT_RELASZ, DT_RELAENT, DT_RELACOUNT, DT_NULL -- 10 fixed entries,
    Elf64_Dyn = 16 bytes -- plus DT_INIT and DT_FINI when the frontend emitted
    thunks for them. COUNTED FROM THE SAME CONDITION that writes them below,
    not from a second reading of it: this size decides where .dynstr lands, so a
    count that disagrees with the writes by one entry moves every following
    section by 16 bytes and the library loads with a shredded string table. }
  dynamicSize := (neededCount + 10) * 16;
  if InitThunkOff >= 0 then Inc(dynamicSize, 16);
  if FiniThunkOff >= 0 then Inc(dynamicSize, 16);

  phOff := ELF_HEADER_SIZE;
  textOff := phOff + 3 * PROG_HEADER_SIZE;   { PT_LOAD + PT_DYNAMIC + PT_GNU_STACK }
  dataOff := AlignTo(textOff + CodeLen, 8);
  dynstrOff := dataOff + DataLen;
  dynsymOff := AlignTo(dynstrOff + dynstrSize, 8);
  hashOff := dynsymOff + numDynSyms * 24;
  relaDynOff := AlignTo(hashOff + hashSize, 8);
  dynamicOff := relaDynOff + (relCount + ExternalCount) * 24;
  fileSize := dynamicOff + dynamicSize;

  { .bss lives past the end of the file: the PT_LOAD's memsz exceeds its filesz
    and the kernel zero-fills the difference. Placing it last is what keeps
    vaddr = file offset for everything that IS in the file, which the rest of
    this writer assumes everywhere (st_value, DT_*, every rip displacement).
    The .asm frontend has no .bss, and BSSSize is 0 for it. }
  { SECTION HEADERS. A running loader never reads them -- it works off program
    headers, which is why the .asm --shared output has managed without any --
    but `ld` REFUSES a shared object that has none: linking `prog.c ./lib.so`
    gives "file in wrong format", while dlopen of the same file succeeds. So
    they are what separates a dlopen-able artefact from a linkable library.
    69 bytes of names, then ten Elf64_Shdr. }
  shstrOff := fileSize;
  shstrSize := 69;
  shOff := AlignTo(shstrOff + shstrSize, 8);
  fileSize := shOff + 10 * 64;

  { .bss lives past the end of the file: the PT_LOAD's memsz exceeds its filesz
    and the kernel zero-fills the difference. Placing it last is what keeps
    vaddr = file offset for everything that IS in the file, which the rest of
    this writer assumes everywhere (st_value, DT_*, every rip displacement).
    The .asm frontend has no .bss, and BSSSize is 0 for it. }
  bssBase := AlignTo(fileSize, 16);
  memSize := bssBase + BSSSize;

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

  { A compiled source carries the backend's whole relocation inventory, so it
    needs the same pass an executable gets -- with BASE-0 addresses, because
    this image is loaded wherever the loader puts it and every rip-relative
    displacement is a DIFFERENCE, unchanged by the base. The absolute values
    this leaves in Data[] are the ones .rela.dyn then relocates.

    codeVA and entry are both textOff: entry differs from the code base only
    by AsmEntryOff, which belongs to the frontend that does not come here. }
  if not fromAsm then
    ApplyImageFixups(textOff, dataOff, bssBase, textOff);

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
  writeU64(f,0);writeU64(f,phOff);writeU64(f,shOff);    { entry=0, phoff, shoff }
  writeU32(f,0);                                        { e_flags }
  writeU16(f,ELF_HEADER_SIZE);writeU16(f,PROG_HEADER_SIZE);writeU16(f,3);
  writeU16(f,64);writeU16(f,10);writeU16(f,9);  { shentsize, shnum, shstrndx }

  { PT_LOAD: whole file, RWX (same single-segment simplification the ET_EXEC
    writer already uses). }
  writeU32(f,1);writeU32(f,7);
  writeU64(f,0);writeU64(f,0);writeU64(f,0);
  { memsz > filesz: the tail is .bss, zero-filled by the kernel. }
  writeU64(f,fileSize);writeU64(f,memSize);writeU64(f,$200000);

  { PT_DYNAMIC }
  writeU32(f,2);writeU32(f,6);
  writeU64(f,dynamicOff);writeU64(f,dynamicOff);writeU64(f,dynamicOff);
  writeU64(f,dynamicSize);writeU64(f,dynamicSize);writeU64(f,8);

  { PT_GNU_STACK (RW, no X): without it a modern kernel refuses to dlopen this
    .so at all, since the absent header defaults to "requires an executable
    stack" (bug-elf-missing-pt-gnu-stack). }
  writeU32(f,$6474E551);writeU32(f,6);
  writeU64(f,0);writeU64(f,0);writeU64(f,0);
  writeU64(f,0);writeU64(f,0);writeU64(f,$10);

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
  if fromAsm then
    for i := 0 to AsmGlobalSymCount - 1 do writeStrZ(f, AsmGlobalSymName[i])
  else
    for i := 0 to ProcCount-1 do
      if ObjProcStrOff[i] >= 0 then writeStrZ(f, Procs[i].Name);
  for i := 0 to ExternalCount - 1 do writeStrZ(f, ExternalLinkName(i));
  for i := 0 to neededCount - 1 do writeStrZ(f, Strs[neededLibStr[i]].Text);
  writePad(f, dynsymOff - (dynstrOff + dynstrSize));

  { .dynsym: null, then export syms (defined -- st_value is a real virtual
    address here, base 0 so textOff+offset-into-Code[]; shndx=1 is a
    placeholder, there is no real section header table to match it against
    -- what matters for dynamic symbol resolution is shndx<>SHN_UNDEF and
    st_value), then import syms (UND). }
  writeSym64(f, 0, 0, 0, 0, 0);
  if fromAsm then
    for i := 0 to AsmGlobalSymCount - 1 do
      writeSym64(f, strOffExport[i], $10, 1, textOff + AsmGlobalSymOff[i], 0)
  else
    { $12 = GLOBAL FUNC, where the .asm labels are $10 GLOBAL NOTYPE: these are
      known to be routines and their size is known, so say so. A dlsym'd NOTYPE
      resolves fine, but the type and st_size are what every disassembler and
      profiler reads. }
    for i := 0 to ProcCount-1 do
      if ObjProcStrOff[i] >= 0 then
        writeSym64(f, ObjProcStrOff[i], $12, 1,
                   textOff + Procs[i].BodyAddr, ObjProcSize(i));
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
  { R_X86_64_RELATIVE (type 8) FIRST, because DT_RELACOUNT below tells the
    loader the first N entries are exactly these and it may take a fast path
    over them. With RELA the loader stores (load_base + addend) and ignores
    what is in the slot, so the addend is the base-0 address ApplyImageFixups
    already computed. }
  if not fromAsm then
  begin
    for i := 0 to DataPtrFixCount-1 do
      writeRela64(f, dataOff + DataPtrFix[i].DataPos, 0, 8,
                  dataOff + DataPtrFix[i].TargetOff);
    for i := 0 to MethodFixCount-1 do
      writeRela64(f, dataOff + MethodFixups[i].DataPos, 0, 8,
                  textOff + Procs[MethodFixups[i].ProcIdx].BodyAddr);
  end;
  for i := 0 to ExternalCount - 1 do
    writeRela64(f, dataOff + ExternalGotOff[i], 1 + expCount + i, 6, 0);

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
  writeU64(f, 8); writeU64(f, (relCount + ExternalCount) * 24); { DT_RELASZ }
  writeU64(f, 9); writeU64(f, 24);                   { DT_RELAENT }
  writeU64(f, $6ffffff9); writeU64(f, relCount);     { DT_RELACOUNT }
  { DT_INIT / DT_FINI -- the whole point of the thunks. A .so has no ELF entry
    point, so this is the ONLY way the loader can be told to run anything before
    a caller arrives; without them the initialisers sit in the image with
    nothing able to reach them (bug-a-c-a-shared-library-never-runs-its-
    initialisation). vaddr = file offset holds for everything IN the file in
    this layout, which is why a code offset plus textOff is the address. }
  if InitThunkOff >= 0 then
  begin
    writeU64(f, 12); writeU64(f, textOff + InitThunkOff);   { DT_INIT }
  end;
  if FiniThunkOff >= 0 then
  begin
    writeU64(f, 13); writeU64(f, textOff + FiniThunkOff);   { DT_FINI }
  end;
  writeU64(f, 0); writeU64(f, 0);                    { DT_NULL }

  { .shstrtab -- 69 bytes, and the offsets below are hand-counted against it.
    Written as one literal rather than assembled, so the two cannot drift. }
  writeU8(f, 0);
  writeStrZ(f, '.text');      {  1 }
  writeStrZ(f, '.data');      {  7 }
  writeStrZ(f, '.bss');       { 13 }
  writeStrZ(f, '.dynstr');    { 18 }
  writeStrZ(f, '.dynsym');    { 26 }
  writeStrZ(f, '.hash');      { 34 }
  writeStrZ(f, '.rela.dyn');  { 40 }
  writeStrZ(f, '.dynamic');   { 50 }
  writeStrZ(f, '.shstrtab');  { 59 }
  writePad(f, shOff - (shstrOff + shstrSize));

  { Ten Elf64_Shdr. sh_addr = sh_offset throughout, which is the whole reason
    this writer keeps vaddr equal to the file offset. .dynsym's sh_link is
    .dynstr and its sh_info is the index of the first non-local symbol -- 1,
    since only the null symbol is local; getting sh_info wrong makes ld treat
    the exports as locals and refuse to bind them. }
  shName[0]:=0;  shType[0]:=0;  shFlags[0]:=0; shOffs[0]:=0;          shSize[0]:=0;                          shLink[0]:=0; shInfo[0]:=0; shAlign[0]:=0;  shEnt[0]:=0;
  shName[1]:=1;  shType[1]:=1;  shFlags[1]:=6; shOffs[1]:=textOff;    shSize[1]:=CodeLen;                    shLink[1]:=0; shInfo[1]:=0; shAlign[1]:=16; shEnt[1]:=0;
  shName[2]:=7;  shType[2]:=1;  shFlags[2]:=3; shOffs[2]:=dataOff;    shSize[2]:=DataLen;                    shLink[2]:=0; shInfo[2]:=0; shAlign[2]:=8;  shEnt[2]:=0;
  shName[3]:=13; shType[3]:=8;  shFlags[3]:=3; shOffs[3]:=bssBase;    shSize[3]:=BSSSize;                    shLink[3]:=0; shInfo[3]:=0; shAlign[3]:=16; shEnt[3]:=0;
  shName[4]:=18; shType[4]:=3;  shFlags[4]:=2; shOffs[4]:=dynstrOff;  shSize[4]:=dynstrSize;                 shLink[4]:=0; shInfo[4]:=0; shAlign[4]:=1;  shEnt[4]:=0;
  shName[5]:=26; shType[5]:=11; shFlags[5]:=2; shOffs[5]:=dynsymOff;  shSize[5]:=numDynSyms * 24;            shLink[5]:=4; shInfo[5]:=1; shAlign[5]:=8;  shEnt[5]:=24;
  shName[6]:=34; shType[6]:=5;  shFlags[6]:=2; shOffs[6]:=hashOff;    shSize[6]:=hashSize;                   shLink[6]:=5; shInfo[6]:=0; shAlign[6]:=8;  shEnt[6]:=4;
  shName[7]:=40; shType[7]:=4;  shFlags[7]:=2; shOffs[7]:=relaDynOff; shSize[7]:=(relCount+ExternalCount)*24;shLink[7]:=5; shInfo[7]:=0; shAlign[7]:=8;  shEnt[7]:=24;
  shName[8]:=50; shType[8]:=6;  shFlags[8]:=3; shOffs[8]:=dynamicOff; shSize[8]:=dynamicSize;                shLink[8]:=4; shInfo[8]:=0; shAlign[8]:=8;  shEnt[8]:=16;
  shName[9]:=59; shType[9]:=3;  shFlags[9]:=0; shOffs[9]:=shstrOff;   shSize[9]:=shstrSize;                  shLink[9]:=0; shInfo[9]:=0; shAlign[9]:=1;  shEnt[9]:=0;
  for sIdx := 0 to 9 do
  begin
    writeU32(f, Integer(shName[sIdx])); writeU32(f, Integer(shType[sIdx]));
    writeU64(f, shFlags[sIdx]);
    { sh_addr: 0 for a non-allocated section, else the vaddr, which is the file
      offset in this base-0 image. }
    if shFlags[sIdx] = 0 then writeU64(f, 0) else writeU64(f, shOffs[sIdx]);
    writeU64(f, shOffs[sIdx]); writeU64(f, shSize[sIdx]);
    writeU32(f, Integer(shLink[sIdx])); writeU32(f, Integer(shInfo[sIdx]));
    writeU64(f, shAlign[sIdx]); writeU64(f, shEnt[sIdx]);
  end;

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
{$ifdef CPU_WASM32}
  { wasm has no syscall instruction, so __pxxrawsyscall (IR op 54) is the one
    node this target can never lower -- it was the LAST unlowerable body in
    compiler.pas. WASI spells the same operation fd_readdir, in a different
    record and with the walk position handed back to the caller as a cookie;
    PXXWasiGetDents translates both. The unit is in scope here because the
    demand scan pulls it for any wasm32 compilation containing a sys*
    intrinsic, which this file is full of. }
  Result := PXXWasiGetDents(fd, @buf, count);
{$else}
  Result := Integer(__pxxrawsyscall(217, fd, Int64(@buf), count, 0, 0, 0));
{$endif}
end;
{$endif}

{ THE directory scanner. Fills DirEntNames/DirEntCount with dir's entries
  ('.' and '..' dropped), and sets DirEntTruncated when there were more than
  MAX_DIRENT of them.

  One scanner, two callers (the case-insensitive path fallback below and
  `--list-libraries`), because a second copy of a getdents walk is exactly the
  duplicated path devdocs/dev/normalise-dont-special-case.md is about: the two
  would drift, and the one nobody runs is the one that breaks. The FPC arm
  exists because the seed build has no raw syscalls; both arms produce the same
  DirEntNames, so everything above this line is target-agnostic. }
procedure PxxListDir(const dir: AnsiString);
var scanDir, entry: AnsiString;
    fd, n, off, reclen: Integer;
{$ifdef FPC}
    sr: TSearchRec;
{$else}
    buf: array[0..4095] of Byte;
    b: Byte;
{$endif}
begin
  DirEntCount := 0;
  DirEntTruncated := False;
  scanDir := dir;
  if Length(scanDir) = 0 then scanDir := '.';
{$ifdef FPC}
  if FindFirst(scanDir + '/*', faAnyFile, sr) = 0 then
  begin
    repeat
      if (sr.Name <> '.') and (sr.Name <> '..') then
      begin
        if DirEntCount >= MAX_DIRENT then
          DirEntTruncated := True
        else
        begin
          DirEntNames[DirEntCount] := sr.Name;
          Inc(DirEntCount);
        end;
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
      { d_reclen at +16, the NUL-terminated d_name at +19 (d_type sits at +18) }
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
        if (entry <> '.') and (entry <> '..') then
        begin
          if DirEntCount >= MAX_DIRENT then
            DirEntTruncated := True
          else
          begin
            DirEntNames[DirEntCount] := entry;
            Inc(DirEntCount);
          end;
        end;
        off := off + reclen;
      end;
    end;
    n := sysgetdents64(fd, buf, 4096);
  end;
  sysclose(fd);
{$endif}
end;

{ 'lib/RTL/SysUtils.pas' -> 'lib/rtl/sysutils.pas', when EXACTLY ONE entry of
  the directory matches case-insensitively. Two matches is not a resolution: on
  a case-sensitive filesystem both are real files and picking either is a guess,
  so it stays unresolved. }
function ResolveCaseInsensitivePath(const path: AnsiString; var resolved: AnsiString): Boolean;
var dir, want, candidate: AnsiString;
    matches, i, off: Integer;
begin
  Result := False;
  resolved := path;
  dir := GetFilePath(path);
  want := '';
  if Length(path) = 0 then Exit;
  for off := Length(dir) + 1 to Length(path) do
    AppendChar(want, path[off]);
  if Length(want) = 0 then Exit;

  PxxListDir(dir);
  { A truncated scan cannot answer this: the one entry that matches may be the
    one past the cap, and "no match" would then read as "the file is missing"
    when it is a case mismatch we simply did not look at. }
  if DirEntTruncated then Exit;

  matches := 0;
  candidate := '';
  for i := 0 to DirEntCount - 1 do
  begin
    if CaseEqual(DirEntNames[i], want) then
    begin
      Inc(matches);
      if Length(dir) = 0 then
        candidate := DirEntNames[i]
      else
        ConcatThree(dir, DirEntNames[i], '', candidate);
    end;
  end;

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
            if depth >= 128 then ErrorNoPos('NormalizePath: path too deep');
            keptStart[depth] := segStart; keptLen[depth] := segLen;
            Inc(depth);
          end;
          { absolute path: '..' at the root is dropped }
        end
        else
        begin
          if depth >= 128 then ErrorNoPos('NormalizePath: path too deep');
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

procedure ExpandPasMacros(var src: AnsiString);
{ FPC MACRO-ON text macros: a dollar-define directive of the form
  "define name := replacement" splices the replacement wherever the bare
  identifier later appears (rtl-generics' generics.hashes builds its Jenkins
  mixers this way). Textual pre-pass, run AFTER ExpandIncludes on a unit's
  full source:

  - A macro BODY is flattened to one line (newlines -> spaces; Pascal is
    newline-insensitive) and the directive itself is blanked to spaces with
    its newlines kept, so LINE NUMBERS downstream are exactly preserved.
  - Strings, line comments, paren-star and (nested) brace comments are copied
    verbatim; plain dollar-directives pass through for the real lexer.
  - Macros are unit-scoped (the table resets per call, includes are already
    spliced in). No parameters, no recursive expansion — FPC's plain form.
  - The whole pass runs ONLY when the source contains a value-define (a
    dollar-define whose directive text has a := before it closes), so every
    other unit — including the self-host — passes through untouched.
  NOTE the doc comment avoids literal brace characters on purpose: see the
  nested-comment-brace self-host landmine. }
var
  mNames, mBodies: array[0..31] of AnsiString;
  mCount, i, j, k, n, mi, depth: Integer;
  res, w, cmd, body: AnsiString;
  c: Char;
  found, seen, nest: Boolean;
begin
  { cheap guard: any dollar-define whose directive text contains := ? }
  n := Length(src);
  seen := False;
  i := 1;
  while (i + 8 <= n) and (not seen) do
  begin
    if (src[i] = '{') and (src[i+1] = '$') and
       ((src[i+2] = 'd') or (src[i+2] = 'D')) then
    begin
      j := i + 2;
      w := '';
      while (j <= n) and (((src[j] >= 'a') and (src[j] <= 'z')) or
                          ((src[j] >= 'A') and (src[j] <= 'Z'))) do
      begin
        AppendChar(w, src[j]);
        Inc(j);
      end;
      if CaseEqual(w, 'define') then
        while (j <= n) and (src[j] <> '}') do
        begin
          if (src[j] = ':') and (j < n) and (src[j+1] = '=') then
          begin
            seen := True;
            Break;
          end;
          Inc(j);
        end;
    end;
    Inc(i);
  end;
  if not seen then Exit;

  mCount := 0;
  { Comment nesting is MODE-dependent and this pass runs before the lexer, so it
    must track the two directives that set it or it scans the wrong text as
    comment. Seeded from the ambient state the caller just set (pasparser_*.inc resets
    it per unit); the unit's own {$MODE} / {$NESTEDCOMMENTS} then apply below. }
  nest := NestedComments;
  res := '';
  i := 1;
  while i <= n do
  begin
    c := src[i];
    if c = '''' then
    begin
      { string literal ('it''s' scans as two adjacent strings — fine here) }
      AppendChar(res, c); Inc(i);
      while i <= n do
      begin
        AppendChar(res, src[i]);
        if src[i] = '''' then begin Inc(i); Break; end;
        Inc(i);
      end;
    end
    else if (c = '/') and (i < n) and (src[i+1] = '/') then
    begin
      while (i <= n) and (src[i] <> #10) do begin AppendChar(res, src[i]); Inc(i); end;
    end
    else if (c = '(') and (i < n) and (src[i+1] = '*') then
    begin
      AppendChar(res, src[i]); AppendChar(res, src[i+1]); i := i + 2;
      while i <= n do
      begin
        AppendChar(res, src[i]);
        if (src[i] = ')') and (src[i-1] = '*') then begin Inc(i); Break; end;
        Inc(i);
      end;
    end
    else if c = '{' then
    begin
      if (i < n) and (src[i+1] = '$') then
      begin
        j := i + 2;
        while (j <= n) and (src[j] = ' ') do Inc(j);
        w := '';
        while (j <= n) and (((src[j] >= 'a') and (src[j] <= 'z')) or
                            ((src[j] >= 'A') and (src[j] <= 'Z'))) do
        begin
          AppendChar(w, src[j]);
          Inc(j);
        end;
        cmd := w;
        found := False;
        if CaseEqual(w, 'define') then
        begin
          while (j <= n) and ((src[j] = ' ') or (src[j] = #9)) do Inc(j);
          w := '';
          while (j <= n) and (((src[j] >= 'a') and (src[j] <= 'z')) or
                              ((src[j] >= 'A') and (src[j] <= 'Z')) or
                              ((src[j] >= '0') and (src[j] <= '9')) or
                              (src[j] = '_')) do
          begin
            AppendChar(w, src[j]);
            Inc(j);
          end;
          while (j <= n) and ((src[j] = ' ') or (src[j] = #9) or (src[j] = #10) or (src[j] = #13)) do Inc(j);
          if (j < n) and (src[j] = ':') and (src[j+1] = '=') then
          begin
            j := j + 2;
            body := '';
            while (j <= n) and (src[j] <> '}') do
            begin
              if (src[j] = #10) or (src[j] = #13) then AppendChar(body, ' ')
              else AppendChar(body, src[j]);
              Inc(j);
            end;
            if j > n then ErrorNoPos('unterminated text-macro define directive');
            if mCount >= 32 then ErrorNoPos('too many text macros in one unit');
            mNames[mCount] := w;
            mBodies[mCount] := body;
            Inc(mCount);
            { blank the directive; keep its newlines so line numbers hold }
            for k := i to j do
              if (src[k] = #10) then AppendChar(res, #10) else AppendChar(res, ' ');
            i := j + 1;
            found := True;
          end;
        end;
        if not found then
        begin
          { {$MODE DELPHI} turns comment nesting OFF for the rest of the unit and
            {$NESTEDCOMMENTS} sets it directly -- the same two the lexer reads.
            rtl-generics is {$MODE DELPHI} and banners its sections with a brace
            comment whose SECOND line opens another brace, so under forced
            nesting every banner left the scanner "inside a comment" and no
            macro was expanded after the first one: HASH_FACTORY reached the
            parser as an undefined variable. }
          if CaseEqual(cmd, 'mode') or CaseEqual(cmd, 'nestedcomments') then
          begin
            while (j <= n) and ((src[j] = ' ') or (src[j] = #9)) do Inc(j);
            w := '';
            while (j <= n) and (((src[j] >= 'a') and (src[j] <= 'z')) or
                                ((src[j] >= 'A') and (src[j] <= 'Z'))) do
            begin
              AppendChar(w, src[j]);
              Inc(j);
            end;
            if CaseEqual(cmd, 'mode') then nest := not CaseEqual(w, 'delphi')
            else if CaseEqual(w, 'off') then nest := False
            else if CaseEqual(w, 'on') then nest := True;
          end;
          { any other directive: copy verbatim through its closing brace }
          while (i <= n) and (src[i] <> '}') do begin AppendChar(res, src[i]); Inc(i); end;
          if i <= n then begin AppendChar(res, src[i]); Inc(i); end;
        end;
      end
      else
      begin
        { Comment. Exactly the lexer's rule (lexer.inc, the brace arm): nest on
          an inner open-brace under NESTEDCOMMENTS, and ALWAYS on a
          directive-looking open-brace-dollar so prose quoting a directive keeps
          its close-brace from ending the comment early. Getting this wrong
          costs no text -- the comment is copied verbatim either way -- but it
          silently moves where macro expansion stops. }
        depth := 1;
        AppendChar(res, src[i]);
        Inc(i);
        while i <= n do
        begin
          AppendChar(res, src[i]);
          if (src[i] = '{') and (nest or ((i < n) and (src[i+1] = '$'))) then
            Inc(depth)
          else if src[i] = '}' then
          begin
            Dec(depth);
            if depth = 0 then begin Inc(i); Break; end;
          end;
          Inc(i);
        end;
      end;
    end
    else if ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) or (c = '_') then
    begin
      w := '';
      while (i <= n) and (((src[i] >= 'a') and (src[i] <= 'z')) or
                          ((src[i] >= 'A') and (src[i] <= 'Z')) or
                          ((src[i] >= '0') and (src[i] <= '9')) or
                          (src[i] = '_')) do
      begin
        AppendChar(w, src[i]);
        Inc(i);
      end;
      found := False;
      mi := 0;
      while (mi < mCount) and (not found) do
      begin
        if CaseEqual(w, mNames[mi]) then
        begin
          AppendString(res, mBodies[mi]);
          found := True;
        end;
        Inc(mi);
      end;
      if not found then AppendString(res, w);
    end
    else
    begin
      AppendChar(res, c);
      Inc(i);
    end;
  end;
  src := res;
end;

{ ===== -g line markers (Pascal include splice) ================================
  ExpandIncludes splices every `{$I}` into ONE buffer and the lexer numbers
  lines in that buffer, so `info line IRDump` answered "line 61871 of
  compiler.pas" — a real line of the 1001-line file's include-EXPANDED text,
  and the wrong file name for every routine that actually lives in an .inc.

  Same shape, and the same fix, as the C side's
  bug-c-dwarf-lines-index-the-preprocessed-text: emit gcc-style
  `# <line> "<path>"` markers at each splice boundary and let the lexer recover
  the origin (PasLexLineMarker in lexer.inc). Two markers per include — one
  entering the file at its line 1, one resuming the includer at the line after
  the directive — so a marker is an ABSOLUTE anchor and no drift accumulates
  between them.

  Emitted for any source that names itself by passing a non-empty selfPath.

  This was gated on -g until 2026-08-21, which meant that without -g every line
  number after an include was an offset into the SPLICED text and named no real
  line of any file: an error at globtype.pas:800 was reported as `pascal26:1103`
  in an 843-line file, the 303 being fpcdefs.inc's length. -g quietly fixed it,
  which is how it hid — the markers were built for DWARF and the diagnostics
  were getting them by accident. The C side has always emitted its markers
  unconditionally (cpreproc.inc), and this is the Pascal side catching up.
  bug-a-a-parse-error-in-a-used-unit-reports-a-line-in-no-file }
function IncSmallIntStr(n: Integer): AnsiString;
{ Decimal text of a small non-negative int. elfwriter.inc is included before
  cpreproc.inc, so its CPSmallIntStr twin is not in scope here, and this
  dialect surface has no IntToStr. }
var r: AnsiString;
begin
  if n <= 0 then begin IncSmallIntStr := '0'; Exit; end;
  r := '';
  while n > 0 do
  begin
    r := Chr(Ord('0') + (n mod 10)) + r;
    n := n div 10;
  end;
  IncSmallIntStr := r;
end;

procedure IncEmitLineMarker(const path: AnsiString; line: Integer);
{ Append `# <line> "<path>"` on a line of its own. The lexer does not count the
  marker's own newline, so a marker never shifts the numbering it just set. }
begin
  if (Length(IncExpanded) > 0) and (IncExpanded[Length(IncExpanded)] <> #10) then
    AppendChar(IncExpanded, #10);
  AppendString(IncExpanded, '# ');
  AppendString(IncExpanded, IncSmallIntStr(line));
  AppendString(IncExpanded, ' "');
  AppendString(IncExpanded, path);
  AppendString(IncExpanded, '"');
  AppendChar(IncExpanded, #10);
end;

procedure ExpandIncludes(var src: AnsiString; const baseDir, selfPath: AnsiString);
{ Replace active dollar-include directives with file contents, RECURSIVELY: an
  include inside an include is ordinary Pascal and FPC expands it, so we must
  too. Until 2026-08-20 this ran one level deep and a nested directive was left
  in the text, where the lexer skipped it as an unknown directive — a silent
  drop that compiled a DIFFERENT program than FPC did from the same source
  (bug-a-a-nested-include-is-silently-dropped).

  Recursion, not a re-scan of the result: the -g line markers name the file a
  line came from, and a second pass over already-spliced text would attribute
  the inner file's lines to the outer one. Recursing lets each file emit its own
  markers, which is why the splice below saves and restores the two module-level
  buffers rather than making the pass re-entrant on globals.

  Conditional directives remain in the text for the real lexer pass; this
  pre-pass only simulates enough state to avoid loading includes from inactive
  branches.

  selfPath is the path of `src` itself, used to name it in the -g line markers
  above. Pass '' to suppress markers entirely: a Pascal UNIT is deliberately
  left out of the line table (see the DbgMarkTokFile note in dbg_filetable.inc — the
  RTL would swamp it), and a marker is exactly what would opt it back in. }
var
  i, j, k, incDi, closePos, condCount, savedDefineCount, savedDefineCharLen: Integer;
  markLine, markPos: Integer;   { -g: line of src at markPos, both advance forward only }
  wantMarkers: Boolean;
  fname, command, name, exprSource: AnsiString;
  incNested, incDir, savedExpanded: AnsiString;   { see the recursive splice below }
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
  wantMarkers := Length(selfPath) > 0;
  markLine := 1;
  markPos := 1;
  { Name the source from its very first token, so a diagnostic in the text
    BEFORE any include still knows which file it is in. Without this the first
    range only starts at the first splice, and everything above it inherits
    whatever file was marked last — which, for a `uses`d unit, is the previous
    unit. Sets SrcLine := 1, which it already is, so numbering is untouched. }
  if wantMarkers then IncEmitLineMarker(selfPath, 1);
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
      if closePos > Length(src) then ErrorNoPos('unterminated Pascal directive during include expansion');

      if CaseEqual(command, 'ifdef') or CaseEqual(command, 'ifndef') or
         CaseEqual(command, 'if') or CaseEqual(command, 'ifopt') then
      begin
        if condCount >= MAX_PAS_CONDS then ErrorNoPos('include conditional nesting overflow');
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
        if condCount = 0 then ErrorNoPos('unexpected elseif directive during include expansion');
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
        if condCount = 0 then ErrorNoPos('unexpected else directive during include expansion');
        k := condCount - 1;
        condActive[k] := condParent[k] and not condTaken[k];
        condTaken[k] := True;
        active := condActive[k];
      end
      else if CaseEqual(command, 'endif') or CaseEqual(command, 'ifend') then
      begin
        if condCount = 0 then ErrorNoPos('unexpected endif directive during include expansion');
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
            ErrorNoPos('cannot open include file');
          end;
          { Expand the includes INSIDE this file before splicing it in. The
            recursive call reuses IncExpanded/IncIncluded (they are module-level
            buffers, not locals), so hand it copies and put ours back after. }
          incNested := IncIncluded;
          savedExpanded := IncExpanded;
          incDir := '';
          for k := Length(fullPath) downto 1 do
            if fullPath[k] = '/' then
            begin
              AppendRange(incDir, fullPath, 1, k);
              Break;
            end;
          if Length(incDir) = 0 then incDir := baseDir;
          Inc(IncExpandDepth);
          if IncExpandDepth > MAX_INC_DEPTH then
          begin
            ErrorIdent := fname;
            ErrorNoPos('include nesting too deep (circular include?)');
          end;
          if wantMarkers then
            ExpandIncludes(incNested, incDir, fullPath)
          else
            ExpandIncludes(incNested, incDir, '');
          Dec(IncExpandDepth);
          IncExpanded := savedExpanded;
          IncIncluded := incNested;
          if wantMarkers then
          begin
            { The included text starts at ITS line 1; afterwards the includer
              resumes at the line the directive's closing brace sits on. }
            IncEmitLineMarker(fullPath, 1);
            AppendString(IncExpanded, IncIncluded);
            while markPos <= j do
            begin
              if src[markPos] = #10 then Inc(markLine);
              Inc(markPos);
            end;
            IncEmitLineMarker(selfPath, markLine);
          end
          else
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
  if condCount <> 0 then ErrorNoPos('unterminated conditional directive during include expansion');
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
