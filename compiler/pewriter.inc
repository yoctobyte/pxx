{ pewriter.inc -- the PE32+ (Windows x64) executable writer, --os=windows.
  feature-port-windows-pe

  ONE IMAGE, LAID OUT LIKE THE ELF ONE. FileAlignment = SectionAlignment =
  4096, so a file offset IS an RVA: the headers fill page 0, .text starts at
  RVA $1000 exactly where writeELF puts the code (codeOffset), and .data
  follows the page-padded code at dataBase, as in writeELF. Every fixup is
  then resolved by the same ApplyImageFixups against ImageBase + RVA.

  NO BASE RELOCATIONS: the image is fixed at ImageBase ($400000) with
  IMAGE_FILE_RELOCS_STRIPPED, and DYNAMIC_BASE is not set, so the loader maps
  it there or refuses it. An EXE is the first thing mapped into its process,
  so the address is free in practice. ASLR (a .reloc section) is later work.

  IMPORTS: the GOT slots the x86-64 external call already reads through
  (`call [rip+slot]`) become the Import Address Table. PreparePEImports
  appends the IAT, the lookup tables, the hint/name entries and the import
  descriptors to Data[] and points ExternalGotOff at the IAT slots, so
  PatchDynCallSites needs no change. The RVA fields inside the block are
  patched once dataBase is known (PatchPEImports).

  THE STACK is committed whole (SizeOfStackCommit = SizeOfStackReserve).
  Windows grows a stack through a guard page one page at a time and pxx's
  frames do not probe (__chkstk): a frame over 4 KiB would jump the guard.
  With nothing left to grow, there is no guard to jump. }

const
  PE_IMAGE_STACK = 8 * 1024 * 1024;   { Linux's default RLIMIT_STACK; winabi's getrlimit agrees }
  PE_MAX_IMPORT_LIBS = 64;

var
  PeImportDirOff, PeImportDirSize: Integer;   { Data[] offset of the descriptor array }
  PeIatOff, PeIatSize: Integer;               { Data[] offset of the whole IAT }
  PeRvaFixPos: array of Integer;              { Data[] offsets holding an RVA to patch }
  PeRvaFixTgt: array of Integer;              { the Data[] offset each one names }
  PeRvaFixWide: array of Boolean;             { 8-byte (lookup/IAT entry) or 4-byte field }
  PeRvaFixCount: Integer;

procedure PeRvaFixAdd(pos, tgt: Integer; wide: Boolean);
begin
  if PeRvaFixCount >= Length(PeRvaFixPos) then
  begin
    SetLength(PeRvaFixPos, PeRvaFixCount * 2 + 64);
    SetLength(PeRvaFixTgt, PeRvaFixCount * 2 + 64);
    SetLength(PeRvaFixWide, PeRvaFixCount * 2 + 64);
  end;
  PeRvaFixPos[PeRvaFixCount] := pos;
  PeRvaFixTgt[PeRvaFixCount] := tgt;
  PeRvaFixWide[PeRvaFixCount] := wide;
  Inc(PeRvaFixCount);
end;

procedure PeDataAlign(n: Integer);
begin
  while (DataLen mod n) <> 0 do DataPutB(0);
end;

{ Group the externals by library and build the import block in Data[]. }
procedure PreparePEImports;
var
  libStr: array[0..PE_MAX_IMPORT_LIBS-1] of Integer;   { Strs[] index of each DLL name }
  libCount, i, j, l, iatPos, iltPos, descPos: Integer;
  libOfExt: array[0..MAX_EXTERNAL-1] of Integer;
  libIat, libIlt, libName: array[0..PE_MAX_IMPORT_LIBS-1] of Integer;
  hintOff: array[0..MAX_EXTERNAL-1] of Integer;
  found: Boolean;
begin
  PeRvaFixCount := 0;
  PeImportDirOff := 0; PeImportDirSize := 0;
  PeIatOff := 0; PeIatSize := 0;
  if ExternalCount = 0 then Exit;
  ResolveSynthImportLibraries;
  libCount := 0;
  for i := 0 to ExternalCount - 1 do
  begin
    found := False;
    for j := 0 to libCount - 1 do
      if libStr[j] = ProcLibrary[ExternalProc[i]] then
      begin
        libOfExt[i] := j; found := True; Break;
      end;
    if not found then
    begin
      if libCount >= PE_MAX_IMPORT_LIBS then
        ErrorNoPos('--os=windows: more than 64 imported DLLs');
      libStr[libCount] := ProcLibrary[ExternalProc[i]];
      libOfExt[i] := libCount;
      Inc(libCount);
    end;
  end;

  { The IAT: one run per DLL, each ending in a zero entry. The loader writes
    the resolved addresses here, and these are the slots the calls read. }
  PeDataAlign(8);
  PeIatOff := DataLen;
  for l := 0 to libCount - 1 do
  begin
    libIat[l] := DataLen;
    for i := 0 to ExternalCount - 1 do
      if libOfExt[i] = l then
      begin
        ExternalGotOff[i] := DataLen;
        DataPutU64(0);
      end;
    DataPutU64(0);
  end;
  PeIatSize := DataLen - PeIatOff;

  { The import lookup tables: the same shape, never overwritten. }
  for l := 0 to libCount - 1 do
  begin
    libIlt[l] := DataLen;
    for i := 0 to ExternalCount - 1 do
      if libOfExt[i] = l then DataPutU64(0);
    DataPutU64(0);
  end;

  { The descriptors, then a zero one. }
  PeImportDirOff := DataLen;
  for l := 0 to libCount - 1 do
  begin
    descPos := DataLen;
    DataPutU32(0); DataPutU32(0); DataPutU32(0); DataPutU32(0); DataPutU32(0);
    PeRvaFixAdd(descPos, libIlt[l], False);        { OriginalFirstThunk }
    PeRvaFixAdd(descPos + 16, libIat[l], False);   { FirstThunk }
    libName[l] := descPos + 12;                    { Name: patched below }
  end;
  for i := 1 to 20 do DataPutB(0);
  PeImportDirSize := DataLen - PeImportDirOff;

  { Hint/name entries (hint 0: the loader then searches by name), 2-aligned. }
  for i := 0 to ExternalCount - 1 do
  begin
    PeDataAlign(2);
    hintOff[i] := DataLen;
    DataPutU16(0);
    DataPutZ(ExternalLinkName(i));
  end;
  { DLL names }
  for l := 0 to libCount - 1 do
  begin
    PeRvaFixAdd(libName[l], DataLen, False);
    DataPutZ(Strs[libStr[l]].Text);
  end;
  PeDataAlign(8);

  { Both tables name the same hint/name entry for each import. }
  for l := 0 to libCount - 1 do
  begin
    iatPos := libIat[l];
    iltPos := libIlt[l];
    for i := 0 to ExternalCount - 1 do
      if libOfExt[i] = l then
      begin
        PeRvaFixAdd(iatPos, hintOff[i], True);
        PeRvaFixAdd(iltPos, hintOff[i], True);
        Inc(iatPos, 8);
        Inc(iltPos, 8);
      end;
  end;
end;

procedure PatchPEImports(dataRva: Int64);
var i: Integer;
begin
  for i := 0 to PeRvaFixCount - 1 do
    if PeRvaFixWide[i] then
      PatchDataU64(PeRvaFixPos[i], dataRva + PeRvaFixTgt[i])
    else
      PatchDataI32(PeRvaFixPos[i], Integer(dataRva + PeRvaFixTgt[i]));
end;

procedure PeHdrU8(var h: array of Byte; pos, v: Integer);
begin
  h[pos] := v and $FF;
end;

procedure PeHdrU16(var h: array of Byte; pos, v: Integer);
begin
  h[pos] := v and $FF;
  h[pos + 1] := (v shr 8) and $FF;
end;

procedure PeHdrU32(var h: array of Byte; pos: Integer; v: Int64);
begin
  h[pos] := v and $FF;
  h[pos + 1] := (v shr 8) and $FF;
  h[pos + 2] := (v shr 16) and $FF;
  h[pos + 3] := (v shr 24) and $FF;
end;

procedure PeHdrU64(var h: array of Byte; pos: Integer; v: Int64);
begin
  PeHdrU32(h, pos, v and $FFFFFFFF);
  PeHdrU32(h, pos + 4, (v shr 32) and $FFFFFFFF);
end;

procedure PeHdrName(var h: array of Byte; pos: Integer; const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do h[pos + i - 1] := Ord(s[i]);
end;

procedure writePE(const outPath: AnsiString);
const
  PAGE = 4096;
  OPT_SIZE = 240;                  { PE32+ optional header with 16 directories }
var
  hdr: array[0..4095] of Byte;
  pad: array[0..4095] of Byte;
  codeOffset, i, p, sec, dataRawLen, dataPad: Integer;
  dataBase, bssBase, entry, dataRva, imageEnd: Int64;
{$ifdef FPC}
  f: File;
{$else}
  f: Integer;
{$endif}
begin
  DropWeakOnlyImports;
  PreparePEImports;
  RoLayoutPrepare(False, PAGE);    { one RW .data: no read-only split yet }
  codeOffset := PAGE;              { the headers' page }
  AlignCodeForData(codeOffset);
  PadCodeToPageBoundary(codeOffset);
  dataBase := ImageBase + codeOffset + CodeLen;
  CheckDataBaseAligned(dataBase);
  bssBase := (DataVA(dataBase, DataLen) + 7) and (not Int64(7));
  if ReqBssAlign > 8 then
    bssBase := (bssBase + ReqBssAlign - 1) and (not Int64(ReqBssAlign - 1));
  entry := ImageBase + codeOffset + AsmEntryOff;
  dataRva := dataBase - ImageBase;
  imageEnd := bssBase + BSSSize - ImageBase;
  imageEnd := (imageEnd + PAGE - 1) and (not Int64(PAGE - 1));
  if imageEnd > $7FFFFFFF then
    ErrorNoPos('--os=windows: the image is larger than 2 GiB');

  ApplyImageFixups(ImageBase + codeOffset, dataBase, bssBase, entry);
  PatchPEImports(dataRva);
  RoPermuteData;

  dataRawLen := (DataFileLen + PAGE - 1) and (not (PAGE - 1));
  dataPad := dataRawLen - DataFileLen;

  for i := 0 to PAGE - 1 do begin hdr[i] := 0; pad[i] := 0; end;
  { DOS header: just "MZ" and e_lfanew. }
  hdr[0] := Ord('M'); hdr[1] := Ord('Z');
  PeHdrU32(hdr, $3C, $40);
  { PE signature + COFF file header }
  p := $40;
  hdr[p] := Ord('P'); hdr[p + 1] := Ord('E');
  Inc(p, 4);
  PeHdrU16(hdr, p, $8664);         { Machine: AMD64 }
  PeHdrU16(hdr, p + 2, 2);         { NumberOfSections }
  PeHdrU32(hdr, p + 4, 0);         { TimeDateStamp: 0, reproducible }
  PeHdrU16(hdr, p + 16, OPT_SIZE);
  PeHdrU16(hdr, p + 18, $0023);    { RELOCS_STRIPPED | EXECUTABLE_IMAGE | LARGE_ADDRESS_AWARE }
  Inc(p, 20);
  { Optional header, PE32+ }
  PeHdrU16(hdr, p, $020B);
  PeHdrU8(hdr, p + 2, 1);          { linker version 1.0 }
  PeHdrU32(hdr, p + 4, CodeLen);   { SizeOfCode }
  PeHdrU32(hdr, p + 8, dataRawLen);
  PeHdrU32(hdr, p + 12, 0);
  PeHdrU32(hdr, p + 16, entry - ImageBase);   { AddressOfEntryPoint }
  PeHdrU32(hdr, p + 20, codeOffset);          { BaseOfCode }
  PeHdrU64(hdr, p + 24, ImageBase);
  PeHdrU32(hdr, p + 32, PAGE);     { SectionAlignment }
  PeHdrU32(hdr, p + 36, PAGE);     { FileAlignment }
  PeHdrU16(hdr, p + 40, 6);        { OS 6.0 (Vista) }
  PeHdrU16(hdr, p + 48, 6);        { subsystem 6.0 }
  PeHdrU32(hdr, p + 56, imageEnd); { SizeOfImage }
  PeHdrU32(hdr, p + 60, PAGE);     { SizeOfHeaders }
  PeHdrU16(hdr, p + 68, 3);        { Subsystem: WINDOWS_CUI (console) }
  PeHdrU16(hdr, p + 70, $8100);    { NX_COMPAT | TERMINAL_SERVER_AWARE }
  PeHdrU64(hdr, p + 72, PE_IMAGE_STACK);   { SizeOfStackReserve }
  PeHdrU64(hdr, p + 80, PE_IMAGE_STACK);   { SizeOfStackCommit: all of it, see the top }
  PeHdrU64(hdr, p + 88, $100000);  { SizeOfHeapReserve }
  PeHdrU64(hdr, p + 96, $1000);    { SizeOfHeapCommit }
  PeHdrU32(hdr, p + 108, 16);      { NumberOfRvaAndSizes }
  { data directories at p + 112, 8 bytes each }
  if PeImportDirSize > 0 then
  begin
    PeHdrU32(hdr, p + 112 + 8 * 1, dataRva + PeImportDirOff);
    PeHdrU32(hdr, p + 112 + 8 * 1 + 4, PeImportDirSize);
    PeHdrU32(hdr, p + 112 + 8 * 12, dataRva + PeIatOff);
    PeHdrU32(hdr, p + 112 + 8 * 12 + 4, PeIatSize);
  end;
  Inc(p, OPT_SIZE);
  { Section table }
  sec := p;
  PeHdrName(hdr, sec, '.text');
  PeHdrU32(hdr, sec + 8, CodeLen);        { VirtualSize }
  PeHdrU32(hdr, sec + 12, codeOffset);    { VirtualAddress }
  PeHdrU32(hdr, sec + 16, CodeLen);       { SizeOfRawData (page-padded already) }
  PeHdrU32(hdr, sec + 20, codeOffset);    { PointerToRawData }
  PeHdrU32(hdr, sec + 36, $60000020);     { CODE | EXECUTE | READ }
  Inc(sec, 40);
  PeHdrName(hdr, sec, '.data');
  PeHdrU32(hdr, sec + 8, imageEnd - dataRva);   { VirtualSize: data + bss }
  PeHdrU32(hdr, sec + 12, dataRva);
  PeHdrU32(hdr, sec + 16, dataRawLen);
  PeHdrU32(hdr, sec + 20, codeOffset + CodeLen);
  PeHdrU32(hdr, sec + 36, $C0000040);     { INITIALIZED_DATA | READ | WRITE }

{$ifdef FPC}
  Assign(f, outPath); Rewrite(f, 1);
  Blockwrite(f, hdr[0], PAGE);
  if CodeLen > 0 then Blockwrite(f, Code[0], CodeLen);
  if DataFileLen > 0 then Blockwrite(f, Data[0], DataFileLen);
  if dataPad > 0 then Blockwrite(f, pad[0], dataPad);
  Close(f);
  FpChmod(outPath, &755);
{$else}
  AssignPath := outPath;
  f := OutOpen(AssignPath);
  OutWrite(f, hdr, 0, PAGE);
  if CodeLen > 0 then OutWrite(f, Code, 0, CodeLen);
  if DataFileLen > 0 then OutWrite(f, Data, 0, DataFileLen);
  if dataPad > 0 then OutWrite(f, pad, 0, dataPad);
  sysfchmod(f, 493);
  sysclose(f);
{$endif}
  if EmitMapFile then WriteMapFile(outPath, ImageBase, codeOffset);
end;
