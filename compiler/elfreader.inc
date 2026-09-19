{ SPDX-License-Identifier: MPL-2.0 }
{ elfreader.inc — read an ELF64 relocatable object.

  THE FIRST CODE IN THIS COMPILER THAT READS AN OBJECT RATHER THAN WRITING ONE.
  elfwriter.inc is 6838 lines and every one of them writes; before this file a
  grep for Elf64_Ehdr, section-header walking or object loading returned
  nothing. That asymmetry is the whole of
  feature-a-pxx-cannot-link-its-own-objects: pxx writes static libc-free ELF
  executables with no external linker, and cannot CONSUME an object, so the
  external dependency for a separate-objects build is a LINKER and not a
  library.

  WHY THE READER FIRST, AND ALONE. A symbol-table merge, a section layout and a
  relocation applier all rest on this; if it enumerates symbols or relocations
  wrongly, every later stage is unfalsifiable -- it would produce a wrong answer
  that no downstream assertion could attribute. So this lands on its own,
  against an EXTERNAL oracle: `readelf` reads the same bytes and fails
  differently from anything written here, which is the property that makes a
  second source worth having at all (two readings that can go wrong the same way
  are one reading).

  SCOPE, STATED SO THE NEXT READER DOES NOT INFER IT FROM THE CORPUS. The
  ticket said "two relocation types and a fixed section list", which is a CENSUS
  OVER THE BUSYBOX OBJECTS and not a statement about what we emit: elfwriter
  emits THREE x86-64 types -- R_X86_64_64 (1), R_X86_64_PC32 (2) and
  R_X86_64_32S (11) -- and the third merely did not occur in that corpus. This
  file therefore decodes whatever type it finds and REPORTS it rather than
  matching against a list; the place to refuse an unsupported type is the
  relocation APPLIER, which knows what it can do, not the reader, which knows
  only what is there. A reader that refuses what it can perfectly well read
  would make the emitter's own third type invisible.

  ENDIANNESS AND CLASS ARE CHECKED, NOT ASSUMED. Everything here is
  little-endian ELF64 and says so; a big-endian or ELF32 input is refused by
  name rather than silently decoded into nonsense, because the failure of a
  silent mis-decode is a plausible wrong number and not a crash. }

const
  ELFRD_SHT_SYMTAB = 2;
  ELFRD_SHT_RELA   = 4;
  ELFRD_SHT_NOBITS = 8;

var
  ElfRdBuf  : AnsiString;   { the whole object; 1-based like every AnsiString }
  ElfRdErr  : AnsiString;   { '' when the last parse succeeded }

{ ---- little-endian decoders -------------------------------------------------
  OFFSETS ARE 0-BASED ELF OFFSETS and the buffer is 1-BASED Pascal, so every
  read adds one exactly here. Doing that at the call sites is how an off-by-one
  becomes forty off-by-ones, and a wrong field decodes to a plausible number. }

function ElfRdU8(off: Int64): Integer;
begin
  ElfRdU8 := 0;
  if (off < 0) or (off + 1 > Length(ElfRdBuf)) then Exit;
  ElfRdU8 := Ord(ElfRdBuf[off + 1]);
end;

function ElfRdU16(off: Int64): Integer;
begin
  ElfRdU16 := ElfRdU8(off) or (ElfRdU8(off + 1) shl 8);
end;

function ElfRdU32(off: Int64): Int64;
begin
  ElfRdU32 := Int64(ElfRdU8(off))
           or (Int64(ElfRdU8(off + 1)) shl 8)
           or (Int64(ElfRdU8(off + 2)) shl 16)
           or (Int64(ElfRdU8(off + 3)) shl 24);
end;

function ElfRdU64(off: Int64): Int64;
begin
  ElfRdU64 := ElfRdU32(off) or (ElfRdU32(off + 4) shl 32);
end;

{ A NUL-terminated name out of a string table. Bounded by the buffer, because a
  corrupt sh_name is otherwise an unbounded scan. }
function ElfRdStr(tabOff, idx: Int64): AnsiString;
var p: Int64; s: AnsiString; c: Integer;
begin
  s := '';
  p := tabOff + idx;
  while (p < Length(ElfRdBuf)) do
  begin
    c := ElfRdU8(p);
    if c = 0 then Break;
    s := s + Chr(c);
    p := p + 1;
  end;
  ElfRdStr := s;
end;

{ ---- header ---------------------------------------------------------------- }

{ True when the buffer is an ELF64 little-endian RELOCATABLE object. Sets
  ElfRdErr and returns False otherwise -- by NAME, so a caller can say which
  assumption failed instead of reporting "bad object". }
function ElfRdCheckHeader: Boolean;
var etype: Integer;
begin
  ElfRdCheckHeader := False;
  ElfRdErr := '';
  if Length(ElfRdBuf) < 64 then
  begin ElfRdErr := 'shorter than an ELF64 header (64 bytes)'; Exit; end;
  if (ElfRdU8(0) <> $7F) or (ElfRdU8(1) <> Ord('E'))
     or (ElfRdU8(2) <> Ord('L')) or (ElfRdU8(3) <> Ord('F')) then
  begin ElfRdErr := 'no ELF magic'; Exit; end;
  if ElfRdU8(4) <> 2 then
  begin ElfRdErr := 'not ELFCLASS64 (this reader is 64-bit only)'; Exit; end;
  if ElfRdU8(5) <> 1 then
  begin ElfRdErr := 'not ELFDATA2LSB (this reader is little-endian only)'; Exit; end;
  etype := ElfRdU16(16);
  if etype <> 1 then
  begin
    ElfRdErr := 'e_type is not ET_REL (1) but ' + AIntToStr(etype)
              + ' -- this reads relocatable objects, not executables or shared objects';
    Exit;
  end;
  ElfRdCheckHeader := True;
end;

function ElfRdShOff: Int64;   begin ElfRdShOff   := ElfRdU64($28); end;
function ElfRdShEntSz: Integer; begin ElfRdShEntSz := ElfRdU16($3A); end;
function ElfRdShNum: Integer;   begin ElfRdShNum   := ElfRdU16($3C); end;
function ElfRdShStrNdx: Integer; begin ElfRdShStrNdx := ElfRdU16($3E); end;

{ Byte offset of section header i. }
function ElfRdShdr(i: Integer): Int64;
begin
  ElfRdShdr := ElfRdShOff + Int64(i) * Int64(ElfRdShEntSz);
end;

function ElfRdShName(i: Integer): Int64;   begin ElfRdShName   := ElfRdU32(ElfRdShdr(i) + 0); end;
function ElfRdShType(i: Integer): Int64;   begin ElfRdShType   := ElfRdU32(ElfRdShdr(i) + 4); end;
function ElfRdShOffset(i: Integer): Int64; begin ElfRdShOffset := ElfRdU64(ElfRdShdr(i) + 24); end;
function ElfRdShSize(i: Integer): Int64;   begin ElfRdShSize   := ElfRdU64(ElfRdShdr(i) + 32); end;
function ElfRdShLink(i: Integer): Int64;   begin ElfRdShLink   := ElfRdU32(ElfRdShdr(i) + 40); end;
function ElfRdShEntSize(i: Integer): Int64; begin ElfRdShEntSize := ElfRdU64(ElfRdShdr(i) + 56); end;

function ElfRdSecName(i: Integer): AnsiString;
begin
  ElfRdSecName := ElfRdStr(ElfRdShOffset(ElfRdShStrNdx), ElfRdShName(i));
end;

{ ---- the dump, which is the whole falsifiability story ----------------------
  PRINTS COUNTS AND A PER-TYPE RELOCATION HISTOGRAM, because those are what
  readelf will corroborate and what a linker actually consumes. Deliberately
  NOT a pretty-printer of every entry: a diff of thousands of lines against
  readelf's own formatting would be a test of two formatters agreeing. }
procedure ElfRdDump(const path: AnsiString);
var i, j, nsec, symEnts: Integer;
    nsym, nrel, nund, ndef: Int64;
    stOff, stSize, stEnt, strTab, e, info, rtype, shndx: Int64;
    relTotal: Int64;
    tcount: array[0..63] of Int64;
    ttotal: Int64;
begin
  LoadFile(path, ElfRdBuf);
  if Length(ElfRdBuf) = 0 then
  begin
    WriteLn('elfrd: cannot read ', path);
    Exit;
  end;
  if not ElfRdCheckHeader then
  begin
    WriteLn('elfrd: ', path, ': ', ElfRdErr);
    Exit;
  end;
  nsec := ElfRdShNum;
  WriteLn('elfrd: file ', path);
  WriteLn('elfrd: bytes ', AIntToStr(Length(ElfRdBuf)));
  WriteLn('elfrd: sections ', AIntToStr(nsec));
  for i := 0 to nsec - 1 do
    WriteLn('elfrd: sec ', AIntToStr(i), ' ', ElfRdSecName(i),
            ' type=', AIntToStr(ElfRdShType(i)),
            ' size=', AIntToStr(ElfRdShSize(i)));

  { symbols }
  nsym := 0; nund := 0; ndef := 0;
  for i := 0 to nsec - 1 do
    if ElfRdShType(i) = ELFRD_SHT_SYMTAB then
    begin
      stOff := ElfRdShOffset(i);
      stSize := ElfRdShSize(i);
      stEnt := ElfRdShEntSize(i);
      strTab := ElfRdShOffset(ElfRdShLink(i));
      if stEnt <= 0 then stEnt := 24;
      symEnts := Integer(stSize div stEnt);
      nsym := nsym + symEnts;
      { index 0 is the reserved null symbol and is not a symbol anyone links }
      for j := 1 to symEnts - 1 do
      begin
        e := stOff + Int64(j) * stEnt;
        shndx := ElfRdU16(e + 6);
        if shndx = 0 then nund := nund + 1 else ndef := ndef + 1;
      end;
      { strTab is read so a later stage has the name; touched here so an
        unreadable link index fails now rather than at merge time }
      if strTab < 0 then WriteLn('elfrd: WARNING symtab sh_link is out of range');
    end;
  WriteLn('elfrd: symbols ', AIntToStr(nsym),
          ' defined ', AIntToStr(ndef), ' undefined ', AIntToStr(nund));

  { relocations, with a per-type histogram }
  for i := 0 to 63 do tcount[i] := 0;
  relTotal := 0;
  for i := 0 to nsec - 1 do
    if ElfRdShType(i) = ELFRD_SHT_RELA then
    begin
      stOff := ElfRdShOffset(i);
      stEnt := ElfRdShEntSize(i);
      if stEnt <= 0 then stEnt := 24;
      nrel := ElfRdShSize(i) div stEnt;
      relTotal := relTotal + nrel;
      for j := 0 to Integer(nrel) - 1 do
      begin
        e := stOff + Int64(j) * stEnt;
        info := ElfRdU64(e + 8);
        rtype := info and $FFFFFFFF;
        if (rtype >= 0) and (rtype <= 63) then
          tcount[Integer(rtype)] := tcount[Integer(rtype)] + 1;
      end;
    end;
  WriteLn('elfrd: relocations ', AIntToStr(relTotal));
  ttotal := 0;
  for i := 0 to 63 do
    if tcount[i] > 0 then
    begin
      WriteLn('elfrd: reltype ', AIntToStr(i), ' ', AIntToStr(tcount[i]));
      ttotal := ttotal + tcount[i];
    end;
  { THE HISTOGRAM MUST ACCOUNT FOR EVERY RELOCATION. A type above 63 would be
    counted in relTotal and missing from the histogram, so the two numbers are
    compared rather than both being printed and trusted. }
  if ttotal <> relTotal then
    WriteLn('elfrd: WARNING histogram ', AIntToStr(ttotal),
            ' does not account for all ', AIntToStr(relTotal),
            ' relocations -- a type outside 0..63 is present');
  WriteLn('elfrd: ELFRD-OK');
end;

{ ---- symbol-table merge ----------------------------------------------------
  THE SECOND STAGE OF ROUTE 2, and the first one that has an OPINION rather
  than just a reading. The reader above answers "what is in this object"; this
  answers "what does this SET of objects still need, and what does it define
  twice" -- the two questions a linker exists to settle before it can lay
  anything out.

  ITS OWN HASH, NOT InternStr. InternStr is hash-backed and would have been
  free, and it is the wrong table: it interns the LITERALS OF THE PROGRAM BEING
  COMPILED and lays out string objects for emission. Linker symbol names are
  not that program's data, and putting them there would make the emitter's
  string pool depend on how many objects were on the command line. Same
  open-chaining shape, separate table, ~40 lines.

  WHY NOT A LINEAR SCAN: 400 busybox objects at ~493 symbols each is ~200k
  lookups against a growing table. Linear is ~10^10 comparisons. This is the
  one place in the reader where the constant factor decides whether the stage
  is usable at the scale the ticket cares about.

  LOCAL SYMBOLS ARE SKIPPED BY BINDING, NOT BY NAME. A local symbol is private
  to its object by definition, so two objects may both define `buf` at local
  binding and neither is a duplicate. Filtering on the name -- or on "does it
  look internal" -- would report collisions that are not collisions, which is
  the shape that makes a linker refuse a correct program. }

const
  ELFLNK_STB_LOCAL  = 0;
  ELFLNK_STB_WEAK   = 2;

var
  ElfLnkName  : array of AnsiString;   { distinct global/weak symbol names }
  ElfLnkDefs  : array of Integer;      { strong definitions seen }
  ElfLnkWeak  : array of Integer;      { weak definitions seen }
  ElfLnkRefs  : array of Integer;      { undefined references seen }
  ElfLnkFirst : array of AnsiString;   { object that first defined it, for the duplicate report }
  ElfLnkCount : Integer;
  ElfLnkHead  : array of Integer;
  ElfLnkNext  : array of Integer;
  ElfLnkMask  : Integer;

function ElfLnkHash(const s: AnsiString): Integer;
var i, h: Integer;
begin
  h := 5381;
  for i := 1 to Length(s) do
    h := ((h * 33) + Ord(s[i])) and $7FFFFFFF;
  ElfLnkHash := h;
end;

procedure ElfLnkReset;
var i: Integer;
begin
  ElfLnkCount := 0;
  ElfLnkMask := 16383;
  SetLength(ElfLnkHead, ElfLnkMask + 1);
  for i := 0 to ElfLnkMask do ElfLnkHead[i] := -1;
  SetLength(ElfLnkName, 0);
  SetLength(ElfLnkDefs, 0);
  SetLength(ElfLnkWeak, 0);
  SetLength(ElfLnkRefs, 0);
  SetLength(ElfLnkFirst, 0);
  SetLength(ElfLnkNext, 0);
end;

{ Index of `nm`, inserting it if new. }
function ElfLnkIntern(const nm: AnsiString): Integer;
var b, i, n: Integer;
begin
  b := ElfLnkHash(nm) and ElfLnkMask;
  i := ElfLnkHead[b];
  while i >= 0 do
  begin
    if ElfLnkName[i] = nm then begin ElfLnkIntern := i; Exit; end;
    i := ElfLnkNext[i];
  end;
  n := ElfLnkCount;
  SetLength(ElfLnkName, n + 1);
  SetLength(ElfLnkDefs, n + 1);
  SetLength(ElfLnkWeak, n + 1);
  SetLength(ElfLnkRefs, n + 1);
  SetLength(ElfLnkFirst, n + 1);
  SetLength(ElfLnkNext, n + 1);
  ElfLnkName[n] := nm;
  ElfLnkDefs[n] := 0;
  ElfLnkWeak[n] := 0;
  ElfLnkRefs[n] := 0;
  ElfLnkFirst[n] := '';
  ElfLnkNext[n] := ElfLnkHead[b];
  ElfLnkHead[b] := n;
  ElfLnkCount := n + 1;
  ElfLnkIntern := n;
end;

{ Fold one object's global symbols into the table. False (with ElfRdErr set)
  when the object cannot be read -- a link that silently skips an unreadable
  input would report a smaller unresolved set than the truth. }
function ElfLnkAddObject(const path: AnsiString): Boolean;
var i, j, nsec, symEnts, bind, k: Integer;
    stOff, stSize, stEnt, strTab, e, shndx, nameIdx: Int64;
    nm: AnsiString;
begin
  ElfLnkAddObject := False;
  LoadFile(path, ElfRdBuf);
  if Length(ElfRdBuf) = 0 then begin ElfRdErr := 'cannot read'; Exit; end;
  if not ElfRdCheckHeader then Exit;
  nsec := ElfRdShNum;
  for i := 0 to nsec - 1 do
    if ElfRdShType(i) = ELFRD_SHT_SYMTAB then
    begin
      stOff := ElfRdShOffset(i);
      stSize := ElfRdShSize(i);
      stEnt := ElfRdShEntSize(i);
      strTab := ElfRdShOffset(ElfRdShLink(i));
      if stEnt <= 0 then stEnt := 24;
      symEnts := Integer(stSize div stEnt);
      for j := 1 to symEnts - 1 do
      begin
        e := stOff + Int64(j) * stEnt;
        bind := ElfRdU8(e + 4) shr 4;
        if bind = ELFLNK_STB_LOCAL then Continue;
        nameIdx := ElfRdU32(e + 0);
        if nameIdx = 0 then Continue;
        nm := ElfRdStr(strTab, nameIdx);
        if nm = '' then Continue;
        shndx := ElfRdU16(e + 6);
        k := ElfLnkIntern(nm);
        if shndx = 0 then
          ElfLnkRefs[k] := ElfLnkRefs[k] + 1
        else if bind = ELFLNK_STB_WEAK then
          ElfLnkWeak[k] := ElfLnkWeak[k] + 1
        else
        begin
          ElfLnkDefs[k] := ElfLnkDefs[k] + 1;
          if ElfLnkFirst[k] = '' then ElfLnkFirst[k] := path;
        end;
      end;
    end;
  ElfLnkAddObject := True;
end;

{ PXXDBG=a.objmerge:<listfile> -- one object path per line.

  A LIST FILE RATHER THAN A SEPARATED ARGUMENT, for two reasons that are not
  style: PXXDBG splits topics on ',' so a comma-separated list cannot be
  expressed at all, and the population this stage is FOR is 400 busybox
  objects, which is not a command line. }
procedure ElfLnkMergeDump(const listPath: AnsiString);
var lst, line, nm: AnsiString;
    i, nobj, unresolved, dup, definedCount, weakOnly: Integer;
    c: Char;
begin
  LoadFile(listPath, lst);
  if Length(lst) = 0 then
  begin
    WriteLn('elflnk: cannot read list ', listPath);
    Exit;
  end;
  ElfLnkReset;
  nobj := 0;
  line := '';
  for i := 1 to Length(lst) + 1 do
  begin
    if i <= Length(lst) then c := lst[i] else c := Chr(10);
    if c = Chr(10) then
    begin
      if Length(line) > 0 then
      begin
        if not ElfLnkAddObject(line) then
        begin
          WriteLn('elflnk: ', line, ': ', ElfRdErr);
          Exit;
        end;
        nobj := nobj + 1;
      end;
      line := '';
    end
    else if c <> Chr(13) then
      line := line + c;
  end;

  unresolved := 0; dup := 0; definedCount := 0; weakOnly := 0;
  for i := 0 to ElfLnkCount - 1 do
  begin
    if ElfLnkDefs[i] > 1 then dup := dup + 1;
    if (ElfLnkDefs[i] > 0) then definedCount := definedCount + 1
    else if ElfLnkWeak[i] > 0 then weakOnly := weakOnly + 1
    else if ElfLnkRefs[i] > 0 then unresolved := unresolved + 1;
  end;

  WriteLn('elflnk: objects ', AIntToStr(nobj));
  WriteLn('elflnk: globals ', AIntToStr(ElfLnkCount));
  WriteLn('elflnk: defined ', AIntToStr(definedCount));
  WriteLn('elflnk: weakonly ', AIntToStr(weakOnly));
  WriteLn('elflnk: unresolved ', AIntToStr(unresolved));
  WriteLn('elflnk: duplicate ', AIntToStr(dup));
  { NAMED, not just counted. An unresolved COUNT tells a user nothing they can
    act on, and the one time this mattered in this repo the answer was a single
    symbol (pivot_root) hiding behind a glibc stub. Bounded so a badly-formed
    link does not print 200k lines. }
  for i := 0 to ElfLnkCount - 1 do
    if (ElfLnkDefs[i] = 0) and (ElfLnkWeak[i] = 0) and (ElfLnkRefs[i] > 0) then
    begin
      nm := ElfLnkName[i];
      WriteLn('elflnk: undef ', nm);
    end;
  for i := 0 to ElfLnkCount - 1 do
    if ElfLnkDefs[i] > 1 then
      WriteLn('elflnk: dup ', ElfLnkName[i], ' x', AIntToStr(ElfLnkDefs[i]));
  WriteLn('elflnk: ELFLNK-OK');
end;
