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

{ ---- stage 3 state: which object and section DEFINES each global ------------
  The merge above only COUNTS, which is enough to say what a set needs and
  what it defines twice. A layout has to say WHERE, so the merge now also
  remembers, per global, the definition a linker would choose -- and per
  object, the input sections that carry bytes into the image.

  SECTIONS ARE CONCATENATED PER NAME, NOT PER TYPE, and this is the decision
  the stage opens with. Per TYPE is simply wrong for our objects: .text and
  .data are BOTH SHT_PROGBITS, so a type key merges code into data. The name
  is what ld's default script keys on too. The TYPE and FLAGS are then CHECKED
  against the name rather than trusted, so a section that is called .text but
  is not ALLOC|EXEC is refused instead of mapped.

  THE SET IS TAKEN FROM THE EMITTER, NOT FROM A CORPUS: writeELFRelX64General
  writes exactly .text, .data, .bss and -- only when a frontend emitted the
  thunks -- .init_array and .fini_array; writeELFRelX64 (the .asm frontend's)
  writes .text alone. Those five names are the whole allocated vocabulary. Any
  other ALLOCATED section is refused by name: it is not ours, and this linker's
  scope is pxx's own objects (rung 1 of the ticket). NON-allocated sections
  (.symtab, .rela.*, a .note.GNU-stack) carry no bytes into the image and are
  passed over.

  The kind constants are in OUTPUT ORDER: text first in the RX segment, then
  the RW segment as ld lays it out -- .init_array, .fini_array, .data, .bss. }

const
  ELFLNK_NKIND  = 5;
  ELFLNK_K_TEXT = 0;
  ELFLNK_K_INIT = 1;
  ELFLNK_K_FINI = 2;
  ELFLNK_K_DATA = 3;
  ELFLNK_K_BSS  = 4;
  ELFLNK_K_ABS  = -1;           { a definition against SHN_ABS: its value is the address }
  ELFLNK_BASE   = $400000;      { the static non-PIE image base ld uses on x86-64 }
  ELFLNK_PAGE   = $1000;

var
  ElfLnkObjPath  : array of AnsiString;
  ElfLnkObjCount : Integer;
  { indexed [obj * ELFLNK_NKIND + kind]; shndx 0 means "this object has none" }
  ElfLnkInShndx  : array of Integer;
  ElfLnkInSize   : array of Int64;
  ElfLnkInAlign  : array of Int64;
  ElfLnkInAddr   : array of Int64;
  { the output sections, indexed by kind }
  ElfLnkOutAddr  : array[0..4] of Int64;
  ElfLnkOutSize  : array[0..4] of Int64;
  { the CHOSEN definition per global: object, kind, st_value, and whether it is
    weak (a later STRONG definition displaces a weak one; a later weak one does
    not -- the first weak definition in link order stands, as in ld). }
  ElfLnkDefObj   : array of Integer;
  ElfLnkDefKind  : array of Integer;
  ElfLnkDefVal   : array of Int64;
  ElfLnkDefIsWeak: array of Boolean;

function ElfLnkKindName(k: Integer): AnsiString;
begin
  case k of
    ELFLNK_K_TEXT: ElfLnkKindName := '.text';
    ELFLNK_K_INIT: ElfLnkKindName := '.init_array';
    ELFLNK_K_FINI: ElfLnkKindName := '.fini_array';
    ELFLNK_K_DATA: ElfLnkKindName := '.data';
    ELFLNK_K_BSS:  ElfLnkKindName := '.bss';
  else
    ElfLnkKindName := '?';
  end;
end;

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
  SetLength(ElfLnkDefObj, 0);
  SetLength(ElfLnkDefKind, 0);
  SetLength(ElfLnkDefVal, 0);
  SetLength(ElfLnkDefIsWeak, 0);
  ElfLnkObjCount := 0;
  SetLength(ElfLnkObjPath, 0);
  SetLength(ElfLnkInShndx, 0);
  SetLength(ElfLnkInSize, 0);
  SetLength(ElfLnkInAlign, 0);
  SetLength(ElfLnkInAddr, 0);
  for i := 0 to ELFLNK_NKIND - 1 do
  begin
    ElfLnkOutAddr[i] := 0;
    ElfLnkOutSize[i] := 0;
  end;
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
  SetLength(ElfLnkDefObj, n + 1);
  SetLength(ElfLnkDefKind, n + 1);
  SetLength(ElfLnkDefVal, n + 1);
  SetLength(ElfLnkDefIsWeak, n + 1);
  ElfLnkDefObj[n] := -1;
  ElfLnkDefKind[n] := 0;
  ElfLnkDefVal[n] := 0;
  ElfLnkDefIsWeak[n] := False;
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
function ElfRdShFlags(i: Integer): Int64;     begin ElfRdShFlags     := ElfRdU64(ElfRdShdr(i) + 8); end;
function ElfRdShAddrAlign(i: Integer): Int64; begin ElfRdShAddrAlign := ElfRdU64(ElfRdShdr(i) + 48); end;

{ The output kind of input section i, ELFLNK_NKIND when it carries nothing into
  the image (not SHF_ALLOC), or -1 with ElfRdErr set when it is allocated and
  not one of ours. THE TYPE AND FLAGS ARE CHECKED AGAINST THE NAME: the name
  picks the kind, and a section whose type contradicts its name is refused
  rather than mapped by whichever of the two a reader happened to trust. }
function ElfLnkSecKind(i: Integer): Integer;
var nm: AnsiString; ty, fl, wantTy, wantFl: Int64; k: Integer;
begin
  ElfLnkSecKind := -1;
  nm := ElfRdSecName(i);
  ty := ElfRdShType(i);
  fl := ElfRdShFlags(i);
  if (fl and 2) = 0 then begin ElfLnkSecKind := ELFLNK_NKIND; Exit; end;   { not SHF_ALLOC }
  k := -1; wantTy := 0; wantFl := 0;
  if nm = '.text'       then begin k := ELFLNK_K_TEXT; wantTy := 1;  wantFl := 6; end
  else if nm = '.data'  then begin k := ELFLNK_K_DATA; wantTy := 1;  wantFl := 3; end
  else if nm = '.bss'   then begin k := ELFLNK_K_BSS;  wantTy := ELFRD_SHT_NOBITS; wantFl := 3; end
  else if nm = '.init_array' then begin k := ELFLNK_K_INIT; wantTy := 14; wantFl := 3; end
  else if nm = '.fini_array' then begin k := ELFLNK_K_FINI; wantTy := 15; wantFl := 3; end;
  if k < 0 then
  begin
    ElfRdErr := 'allocated section ''' + nm + ''' is not one pxx emits -- this '
              + 'links pxx''s own objects (.text .data .bss .init_array .fini_array), '
              + 'not a third-party toolchain''s';
    Exit;
  end;
  { ALLOC|WRITE|EXEC only; SHF_INFO_LINK and the rest are not layout-bearing }
  if (ty <> wantTy) or ((fl and 7) <> wantFl) then
  begin
    ElfRdErr := 'section ''' + nm + ''' has type ' + AIntToStr(ty) + ' flags '
              + AIntToStr(fl and 7) + ', and pxx writes that name as type '
              + AIntToStr(wantTy) + ' flags ' + AIntToStr(wantFl);
    Exit;
  end;
  ElfLnkSecKind := k;
end;

function ElfLnkAddObject(const path: AnsiString): Boolean;
var i, j, nsec, symEnts, bind, k, obj, kind, slot: Integer;
    stOff, stSize, stEnt, strTab, e, shndx, nameIdx, al: Int64;
    nm: AnsiString;
    secKind: array of Integer;
begin
  ElfLnkAddObject := False;
  LoadFile(path, ElfRdBuf);
  if Length(ElfRdBuf) = 0 then begin ElfRdErr := 'cannot read'; Exit; end;
  if not ElfRdCheckHeader then Exit;
  nsec := ElfRdShNum;

  { register the object and its input sections }
  obj := ElfLnkObjCount;
  ElfLnkObjCount := obj + 1;
  SetLength(ElfLnkObjPath, obj + 1);
  ElfLnkObjPath[obj] := path;
  SetLength(ElfLnkInShndx, (obj + 1) * ELFLNK_NKIND);
  SetLength(ElfLnkInSize,  (obj + 1) * ELFLNK_NKIND);
  SetLength(ElfLnkInAlign, (obj + 1) * ELFLNK_NKIND);
  SetLength(ElfLnkInAddr,  (obj + 1) * ELFLNK_NKIND);
  for k := 0 to ELFLNK_NKIND - 1 do
  begin
    slot := obj * ELFLNK_NKIND + k;
    ElfLnkInShndx[slot] := 0;
    ElfLnkInSize[slot] := 0;
    ElfLnkInAlign[slot] := 1;
    ElfLnkInAddr[slot] := 0;
  end;
  SetLength(secKind, nsec);
  for i := 0 to nsec - 1 do
  begin
    secKind[i] := ELFLNK_NKIND;
    if i = 0 then Continue;
    kind := ElfLnkSecKind(i);
    if kind < 0 then Exit;
    secKind[i] := kind;
    if kind = ELFLNK_NKIND then Continue;
    slot := obj * ELFLNK_NKIND + kind;
    { ONE PER NAME PER OBJECT is what the emitter writes. Two would need a rule
      for their relative order that nothing here has had to decide. }
    if ElfLnkInShndx[slot] <> 0 then
    begin
      ElfRdErr := 'two ' + ElfLnkKindName(kind) + ' sections in one object; pxx writes one';
      Exit;
    end;
    al := ElfRdShAddrAlign(i);
    if al < 1 then al := 1;
    ElfLnkInShndx[slot] := i;
    ElfLnkInSize[slot] := ElfRdShSize(i);
    ElfLnkInAlign[slot] := al;
  end;
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
        begin
          ElfLnkRefs[k] := ElfLnkRefs[k] + 1;
          Continue;
        end;
        if bind = ELFLNK_STB_WEAK then
          ElfLnkWeak[k] := ElfLnkWeak[k] + 1
        else
        begin
          ElfLnkDefs[k] := ElfLnkDefs[k] + 1;
          if ElfLnkFirst[k] = '' then ElfLnkFirst[k] := path;
        end;
        { WHERE the definition lives. SHN_ABS carries its address in st_value.
          SHN_COMMON is what -fcommon would emit and our writer does not (a
          tentative definition is a real .bss OBJECT here), so it is refused
          by name rather than laid out by a rule nobody decided. }
        if shndx = $FFF1 then kind := ELFLNK_K_ABS
        else if (shndx >= $FF00) or (shndx >= nsec) then
        begin
          ElfRdErr := 'symbol ''' + nm + ''' is defined against special section index '
                    + AIntToStr(shndx) + ', which pxx does not emit';
          Exit;
        end
        else
        begin
          kind := secKind[Integer(shndx)];
          if kind = ELFLNK_NKIND then
          begin
            ElfRdErr := 'symbol ''' + nm + ''' is defined in section '''
                      + ElfRdSecName(Integer(shndx)) + ''', which is not allocated';
            Exit;
          end;
        end;
        { ld's rule: a STRONG definition displaces a weak one, and among weak
          ones the FIRST in link order stands. Two strong ones are the
          duplicate the counts above already report; the first is kept so the
          layout is still defined for the dump. }
        if (ElfLnkDefObj[k] < 0)
           or (ElfLnkDefIsWeak[k] and (bind <> ELFLNK_STB_WEAK)) then
        begin
          ElfLnkDefObj[k] := obj;
          ElfLnkDefKind[k] := kind;
          ElfLnkDefVal[k] := ElfRdU64(e + 8);
          ElfLnkDefIsWeak[k] := bind = ELFLNK_STB_WEAK;
        end;
      end;
    end;
  ElfLnkAddObject := True;
end;

function ElfLnkAlignUp(v, a: Int64): Int64;
begin
  if a <= 1 then ElfLnkAlignUp := v
  else ElfLnkAlignUp := ((v + a - 1) div a) * a;
end;

{ ---- stage 3: section layout -----------------------------------------------
  Assign every input section an output address. Inputs are concatenated per
  kind IN LINK ORDER, each at its own sh_addralign -- which is what ld does, and
  what makes the order of .init_array entries (and so of constructors) the
  command-line order rather than an accident of this table.

  THE IMAGE: one RX segment from ELFLNK_BASE holding the ELF and program
  headers in its first page and .text from base+page -- the address ld gives
  .text in a -static -nostdlib link, so a reader comparing the two images sees
  the same code addresses -- then a RW segment starting on the next page
  boundary IN THE FILE, at the congruent address, holding .init_array,
  .fini_array, .data and .bss in that order. ld packs the RW segment tighter
  (it shares a page with the end of .text and aligns RELRO); that costs it
  nothing and saves under a page, and matching it would couple this layout to
  one linker version's script for no behaviour. Where the two layouts differ
  is exactly what the oracle neutralises with --section-start.

  An output section with no inputs has size 0 and an address that nothing
  refers to; the writer omits it. }
procedure ElfLnkLayout;
var k, o, slot: Integer;
    addr, start, maxAl, rwFile: Int64;
begin
  addr := ELFLNK_BASE + ELFLNK_PAGE;
  for k := 0 to ELFLNK_NKIND - 1 do
  begin
    if k = ELFLNK_K_INIT then
    begin
      { the RW segment: next page in the FILE, at the congruent address }
      rwFile := ElfLnkAlignUp(ELFLNK_PAGE + ElfLnkOutSize[ELFLNK_K_TEXT], ELFLNK_PAGE);
      addr := ELFLNK_BASE + rwFile;
    end;
    maxAl := 1;
    for o := 0 to ElfLnkObjCount - 1 do
    begin
      slot := o * ELFLNK_NKIND + k;
      if (ElfLnkInShndx[slot] <> 0) and (ElfLnkInAlign[slot] > maxAl) then
        maxAl := ElfLnkInAlign[slot];
    end;
    start := ElfLnkAlignUp(addr, maxAl);
    addr := start;
    for o := 0 to ElfLnkObjCount - 1 do
    begin
      slot := o * ELFLNK_NKIND + k;
      if ElfLnkInShndx[slot] = 0 then Continue;
      addr := ElfLnkAlignUp(addr, ElfLnkInAlign[slot]);
      ElfLnkInAddr[slot] := addr;
      addr := addr + ElfLnkInSize[slot];
    end;
    ElfLnkOutAddr[k] := start;
    ElfLnkOutSize[k] := addr - start;
  end;
end;

{ The final address of global k's chosen definition. Only meaningful when
  ElfLnkDefObj[k] >= 0. }
function ElfLnkGlobalAddr(k: Integer): Int64;
begin
  if ElfLnkDefKind[k] = ELFLNK_K_ABS then
    ElfLnkGlobalAddr := ElfLnkDefVal[k]
  else
    ElfLnkGlobalAddr := ElfLnkInAddr[ElfLnkDefObj[k] * ELFLNK_NKIND + ElfLnkDefKind[k]]
                        + ElfLnkDefVal[k];
end;

{ PXXDBG=a.objmerge:<listfile> -- one object path per line.

  A LIST FILE RATHER THAN A SEPARATED ARGUMENT, for two reasons that are not
  style: PXXDBG splits topics on ',' so a comma-separated list cannot be
  expressed at all, and the population this stage is FOR is 400 busybox
  objects, which is not a command line. }
{ Read a list file and fold every object in it, IN ORDER -- the order is the
  link order, and stage 3 makes it observable. False after printing the reason
  under `tag` when the list or any object cannot be read: a link that skips an
  unreadable input reports a smaller world than the truth. }
function ElfLnkLoadList(const listPath, tag: AnsiString): Boolean;
var lst, line: AnsiString;
    i: Integer;
    c: Char;
begin
  ElfLnkLoadList := False;
  LoadFile(listPath, lst);
  if Length(lst) = 0 then
  begin
    WriteLn(tag, ': cannot read list ', listPath);
    Exit;
  end;
  ElfLnkReset;
  line := '';
  for i := 1 to Length(lst) + 1 do
  begin
    if i <= Length(lst) then c := lst[i] else c := Chr(10);
    if c = Chr(10) then
    begin
      if Length(line) > 0 then
        if not ElfLnkAddObject(line) then
        begin
          WriteLn(tag, ': ', line, ': ', ElfRdErr);
          Exit;
        end;
      line := '';
    end
    else if c <> Chr(13) then
      line := line + c;
  end;
  ElfLnkLoadList := True;
end;

procedure ElfLnkMergeDump(const listPath: AnsiString);
var nm: AnsiString;
    i, nobj, unresolved, dup, definedCount, weakOnly: Integer;
begin
  if not ElfLnkLoadList(listPath, 'elflnk') then Exit;
  nobj := ElfLnkObjCount;

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

{ PXXDBG=a.objlayout:<listfile> -- stage 3's answer: where every output
  section starts and how big it is, where each object's input sections landed,
  and the final address of every DEFINED global.

  THE SYMBOL ADDRESSES ARE THE CHECKABLE PART. ld, told to put each output
  section where this layout did (--section-start), must then give every global
  the same address; that single comparison exercises input order, per-input
  alignment, the per-kind concatenation AND the weak/strong choice at once,
  because a wrong choice between two weak copies lands the name in a different
  object. An address is printed only for a global that HAS a definition --
  an unresolved one has none to compare, and the merge dump names those. }
procedure ElfLnkLayoutDump(const listPath: AnsiString);
var k, o, slot: Integer;
begin
  if not ElfLnkLoadList(listPath, 'elflay') then Exit;
  ElfLnkLayout;
  WriteLn('elflay: objects ', AIntToStr(ElfLnkObjCount));
  for k := 0 to ELFLNK_NKIND - 1 do
    WriteLn('elflay: out ', ElfLnkKindName(k), ' 0x', IntToHexStr(ElfLnkOutAddr[k], 16),
            ' size ', AIntToStr(ElfLnkOutSize[k]));
  for o := 0 to ElfLnkObjCount - 1 do
    for k := 0 to ELFLNK_NKIND - 1 do
    begin
      slot := o * ELFLNK_NKIND + k;
      if ElfLnkInShndx[slot] <> 0 then
        WriteLn('elflay: in ', AIntToStr(o), ' ', ElfLnkKindName(k),
                ' 0x', IntToHexStr(ElfLnkInAddr[slot], 16),
                ' size ', AIntToStr(ElfLnkInSize[slot]),
                ' align ', AIntToStr(ElfLnkInAlign[slot]));
    end;
  for k := 0 to ElfLnkCount - 1 do
    if ElfLnkDefObj[k] >= 0 then
      WriteLn('elflay: sym ', IntToHexStr(ElfLnkGlobalAddr(k), 16), ' ', ElfLnkName[k]);
  WriteLn('elflay: ELFLAY-OK');
end;
