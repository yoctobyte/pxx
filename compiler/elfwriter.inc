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

