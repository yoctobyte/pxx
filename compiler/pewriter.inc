{ pewriter.inc -- the PE32+ (Windows x64) executable writer, --os=windows.
  feature-port-windows-pe

  ONE IMAGE, LAID OUT LIKE THE ELF ONE. FileAlignment = SectionAlignment =
  4096, so a file offset IS an RVA: the headers fill page 0, .text starts at
  RVA $1000 exactly where writeELF puts the code (codeOffset), and .data
  follows the page-padded code at dataBase, as in writeELF. Every fixup is
  then resolved by the same ApplyImageFixups against ImageBase + RVA.

  BASE RELOCATIONS (ASLR): the image prefers ImageBase ($400000) and carries
  a .reloc section listing every absolute 64-bit address in it, so it sets
  DYNAMIC_BASE and the loader may put it anywhere below 4 GiB (no
  HIGH_ENTROPY_VA). The list is the writers' own fixup inventory (PeRelBuild):
  the code fixups that stayed absolute (movabs), and in .data every pointer
  ApplyImageFixups and PatchPETls store -- method slots, data pointers, C
  initialisers, the TLS directory. Everything else is rip-relative or an RVA.
  An image holding a 32-bit absolute (a GlobFix that is not rip-relative) is
  written the old way instead: fixed at ImageBase, RELOCS_STRIPPED, no
  DYNAMIC_BASE -- such a field cannot follow a move above 2 GiB.

  IMPORTS (weak ones excepted, see PreparePEImports): the GOT slots the x86-64 external call already reads through
  (`call [rip+slot]`) become the Import Address Table. PreparePEImports
  appends the IAT, the lookup tables, the hint/name entries and the import
  descriptors to Data[] and points ExternalGotOff at the IAT slots, so
  PatchDynCallSites needs no change. The RVA fields inside the block are
  patched once dataBase is known (PatchPEImports).

  THREAD-LOCAL STORAGE is the PE TLS directory (PreparePETls): its data is
  the pxx TLS block plus a 32-byte scratch (getrlimit's at startup, then
  winabi's per-thread words), all zeros and all raw data (ReactOS's
  loader ignores SizeOfZeroFill; see PreparePETls), so the loader
  hands every thread -- the main one, CreateThread's, and the ones Windows
  starts itself (the console control handler) -- a zeroed block of its own,
  reached through the TEB (TlsViaTeb in defs.inc).

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

var
  PeTlsDirOff: Integer;                       { Data[] offset of IMAGE_TLS_DIRECTORY64, or -1 }
  PeTlsTplSize: Integer;                      { bytes of TLS template (all raw data) }

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
  if ProcWeakExternal[ExternalProc[i]] then
    libOfExt[i] := -1
  else
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
  { A `weakexternal` is not imported: Windows has no weak import, and a DLL
    that is not there (libc.so.6 for palthread's pthread pair) stops the
    program from loading at all. Its slot is a zero of its own, so `@f`
    reads nil, as on a static Linux build. }
  for i := 0 to ExternalCount - 1 do
    if libOfExt[i] < 0 then
    begin
      ExternalGotOff[i] := DataLen;
      DataPutU64(0);
    end;

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
  if libOfExt[i] >= 0 then
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

{ IMAGE_TLS_DIRECTORY64 (40 bytes), then the index the loader writes, an
  empty callback list and the template: the whole block plus winabi's
  32-byte scratch, as zero bytes of RAW DATA with SizeOfZeroFill 0, the
  way MSVC's link always emits it. ReactOS's loader (LdrpAllocateTls)
  allocates and copies only End - Start and ignores SizeOfZeroFill, so a
  zero-fill template there is an 8-byte heap block that the program's
  thread-locals and winabi's per-thread words overrun (seen: a hello world
  exiting 130, a stray "signal" from the heap bytes after it). The four
  VAs are patched once dataBase is known. }
procedure PreparePETls;
var i: Integer;
begin
  PeTlsDirOff := -1;
  if not TlsMainInstalled then Exit;
  PeDataAlign(16);
  PeTlsDirOff := DataLen;
  DataPutU64(0);                    { StartAddressOfRawData }
  DataPutU64(0);                    { EndAddressOfRawData }
  DataPutU64(0);                    { AddressOfIndex }
  DataPutU64(0);                    { AddressOfCallBacks }
  DataPutU32(0);                    { SizeOfZeroFill: none, see above }
  DataPutU32(0);                    { Characteristics }
  DataPutU64(0);                    { +40: the index (a DWORD, padded) }
  DataPutU64(0);                    { +48: the callback list's terminator }
  PeTlsTplSize := TlsBlockSize + 32;   { +56: the template: the block, then winabi's scratch }
  for i := 1 to PeTlsTplSize do DataPutB(0);
end;

procedure PatchPETls(dataVa: Int64);
begin
  if PeTlsDirOff < 0 then Exit;
  PatchDataU64(PeTlsDirOff, dataVa + PeTlsDirOff + 56);
  PatchDataU64(PeTlsDirOff + 8, dataVa + PeTlsDirOff + 56 + PeTlsTplSize);
  PatchDataU64(PeTlsDirOff + 16, dataVa + PeTlsDirOff + 40);
  PatchDataU64(PeTlsDirOff + 24, dataVa + PeTlsDirOff + 48);
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

{ ---- .reloc: the base relocation table --------------------------------------
  Blocks of IMAGE_BASE_RELOCATION, one per 4 KiB page that holds an absolute
  address: PageRVA, BlockSize, then one 16-bit entry per address (type 10,
  DIR64, in the top four bits; the offset in the page below), padded to four
  bytes with an ABSOLUTE (type 0) entry. Built by a counting sort over pages,
  so the order within a page is the order the fixups were recorded in, which
  the loader does not care about. }
var
  PeRelRva: array of Int64;
  PeRelN: Integer;
  PeRelBuf: array of Byte;
  PeRelLen: Integer;

procedure PeRelAdd(rva: Int64);
begin
  if PeRelN >= Length(PeRelRva) then SetLength(PeRelRva, PeRelN * 2 + 1024);
  PeRelRva[PeRelN] := rva;
  Inc(PeRelN);
end;

{ False when the image cannot be relocated (a 32-bit absolute), True with
  PeRelBuf/PeRelLen filled otherwise. Called after every patch, with the
  final layout. }
function PeRelBuild(codeOffset: Integer; dataBase: Int64; imageEnd: Int64): Boolean;
var i, pages, pg, k, off: Integer;
    cnt, start, fill: array of Integer;
    sorted: array of Integer;
    rva: Int64;
begin
  Result := False;
  PeRelN := 0; PeRelLen := 0;
  for i := 0 to GlobFixCount - 1 do
    if not GlobFixPCRel[i] then Exit;
  for i := 0 to FixCount - 1 do
    if not FixupPCRel[i] then PeRelAdd(codeOffset + Fixups[i].CodePos);
  for i := 0 to MethodFixCount - 1 do PeRelAdd(DataVA(dataBase, MethodFixups[i].DataPos) - ImageBase);
  for i := 0 to DataPtrFixCount - 1 do PeRelAdd(DataVA(dataBase, DataPtrFix[i].DataPos) - ImageBase);
  for i := 0 to CDRCount - 1 do PeRelAdd(DataVA(dataBase, CDRPos[i]) - ImageBase);
  if PeTlsDirOff >= 0 then
    for i := 0 to 3 do PeRelAdd(DataVA(dataBase, PeTlsDirOff + 8 * i) - ImageBase);
  pages := Integer(imageEnd div 4096) + 1;
  SetLength(cnt, pages); SetLength(start, pages); SetLength(fill, pages);
  for i := 0 to pages - 1 do cnt[i] := 0;
  for i := 0 to PeRelN - 1 do
  begin
    rva := PeRelRva[i];
    if (rva < 0) or (rva >= imageEnd) then
      ErrorNoPos('internal: --os=nt base relocation outside the image');
    Inc(cnt[Integer(rva div 4096)]);
  end;
  k := 0;
  for i := 0 to pages - 1 do begin start[i] := k; fill[i] := k; k := k + cnt[i]; end;
  SetLength(sorted, PeRelN + 1);
  for i := 0 to PeRelN - 1 do
  begin
    pg := Integer(PeRelRva[i] div 4096);
    sorted[fill[pg]] := Integer(PeRelRva[i] and 4095);
    Inc(fill[pg]);
  end;
  SetLength(PeRelBuf, PeRelN * 2 + pages * 12 + 16);
  off := 0;
  for pg := 0 to pages - 1 do
    if cnt[pg] > 0 then
    begin
      k := 8 + 2 * cnt[pg];
      if (k and 3) <> 0 then k := k + 2;
      PeHdrU32(PeRelBuf, off, Int64(pg) * 4096);
      PeHdrU32(PeRelBuf, off + 4, k);
      for i := 0 to cnt[pg] - 1 do
        PeHdrU16(PeRelBuf, off + 8 + 2 * i, $A000 or sorted[start[pg] + i]);
      if ((8 + 2 * cnt[pg]) and 3) <> 0 then PeHdrU16(PeRelBuf, off + 8 + 2 * cnt[pg], 0);
      off := off + k;
    end;
  PeRelLen := off;
  Result := True;
end;

{ ---- --os=nt --shared: a DLL ------------------------------------------------
  WHAT IS EXPORTED: the program's own C-convention routines (cdecl, stdcall,
  every function of a C source), not the runtime's -- winabi, crtl and the
  builtin units stay inside -- plus any routine an `exports` clause names.
  Variadic routines are not exported.

  THE CONVENTION: Windows callers use the Microsoft x64 convention and pxx
  code System V's. Each export's address in the export table is a stub,
  `jmp [rip+slot]`, and DllMain (DLL_PROCESS_ATTACH) fills every slot with
  winabi's PxxWinCallback adapter for that routine -- the one a callback
  handed to Windows gets: arguments moved over, rdi/rsi/xmm6-15 kept for
  the caller. So the limits are the adapter's: up to 14 parameters, scalar
  or pointer; a record by value, as a parameter or a result, is refused here.

  INITIALISATION RUNS AT LOAD, as a Linux .so's DT_INIT does: DllMain calls
  the init thunk (EmitInitFiniThunks: the global initialisers, the units'
  initialization sections, then the library's main body) and only then
  builds the adapters -- the adapter generator itself reads typed constants,
  which that code sets. Finalization does not run (no DLL_PROCESS_DETACH
  work yet).

  THREAD-LOCAL STORAGE is the DLL's own TLS directory, with the index the
  loader assigns written into a BSS word (EmitTlsSelfLoad). }
var
  PeDllExp: array of Integer;          { proc indexes, sorted by name }
  PeDllExpCount: Integer;
  PeDllStubPos: array of Integer;      { Code[] offset of each export's stub }
  PeDllMainPos: Integer;
  PeDllLeaPos: Integer;                { Code[] offset of DllMain's table displacement }
  PeDllTableOff: Integer;              { Data[]: count, then (rva, shape, slot) per export }
  PeExportDirOff, PeExportDirSize, PeExportEatOff: Integer;

function PeDllNamed(pi: Integer): Boolean;
var i: Integer;
begin
  Result := False;
  for i := 0 to ExportCount - 1 do
    if FindProc(ExportName[i]) = pi then begin Result := True; Exit; end;
end;

function PeDllExports(pi: Integer): Boolean;
begin
  Result := False;
  if not ObjProcIsDefined(pi) then Exit;
  if ProcCStaticLink[pi] or CProcInlineOnly(pi) or ProcVariadic[pi] then Exit;
  if Pos('$', Procs[pi].Name) > 0 then Exit;
  if PeDllNamed(pi) then begin Result := True; Exit; end;
  if ProcUnitIdx[pi] >= 0 then Exit;          { a unit's routine: the runtime }
  { A C library's own runtime: lib/crtl's bodies (strdup, div, ...) are
    compiled in with the program's, but they are the DLL's private copy, not
    its interface -- and every export costs an adapter at load. }
  if ProcObjRuntimeCopy[pi] then Exit;
  Result := ProcCdecl[pi];
end;

procedure PeDllMovups(n, disp: Integer; load: Boolean);
begin
  if n >= 8 then EmitB($44);
  EmitB($0F);
  if load then EmitB($10) else EmitB($11);
  EmitB($84 or ((n and 7) shl 3)); EmitB($24); EmitI32(disp);
end;

procedure EmitPeDllEntry;
var i, j, t, k, att, jpos: Integer;
    shape: Int64;
begin
  PeDllExpCount := 0;
  SetLength(PeDllExp, ProcCount + 1);
  for i := 0 to ProcCount - 1 do
    if PeDllExports(i) then begin PeDllExp[PeDllExpCount] := i; Inc(PeDllExpCount); end;
  if PeDllExpCount = 0 then
    ErrorNoPos('--os=nt --shared: the DLL would export nothing; declare the routines it exports cdecl');
  { GetProcAddress binary-searches the name table: sorted, byte order }
  for i := 1 to PeDllExpCount - 1 do
  begin
    t := PeDllExp[i]; j := i - 1;
    while (j >= 0) and (Procs[PeDllExp[j]].Name > Procs[t].Name) do
    begin
      PeDllExp[j + 1] := PeDllExp[j]; Dec(j);
    end;
    PeDllExp[j + 1] := t;
  end;
  for i := 0 to PeDllExpCount - 1 do
  begin
    t := PeDllExp[i];
    if (i > 0) and (Procs[PeDllExp[i - 1]].Name = Procs[t].Name) then
      ErrorNoPos('--os=nt --shared: two exported routines are named ' + Procs[t].Name);
    if Procs[t].ParamCount > 14 then
      ErrorNoPos('--os=nt --shared: cannot export ' + Procs[t].Name + ': more than 14 parameters');
    for k := 0 to Procs[t].ParamCount - 1 do
      if (not Procs[t].Params[k].IsRef) and (Procs[t].Params[k].TypeKind = tyRecord) then
        ErrorNoPos('--os=nt --shared: cannot export ' + Procs[t].Name +
          ': a record parameter by value (pass a pointer, or const/var)');
    if Procs[t].IsFunc and (Procs[t].RetType = tyRecord) then
      ErrorNoPos('--os=nt --shared: cannot export ' + Procs[t].Name + ': it returns a record');
  end;
  att := FindProc('PxxDllAttach');
  if (att < 0) or (Procs[att].BodyAddr < 0) then
    ErrorNoPos('internal: --os=nt --shared: winabi''s PxxDllAttach is missing');

  PeDataAlign(8);
  PeDllTableOff := DataLen;
  DataPutU64(PeDllExpCount);
  for i := 0 to PeDllExpCount - 1 do
  begin
    t := PeDllExp[i];
    shape := Int64(Procs[t].ParamCount) shl 16;
    for k := 0 to Procs[t].ParamCount - 1 do
      if (k < 16) and (not Procs[t].Params[k].IsRef) and
         ((Procs[t].Params[k].TypeKind = tyDouble) or (Procs[t].Params[k].TypeKind = tySingle)) then
        shape := shape or (Int64(1) shl k);
    DataPutU64(0);                       { the routine's RVA (PatchPEDll) }
    DataPutU64(shape);
    DataPutU64(0);                       { the adapter, filled by PxxDllAttach }
  end;

  SetLength(PeDllStubPos, PeDllExpCount);
  for i := 0 to PeDllExpCount - 1 do
  begin
    while (CodeLen and 7) <> 0 do EmitB($CC);
    PeDllStubPos[i] := CodeLen;
    EmitB($FF); EmitB($25); EmitI32(0);  { jmp [rip+slot] (PatchPEDll) }
  end;

  { DllMain(hinst rcx, reason edx, reserved r8): on DLL_PROCESS_ATTACH call
    PxxDllAttach(hinst, table) -- System V, so keep what Microsoft's
    convention says the callee keeps -- and answer TRUE for every reason. }
  while (CodeLen and 15) <> 0 do EmitB($CC);
  PeDllMainPos := CodeLen;
  EmitB($83); EmitB($FA); EmitB($01);                  { cmp edx, 1 }
  EmitB($0F); EmitB($85); jpos := CodeLen; EmitI32(0); { jne .done }
  EmitB($55);                                          { push rbp  (rsp 0 mod 16) }
  EmitB($48); EmitB($89); EmitB($E5);                  { mov rbp, rsp }
  EmitB($56); EmitB($57); EmitB($53);                  { push rsi; push rdi; push rbx }
  EmitB($41); EmitB($54); EmitB($41); EmitB($55);      { push r12; push r13 }
  EmitB($41); EmitB($56); EmitB($41); EmitB($57);      { push r14; push r15  (8 mod 16) }
  EmitB($48); EmitB($81); EmitB($EC); EmitI32(168);    { sub rsp, 168  (0 mod 16) }
  for k := 6 to 15 do PeDllMovups(k, 16 * (k - 6), False);
  EmitB($48); EmitB($89); EmitB($CB);                  { mov rbx, rcx  (hinst, kept across the init) }
  if InitThunkOff >= 0 then
  begin
    EmitB($E8); EmitI32(InitThunkOff - (CodeLen + 4)); { call the init thunk }
  end;
  EmitB($48); EmitB($89); EmitB($DF);                  { mov rdi, rbx }
  EmitB($48); EmitB($8D); EmitB($35);                  { lea rsi, [rip+table] }
  PeDllLeaPos := CodeLen; EmitI32(0);
  EmitB($E8); EmitI32(Procs[att].BodyAddr - (CodeLen + 4));   { call PxxDllAttach }
  for k := 6 to 15 do PeDllMovups(k, 16 * (k - 6), True);
  EmitB($48); EmitB($81); EmitB($C4); EmitI32(168);    { add rsp, 168 }
  EmitB($41); EmitB($5F); EmitB($41); EmitB($5E);      { pop r15; pop r14 }
  EmitB($41); EmitB($5D); EmitB($41); EmitB($5C);      { pop r13; pop r12 }
  EmitB($5B); EmitB($5F); EmitB($5E); EmitB($5D);      { pop rbx; pop rdi; pop rsi; pop rbp }
  Patch32(jpos, CodeLen - (jpos + 4));                 { .done: }
  EmitB($B8); EmitI32(1);                              { mov eax, 1 }
  EmitB($C3);                                          { ret }
end;

{ The export directory, in Data[] like the imports: the directory, the
  address table (the stubs' RVAs, PatchPEDll), the name pointers, the
  ordinals, the names, then the DLL's own name. }
procedure PreparePEExports(const dllName: AnsiString);
var i, k, nameFix, eatFix, enptFix, eotFix, enpt, total: Integer;
    nm: AnsiString;
begin
  PeExportDirOff := -1; PeExportDirSize := 0;
  if PeDllExpCount = 0 then Exit;
  total := PeDllExpCount;
  PeDataAlign(4);
  PeExportDirOff := DataLen;
  DataPutU32(0); DataPutU32(0); DataPutU32(0);       { Characteristics, TimeDateStamp, version }
  nameFix := DataLen; DataPutU32(0);                 { Name }
  DataPutU32(1);                                     { Base }
  DataPutU32(total); DataPutU32(total);
  eatFix := DataLen; DataPutU32(0);
  enptFix := DataLen; DataPutU32(0);
  eotFix := DataLen; DataPutU32(0);
  PeExportEatOff := DataLen;
  PeRvaFixAdd(eatFix, PeExportEatOff, False);
  for i := 0 to total - 1 do DataPutU32(0);
  enpt := DataLen;
  PeRvaFixAdd(enptFix, enpt, False);
  for i := 0 to total - 1 do DataPutU32(0);
  PeRvaFixAdd(eotFix, DataLen, False);
  for i := 0 to total - 1 do DataPutU16(i);
  for i := 0 to total - 1 do
  begin
    PeRvaFixAdd(enpt + 4 * i, DataLen, False);
    nm := Procs[PeDllExp[i]].Name;
    for k := 1 to Length(nm) do DataPutB(Ord(nm[k]));
    DataPutB(0);
  end;
  PeRvaFixAdd(nameFix, DataLen, False);
  for k := 1 to Length(dllName) do DataPutB(Ord(dllName[k]));
  DataPutB(0);
  PeExportDirSize := DataLen - PeExportDirOff;
end;

procedure PatchPEDll(codeOffset: Integer; dataRva, bssBase: Int64);
var i: Integer;
begin
  if PeDllExpCount = 0 then Exit;
  for i := 0 to PeDllExpCount - 1 do
  begin
    PatchDataU64(PeDllTableOff + 8 + 24 * i, codeOffset + Procs[PeDllExp[i]].BodyAddr);
    Patch32(PeDllStubPos[i] + 2,
      (dataRva + PeDllTableOff + 8 + 24 * i + 16) - (codeOffset + PeDllStubPos[i] + 6));
    PatchDataI32(PeExportEatOff + 4 * i, codeOffset + PeDllStubPos[i]);
  end;
  Patch32(PeDllLeaPos, (dataRva + PeDllTableOff) - (codeOffset + PeDllLeaPos + 4));
  if (PeTlsDirOff >= 0) and (PeDllTlsIdxBss >= 0) then
    PatchDataU64(PeTlsDirOff + 16, bssBase + PeDllTlsIdxBss);   { AddressOfIndex }
end;

function PeFileName(const p: AnsiString): AnsiString;
var i: Integer;
begin
  i := Length(p);
  while (i > 0) and (p[i] <> '/') and (p[i] <> '\') do Dec(i);
  Result := Copy(p, i + 1, Length(p) - i);
end;

procedure writePE(const outPath: AnsiString);
const
  PAGE = 4096;
  OPT_SIZE = 240;                  { PE32+ optional header with 16 directories }
var
  hdr: array[0..4095] of Byte;
  pad: array[0..4095] of Byte;
  codeOffset, i, p, sec, dataRawLen, dataPad, relRawLen: Integer;
  dataBase, bssBase, entry, hdrEntry, dataRva, imageEnd, relRva: Int64;
  relocs: Boolean;
{$ifdef FPC}
  f: File;
{$else}
  f: Integer;
{$endif}
begin
  DropWeakOnlyImports;
  PreparePEImports;
  PreparePEExports(PeFileName(outPath));
  PreparePETls;
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
  { A DLL's header names DllMain. `entry` itself stays the code base the
    fixups measure from (a VMT slot is entry + BodyAddr): pointing it at
    DllMain put every method that far past its code. }
  hdrEntry := entry;
  if PeDllExpCount > 0 then hdrEntry := ImageBase + codeOffset + PeDllMainPos;
  dataRva := dataBase - ImageBase;
  imageEnd := bssBase + BSSSize - ImageBase;
  imageEnd := (imageEnd + PAGE - 1) and (not Int64(PAGE - 1));
  if imageEnd > $7FFFFFFF then
    ErrorNoPos('--os=windows: the image is larger than 2 GiB');

  ApplyImageFixups(ImageBase + codeOffset, dataBase, bssBase, entry);
  PatchPEImports(dataRva);
  PatchPETls(dataBase);
  PatchPEDll(codeOffset, dataRva, bssBase);
  RoPermuteData;

  dataRawLen := (DataFileLen + PAGE - 1) and (not (PAGE - 1));
  dataPad := dataRawLen - DataFileLen;
  relocs := PeRelBuild(codeOffset, dataBase, imageEnd);
  relRva := imageEnd;                               { the .reloc section's page(s), after data + bss }
  relRawLen := (PeRelLen + PAGE - 1) and (not (PAGE - 1));
  if relocs and (PeRelLen = 0) then relocs := False; { nothing to move: keep the fixed image }
  if relocs then
  begin
    for i := PeRelLen to relRawLen - 1 do PeRelBuf[i] := 0;
    imageEnd := relRva + relRawLen;
  end;

  for i := 0 to PAGE - 1 do begin hdr[i] := 0; pad[i] := 0; end;
  { DOS header: just "MZ" and e_lfanew. }
  hdr[0] := Ord('M'); hdr[1] := Ord('Z');
  PeHdrU32(hdr, $3C, $40);
  { PE signature + COFF file header }
  p := $40;
  hdr[p] := Ord('P'); hdr[p + 1] := Ord('E');
  Inc(p, 4);
  PeHdrU16(hdr, p, $8664);         { Machine: AMD64 }
  if relocs then PeHdrU16(hdr, p + 2, 3)          { NumberOfSections: .text .data .reloc }
  else PeHdrU16(hdr, p + 2, 2);
  PeHdrU32(hdr, p + 4, 0);         { TimeDateStamp: 0, reproducible }
  PeHdrU16(hdr, p + 16, OPT_SIZE);
  if relocs then PeHdrU16(hdr, p + 18, $0022)      { EXECUTABLE_IMAGE | LARGE_ADDRESS_AWARE }
  else PeHdrU16(hdr, p + 18, $0023);              { ... | RELOCS_STRIPPED }
  if PeDllExpCount > 0 then
    PeHdrU16(hdr, p + 18, $2000 or (hdr[p + 18] + 256 * hdr[p + 19]));   { | DLL }
  Inc(p, 20);
  { Optional header, PE32+ }
  PeHdrU16(hdr, p, $020B);
  PeHdrU8(hdr, p + 2, 1);          { linker version 1.0 }
  PeHdrU32(hdr, p + 4, CodeLen);   { SizeOfCode }
  PeHdrU32(hdr, p + 8, dataRawLen);
  PeHdrU32(hdr, p + 12, 0);
  PeHdrU32(hdr, p + 16, hdrEntry - ImageBase);   { AddressOfEntryPoint }
  PeHdrU32(hdr, p + 20, codeOffset);          { BaseOfCode }
  PeHdrU64(hdr, p + 24, ImageBase);
  PeHdrU32(hdr, p + 32, PAGE);     { SectionAlignment }
  PeHdrU32(hdr, p + 36, PAGE);     { FileAlignment }
  PeHdrU16(hdr, p + 40, 6);        { OS 6.0 (Vista) }
  PeHdrU16(hdr, p + 48, 6);        { subsystem 6.0 }
  PeHdrU32(hdr, p + 56, imageEnd); { SizeOfImage }
  PeHdrU32(hdr, p + 60, PAGE);     { SizeOfHeaders }
  PeHdrU16(hdr, p + 68, 3);        { Subsystem: WINDOWS_CUI (console) }
  if relocs then PeHdrU16(hdr, p + 70, $8140)      { DYNAMIC_BASE | NX_COMPAT | TERMINAL_SERVER_AWARE }
  else PeHdrU16(hdr, p + 70, $8100);
  PeHdrU64(hdr, p + 72, PE_IMAGE_STACK);   { SizeOfStackReserve }
  PeHdrU64(hdr, p + 80, PE_IMAGE_STACK);   { SizeOfStackCommit: all of it, see the top }
  PeHdrU64(hdr, p + 88, $100000);  { SizeOfHeapReserve }
  PeHdrU64(hdr, p + 96, $1000);    { SizeOfHeapCommit }
  PeHdrU32(hdr, p + 108, 16);      { NumberOfRvaAndSizes }
  { data directories at p + 112, 8 bytes each }
  if PeExportDirSize > 0 then
  begin
    PeHdrU32(hdr, p + 112, dataRva + PeExportDirOff);   { EXPORT }
    PeHdrU32(hdr, p + 112 + 4, PeExportDirSize);
  end;
  if PeImportDirSize > 0 then
  begin
    PeHdrU32(hdr, p + 112 + 8 * 1, dataRva + PeImportDirOff);
    PeHdrU32(hdr, p + 112 + 8 * 1 + 4, PeImportDirSize);
    PeHdrU32(hdr, p + 112 + 8 * 12, dataRva + PeIatOff);
    PeHdrU32(hdr, p + 112 + 8 * 12 + 4, PeIatSize);
  end;
  if relocs then
  begin
    PeHdrU32(hdr, p + 112 + 8 * 5, relRva);          { BASERELOC }
    PeHdrU32(hdr, p + 112 + 8 * 5 + 4, PeRelLen);
  end;
  if PeTlsDirOff >= 0 then
  begin
    PeHdrU32(hdr, p + 112 + 8 * 9, dataRva + PeTlsDirOff);
    PeHdrU32(hdr, p + 112 + 8 * 9 + 4, 40);
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
  { VirtualSize: data + bss, which end where .reloc begins (relRva is the
    page-rounded end of bss either way). imageEnd here already includes the
    .reloc pages, and a .data that overlapped them loaded under Wine but hung
    every program on ReactOS. }
  PeHdrU32(hdr, sec + 8, relRva - dataRva);
  PeHdrU32(hdr, sec + 12, dataRva);
  PeHdrU32(hdr, sec + 16, dataRawLen);
  PeHdrU32(hdr, sec + 20, codeOffset + CodeLen);
  PeHdrU32(hdr, sec + 36, $C0000040);     { INITIALIZED_DATA | READ | WRITE }
  if relocs then
  begin
    Inc(sec, 40);
    PeHdrName(hdr, sec, '.reloc');
    PeHdrU32(hdr, sec + 8, PeRelLen);
    PeHdrU32(hdr, sec + 12, relRva);
    PeHdrU32(hdr, sec + 16, relRawLen);
    PeHdrU32(hdr, sec + 20, codeOffset + CodeLen + dataRawLen);
    PeHdrU32(hdr, sec + 36, $42000040);   { INITIALIZED_DATA | DISCARDABLE | READ }
  end;

{$ifdef FPC}
  Assign(f, outPath); Rewrite(f, 1);
  Blockwrite(f, hdr[0], PAGE);
  if CodeLen > 0 then Blockwrite(f, Code[0], CodeLen);
  if DataFileLen > 0 then Blockwrite(f, Data[0], DataFileLen);
  if dataPad > 0 then Blockwrite(f, pad[0], dataPad);
  if relocs then Blockwrite(f, PeRelBuf[0], relRawLen);
  Close(f);
  FpChmod(outPath, &755);
{$else}
  AssignPath := outPath;
  f := OutOpen(AssignPath);
  OutWrite(f, hdr, 0, PAGE);
  if CodeLen > 0 then OutWrite(f, Code, 0, CodeLen);
  if DataFileLen > 0 then OutWrite(f, Data, 0, DataFileLen);
  if dataPad > 0 then OutWrite(f, pad, 0, dataPad);
  if relocs then OutWrite(f, PeRelBuf, 0, relRawLen);
  sysfchmod(f, 493);
  sysclose(f);
{$endif}
  if EmitMapFile then WriteMapFile(outPath, ImageBase, codeOffset);
end;
