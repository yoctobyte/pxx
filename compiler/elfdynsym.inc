{ SPDX-License-Identifier: MPL-2.0 }
{ ===== .dynsym: does this library DEFINE this symbol? ========================

  A minimal ELF64 reader, and deliberately only that. It answers one question --
  is `sym` a DEFINED dynamic symbol of the shared object at `path` -- which is
  what upgrades the header-to-library guard in RegisterExternal from "does this
  library exist" to "does this library answer". See the DIRECTORY-key note
  beside LdCacheDirCandidate in pasparser_proc.inc for why that upgrade is what
  makes a header's own directory usable as the library name.

  ITS OWN FILE, and not for tidiness. Two reasons, both operational:

  1. It is not parser code and it was sitting in the parser. Nothing here knows
     what a token is; it reads a file format written by somebody else.

  2. IT IS THE ONLY WAY TO EXERCISE THE REFUSAL ARM OF ITS OWN GUARDS. Measured
     2026-09-10 on this box: of 250 cache keys carrying more than one entry,
     every single one lists its x86-64 entry FIRST -- the sole exception is
     ld-linux.so.2, which no header directory can name. So no header reachable
     through the compiler's front door ever makes ElfIsNative64 return False,
     and a guard whose refusal arm cannot be reached is a guard that prints
     PASS. The class byte is meanwhile the ONLY thing separating
     /usr/lib/x86_64-linux-gnu/libSDL2-2.0.so.0 from
     /usr/lib/i386-linux-gnu/libSDL2-2.0.so.0: same cache key, both exporting
     SDL_Init. Standalone-includable so test/test_elfdynsym.pas can assert the
     pair directly -- one key, two paths, one accept and one reject.

  Every read is bounds-checked against the real file length rather than trusted
  from the header, the same rule the ld.so.cache reader states for itself: this
  parses files written by something else, and a compiler that segfaults on a
  truncated .so would be a worse bug than the one it fixes. }

function ElfU16At(const body: AnsiString; off: Int64): Int64;
{ Little-endian u16 at 0-based `off`. -1 when the read runs past the end, which
  every caller treats as "this file is not one we can read". }
begin
  ElfU16At := -1;
  if (off < 0) or (off + 2 > Length(body)) then Exit;
  ElfU16At := Int64(Ord(body[off + 1])) + Int64(Ord(body[off + 2])) * 256;
end;

function ElfU32At(const body: AnsiString; off: Int64): Int64;
begin
  ElfU32At := -1;
  if (off < 0) or (off + 4 > Length(body)) then Exit;
  ElfU32At := Int64(Ord(body[off + 1])) +
              Int64(Ord(body[off + 2])) * 256 +
              Int64(Ord(body[off + 3])) * 65536 +
              Int64(Ord(body[off + 4])) * 16777216;
end;

function ElfU64At(const body: AnsiString; off: Int64): Int64;
{ Low 4 bytes plus the high 4 scaled. A .so with a section past 2^63 does not
  exist; a TRUNCATED one with garbage there does, so the high half is read
  rather than assumed zero and the bounds check below catches the result. }
var lo, hi: Int64;
begin
  ElfU64At := -1;
  lo := ElfU32At(body, off);
  hi := ElfU32At(body, off + 4);
  if (lo < 0) or (hi < 0) then Exit;
  if hi > 2147483 then Exit;          { would overflow anything we can index }
  ElfU64At := lo + hi * 4294967296;
end;

function ElfIsNative64(const body: AnsiString): Boolean;
{ ELF64, little-endian. NOT a formality: see the two-architectures-one-key note
  above. This is the ONLY thing separating /usr/lib/x86_64-linux-gnu's
  libSDL2-2.0.so.0 from /usr/lib/i386-linux-gnu's, which carry the same cache
  key and export the same symbols.

  Guarded on TargetArch by the caller, not here -- LdCacheLoad already refuses
  to read this box's cache at all when cross-compiling, so a non-x86-64 target
  never reaches any of this. }
begin
  ElfIsNative64 := False;
  if Length(body) < 64 then Exit;
  if body[1] <> Chr(127) then Exit;
  if (body[2] <> 'E') or (body[3] <> 'L') or (body[4] <> 'F') then Exit;
  if body[5] <> Chr(2) then Exit;     { EI_CLASS  = ELFCLASS64 }
  if body[6] <> Chr(1) then Exit;     { EI_DATA   = ELFDATA2LSB }
  ElfIsNative64 := True;
end;

procedure ElfLoadMemo(const libpath: AnsiString);
{ One-entry memo. A header that references fifty symbols asks the same library
  fifty times and the answer is a 1.5 MB file; one entry is enough because the
  queries arrive grouped by library, being one header's externals in
  declaration order. }
begin
  if DynSymMemoPath = libpath then Exit;
  DynSymMemoPath := libpath;
  DynSymMemoBody := '';
  LoadFile(libpath, DynSymMemoBody);
end;

function ElfSoExportsSymbol(const libpath, sym: AnsiString): Boolean;
{ Is `sym` DEFINED (not merely named) in this .so's .dynsym?

  SHN_UNDEF entries are skipped, and that is the half that carries the meaning:
  a .dynsym lists what a library IMPORTS as well as what it exports, so a
  membership test that ignored st_shndx would accept any library that merely
  calls the function -- which is exactly the wrong answer for a guard whose
  question is "will the loader find this here".

  Every read is bounds-checked against the real file length rather than trusted
  from the header. This parses files written by somebody else, and a compiler
  that segfaults on a truncated .so would be a worse bug than the one it
  fixes -- the same rule the ld.so.cache reader states for itself. }
var shoff, shentsize, shnum, i, o: Int64;
    symOff, symSize, symEntsize, symLink, strOff, strSize: Int64;
    n, k, nameOff, shndx, p: Int64;
    c: Char;
begin
  ElfSoExportsSymbol := False;
  if Length(sym) = 0 then Exit;
  ElfLoadMemo(libpath);
  if not ElfIsNative64(DynSymMemoBody) then Exit;

  shoff     := ElfU64At(DynSymMemoBody, $28);
  shentsize := ElfU16At(DynSymMemoBody, $3A);
  shnum     := ElfU16At(DynSymMemoBody, $3C);
  if (shoff <= 0) or (shentsize < 64) or (shnum <= 0) then Exit;
  if shoff + shnum * shentsize > Length(DynSymMemoBody) then Exit;

  symOff := -1; symSize := 0; symEntsize := 0; symLink := -1;
  for i := 0 to shnum - 1 do
  begin
    o := shoff + i * shentsize;
    if ElfU32At(DynSymMemoBody, o + 4) = 11 then      { SHT_DYNSYM }
    begin
      symOff     := ElfU64At(DynSymMemoBody, o + $18);
      symSize    := ElfU64At(DynSymMemoBody, o + $20);
      symLink    := ElfU32At(DynSymMemoBody, o + $28);
      symEntsize := ElfU64At(DynSymMemoBody, o + $38);
    end;
  end;
  { A STRIPPED .so still carries .dynsym -- it is an allocated section the
    loader itself needs -- so the absence of one is a real answer (a static
    archive, a linker script, something that is not a shared object) and not a
    case to work around. }
  if (symOff < 0) or (symSize <= 0) or (symLink < 0) or (symLink >= shnum) then Exit;
  if symEntsize <= 0 then symEntsize := 24;
  if symOff + symSize > Length(DynSymMemoBody) then Exit;

  o := shoff + symLink * shentsize;
  strOff  := ElfU64At(DynSymMemoBody, o + $18);
  strSize := ElfU64At(DynSymMemoBody, o + $20);
  if (strOff < 0) or (strSize <= 0) then Exit;
  if strOff + strSize > Length(DynSymMemoBody) then Exit;

  n := symSize div symEntsize;
  for k := 0 to n - 1 do
  begin
    o := symOff + k * symEntsize;
    shndx := ElfU16At(DynSymMemoBody, o + 6);
    if shndx <= 0 then Continue;             { SHN_UNDEF: imported, not exported }
    nameOff := ElfU32At(DynSymMemoBody, o);
    if (nameOff <= 0) or (nameOff >= strSize) then Continue;
    { Compare in place: building an AnsiString per symbol costs 3490 allocations
      on libGL.so.1 alone, and the overwhelming majority differ in byte one. }
    p := strOff + nameOff;
    i := 0;
    while (i < Length(sym)) and (p + i < strOff + strSize) do
    begin
      c := DynSymMemoBody[p + i + 1];
      if c <> sym[i + 1] then Break;
      i := i + 1;
    end;
    if i < Length(sym) then Continue;
    if p + i >= strOff + strSize then Continue;
    if DynSymMemoBody[p + i + 1] <> Chr(0) then Continue;   { a longer name }
    ElfSoExportsSymbol := True;
    Exit;
  end;
end;

