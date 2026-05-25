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
    dataBase, bssBase, entry, filesz, memsz, addr: Int64;
begin
  dataBase := LOAD_ADDR + CODE_OFFSET + CodeLen;
  bssBase  := dataBase + DataLen;
  entry    := LOAD_ADDR + CODE_OFFSET;
  filesz   := CODE_OFFSET + CodeLen + DataLen;
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

  Assign(f, outPath); Rewrite(f, 1);

  writeU8(f,$7F);writeU8(f,$45);writeU8(f,$4C);writeU8(f,$46);
  writeU8(f,2);writeU8(f,1);writeU8(f,1);writeU8(f,0);
  writeU8(f,0);writeU8(f,0);writeU8(f,0);writeU8(f,0);
  writeU8(f,0);writeU8(f,0);writeU8(f,0);writeU8(f,0);
  writeU16(f,2);writeU16(f,62);writeU32(f,1);
  writeU64(f,entry);writeU64(f,64);writeU64(f,0);
  writeU32(f,0);writeU16(f,64);writeU16(f,56);
  writeU16(f,1);writeU16(f,64);writeU16(f,0);writeU16(f,0);

  writeU32(f,1);writeU32(f,7);  { PT_LOAD, RWX }
  writeU64(f,0);writeU64(f,LOAD_ADDR);writeU64(f,LOAD_ADDR);
  writeU64(f,filesz);writeU64(f,memsz);writeU64(f,$200000);

  if CodeLen > 0 then Blockwrite(f,Code[0],CodeLen);
  if DataLen > 0 then Blockwrite(f,Data[0],DataLen);
  Close(f);
  FpChmod(outPath,&755);
end;
{$else}
procedure writeELF(const outPath: AnsiString);
var f: Integer; i: Integer;
    dataBase, bssBase, entry, filesz, memsz, addr: Int64;
begin
  dataBase := LOAD_ADDR + CODE_OFFSET + CodeLen;
  bssBase  := dataBase + DataLen;
  entry    := LOAD_ADDR + CODE_OFFSET;
  filesz   := CODE_OFFSET + CodeLen + DataLen;
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

  AssignPath := outPath;
  f := sysopen(AssignPath, 577); { O_WRONLY | O_CREAT | O_TRUNC }

  writeU8(f,$7F);writeU8(f,$45);writeU8(f,$4C);writeU8(f,$46);
  writeU8(f,2);writeU8(f,1);writeU8(f,1);writeU8(f,0);
  writeU8(f,0);writeU8(f,0);writeU8(f,0);writeU8(f,0);
  writeU8(f,0);writeU8(f,0);writeU8(f,0);writeU8(f,0);
  writeU16(f,2);writeU16(f,62);writeU32(f,1);
  writeU64(f,entry);writeU64(f,64);writeU64(f,0);
  writeU32(f,0);writeU16(f,64);writeU16(f,56);
  writeU16(f,1);writeU16(f,64);writeU16(f,0);writeU16(f,0);

  writeU32(f,1);writeU32(f,7);  { PT_LOAD, RWX }
  writeU64(f,0);writeU64(f,LOAD_ADDR);writeU64(f,LOAD_ADDR);
  writeU64(f,filesz);writeU64(f,memsz);writeU64(f,$200000);

  if CodeLen > 0 then syswrite(f,Code,CodeLen);
  if DataLen > 0 then syswrite(f,Data,DataLen);
  sysfchmod(f, 493); { chmod 755 }
  sysclose(f);
end;
{$endif}

{$ifdef FPC}
procedure LoadFile(const path: AnsiString; var dst: AnsiString);
var f: File; n: Integer;
begin
  SetLength(dst, STRING_CAP);
  Assign(f, path);
  Reset(f, 1);
  BlockRead(f, dst[1], STRING_CAP, n);
  Close(f);
  SetLength(dst, n);
end;
{$else}
procedure LoadFile(const path: AnsiString; var dst: AnsiString);
begin
  { LoadFile is parsed as built-in instead }
end;
{$endif}

