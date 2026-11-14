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
  LoadInput(path, ElfRdBuf);
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
  ElfLnkStrongRef : array of Boolean;  { some reference is NOT weak -- an undefined weak one is 0, not an error }
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
  the RW segment as ld lays it out -- .init_array, .fini_array, .data, .bss.

  --link --freestanding (a kernel; Gibux, 2026-11-12) widens the vocabulary by
  two RX kinds and one relocation type, and only there, so the refusal controls
  in tools/elf_reader_vs_readelf.sh keep their meaning for ordinary links:
    .multiboot          first in the image (a boot loader looks for its header
                        in the first 8 KiB) and never collected, like
                        KEEP(*(.multiboot)) in a GNU script;
    .rodata .rodata.*   after .text, in the same RX segment;
    R_X86_64_32         a zero-extended 32-bit absolute (32-bit boot code);
    .note .note.*       SHT_NOTE, after .rodata in the RX segment, never
                        collected, and covered by a PT_NOTE program header
                        (a PVH loader reads XEN_ELFNOTE_PHYS32_ENTRY there).
  Those inputs come from the kernel's .S files assembled by gas until pxx has
  its own .S frontend. }

const
  ELFLNK_NKIND  = 8;
  ELFLNK_K_HEAD = 0;
  ELFLNK_K_TEXT = 1;
  ELFLNK_K_RODATA = 2;
  ELFLNK_K_NOTE = 3;
  ELFLNK_K_INIT = 4;
  ELFLNK_K_FINI = 5;
  ELFLNK_K_DATA = 6;
  ELFLNK_K_BSS  = 7;
  ELFLNK_K_ABS  = -1;           { a definition against SHN_ABS: its value is the address }
  { The image base is ImageBase: LOAD_ADDR ($400000, the static non-PIE base ld
    uses on x86-64) unless --image-base / --gibix moved it. }
  ELFLNK_PAGE   = $1000;
  ELFLNK_STUB_SIZE_X64 = 93;    { the synthesised _start; see ElfLnkPutStub }
  ELFLNK_STUB_SIZE_A64 = 128;   { 26 instructions + 3 literal quads; ElfLnkPutStubA64 }
  ELFLNK_EM_X86_64 = 62;
  ELFLNK_EM_AARCH64 = 183;

var
  ElfLnkObjPath  : array of AnsiString;
  ElfLnkObjCount : Integer;
  { ONE SLOT PER SECTION HEADER of every object: object o's section i is slot
    ElfLnkObjSec0[o] + i. A slot rather than one input per KIND because a
    --function-sections object carries a .text section per function, and
    garbage collection keeps or drops them one at a time. }
  ElfLnkObjSec0  : array of Integer;
  ElfLnkObjNsec  : array of Integer;
  ElfLnkSecKindOf: array of Integer;   { output kind, or ELFLNK_NKIND: carries no bytes }
  ElfLnkSecSize  : array of Int64;
  ElfLnkSecAlign : array of Int64;
  ElfLnkSecAddr  : array of Int64;
  ElfLnkSecLive  : array of Boolean;   { laid out and written; see ElfLnkGcMark }
  ElfLnkSecCount : Integer;
  { THE REFERENCE GRAPH, one edge per relocation: FROM the slot it patches TO a
    slot (>= 0, a local or section symbol) or to a global NAME, -(g+1) --
    resolved only at marking time, because which object's copy a global means
    is decided by the whole link, not by the object that names it. }
  ElfLnkEdgeFrom : array of Integer;
  ElfLnkEdgeTo   : array of Integer;
  ElfLnkEdgeCount: Integer;
  ElfLnkGcOn     : Boolean;
  { the output sections, indexed by kind }
  ElfLnkOutAddr  : array[0..7] of Int64;
  ElfLnkOutSize  : array[0..7] of Int64;
  ElfLnkNoteAlign: Int64;             { the largest .note* input alignment: PT_NOTE's p_align }
  { the CHOSEN definition per global: object, kind, st_value, and whether it is
    weak (a later STRONG definition displaces a weak one; a later weak one does
    not -- the first weak definition in link order stands, as in ld). }
  ElfLnkDefObj   : array of Integer;
  ElfLnkDefSec   : array of Integer;  { slot of the chosen definition, -1 for SHN_ABS }
  ElfLnkDefVal   : array of Int64;
  ElfLnkDefIsWeak: array of Boolean;
  ElfLnkDefInfo  : array of Integer;  { st_info of the chosen definition, for the output .symtab }
  ElfLnkDefSize  : array of Int64;
  ElfLnkRwFile   : Int64;             { file offset (and base-relative address) of the RW segment }
  ElfLnkRxEnd    : Int64;             { file offset (and base-relative address) where the RX segment ends }
  ElfLnkEntryStub: Boolean;           { reserve and write the synthesised _start (stage 5) }
  ElfLnkStubAddr : Int64;
  ElfLnkMachine  : Integer;           { e_machine of the inputs and the output: 62 or 183 }

function ElfLnkKindName(k: Integer): AnsiString;
begin
  case k of
    ELFLNK_K_HEAD: ElfLnkKindName := '.multiboot';
    ELFLNK_K_TEXT: ElfLnkKindName := '.text';
    ELFLNK_K_RODATA: ElfLnkKindName := '.rodata';
    ELFLNK_K_NOTE: ElfLnkKindName := '.note';
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
  SetLength(ElfLnkStrongRef, 0);
  SetLength(ElfLnkFirst, 0);
  SetLength(ElfLnkNext, 0);
  SetLength(ElfLnkDefObj, 0);
  SetLength(ElfLnkDefSec, 0);
  SetLength(ElfLnkDefVal, 0);
  SetLength(ElfLnkDefIsWeak, 0);
  SetLength(ElfLnkDefInfo, 0);
  SetLength(ElfLnkDefSize, 0);
  ElfLnkRwFile := 0;
  ElfLnkRxEnd := 0;
  ElfLnkEntryStub := False;
  ElfLnkStubAddr := 0;
  ElfLnkMachine := ELFLNK_EM_X86_64;
  ElfLnkObjCount := 0;
  SetLength(ElfLnkObjPath, 0);
  SetLength(ElfLnkObjSec0, 0);
  SetLength(ElfLnkObjNsec, 0);
  ElfLnkSecCount := 0;
  ElfLnkEdgeCount := 0;
  ElfLnkGcOn := False;
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
  SetLength(ElfLnkStrongRef, n + 1);
  ElfLnkStrongRef[n] := False;
  SetLength(ElfLnkFirst, n + 1);
  SetLength(ElfLnkNext, n + 1);
  SetLength(ElfLnkDefObj, n + 1);
  SetLength(ElfLnkDefSec, n + 1);
  SetLength(ElfLnkDefVal, n + 1);
  SetLength(ElfLnkDefIsWeak, n + 1);
  SetLength(ElfLnkDefInfo, n + 1);
  SetLength(ElfLnkDefSize, n + 1);
  ElfLnkDefInfo[n] := 0;
  ElfLnkDefSize[n] := 0;
  ElfLnkDefObj[n] := -1;
  ElfLnkDefSec[n] := -1;
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
  { `.text.<name>` is a --function-sections function: code, laid out like
    `.text` in object order. }
  if (nm = '.text') or (Copy(nm, 1, 6) = '.text.') then
    begin k := ELFLNK_K_TEXT; wantTy := 1;  wantFl := 6; end
  else if nm = '.data'  then begin k := ELFLNK_K_DATA; wantTy := 1;  wantFl := 3; end
  else if nm = '.bss'   then begin k := ELFLNK_K_BSS;  wantTy := ELFRD_SHT_NOBITS; wantFl := 3; end
  else if nm = '.init_array' then begin k := ELFLNK_K_INIT; wantTy := 14; wantFl := 3; end
  else if nm = '.fini_array' then begin k := ELFLNK_K_FINI; wantTy := 15; wantFl := 3; end
  else if FreestandingMode and (nm = '.multiboot') then
    begin k := ELFLNK_K_HEAD; wantTy := 1; wantFl := 2; end
  else if FreestandingMode and ((nm = '.rodata') or (Copy(nm, 1, 8) = '.rodata.')) then
    begin k := ELFLNK_K_RODATA; wantTy := 1; wantFl := 2; end
  else if FreestandingMode and ((nm = '.note') or (Copy(nm, 1, 6) = '.note.')) then
    begin k := ELFLNK_K_NOTE; wantTy := 7; wantFl := 2; end;
  if k < 0 then
  begin
    ElfRdErr := 'allocated section ''' + nm + ''' is not one pxx emits -- this '
              + 'links pxx''s own objects (.text .text.* .data .bss .init_array .fini_array), '
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

procedure ElfLnkGrowSecs(n: Integer);
var cap: Integer;
begin
  cap := Length(ElfLnkSecKindOf);
  if n <= cap then Exit;
  if cap < 1024 then cap := 1024;
  while cap < n do cap := cap * 2;
  SetLength(ElfLnkSecKindOf, cap);
  SetLength(ElfLnkSecSize, cap);
  SetLength(ElfLnkSecAlign, cap);
  SetLength(ElfLnkSecAddr, cap);
  SetLength(ElfLnkSecLive, cap);
end;

{ One edge; a repeat of the previous one is dropped, which is most of them --
  a function calls the same few neighbours, and consecutive relocations in one
  section very often name one target. }
procedure ElfLnkAddEdge(fromS, toS: Integer);
var cap: Integer;
begin
  if (ElfLnkEdgeCount > 0) and (ElfLnkEdgeFrom[ElfLnkEdgeCount - 1] = fromS)
     and (ElfLnkEdgeTo[ElfLnkEdgeCount - 1] = toS) then Exit;
  cap := Length(ElfLnkEdgeFrom);
  if ElfLnkEdgeCount >= cap then
  begin
    if cap < 4096 then cap := 4096 else cap := cap * 2;
    SetLength(ElfLnkEdgeFrom, cap);
    SetLength(ElfLnkEdgeTo, cap);
  end;
  ElfLnkEdgeFrom[ElfLnkEdgeCount] := fromS;
  ElfLnkEdgeTo[ElfLnkEdgeCount] := toS;
  Inc(ElfLnkEdgeCount);
end;

function ElfLnkStubSize: Integer;
begin
  if ElfLnkMachine = ELFLNK_EM_AARCH64 then ElfLnkStubSize := ELFLNK_STUB_SIZE_A64
  else ElfLnkStubSize := ELFLNK_STUB_SIZE_X64;
end;

function ElfLnkAddObject(const path: AnsiString): Boolean;
var i, j, n, nsec, symEnts, bind, k, obj, kind, base, tgt, slot: Integer;
    stOff, stSize, stEnt, strTab, e, shndx, nameIdx, al, rOff, rEnt, sidx, symSec: Int64;
    nm: AnsiString;
    seen: array of Boolean;
    symG: array of Integer;   { per symbol index: its global, -1 for a local }
begin
  ElfLnkAddObject := False;
  LoadInput(path, ElfRdBuf);
  if Length(ElfRdBuf) = 0 then begin ElfRdErr := 'cannot read'; Exit; end;
  if not ElfRdCheckHeader then Exit;
  if ElfRdU16(18) <> ElfLnkMachine then
  begin
    ElfRdErr := 'e_machine is ' + AIntToStr(ElfRdU16(18)) + ', and this link is for '
              + AIntToStr(ElfLnkMachine) + ' (62 x86-64, 183 aarch64): pass the same --target'
              + ' to --link as to --emit-obj';
    Exit;
  end;
  nsec := ElfRdShNum;

  { register the object and a slot for every section header }
  obj := ElfLnkObjCount;
  ElfLnkObjCount := obj + 1;
  SetLength(ElfLnkObjPath, obj + 1);
  SetLength(ElfLnkObjSec0, obj + 1);
  SetLength(ElfLnkObjNsec, obj + 1);
  ElfLnkObjPath[obj] := path;
  base := ElfLnkSecCount;
  ElfLnkGrowSecs(base + nsec);
  ElfLnkSecCount := base + nsec;
  ElfLnkObjSec0[obj] := base;
  ElfLnkObjNsec[obj] := nsec;
  SetLength(seen, ELFLNK_NKIND);
  for k := 0 to ELFLNK_NKIND - 1 do seen[k] := False;
  for i := 0 to nsec - 1 do
  begin
    slot := base + i;
    ElfLnkSecKindOf[slot] := ELFLNK_NKIND;
    ElfLnkSecSize[slot] := 0;
    ElfLnkSecAlign[slot] := 1;
    ElfLnkSecAddr[slot] := 0;
    ElfLnkSecLive[slot] := False;
    if i = 0 then Continue;
    kind := ElfLnkSecKind(i);
    if kind < 0 then Exit;
    ElfLnkSecKindOf[slot] := kind;
    if kind = ELFLNK_NKIND then Continue;
    { ONE PER NAME PER OBJECT is what the emitter writes for everything but
      code. Two .init_array sections would need a rule for their relative
      order -- constructor order -- that nothing here has had to decide. Code
      may come in any number: --function-sections writes one per function,
      and their order is simply header order. }
    if (kind <> ELFLNK_K_TEXT) and (kind <> ELFLNK_K_RODATA) and seen[kind] then
    begin
      ElfRdErr := 'two ' + ElfLnkKindName(kind) + ' sections in one object; pxx writes one';
      Exit;
    end;
    seen[kind] := True;
    al := ElfRdShAddrAlign(i);
    if al < 1 then al := 1;
    ElfLnkSecSize[slot] := ElfRdShSize(i);
    ElfLnkSecAlign[slot] := al;
  end;
  SetLength(symG, 0);
  for i := 0 to nsec - 1 do
    if ElfRdShType(i) = ELFRD_SHT_SYMTAB then
    begin
      stOff := ElfRdShOffset(i);
      stSize := ElfRdShSize(i);
      stEnt := ElfRdShEntSize(i);
      strTab := ElfRdShOffset(ElfRdShLink(i));
      if stEnt <= 0 then stEnt := 24;
      symEnts := Integer(stSize div stEnt);
      SetLength(symG, symEnts);
      for j := 0 to symEnts - 1 do symG[j] := -1;
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
        symG[j] := k;
        if shndx = 0 then
        begin
          ElfLnkRefs[k] := ElfLnkRefs[k] + 1;
          if bind <> ELFLNK_STB_WEAK then ElfLnkStrongRef[k] := True;
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
        if shndx = $FFF1 then slot := -1
        else if (shndx >= $FF00) or (shndx >= nsec) then
        begin
          ElfRdErr := 'symbol ''' + nm + ''' is defined against special section index '
                    + AIntToStr(shndx) + ', which pxx does not emit';
          Exit;
        end
        else
        begin
          slot := base + Integer(shndx);
          if ElfLnkSecKindOf[slot] = ELFLNK_NKIND then
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
          ElfLnkDefSec[k] := slot;
          ElfLnkDefVal[k] := ElfRdU64(e + 8);
          ElfLnkDefIsWeak[k] := bind = ELFLNK_STB_WEAK;
          ElfLnkDefInfo[k] := ElfRdU8(e + 4);
          ElfLnkDefSize[k] := ElfRdU64(e + 16);
        end;
      end;
    end;
  { THE REFERENCE GRAPH, taken now because the object is in memory now: the
    link does not hold 500 objects at once. A relocation in an allocated
    section is an edge from that section to what its symbol names. }
  for i := 1 to nsec - 1 do
    if ElfRdShType(i) = ELFRD_SHT_RELA then
    begin
      tgt := Integer(ElfRdU32(ElfRdShdr(i) + 44));
      if (tgt <= 0) or (tgt >= nsec) then Continue;
      if ElfLnkSecKindOf[base + tgt] = ELFLNK_NKIND then Continue;
      symSec := ElfRdShLink(i);
      stOff := ElfRdShOffset(Integer(symSec));
      rOff := ElfRdShOffset(i);
      rEnt := ElfRdShEntSize(i);
      if rEnt <= 0 then rEnt := 24;
      n := Integer(ElfRdShSize(i) div rEnt);
      for j := 0 to n - 1 do
      begin
        sidx := (ElfRdU64(rOff + Int64(j) * rEnt + 8) shr 32) and $FFFFFFFF;
        if sidx = 0 then Continue;
        if (sidx < Length(symG)) and (symG[Integer(sidx)] >= 0) then
          ElfLnkAddEdge(base + tgt, -(symG[Integer(sidx)] + 1))
        else
        begin
          e := stOff + sidx * 24;
          shndx := ElfRdU16(e + 6);
          if (shndx > 0) and (shndx < nsec) then
            if ElfLnkSecKindOf[base + Integer(shndx)] <> ELFLNK_NKIND then
              ElfLnkAddEdge(base + tgt, base + Integer(shndx));
        end;
      end;
    end;
  ElfLnkAddObject := True;
end;

function ElfLnkAlignUp(v, a: Int64): Int64;
begin
  { by mask for a power of two: `div' truncates toward zero, so the old
    arithmetic rounded a high-half address (negative as Int64) DOWN }
  if a <= 1 then ElfLnkAlignUp := v
  else if (a and (a - 1)) = 0 then ElfLnkAlignUp := (v + a - 1) and (not (a - 1))
  else ElfLnkAlignUp := ((v + a - 1) div a) * a;
end;

{ ---- section garbage collection ------------------------------------------
  THE SAME RULE AS ld --gc-sections, and ld is the oracle for it
  (PXXDBG=a.objgc, compared against --print-gc-sections): a section is kept
  when the ENTRY reaches it through relocations, or when it is an .init_array
  or .fini_array, which the process-entry contract walks without anything
  naming their contents. A reference to a GLOBAL marks the section of the
  definition the link CHOSE -- so the losing weak copies of crtl in every
  other object are never reached, and that is the whole point.

  WHY IT IS CORRECT UNDER EITHER ANSWER TO WHAT AN OBJECT IS
  (decide-a-is-a-pxx-object-a-self-contained-runtime-or-a-translation-unit):
  nothing here changes an object. It prunes an EXECUTABLE, which nothing links
  against, from what that executable's own entry can reach. Exported symbols
  are not roots, because in a static executable there is nobody left to
  import them.

  With GC off every allocated section is live, which is what the stage 3/4
  oracles (ld without --gc-sections) compare against. }
procedure ElfLnkGcMark(entryG: Integer);
var i, s, t, sp, g: Integer;
    first, adj, fill, stack: array of Integer;
begin
  for s := 0 to ElfLnkSecCount - 1 do
    ElfLnkSecLive[s] := (not ElfLnkGcOn) and (ElfLnkSecKindOf[s] <> ELFLNK_NKIND);
  if not ElfLnkGcOn then Exit;
  { adjacency by source slot, counting sort }
  SetLength(first, ElfLnkSecCount + 1);
  for s := 0 to ElfLnkSecCount do first[s] := 0;
  for i := 0 to ElfLnkEdgeCount - 1 do Inc(first[ElfLnkEdgeFrom[i] + 1]);
  for s := 1 to ElfLnkSecCount do first[s] := first[s] + first[s - 1];
  SetLength(adj, ElfLnkEdgeCount);
  SetLength(fill, ElfLnkSecCount);
  for s := 0 to ElfLnkSecCount - 1 do fill[s] := first[s];
  for i := 0 to ElfLnkEdgeCount - 1 do
  begin
    adj[fill[ElfLnkEdgeFrom[i]]] := ElfLnkEdgeTo[i];
    Inc(fill[ElfLnkEdgeFrom[i]]);
  end;
  SetLength(stack, ElfLnkSecCount);
  sp := 0;
  for s := 0 to ElfLnkSecCount - 1 do
    if (ElfLnkSecKindOf[s] = ELFLNK_K_INIT) or (ElfLnkSecKindOf[s] = ELFLNK_K_FINI)
       or (ElfLnkSecKindOf[s] = ELFLNK_K_HEAD) or (ElfLnkSecKindOf[s] = ELFLNK_K_NOTE) then
    begin
      ElfLnkSecLive[s] := True;
      stack[sp] := s; Inc(sp);
    end;
  if (entryG >= 0) and (ElfLnkDefObj[entryG] >= 0) and (ElfLnkDefSec[entryG] >= 0) then
  begin
    s := ElfLnkDefSec[entryG];
    if not ElfLnkSecLive[s] then
    begin
      ElfLnkSecLive[s] := True;
      stack[sp] := s; Inc(sp);
    end;
  end;
  while sp > 0 do
  begin
    Dec(sp);
    s := stack[sp];
    for i := first[s] to first[s + 1] - 1 do
    begin
      t := adj[i];
      if t < 0 then
      begin
        g := -t - 1;
        if (ElfLnkDefObj[g] < 0) or (ElfLnkDefSec[g] < 0) then Continue;
        t := ElfLnkDefSec[g];
      end;
      if not ElfLnkSecLive[t] then
      begin
        ElfLnkSecLive[t] := True;
        stack[sp] := t; Inc(sp);
      end;
    end;
  end;
end;

{ Is global k's chosen definition in the image? False for an undefined one and
  for one whose section the GC dropped. }
function ElfLnkDefKept(k: Integer): Boolean;
begin
  if ElfLnkDefObj[k] < 0 then ElfLnkDefKept := False
  else if ElfLnkDefSec[k] < 0 then ElfLnkDefKept := True
  else ElfLnkDefKept := ElfLnkSecLive[ElfLnkDefSec[k]];
end;

{ ---- stage 3: section layout -----------------------------------------------
  Assign every input section an output address. Inputs are concatenated per
  kind IN LINK ORDER, each at its own sh_addralign -- which is what ld does, and
  what makes the order of .init_array entries (and so of constructors) the
  command-line order rather than an accident of this table.

  THE IMAGE: one RX segment from ImageBase holding the ELF and program
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
var k, o, i, s0: Integer;
    addr, start, maxAl, rwFile: Int64;
begin
  addr := ImageBase + ELFLNK_PAGE;
  for k := 0 to ELFLNK_NKIND - 1 do
  begin
    if k = ELFLNK_K_INIT then
    begin
      { the RW segment: next page in the FILE, at the congruent address }
      ElfLnkRxEnd := addr - ImageBase;
      rwFile := ElfLnkAlignUp(ElfLnkRxEnd, ELFLNK_PAGE);
      ElfLnkRwFile := rwFile;
      addr := ImageBase + rwFile;
    end;
    maxAl := 1;
    for i := 0 to ElfLnkSecCount - 1 do
      if ElfLnkSecLive[i] and (ElfLnkSecKindOf[i] = k) and (ElfLnkSecAlign[i] > maxAl) then
        maxAl := ElfLnkSecAlign[i];
    start := ElfLnkAlignUp(addr, maxAl);
    addr := start;
    if k = ELFLNK_K_NOTE then ElfLnkNoteAlign := maxAl;
    { object order, then header order within an object -- which for a split
      object is code order, so a link that keeps every section reproduces the
      unsplit object's layout }
    for o := 0 to ElfLnkObjCount - 1 do
    begin
      s0 := ElfLnkObjSec0[o];
      for i := s0 to s0 + ElfLnkObjNsec[o] - 1 do
      begin
        if (not ElfLnkSecLive[i]) or (ElfLnkSecKindOf[i] <> k) then Continue;
        addr := ElfLnkAlignUp(addr, ElfLnkSecAlign[i]);
        ElfLnkSecAddr[i] := addr;
        addr := addr + ElfLnkSecSize[i];
      end;
    end;
    { the synthesised _start goes AFTER every input's .text, so each input
      keeps the address it has without it -- which keeps the stage 3/4 oracle
      (ld, which has no stub) valid for everything but these bytes }
    if (k = ELFLNK_K_TEXT) and ElfLnkEntryStub then
    begin
      addr := ElfLnkAlignUp(addr, 16);
      ElfLnkStubAddr := addr;
      addr := addr + ElfLnkStubSize;
    end;
    ElfLnkOutAddr[k] := start;
    ElfLnkOutSize[k] := addr - start;
  end;
end;

{ The final address of global k's chosen definition. Only meaningful when
  ElfLnkDefObj[k] >= 0. }
function ElfLnkGlobalAddr(k: Integer): Int64;
begin
  if ElfLnkDefSec[k] < 0 then
    ElfLnkGlobalAddr := ElfLnkDefVal[k]
  else
    ElfLnkGlobalAddr := ElfLnkSecAddr[ElfLnkDefSec[k]] + ElfLnkDefVal[k];
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
  LoadInput(listPath, lst);
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
procedure ElfLnkPrintLayout;
var k, o, slot: Integer;
begin
  WriteLn('elflay: objects ', AIntToStr(ElfLnkObjCount));
  for k := 0 to ELFLNK_NKIND - 1 do
    WriteLn('elflay: out ', ElfLnkKindName(k), ' 0x', IntToHexStr(ElfLnkOutAddr[k], 16),
            ' size ', AIntToStr(ElfLnkOutSize[k]));
  for o := 0 to ElfLnkObjCount - 1 do
    for slot := ElfLnkObjSec0[o] to ElfLnkObjSec0[o] + ElfLnkObjNsec[o] - 1 do
      if ElfLnkSecLive[slot] then
        WriteLn('elflay: in ', AIntToStr(o), ' ', ElfLnkKindName(ElfLnkSecKindOf[slot]),
                ' 0x', IntToHexStr(ElfLnkSecAddr[slot], 16),
                ' size ', AIntToStr(ElfLnkSecSize[slot]),
                ' align ', AIntToStr(ElfLnkSecAlign[slot]));
  for k := 0 to ElfLnkCount - 1 do
    if ElfLnkDefKept(k) then
      WriteLn('elflay: sym ', IntToHexStr(ElfLnkGlobalAddr(k), 16), ' ', ElfLnkName[k]);
end;

procedure ElfLnkLayoutDump(const listPath: AnsiString);
begin
  if not ElfLnkLoadList(listPath, 'elflay') then Exit;
  ElfLnkGcMark(-1);
  ElfLnkLayout;
  ElfLnkPrintLayout;
  WriteLn('elflay: ELFLAY-OK');
end;

{ ---- stage 4: relocation application, and the image it lands in ------------
  THE TYPES THE EMITTERS WRITE, AND ONLY THOSE: R_X86_64_64 (1, S+A into
  8 bytes), R_X86_64_PC32 (2, S+A-P into a signed 32-bit field), R_X86_64_PLT32
  (4, the .asm frontend's extern references; resolved as PC32, no PLT) and
  R_X86_64_32S (11, S+A into a signed 32-bit field). The busybox census saw two
  of them; the third is in writeELFRelX64General for globals addressed
  absolutely and simply did not occur there. Anything else is refused BY NAME
  here, which is the place the reader deferred that refusal to: the applier
  knows what it can do. A 32-bit result that does not fit is refused too --
  ld says "relocation truncated to fit", and silently keeping the low half is
  a jump to a plausible wrong address.

  S IS RESOLVED THE WAY ld RESOLVES IT. A LOCAL symbol (including the section
  symbols most of our data references go through) is this object's own section
  address plus st_value. A non-local one goes through the GLOBAL table -- even
  when this object defines it, because a weak copy here may have lost to another
  object's -- and an undefined WEAK reference is 0.

  THE IMAGE IS STREAMED, NOT HELD. .text is written object by object as it is
  relocated, because at the busybox scale it is the whole 180 MB of the image;
  only the RW segment (.init_array .. end of .data, a few MB) is assembled in
  memory, since its inputs interleave by kind rather than by object. }

var
{$ifdef FPC}
  ElfLnkF    : File;
{$else}
  ElfLnkF    : Integer;
{$endif}
  ElfLnkRw   : array of Byte;   { the RW segment's file bytes }
  ElfLnkHd   : array of Byte;   { .multiboot's bytes (--link --freestanding) }
  ElfLnkRd   : array of Byte;   { .rodata's bytes (--link --freestanding) }
  ElfLnkNt   : array of Byte;   { the .note* bytes (--link --freestanding) }
  ElfLnkTb   : array of Byte;   { one object's .text while it is relocated }
  ElfLnkB    : array of Byte;   { a small region assembled before it is written }
  ElfLnkBLen : Integer;
  ElfLnkZero : array of Byte;

procedure ElfLnkOpen(const path: AnsiString);
begin
{$ifdef FPC}
  Assign(ElfLnkF, path); Rewrite(ElfLnkF, 1);
{$else}
  AssignPath := path;
  ElfLnkF := OutOpen(AssignPath); { O_WRONLY | O_CREAT | O_TRUNC }
{$endif}
end;

procedure ElfLnkClose(const path: AnsiString);
begin
{$ifdef FPC}
  Close(ElfLnkF);
  FpChmod(path, 493);
{$else}
  sysfchmod(ElfLnkF, 493); { chmod 755 }
  sysclose(ElfLnkF);
{$endif}
end;

procedure ElfLnkWrite(const buf: array of Byte; n: Int64);
begin
  if n <= 0 then Exit;
{$ifdef FPC}
  Blockwrite(ElfLnkF, buf[0], n);
{$else}
  OutWrite(ElfLnkF, buf, 0, Integer(n));
{$endif}
end;

procedure ElfLnkWriteZeros(n: Int64);
var i, chunk: Integer;
begin
  if Length(ElfLnkZero) = 0 then
  begin
    SetLength(ElfLnkZero, 4096);
    for i := 0 to 4095 do ElfLnkZero[i] := 0;
  end;
  while n > 0 do
  begin
    chunk := 4096;
    if n < chunk then chunk := Integer(n);
    ElfLnkWrite(ElfLnkZero, chunk);
    n := n - chunk;
  end;
end;

procedure ElfLnkPutLE(var buf: array of Byte; off: Int64; v: Int64; n: Integer);
var i: Integer;
begin
  for i := 0 to n - 1 do
  begin
    buf[Integer(off) + i] := Byte(v and $FF);
    v := v shr 8;
  end;
end;

{ the assembled-region builder: append little-endian fields to ElfLnkB }
procedure ElfLnkBReset; begin ElfLnkBLen := 0; end;
procedure ElfLnkBPut(v: Int64; n: Integer);
var cap: Integer;
begin
  cap := Length(ElfLnkB);
  if ElfLnkBLen + n > cap then
  begin
    if cap < 4096 then cap := 4096;
    while ElfLnkBLen + n > cap do cap := cap * 2;
    SetLength(ElfLnkB, cap);
  end;
  ElfLnkPutLE(ElfLnkB, ElfLnkBLen, v, n);
  ElfLnkBLen := ElfLnkBLen + n;
end;
procedure ElfLnkBStrZ(const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do ElfLnkBPut(Ord(s[i]), 1);
  ElfLnkBPut(0, 1);
end;
procedure ElfLnkBPadTo(n: Integer);
begin
  while ElfLnkBLen < n do ElfLnkBPut(0, 1);
end;

{ Index of `nm` in the global table, or -1. Never inserts. }
function ElfLnkFind(const nm: AnsiString): Integer;
var i: Integer;
begin
  ElfLnkFind := -1;
  i := ElfLnkHead[ElfLnkHash(nm) and ElfLnkMask];
  while i >= 0 do
  begin
    if ElfLnkName[i] = nm then begin ElfLnkFind := i; Exit; end;
    i := ElfLnkNext[i];
  end;
end;

function ElfLnkRelTypeName(t: Int64): AnsiString;
begin
  case t of
    1:  ElfLnkRelTypeName := 'R_X86_64_64';
    2:  ElfLnkRelTypeName := 'R_X86_64_PC32';
    4:  ElfLnkRelTypeName := 'R_X86_64_PLT32';
    9:  ElfLnkRelTypeName := 'R_X86_64_GOTPCREL';
    10: ElfLnkRelTypeName := 'R_X86_64_32';
    11: ElfLnkRelTypeName := 'R_X86_64_32S';
    41: ElfLnkRelTypeName := 'R_X86_64_GOTPCRELX';
    42: ElfLnkRelTypeName := 'R_X86_64_REX_GOTPCRELX';
    257: ElfLnkRelTypeName := 'R_AARCH64_ABS64';
    258: ElfLnkRelTypeName := 'R_AARCH64_ABS32';
    261: ElfLnkRelTypeName := 'R_AARCH64_PREL32';
    263: ElfLnkRelTypeName := 'R_AARCH64_MOVW_UABS_G0';
    264: ElfLnkRelTypeName := 'R_AARCH64_MOVW_UABS_G0_NC';
    265: ElfLnkRelTypeName := 'R_AARCH64_MOVW_UABS_G1';
    266: ElfLnkRelTypeName := 'R_AARCH64_MOVW_UABS_G1_NC';
    267: ElfLnkRelTypeName := 'R_AARCH64_MOVW_UABS_G2';
    268: ElfLnkRelTypeName := 'R_AARCH64_MOVW_UABS_G2_NC';
    269: ElfLnkRelTypeName := 'R_AARCH64_MOVW_UABS_G3';
    282: ElfLnkRelTypeName := 'R_AARCH64_JUMP26';
    283: ElfLnkRelTypeName := 'R_AARCH64_CALL26';
  else
    ElfLnkRelTypeName := 'relocation type ' + AIntToStr(t);
  end;
end;

{ S for symbol `si` of object `obj` (loaded in ElfRdBuf). ok = False with
  ElfRdErr set when it cannot be resolved. }
function ElfLnkSymS(obj, nsec: Integer; stOff, strTab, si: Int64; var ok: Boolean): Int64;
var e, shndx: Int64; bind, g, slot: Integer; nm: AnsiString;
begin
  ok := True;
  ElfLnkSymS := 0;
  e := stOff + si * 24;
  bind := ElfRdU8(e + 4) shr 4;
  shndx := ElfRdU16(e + 6);
  if bind = ELFLNK_STB_LOCAL then
  begin
    if shndx = $FFF1 then begin ElfLnkSymS := ElfRdU64(e + 8); Exit; end;
    if (shndx = 0) or (shndx >= nsec) then
    begin
      ok := False;
      ElfRdErr := 'local symbol ' + AIntToStr(si) + ' has no section';
      Exit;
    end;
    slot := ElfLnkObjSec0[obj] + Integer(shndx);
    if ElfLnkSecKindOf[slot] = ELFLNK_NKIND then
    begin
      ok := False;
      ElfRdErr := 'local symbol ' + AIntToStr(si) + ' is in unallocated section '''
                + ElfRdSecName(Integer(shndx)) + '''';
      Exit;
    end;
    { cannot happen while the mark follows every relocation -- and if it ever
      does, it is a jump into bytes that were not written, so it is refused }
    if not ElfLnkSecLive[slot] then
    begin
      ok := False;
      ElfRdErr := 'internal: a kept section refers to section '''
                + ElfRdSecName(Integer(shndx)) + ''', which the section GC dropped';
      Exit;
    end;
    ElfLnkSymS := ElfLnkSecAddr[slot] + ElfRdU64(e + 8);
    Exit;
  end;
  nm := ElfRdStr(strTab, ElfRdU32(e));
  g := ElfLnkFind(nm);
  if (g >= 0) and (ElfLnkDefObj[g] >= 0) then
  begin
    if not ElfLnkDefKept(g) then
    begin
      ok := False;
      ElfRdErr := 'internal: a kept section refers to ''' + nm
                + ''', whose definition the section GC dropped';
      Exit;
    end;
    ElfLnkSymS := ElfLnkGlobalAddr(g);
    Exit;
  end;
  if bind = ELFLNK_STB_WEAK then Exit;
  ok := False;
  ElfRdErr := 'undefined reference to ''' + nm + '''';
end;

{ Apply rela section `rela` of object `obj` (-1: none) to its input section
  `target`, whose bytes sit in `buf` from index `bufOff`. }
{ aarch64 (e_machine 183). What pxx's aarch64 object writer emits: data
  words (ABS64/ABS32), absolute addresses built by movz/movk (MOVW_UABS_G0..G3,
  imm16 in bits [20:5]), and b/bl (JUMP26/CALL26, imm26 = (S+A-P)/4), plus
  PREL32 for completeness. An instruction relocation patches the word already
  in buf, so the opcode and register bits the object wrote are kept. }
function ElfLnkRelocateA64(obj, nsec, target, rela: Integer;
                           var buf: array of Byte; bufOff: Int64): Boolean;
var j, n, width, g: Integer;
    symSec, stOff, strTab, rOff, rEnt, e, off, info, rtype, si, add, S, P, v, secSize, w: Int64;
    ok: Boolean;
begin
  ElfLnkRelocateA64 := False;
  secSize := ElfRdShSize(target);
  symSec := ElfRdShLink(rela);
  stOff := ElfRdShOffset(Integer(symSec));
  strTab := ElfRdShOffset(Integer(ElfRdShLink(Integer(symSec))));
  rOff := ElfRdShOffset(rela);
  rEnt := ElfRdShEntSize(rela);
  if rEnt <= 0 then rEnt := 24;
  n := Integer(ElfRdShSize(rela) div rEnt);
  for j := 0 to n - 1 do
  begin
    e := rOff + Int64(j) * rEnt;
    off := ElfRdU64(e);
    info := ElfRdU64(e + 8);
    add := ElfRdU64(e + 16);
    rtype := info and $FFFFFFFF;
    si := (info shr 32) and $FFFFFFFF;
    if rtype = 257 then width := 8
    else if (rtype = 258) or (rtype = 261) or ((rtype >= 263) and (rtype <= 269))
            or (rtype = 282) or (rtype = 283) then width := 4
    else
    begin
      ElfRdErr := ElfLnkRelTypeName(rtype) + ' in ' + ElfRdSecName(target)
                + ' -- the aarch64 link takes R_AARCH64_ABS64/ABS32/PREL32, MOVW_UABS_G0..G3'
                + ' and JUMP26/CALL26';
      Exit;
    end;
    if (off < 0) or (off + width > secSize) then
    begin
      ElfRdErr := 'relocation at offset ' + AIntToStr(off) + ' runs past the end of '
                + ElfRdSecName(target);
      Exit;
    end;
    S := ElfLnkSymS(obj, nsec, stOff, strTab, si, ok);
    if not ok then Exit;
    P := ElfLnkSecAddr[ElfLnkObjSec0[obj] + target] + off;
    if rtype = 257 then
      ElfLnkPutLE(buf, bufOff + off, S + add, 8)
    else if (rtype = 258) or (rtype = 261) then
    begin
      if rtype = 261 then v := S + add - P else v := S + add;
      if (v < -2147483648) or (v > $FFFFFFFF) then
      begin
        ElfRdErr := ElfLnkRelTypeName(rtype) + ' at ' + ElfRdSecName(target) + '+'
                  + AIntToStr(off) + ' does not fit in 32 bits (value 0x' + IntToHexStr(v, 16) + ')';
        Exit;
      end;
      ElfLnkPutLE(buf, bufOff + off, v, 4);
    end
    else
    begin
      w := Int64(buf[Integer(bufOff + off)]) or (Int64(buf[Integer(bufOff + off) + 1]) shl 8)
           or (Int64(buf[Integer(bufOff + off) + 2]) shl 16) or (Int64(buf[Integer(bufOff + off) + 3]) shl 24);
      if (rtype = 282) or (rtype = 283) then
      begin
        v := S + add - P;
        if ((v and 3) <> 0) or (v < -134217728) or (v > 134217724) then
        begin
          ElfRdErr := ElfLnkRelTypeName(rtype) + ' at ' + ElfRdSecName(target) + '+'
                    + AIntToStr(off) + ': branch displacement 0x' + IntToHexStr(v, 16)
                    + ' is not a multiple of 4 within +-128 MiB';
          Exit;
        end;
        w := (w and $FC000000) or ((v shr 2) and $03FFFFFF);
      end
      else
      begin
        { MOVW_UABS_Gg: imm16 = bits [16g+15 : 16g] of S+A. The checked forms
          (odd types, and G3) need the rest above those bits to be zero. }
        g := Integer((rtype - 263) div 2);
        v := S + add;
        if (((rtype - 263) mod 2) = 0) and (g < 3) and ((v shr (16 * (g + 1))) <> 0) then
        begin
          ElfRdErr := ElfLnkRelTypeName(rtype) + ' at ' + ElfRdSecName(target) + '+'
                    + AIntToStr(off) + ': 0x' + IntToHexStr(v, 16) + ' does not fit';
          Exit;
        end;
        w := (w and $FFE0001F) or (((v shr (16 * g)) and $FFFF) shl 5);
      end;
      ElfLnkPutLE(buf, bufOff + off, w, 4);
    end;
  end;
  ElfLnkRelocateA64 := True;
end;

function ElfLnkRelocate(obj, nsec, target, rela: Integer;
                        var buf: array of Byte; bufOff: Int64): Boolean;
var j, n, width, slot: Integer;
    symSec, stOff, strTab, rOff, rEnt, e, off, info, rtype, si, add, S, P, v, secSize: Int64;
    ok: Boolean;
begin
  ElfLnkRelocate := True;
  if rela < 0 then Exit;
  if ElfLnkMachine = ELFLNK_EM_AARCH64 then
  begin
    ElfLnkRelocate := ElfLnkRelocateA64(obj, nsec, target, rela, buf, bufOff);
    Exit;
  end;
  ElfLnkRelocate := False;
  slot := ElfLnkObjSec0[obj] + target;
  secSize := ElfRdShSize(target);
  symSec := ElfRdShLink(rela);
  stOff := ElfRdShOffset(Integer(symSec));
  strTab := ElfRdShOffset(Integer(ElfRdShLink(Integer(symSec))));
  rOff := ElfRdShOffset(rela);
  rEnt := ElfRdShEntSize(rela);
  if rEnt <= 0 then rEnt := 24;
  n := Integer(ElfRdShSize(rela) div rEnt);
  for j := 0 to n - 1 do
  begin
    e := rOff + Int64(j) * rEnt;
    off := ElfRdU64(e);
    info := ElfRdU64(e + 8);
    add := ElfRdU64(e + 16);
    rtype := info and $FFFFFFFF;
    si := (info shr 32) and $FFFFFFFF;
    if rtype = 1 then width := 8
    else if (rtype = 2) or (rtype = 4) or (rtype = 11) then width := 4
    else if FreestandingMode and (rtype = 10) then width := 4
    else
    begin
      ElfRdErr := ElfLnkRelTypeName(rtype) + ' in ' + ElfRdSecName(target)
                + ' -- pxx emits R_X86_64_64, R_X86_64_PC32, R_X86_64_PLT32 and R_X86_64_32S only'
                + ' (R_X86_64_32 too under --link --freestanding)';
      Exit;
    end;
    if (off < 0) or (off + width > secSize) then
    begin
      ElfRdErr := 'relocation at offset ' + AIntToStr(off) + ' runs past the end of '
                + ElfRdSecName(target);
      Exit;
    end;
    S := ElfLnkSymS(obj, nsec, stOff, strTab, si, ok);
    if not ok then Exit;
    P := ElfLnkSecAddr[slot] + off;
    { R_X86_64_PLT32 (4): L + A - P, and in a static image with no PLT the
      target L is the symbol itself, so it is PC32 -- as GNU ld resolves it.
      pxx's own .asm frontend writes it for every extern reference. }
    if (rtype = 2) or (rtype = 4) then v := S + add - P else v := S + add;
    if ((rtype = 10) and ((v < 0) or (v > $FFFFFFFF)))
       or ((rtype <> 10) and (width = 4) and ((v < -2147483648) or (v > 2147483647))) then
    begin
      ElfRdErr := ElfLnkRelTypeName(rtype) + ' at ' + ElfRdSecName(target)
                + '+' + AIntToStr(off) + ' does not fit in 32 bits (value 0x'
                + IntToHexStr(v, 16) + ')';   { hex: AIntToStr narrows, and printed 0 for 2^32 }
      Exit;
    end;
    ElfLnkPutLE(buf, bufOff + off, v, width);
  end;
  ElfLnkRelocate := True;
end;

{ ---- stage 5: the process-entry contract ---------------------------------
  THE CONTRACT IS tools/pxxcrt_x86_64.S's, INSTRUCTION FOR INSTRUCTION, because
  that one is proven: it is what the 663-case freestanding busybox ran on. The
  kernel does not call main. It jumps to the entry with rsp -> argc, then
  argv[0..argc-1], a NULL, then envp. So:

      xor   ebp, ebp                 backtraces stop here
      mov   r12, [rsp]               argc
      lea   r13, [rsp+8]             argv
      lea   r14, [r13+r12*8+8]       envp = argv + argc + 1
      and   rsp, -16                 SysV alignment AT the call
      movabs rbx, <.init_array start>
      movabs r15, <.init_array end>
   1: cmp   rbx, r15 ; jae 2f
      mov   rdi, r12 ; mov rsi, r13 ; mov rdx, r14 ; call [rbx]
      add   rbx, 8 ; jmp 1b
   2: mov   rdi, r12 ; mov rsi, r13 ; mov rdx, r14
      movabs rax, <main> ; call rax
      mov   edi, eax ; mov eax, 60 ; syscall ; hlt

  THE .init_array WALK IS LOAD-BEARING AND ITS OMISSION IS SILENT: the C
  frontend's constructor thunk sets environ from (argc, argv, envp), and a
  missing walk leaves it null -- a wrong VALUE far away, not a crash.

  ONE THING IS BETTER HERE THAN IN THE .S: the array bounds are CONSTANTS. The
  .S names __init_array_start/__init_array_end and relies on ld's internal
  script to PROVIDE them; this linker laid the array out itself and knows both
  addresses, so there are no linker-defined symbols to get wrong. movabs rather
  than rip-relative lea because the image is static at a fixed base, and an
  absolute is one fewer thing to compute.

  exit(2) (60), not exit(): the .S does not run the atexit chain or
  .fini_array either, and matching the proven contract exactly is the point --
  a difference here would be a claim nothing has measured. }
procedure ElfLnkPutStub(var buf: array of Byte; initStart, initEnd, mainAddr: Int64);
const
  { 93 bytes; the three movabs immediates are zero here and filled below }
  STUB: array[0..ELFLNK_STUB_SIZE_X64 - 1] of Byte = (
    $31,$ED,                               {  0 xor ebp,ebp            }
    $4C,$8B,$24,$24,                       {  2 mov r12,[rsp]          }
    $4C,$8D,$6C,$24,$08,                   {  6 lea r13,[rsp+8]        }
    $4F,$8D,$74,$E5,$08,                   { 11 lea r14,[r13+r12*8+8]  }
    $48,$83,$E4,$F0,                       { 16 and rsp,-16            }
    $48,$BB,0,0,0,0,0,0,0,0,               { 20 movabs rbx,imm64 (22)  }
    $49,$BF,0,0,0,0,0,0,0,0,               { 30 movabs r15,imm64 (32)  }
    $4C,$39,$FB,                           { 40 cmp rbx,r15            }
    $73,$11,                               { 43 jae +17 -> 62          }
    $4C,$89,$E7,                           { 45 mov rdi,r12            }
    $4C,$89,$EE,                           { 48 mov rsi,r13            }
    $4C,$89,$F2,                           { 51 mov rdx,r14            }
    $FF,$13,                               { 54 call [rbx]             }
    $48,$83,$C3,$08,                       { 56 add rbx,8              }
    $EB,$EA,                               { 60 jmp -22 -> 40          }
    $4C,$89,$E7,                           { 62 mov rdi,r12            }
    $4C,$89,$EE,                           { 65 mov rsi,r13            }
    $4C,$89,$F2,                           { 68 mov rdx,r14            }
    $48,$B8,0,0,0,0,0,0,0,0,               { 71 movabs rax,imm64 (73)  }
    $FF,$D0,                               { 81 call rax               }
    $89,$C7,                               { 83 mov edi,eax            }
    $B8,$3C,$00,$00,$00,                   { 85 mov eax,60             }
    $0F,$05,                               { 90 syscall                }
    $F4);                                  { 92 hlt                    }
var i: Integer;
begin
  for i := 0 to ELFLNK_STUB_SIZE_X64 - 1 do buf[i] := STUB[i];
  ElfLnkPutLE(buf, 22, initStart, 8);
  ElfLnkPutLE(buf, 32, initEnd, 8);
  ElfLnkPutLE(buf, 73, mainAddr, 8);
end;

{ The same contract on aarch64. The kernel enters with sp -> argc, argv[],
  NULL, envp[], and sp is already 16-aligned (AAPCS64 needs nothing more).
  argc/argv/envp live in callee-saved x19..x21 across the calls, the
  .init_array walk is x22..x23, and every call is (x0, x1, x2) = (argc,
  argv, envp). exit(2) is syscall 93 with main's w0. The three addresses are
  literal quads that the ldr-literal instructions reach PC-relatively.
  Encoded with llvm-mc:

      mov x29, #0 ; mov x30, #0              frame chain stops here
      ldr x19, [sp] ; add x20, sp, #8         argc, argv
      add x21, x20, x19, lsl #3 ; add x21, x21, #8     envp
      ldr x22, lit1 ; ldr x23, lit2           .init_array bounds
   1: cmp x22, x23 ; b.hs 2f
      mov x0, x19 ; mov x1, x20 ; mov x2, x21
      ldr x9, [x22] ; blr x9 ; add x22, x22, #8 ; b 1b
   2: mov x0, x19 ; mov x1, x20 ; mov x2, x21
      ldr x9, lit3 ; blr x9                    main
      mov x8, #93 ; svc #0 ; brk #0 ; nop
   lit1/lit2/lit3 at +104/+112/+120 }
procedure ElfLnkPutStubA64(var buf: array of Byte; initStart, initEnd, mainAddr: Int64);
const
  W: array[0..25] of LongWord = (
    $D280001D, $D280001E, $F94003F3, $910023F4, $8B130E95, $910022B5,
    $58000296, $580002B7, $EB1702DF, $54000102, $AA1303E0, $AA1403E1,
    $AA1503E2, $F94002C9, $D63F0120, $910022D6, $17FFFFF8, $AA1303E0,
    $AA1403E1, $AA1503E2, $58000149, $D63F0120, $D2800BA8, $D4000001,
    $D4200000, $D503201F);
var i: Integer;
begin
  for i := 0 to 25 do ElfLnkPutLE(buf, 4 * i, W[i], 4);
  ElfLnkPutLE(buf, 104, initStart, 8);
  ElfLnkPutLE(buf, 112, initEnd, 8);
  ElfLnkPutLE(buf, 120, mainAddr, 8);
end;

{ Write the linked executable. ElfLnkLoadList and ElfLnkLayout must have run.
  False, with the reason printed under `tag`, on any refusal. }
{ --link --freestanding: relocate every live .multiboot and .rodata input into
  ElfLnkHd / ElfLnkRd, one pass over the objects. }
function ElfLnkFillRo(const tag: AnsiString): Boolean;
var o, i, k, nsec, slot, t: Integer;
    sz, secOff, rel: Int64;
    relaOf: array of Integer;
begin
  ElfLnkFillRo := False;
  SetLength(ElfLnkHd, ElfLnkOutSize[ELFLNK_K_HEAD]);
  for i := 0 to Integer(ElfLnkOutSize[ELFLNK_K_HEAD]) - 1 do ElfLnkHd[i] := 0;
  SetLength(ElfLnkRd, ElfLnkOutSize[ELFLNK_K_RODATA]);
  for i := 0 to Integer(ElfLnkOutSize[ELFLNK_K_RODATA]) - 1 do ElfLnkRd[i] := 0;
  SetLength(ElfLnkNt, ElfLnkOutSize[ELFLNK_K_NOTE]);
  for i := 0 to Integer(ElfLnkOutSize[ELFLNK_K_NOTE]) - 1 do ElfLnkNt[i] := 0;
  for o := 0 to ElfLnkObjCount - 1 do
  begin
    LoadInput(ElfLnkObjPath[o], ElfRdBuf);
    if Length(ElfRdBuf) = 0 then ElfRdErr := 'read back empty'
    else if ElfRdCheckHeader then ElfRdErr := '';
    if ElfRdErr <> '' then
    begin
      WriteLn(tag, ': ', ElfLnkObjPath[o], ': cannot re-read the object: ', ElfRdErr);
      Exit;
    end;
    nsec := ElfRdShNum;
    SetLength(relaOf, nsec);
    for i := 0 to nsec - 1 do relaOf[i] := -1;
    for i := 1 to nsec - 1 do
      if ElfRdShType(i) = ELFRD_SHT_RELA then
      begin
        t := Integer(ElfRdU32(ElfRdShdr(i) + 44));
        if (t > 0) and (t < nsec) then relaOf[t] := i;
      end;
    for i := 1 to nsec - 1 do
    begin
      slot := ElfLnkObjSec0[o] + i;
      k := ElfLnkSecKindOf[slot];
      if (not ElfLnkSecLive[slot])
         or ((k <> ELFLNK_K_HEAD) and (k <> ELFLNK_K_RODATA) and (k <> ELFLNK_K_NOTE)) then Continue;
      sz := ElfLnkSecSize[slot];
      secOff := ElfRdShOffset(i);
      rel := ElfLnkSecAddr[slot] - ElfLnkOutAddr[k];
      if k = ELFLNK_K_HEAD then
      begin
        for t := 0 to Integer(sz) - 1 do ElfLnkHd[Integer(rel) + t] := Ord(ElfRdBuf[secOff + 1 + t]);
        if not ElfLnkRelocate(o, nsec, i, relaOf[i], ElfLnkHd, rel) then
        begin
          WriteLn(tag, ': ', ElfLnkObjPath[o], ': ', ElfRdErr);
          Exit;
        end;
      end
      else if k = ELFLNK_K_NOTE then
      begin
        for t := 0 to Integer(sz) - 1 do ElfLnkNt[Integer(rel) + t] := Ord(ElfRdBuf[secOff + 1 + t]);
        if not ElfLnkRelocate(o, nsec, i, relaOf[i], ElfLnkNt, rel) then
        begin
          WriteLn(tag, ': ', ElfLnkObjPath[o], ': ', ElfRdErr);
          Exit;
        end;
      end
      else
      begin
        for t := 0 to Integer(sz) - 1 do ElfLnkRd[Integer(rel) + t] := Ord(ElfRdBuf[secOff + 1 + t]);
        if not ElfLnkRelocate(o, nsec, i, relaOf[i], ElfLnkRd, rel) then
        begin
          WriteLn(tag, ': ', ElfLnkObjPath[o], ': ', ElfRdErr);
          Exit;
        end;
      end;
    end;
  end;
  ElfLnkFillRo := True;
end;

{ The symbols GNU ld's default script defines, given an address here when an
  object references one and nothing defines it: __executable_start (the image
  base, where the ELF header is mapped), etext (end of the RX segment),
  _edata/edata (end of the RW segment's file bytes), __bss_start and _end/end.
  A kernel's multiboot header names three of them. Run after ElfLnkLayout. }
procedure ElfLnkDefineLinkerSyms;
var k, i, g: Integer;
    dataEnd, bssEnd, v: Int64;
    nm: AnsiString;
begin
  dataEnd := ImageBase + ElfLnkRwFile;
  for k := ELFLNK_K_INIT to ELFLNK_K_DATA do
    if ElfLnkOutAddr[k] + ElfLnkOutSize[k] > dataEnd then
      dataEnd := ElfLnkOutAddr[k] + ElfLnkOutSize[k];
  bssEnd := dataEnd;
  if ElfLnkOutAddr[ELFLNK_K_BSS] + ElfLnkOutSize[ELFLNK_K_BSS] > bssEnd then
    bssEnd := ElfLnkOutAddr[ELFLNK_K_BSS] + ElfLnkOutSize[ELFLNK_K_BSS];
  for i := 0 to 6 do
  begin
    case i of
      0: begin nm := '__executable_start'; v := ImageBase; end;
      1: begin nm := 'etext'; v := ImageBase + ElfLnkRxEnd; end;
      2: begin nm := '_edata'; v := dataEnd; end;
      3: begin nm := 'edata'; v := dataEnd; end;
      4: begin nm := '__bss_start'; v := ElfLnkOutAddr[ELFLNK_K_BSS]; end;
      5: begin nm := '_end'; v := bssEnd; end;
    else
      begin nm := 'end'; v := bssEnd; end;
    end;
    g := ElfLnkFind(nm);
    if (g < 0) or (ElfLnkDefObj[g] >= 0) then Continue;
    ElfLnkDefObj[g] := 0;
    ElfLnkDefSec[g] := -1;           { absolute, like SHN_ABS }
    ElfLnkDefVal[g] := v;
    ElfLnkDefIsWeak[g] := False;
    ElfLnkDefInfo[g] := $10;         { GLOBAL NOTYPE }
    ElfLnkDefSize[g] := 0;
  end;
end;

function ElfLnkWriteExe(const outPath, entryName, tag: AnsiString): Boolean;
var o, k, i, nsec, slot, nUnres, nDef, strSize, strPos, symOff, strOff, shstrOff, shOff, t: Integer;
    mainAddr: Int64;
    stub: array of Byte;
    entry, rwStart, rwLen, rwMem, endAddr, cur, textEnd, secOff, sz, fileAt: Int64;
    relaOf: array of Integer;
    g, phCount, nOut, shstrLen: Integer;
    outIdx: array[0..7] of Integer;
    ldsoVA, pa: Int64;
const
  SHSTR = 68;   { see the blob below }
begin
  ElfLnkWriteExe := False;
  { every STRONG reference must have a definition somewhere in the set }
  nUnres := 0;
  for i := 0 to ElfLnkCount - 1 do
    if ElfLnkStrongRef[i] and (ElfLnkDefObj[i] < 0) then
    begin
      Inc(nUnres);
      if nUnres <= 50 then WriteLn(tag, ': undefined reference to ''', ElfLnkName[i], '''');
    end;
  if nUnres > 0 then
  begin
    WriteLn(tag, ': ', AIntToStr(nUnres), ' undefined reference(s); nothing written');
    Exit;
  end;
  { entryName '' means the synthesised _start, which calls main }
  if entryName = '' then g := ElfLnkFind('main') else g := ElfLnkFind(entryName);
  if (g < 0) or (ElfLnkDefObj[g] < 0) then
  begin
    if entryName = '' then
      WriteLn(tag, ': no object defines main (or _start), so there is nothing to enter')
    else
      WriteLn(tag, ': entry symbol ''', entryName, ''' is not defined by any object');
    Exit;
  end;
  if entryName = '' then
  begin
    if not ElfLnkEntryStub then
    begin
      WriteLn(tag, ': internal -- the layout reserved no room for _start');
      Exit;
    end;
    mainAddr := ElfLnkGlobalAddr(g);
    entry := ElfLnkStubAddr;
  end
  else
    entry := ElfLnkGlobalAddr(g);

  { the RW segment's extent }
  rwStart := ImageBase + ElfLnkRwFile;
  endAddr := rwStart;
  for k := ELFLNK_K_INIT to ELFLNK_K_DATA do
    if ElfLnkOutAddr[k] + ElfLnkOutSize[k] > endAddr then
      endAddr := ElfLnkOutAddr[k] + ElfLnkOutSize[k];
  rwLen := endAddr - rwStart;
  rwMem := rwLen;
  if ElfLnkOutAddr[ELFLNK_K_BSS] + ElfLnkOutSize[ELFLNK_K_BSS] - rwStart > rwMem then
    rwMem := ElfLnkOutAddr[ELFLNK_K_BSS] + ElfLnkOutSize[ELFLNK_K_BSS] - rwStart;
  SetLength(ElfLnkRw, rwLen);
  for i := 0 to Integer(rwLen) - 1 do ElfLnkRw[i] := 0;

  ElfLnkOpen(outPath);

  { ehdr + 3 phdrs (+1 with --ldso-runnable, +1 PT_NOTE when a .note* input
    is kept), padded to the first page }
  phCount := 3;
  if LdsoRunnable then Inc(phCount);
  if ElfLnkOutSize[ELFLNK_K_NOTE] > 0 then Inc(phCount);
  { p_paddr = p_vaddr - LoadOffset (--load-offset, a kernel's physical load
    address: what a PVH loader places a segment at); 0 means p_paddr = p_vaddr }
  pa := -LoadOffset;
  ElfLnkBReset;
  ElfLnkBPut($464C457F, 4); ElfLnkBPut(2, 1); ElfLnkBPut(1, 1); ElfLnkBPut(1, 1);
  ElfLnkBPadTo(16);
  ElfLnkBPut(2, 2); ElfLnkBPut(ElfLnkMachine, 2); ElfLnkBPut(1, 4);   { ET_EXEC, EM_X86_64 / EM_AARCH64 }
  ElfLnkBPut(entry, 8); ElfLnkBPut(64, 8);
  ElfLnkBPut(0, 8);                                        { e_shoff, patched below }
  ElfLnkBPut(0, 4); ElfLnkBPut(64, 2); ElfLnkBPut(56, 2); ElfLnkBPut(phCount, 2);
  ElfLnkBPut(64, 2); ElfLnkBPut(9, 2); ElfLnkBPut(8, 2);   { shentsize, shnum, shstrndx }
  { PT_LOAD R+X: the headers and .text }
  ElfLnkBPut(1, 4); ElfLnkBPut(5, 4); ElfLnkBPut(0, 8);
  ElfLnkBPut(ImageBase, 8); ElfLnkBPut(ImageBase + pa, 8);
  ElfLnkBPut(ElfLnkRxEnd, 8);
  ElfLnkBPut(ElfLnkRxEnd, 8);
  ElfLnkBPut(ELFLNK_PAGE, 8);
  { PT_LOAD R+W: .init_array .fini_array .data, then .bss as memsz }
  ElfLnkBPut(1, 4); ElfLnkBPut(6, 4); ElfLnkBPut(ElfLnkRwFile, 8);
  ElfLnkBPut(rwStart, 8); ElfLnkBPut(rwStart + pa, 8);
  ElfLnkBPut(rwLen, 8); ElfLnkBPut(rwMem, 8); ElfLnkBPut(ELFLNK_PAGE, 8);
  { PT_NOTE R: the .note* inputs, which also lie inside the RX PT_LOAD }
  if ElfLnkOutSize[ELFLNK_K_NOTE] > 0 then
  begin
    ElfLnkBPut(4, 4); ElfLnkBPut(4, 4);
    ElfLnkBPut(ElfLnkOutAddr[ELFLNK_K_NOTE] - ImageBase, 8);
    ElfLnkBPut(ElfLnkOutAddr[ELFLNK_K_NOTE], 8);
    ElfLnkBPut(ElfLnkOutAddr[ELFLNK_K_NOTE] + pa, 8);
    ElfLnkBPut(ElfLnkOutSize[ELFLNK_K_NOTE], 8); ElfLnkBPut(ElfLnkOutSize[ELFLNK_K_NOTE], 8);
    ElfLnkBPut(ElfLnkNoteAlign, 8);
  end;
  { PT_GNU_STACK RW: without it the kernel may map the stack executable }
  ElfLnkBPut($6474E551, 4); ElfLnkBPut(6, 4);
  for i := 1 to 5 do ElfLnkBPut(0, 8);
  ElfLnkBPut(16, 8);
  { --ldso-runnable: PT_DYNAMIC and the minimal dynamic block (see
    WriteLdsoBlock in elfwriter.inc, the same bytes) after the headers, still in
    the first page, which .text never shares. }
  if LdsoRunnable then
  begin
    ldsoVA := ImageBase + 64 + phCount * 56;
    ElfLnkBPut(2, 4); ElfLnkBPut(4, 4); ElfLnkBPut(64 + phCount * 56, 8);
    ElfLnkBPut(ldsoVA, 8); ElfLnkBPut(ldsoVA, 8);
    ElfLnkBPut(LDSO_DYNAMIC_SIZE, 8); ElfLnkBPut(LDSO_DYNAMIC_SIZE, 8); ElfLnkBPut(8, 8);
    ElfLnkBPut(4, 8);  ElfLnkBPut(ldsoVA + LDSO_DYNAMIC_SIZE, 8);            { DT_HASH }
    ElfLnkBPut(6, 8);  ElfLnkBPut(ldsoVA + LDSO_DYNAMIC_SIZE + 16, 8);       { DT_SYMTAB }
    ElfLnkBPut(5, 8);  ElfLnkBPut(ldsoVA + LDSO_DYNAMIC_SIZE + 16 + 24, 8);  { DT_STRTAB }
    ElfLnkBPut(10, 8); ElfLnkBPut(1, 8);                                     { DT_STRSZ }
    ElfLnkBPut(11, 8); ElfLnkBPut(24, 8);                                    { DT_SYMENT }
    ElfLnkBPut(0, 8);  ElfLnkBPut(0, 8);                                     { DT_NULL }
    ElfLnkBPut(1, 4); ElfLnkBPut(1, 4); ElfLnkBPut(0, 4); ElfLnkBPut(0, 4); { nbucket nchain bucket chain }
    for i := 1 to 4 do ElfLnkBPut(0, 8);   { the null symbol (24) + empty strtab padded (8) }
  end;
  ElfLnkBPadTo(ELFLNK_PAGE);
  { e_shoff is known only after the image; computed now from the layout }
  fileAt := ElfLnkRwFile + rwLen;
  symOff := Integer(ElfLnkAlignUp(fileAt, 8));
  nDef := 0; strSize := 1;
  for i := 0 to ElfLnkCount - 1 do
    if ElfLnkDefKept(i) then
    begin
      Inc(nDef);
      strSize := strSize + Length(ElfLnkName[i]) + 1;
    end;
  if entryName = '' then
  begin
    Inc(nDef);
    strSize := strSize + Length('_start') + 1;
  end;
  strOff := symOff + (nDef + 1) * 24;
  shstrOff := strOff + strSize;
  { Output section numbering: the five kinds every link has always written,
    plus .multiboot, .rodata and .note only when they have bytes, so an
    ordinary link's headers are what they were. }
  nOut := 0;
  for k := 0 to ELFLNK_NKIND - 1 do
    if ((k <> ELFLNK_K_HEAD) and (k <> ELFLNK_K_RODATA) and (k <> ELFLNK_K_NOTE))
       or (ElfLnkOutSize[k] > 0) then
    begin
      Inc(nOut);
      outIdx[k] := nOut;
    end
    else outIdx[k] := 0;
  shstrLen := SHSTR;
  if outIdx[ELFLNK_K_HEAD] > 0 then shstrLen := shstrLen + 11;
  if outIdx[ELFLNK_K_RODATA] > 0 then shstrLen := shstrLen + 8;
  if outIdx[ELFLNK_K_NOTE] > 0 then shstrLen := shstrLen + 6;
  shOff := Integer(ElfLnkAlignUp(shstrOff + shstrLen, 8));
  ElfLnkPutLE(ElfLnkB, 40, shOff, 8);
  ElfLnkPutLE(ElfLnkB, 60, nOut + 4, 2);   { e_shnum: null + kinds + 3 }
  ElfLnkPutLE(ElfLnkB, 62, nOut + 3, 2);   { e_shstrndx }
  ElfLnkWrite(ElfLnkB, ElfLnkBLen);

  { .multiboot and .rodata (--link --freestanding) are assembled in memory
    first, because the stream below writes .text as it goes and .multiboot
    precedes it in the file. }
  if (ElfLnkOutSize[ELFLNK_K_HEAD] > 0) or (ElfLnkOutSize[ELFLNK_K_RODATA] > 0)
     or (ElfLnkOutSize[ELFLNK_K_NOTE] > 0) then
    if not ElfLnkFillRo(tag) then
    begin
      ElfLnkClose(outPath);
      Exit;
    end;
  cur := ImageBase + ELFLNK_PAGE;
  if ElfLnkOutSize[ELFLNK_K_HEAD] > 0 then
  begin
    ElfLnkWriteZeros(ElfLnkOutAddr[ELFLNK_K_HEAD] - cur);
    ElfLnkWrite(ElfLnkHd, ElfLnkOutSize[ELFLNK_K_HEAD]);
    cur := ElfLnkOutAddr[ELFLNK_K_HEAD] + ElfLnkOutSize[ELFLNK_K_HEAD];
  end;
  { .text streamed per object; RW inputs copied into ElfLnkRw }
  for o := 0 to ElfLnkObjCount - 1 do
  begin
    LoadInput(ElfLnkObjPath[o], ElfRdBuf);
    if Length(ElfRdBuf) = 0 then ElfRdErr := 'read back empty'
    else if ElfRdCheckHeader then ElfRdErr := '';
    if ElfRdErr <> '' then
    begin
      WriteLn(tag, ': ', ElfLnkObjPath[o], ': cannot re-read the object: ', ElfRdErr);
      ElfLnkClose(outPath);
      Exit;
    end;
    nsec := ElfRdShNum;
    { which rela section patches which section: one pass, so a split object's
      thousand sections do not each rescan the header table }
    SetLength(relaOf, nsec);
    for i := 0 to nsec - 1 do relaOf[i] := -1;
    for i := 1 to nsec - 1 do
      if ElfRdShType(i) = ELFRD_SHT_RELA then
      begin
        t := Integer(ElfRdU32(ElfRdShdr(i) + 44));
        if (t > 0) and (t < nsec) then relaOf[t] := i;
      end;
    for i := 1 to nsec - 1 do
    begin
      slot := ElfLnkObjSec0[o] + i;
      k := ElfLnkSecKindOf[slot];
      if (not ElfLnkSecLive[slot]) or (k = ELFLNK_K_BSS)
         or (k = ELFLNK_K_HEAD) or (k = ELFLNK_K_RODATA) or (k = ELFLNK_K_NOTE) then Continue;
      sz := ElfLnkSecSize[slot];
      secOff := ElfRdShOffset(i);
      if k = ELFLNK_K_TEXT then
      begin
        SetLength(ElfLnkTb, sz);
        for t := 0 to Integer(sz) - 1 do ElfLnkTb[t] := Ord(ElfRdBuf[secOff + 1 + t]);
        if not ElfLnkRelocate(o, nsec, i, relaOf[i], ElfLnkTb, 0) then
        begin
          WriteLn(tag, ': ', ElfLnkObjPath[o], ': ', ElfRdErr);
          ElfLnkClose(outPath);
          Exit;
        end;
        ElfLnkWriteZeros(ElfLnkSecAddr[slot] - cur);
        ElfLnkWrite(ElfLnkTb, sz);
        cur := ElfLnkSecAddr[slot] + sz;
      end
      else
      begin
        for t := 0 to Integer(sz) - 1 do
          ElfLnkRw[Integer(ElfLnkSecAddr[slot] - rwStart) + t] := Ord(ElfRdBuf[secOff + 1 + t]);
        if not ElfLnkRelocate(o, nsec, i, relaOf[i], ElfLnkRw,
                              ElfLnkSecAddr[slot] - rwStart) then
        begin
          WriteLn(tag, ': ', ElfLnkObjPath[o], ': ', ElfRdErr);
          ElfLnkClose(outPath);
          Exit;
        end;
      end;
    end;
  end;
  if entryName = '' then
  begin
    SetLength(stub, ElfLnkStubSize);
    if ElfLnkMachine = ELFLNK_EM_AARCH64 then
      ElfLnkPutStubA64(stub, ElfLnkOutAddr[ELFLNK_K_INIT],
                       ElfLnkOutAddr[ELFLNK_K_INIT] + ElfLnkOutSize[ELFLNK_K_INIT], mainAddr)
    else
      ElfLnkPutStub(stub, ElfLnkOutAddr[ELFLNK_K_INIT],
                    ElfLnkOutAddr[ELFLNK_K_INIT] + ElfLnkOutSize[ELFLNK_K_INIT], mainAddr);
    ElfLnkWriteZeros(ElfLnkStubAddr - cur);
    ElfLnkWrite(stub, ElfLnkStubSize);
    cur := ElfLnkStubAddr + ElfLnkStubSize;
  end;
  textEnd := ElfLnkOutAddr[ELFLNK_K_TEXT] + ElfLnkOutSize[ELFLNK_K_TEXT];
  ElfLnkWriteZeros(textEnd - cur);
  cur := textEnd;
  if ElfLnkOutSize[ELFLNK_K_RODATA] > 0 then
  begin
    ElfLnkWriteZeros(ElfLnkOutAddr[ELFLNK_K_RODATA] - cur);
    ElfLnkWrite(ElfLnkRd, ElfLnkOutSize[ELFLNK_K_RODATA]);
    cur := ElfLnkOutAddr[ELFLNK_K_RODATA] + ElfLnkOutSize[ELFLNK_K_RODATA];
  end;
  if ElfLnkOutSize[ELFLNK_K_NOTE] > 0 then
  begin
    ElfLnkWriteZeros(ElfLnkOutAddr[ELFLNK_K_NOTE] - cur);
    ElfLnkWrite(ElfLnkNt, ElfLnkOutSize[ELFLNK_K_NOTE]);
    cur := ElfLnkOutAddr[ELFLNK_K_NOTE] + ElfLnkOutSize[ELFLNK_K_NOTE];
  end;
  ElfLnkWriteZeros(ImageBase + ElfLnkRxEnd - cur);
  ElfLnkWriteZeros(ElfLnkRwFile - ElfLnkRxEnd);
  ElfLnkWrite(ElfLnkRw, rwLen);
  ElfLnkWriteZeros(symOff - fileAt);

  { .symtab (every defined global), .strtab, .shstrtab, section headers.
    Output section indices: 1 .text 2 .init_array 3 .fini_array 4 .data
    5 .bss 6 .symtab 7 .strtab 8 .shstrtab. }
  ElfLnkBReset;
  for i := 1 to 24 do ElfLnkBPut(0, 1);
  strPos := 1;
  for i := 0 to ElfLnkCount - 1 do
    if ElfLnkDefKept(i) then
    begin
      ElfLnkBPut(strPos, 4);
      ElfLnkBPut(ElfLnkDefInfo[i], 1);
      ElfLnkBPut(0, 1);
      if ElfLnkDefSec[i] < 0 then ElfLnkBPut($FFF1, 2)
      else ElfLnkBPut(outIdx[ElfLnkSecKindOf[ElfLnkDefSec[i]]], 2);
      ElfLnkBPut(ElfLnkGlobalAddr(i), 8);
      ElfLnkBPut(ElfLnkDefSize[i], 8);
      strPos := strPos + Length(ElfLnkName[i]) + 1;
    end;
  if entryName = '' then
  begin
    ElfLnkBPut(strPos, 4); ElfLnkBPut($12, 1); ElfLnkBPut(0, 1);
    ElfLnkBPut(outIdx[ELFLNK_K_TEXT], 2);  { GLOBAL FUNC .text }
    ElfLnkBPut(ElfLnkStubAddr, 8); ElfLnkBPut(ElfLnkStubSize, 8);
  end;
  ElfLnkBPut(0, 1);
  for i := 0 to ElfLnkCount - 1 do
    if ElfLnkDefKept(i) then ElfLnkBStrZ(ElfLnkName[i]);
  if entryName = '' then ElfLnkBStrZ('_start');
  { SHSTR = 68 bytes: offsets .text 1, .init_array 7, .fini_array 19, .data 31,
    .bss 37, .symtab 42, .strtab 50, .shstrtab 58 }
  ElfLnkBPut(0, 1);
  ElfLnkBStrZ('.text'); ElfLnkBStrZ('.init_array'); ElfLnkBStrZ('.fini_array');
  ElfLnkBStrZ('.data'); ElfLnkBStrZ('.bss'); ElfLnkBStrZ('.symtab');
  ElfLnkBStrZ('.strtab'); ElfLnkBStrZ('.shstrtab');
  { appended, so the eight names above keep their offsets }
  if outIdx[ELFLNK_K_HEAD] > 0 then ElfLnkBStrZ('.multiboot');      { at SHSTR }
  if outIdx[ELFLNK_K_RODATA] > 0 then ElfLnkBStrZ('.rodata');       { at SHSTR or SHSTR+11 }
  if outIdx[ELFLNK_K_NOTE] > 0 then ElfLnkBStrZ('.note');           { after those two }
  ElfLnkBPadTo(shOff - symOff);
  { null }
  for i := 1 to 64 do ElfLnkBPut(0, 1);
  { name type flags addr off size link info align entsize }
  for k := 0 to ELFLNK_NKIND - 1 do
  begin
    if outIdx[k] = 0 then Continue;
    case k of
      ELFLNK_K_HEAD: begin ElfLnkBPut(SHSTR, 4); ElfLnkBPut(1, 4); ElfLnkBPut(2, 8); end;
      ELFLNK_K_TEXT: begin ElfLnkBPut(1, 4);  ElfLnkBPut(1, 4);  ElfLnkBPut(6, 8); end;
      ELFLNK_K_RODATA:
        begin
          if outIdx[ELFLNK_K_HEAD] > 0 then ElfLnkBPut(SHSTR + 11, 4) else ElfLnkBPut(SHSTR, 4);
          ElfLnkBPut(1, 4); ElfLnkBPut(2, 8);
        end;
      ELFLNK_K_NOTE:
        begin
          t := SHSTR;
          if outIdx[ELFLNK_K_HEAD] > 0 then t := t + 11;
          if outIdx[ELFLNK_K_RODATA] > 0 then t := t + 8;
          ElfLnkBPut(t, 4); ElfLnkBPut(7, 4); ElfLnkBPut(2, 8);
        end;
      ELFLNK_K_INIT: begin ElfLnkBPut(7, 4);  ElfLnkBPut(14, 4); ElfLnkBPut(3, 8); end;
      ELFLNK_K_FINI: begin ElfLnkBPut(19, 4); ElfLnkBPut(15, 4); ElfLnkBPut(3, 8); end;
      ELFLNK_K_DATA: begin ElfLnkBPut(31, 4); ElfLnkBPut(1, 4);  ElfLnkBPut(3, 8); end;
      ELFLNK_K_BSS:  begin ElfLnkBPut(37, 4); ElfLnkBPut(8, 4);  ElfLnkBPut(3, 8); end;
    end;
    ElfLnkBPut(ElfLnkOutAddr[k], 8);
    if k = ELFLNK_K_TEXT then ElfLnkBPut(ElfLnkOutAddr[k] - ImageBase, 8)
    else if k = ELFLNK_K_BSS then ElfLnkBPut(ElfLnkRwFile + rwLen, 8)
    else ElfLnkBPut(ElfLnkOutAddr[k] - ImageBase, 8);
    ElfLnkBPut(ElfLnkOutSize[k], 8);
    ElfLnkBPut(0, 4); ElfLnkBPut(0, 4);
    if k = ELFLNK_K_TEXT then ElfLnkBPut(16, 8)
    else if (k = ELFLNK_K_INIT) or (k = ELFLNK_K_FINI) then ElfLnkBPut(8, 8)
    else if (k = ELFLNK_K_HEAD) or (k = ELFLNK_K_RODATA) then ElfLnkBPut(1, 8)
    else if k = ELFLNK_K_NOTE then ElfLnkBPut(ElfLnkNoteAlign, 8)
    else ElfLnkBPut(16, 8);
    if (k = ELFLNK_K_INIT) or (k = ELFLNK_K_FINI) then ElfLnkBPut(8, 8) else ElfLnkBPut(0, 8);
  end;
  { .symtab: link .strtab, info = one past the last local (only the null) }
  ElfLnkBPut(42, 4); ElfLnkBPut(2, 4); ElfLnkBPut(0, 8); ElfLnkBPut(0, 8);
  ElfLnkBPut(symOff, 8); ElfLnkBPut((nDef + 1) * 24, 8);
  ElfLnkBPut(nOut + 2, 4); ElfLnkBPut(1, 4); ElfLnkBPut(8, 8); ElfLnkBPut(24, 8);
  ElfLnkBPut(50, 4); ElfLnkBPut(3, 4); ElfLnkBPut(0, 8); ElfLnkBPut(0, 8);
  ElfLnkBPut(strOff, 8); ElfLnkBPut(strSize, 8);
  ElfLnkBPut(0, 4); ElfLnkBPut(0, 4); ElfLnkBPut(1, 8); ElfLnkBPut(0, 8);
  ElfLnkBPut(58, 4); ElfLnkBPut(3, 4); ElfLnkBPut(0, 8); ElfLnkBPut(0, 8);
  ElfLnkBPut(shstrOff, 8); ElfLnkBPut(shstrLen, 8);
  ElfLnkBPut(0, 4); ElfLnkBPut(0, 4); ElfLnkBPut(1, 8); ElfLnkBPut(0, 8);
  ElfLnkWrite(ElfLnkB, ElfLnkBLen);
  ElfLnkClose(outPath);
  ElfLnkWriteExe := True;
end;

{ PXXDBG=a.objlink:<listfile> -- stages 3 and 4 end to end: lay the set out,
  relocate it, and write <listfile>.exe with the entry at `main`. `main`, not
  `_start`, because the process-entry contract is stage 5; this topic exists so
  the RELOCATED BYTES can be compared against ld's while that is not yet built.
  An image entered at main runs until main returns and then faults, which is
  the measured behaviour of `ld -e main` over the same objects. }
procedure ElfLnkLinkDump(const listPath: AnsiString);
begin
  if not ElfLnkLoadList(listPath, 'elflink') then Exit;
  ElfLnkGcMark(-1);
  ElfLnkLayout;
  if not ElfLnkWriteExe(listPath + '.exe', 'main', 'elflink') then Exit;
  WriteLn('elflink: wrote ', listPath, '.exe');
  WriteLn('elflink: ELFLINK-OK');
end;

{ PXXDBG=a.objgclink:<listfile> -- stage 4 WITH section GC: collect from
  main, lay out what survives, print that layout in a.objlayout's form, and
  write <listfile>.exe entered at main. The layout lines are what let the
  oracle force ld --gc-sections to the same addresses and fence the padding
  between the inputs that survived. }
procedure ElfLnkGcLinkDump(const listPath: AnsiString);
begin
  if not ElfLnkLoadList(listPath, 'elflink') then Exit;
  ElfLnkGcOn := True;
  ElfLnkGcMark(ElfLnkFind('main'));
  ElfLnkLayout;
  ElfLnkPrintLayout;
  if not ElfLnkWriteExe(listPath + '.exe', 'main', 'elflink') then Exit;
  WriteLn('elflink: wrote ', listPath, '.exe');
  WriteLn('elflink: ELFLINK-OK');
end;

{ --link <obj>... <out>, ParamStr(first..last) being the objects. If the set
  defines _start it is the entry, as it would be for ld; otherwise the linker
  supplies one (ElfLnkPutStub) that calls main. }
function ElfLnkLinkArgs(first, last: Integer; const outPath: AnsiString; gc: Boolean): Boolean;
var j, g: Integer;
    entryName: AnsiString;
begin
  ElfLnkLinkArgs := False;
  ElfLnkReset;
  if TargetArch = TARGET_AARCH64 then ElfLnkMachine := ELFLNK_EM_AARCH64;
  ElfLnkGcOn := gc;
  for j := first to last do
    if not ElfLnkAddObject(ParamStr(j)) then
    begin
      WriteLn(StdErr, 'pascal26 --link: ', ParamStr(j), ': ', ElfRdErr);
      Exit;
    end;
  g := ElfLnkFind('_start');
  if LinkEntryName <> '' then
  begin
    entryName := LinkEntryName;
    g := ElfLnkFind(entryName);
  end
  else if (g >= 0) and (ElfLnkDefObj[g] >= 0) then entryName := '_start'
  else if FreestandingMode then
  begin
    { a kernel's entry is its own (start32, reached from a boot loader), and
      there is no runtime here to synthesise a _start that calls main }
    WriteLn(StdErr, 'pascal26 --link --freestanding: no object defines _start; '
            + 'name the entry with -e <symbol>');
    Exit;
  end
  else
  begin
    entryName := '';
    ElfLnkEntryStub := True;
    g := ElfLnkFind('main');
  end;
  ElfLnkGcMark(g);
  ElfLnkLayout;
  ElfLnkDefineLinkerSyms;
  ElfLnkLinkArgs := ElfLnkWriteExe(outPath, entryName, 'pascal26 --link');
end;

{ PXXDBG=a.objgc:<listfile> -- the section GC's verdict over that set, rooted
  at _start if an object defines it and at main otherwise: one line per
  DROPPED allocated section in ld's own --print-gc-sections wording, so the
  two lists compare after stripping the prefix, then the totals. }
procedure ElfLnkGcDump(const listPath: AnsiString);
var o, i, g, slot, nAll, nKept: Integer;
    bAll, bKept: Int64;
begin
  if not ElfLnkLoadList(listPath, 'elfgc') then Exit;
  g := ElfLnkFind('_start');
  if (g < 0) or (ElfLnkDefObj[g] < 0) then g := ElfLnkFind('main');
  ElfLnkGcOn := True;
  ElfLnkGcMark(g);
  nAll := 0; nKept := 0; bAll := 0; bKept := 0;
  for o := 0 to ElfLnkObjCount - 1 do
  begin
    LoadInput(ElfLnkObjPath[o], ElfRdBuf);
    if (Length(ElfRdBuf) = 0) or not ElfRdCheckHeader then
    begin
      WriteLn('elfgc: ', ElfLnkObjPath[o], ': cannot re-read the object');
      Exit;
    end;
    for i := 1 to ElfLnkObjNsec[o] - 1 do
    begin
      slot := ElfLnkObjSec0[o] + i;
      if ElfLnkSecKindOf[slot] = ELFLNK_NKIND then Continue;
      Inc(nAll);
      bAll := bAll + ElfLnkSecSize[slot];
      if ElfLnkSecLive[slot] then
      begin
        Inc(nKept);
        bKept := bKept + ElfLnkSecSize[slot];
      end
      else
        WriteLn('elfgc: removing unused section ''', ElfRdSecName(i), ''' in file ''',
                ElfLnkObjPath[o], '''');
    end;
  end;
  WriteLn('elfgc: kept ', AIntToStr(nKept), ' of ', AIntToStr(nAll), ' sections, ',
          AIntToStr(bKept), ' of ', AIntToStr(bAll), ' bytes');
  WriteLn('elfgc: ELFGC-OK');
end;

