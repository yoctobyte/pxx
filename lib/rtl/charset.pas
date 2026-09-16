{ charset -- codepage <-> Unicode mapping tables.

  FPC's rtl/inc/charset.pp, which its COMPILER uses: widestr.pas asks for a map
  by codepage and converts single characters through it
  (umbrella-pxx-compiles-fpc-itself). Eight corpus units name it in a `uses`;
  exactly one of them touches its contents, so the surface below is fpc's whole
  public one rather than the subset one caller happens to need -- a unit that
  compiles for seven importers and lies to the eighth is the worse outcome.

  THIS UNIT IS A REGISTRY, NOT A TABLE. It ships no codepage data, and neither
  does fpc's: maps arrive through registermapping / registerbinarymapping, from
  files or from generated units. So `getmap` answering nil on a fresh process is
  CORRECT and is not a stub -- it is what fpc does, and it is why every caller
  is expected to ask `mappingavailable` first. fpc's own `getunicode(c, p)`
  dereferences p with no nil check; that contract is copied rather than
  softened, because a nil-tolerant version here would silently return character
  0 for every lookup in a program whose real bug is a missing map.

  `{$PACKENUM 1}` is fpc's, at the top of charset.pp, and it is LOAD-BEARING
  rather than cosmetic: it makes tunicodecharmapping 4 bytes instead of 8, and
  the binary map format below is a straight image of that record. Measured
  against fpc 3.2.2 before this unit was written -- SizeOf(the flag)=1,
  SizeOf(the record)=4, identical under both compilers.

  WHERE THIS DELIBERATELY DIVERGES FROM FPC, AND WHY -- three places, all in
  routines the compiler never calls, all measured against fpc 3.2.2 on
  2026-09-16 rather than reasoned about:

    * loadunicodemapping BOUNDS ITS SCANS. fpc's walk the ShortString past its
      length with no check, and on a WELL-FORMED file that reads the residue of
      an EARLIER line -- the buffer is never cleared. Reduced exactly: after a
      `0x8E<tab>#DBCS LEAD BYTE` line (verbatim what Microsoft's CP932.TXT
      contains), the shorter following line `0x8E41<tab>0x4E00` leaves `AD` from
      `...LEAD BYTE` in place, fpc's hex loop consumes it, parses `$4E00AD`, and
      truncates to a word -- so U+4E00 is registered as U+00AD. No diagnostic,
      wrong table, real input. We stop at Length(s).
    * The grow check is `charpos >= datasize`, not fpc's `charpos > datasize`
      (which writes one entry past the array at charpos = datasize), and it runs
      for EVERY line rather than only the ones with a hex unicode column (fpc's
      sits inside that branch, so a lead-byte line beyond the current capacity
      writes out of bounds).
    * getascii's buffer form honours a nil buffer in BOTH arms. See the comment
      at that routine: fpc SEGVs on its own documented length query.

  In every case we answer where fpc corrupts or crashes, so these are not
  compatibility gaps to close. Everything the compiler actually calls -- the
  registry, both getmap doors, getunicode, getascii, the reverse-map build and
  the binary format -- is fpc's algorithm, and the two agree byte for byte
  across the differential probe.

  `string` means ShortString throughout, spelled explicitly, because
  `cpname : string[20]` is unambiguously one and everything else is compared
  against it. }
unit charset;

{$PACKENUM 1}

interface

{ No `uses` in the INTERFACE, as fpc has none -- eight corpus units import this
  one and none of them should acquire from us a transitive dependency they do
  not have under fpc. sysutils is pulled in the implementation only, for
  DirectorySeparator, which fpc has in System and we do not. }

type
  tunicodechar = Word;
  tunicodestring = ^tunicodechar;

  { umf_noinfo is the ORDINARY case -- a character that maps straight through.
    buildreversemap below builds the reverse table from exactly these, which is
    why an entry left umf_unused is absent from it rather than mapping to 0. }
  tunicodecharmappingflag = (umf_noinfo, umf_leadbyte, umf_undefined, umf_unused);

  punicodecharmapping = ^tunicodecharmapping;
  tunicodecharmapping = packed record
    unicode: tunicodechar;
    flag: tunicodecharmappingflag;
    reserved: Byte;
  end;

  preversecharmapping = ^treversecharmapping;
  treversecharmapping = packed record
    unicode: tunicodechar;
    char1: Byte;
    char2: Byte;
  end;

  punicodemap = ^tunicodemap;
  tunicodemap = record
    cpname: string[20];
    cp: Word;
    map: punicodecharmapping;
    lastchar: LongInt;
    reversemap: preversecharmapping;
    reversemaplength: LongInt;
    next: punicodemap;
    internalmap: Boolean;
  end;

  { The on-disk header of a binary map. Fixed-width fields and a packed record,
    so the file is portable between builds -- do not widen these to native
    integers. }
  TSerializedMapHeader = packed record
    cpName: string[20];
    cp: UInt16;
    mapLength: UInt32;
    lastChar: Int32;
    reverseMapLength: UInt32;
  end;

const
  { fpc's, and part of the published surface: a caller that builds its own file
    name needs the same extension registerbinarymapping will look for. }
  BINARY_MAPPING_FILE_EXT = '.bcm';

function loadunicodemapping(const cpname, f: ShortString; cp: Word): punicodemap;
function loadbinaryunicodemapping(const directory, cpname: ShortString): punicodemap; overload;
function loadbinaryunicodemapping(const filename: ShortString): punicodemap; overload;
function loadbinaryunicodemapping(const AData: Pointer; const ADataLength: Integer): punicodemap; overload;
procedure registermapping(p: punicodemap);
function registerbinarymapping(const directory, cpname: ShortString): Boolean;
function getmap(const s: ShortString): punicodemap; overload;
function getmap(cp: Word): punicodemap; overload;
function mappingavailable(const s: ShortString): Boolean; overload;
function mappingavailable(cp: Word): Boolean; overload;
function getunicode(c: AnsiChar; p: punicodemap): tunicodechar; overload;
function getunicode(AAnsiStr: PAnsiChar; AAnsiLen: LongInt; AMap: punicodemap;
                    ADest: tunicodestring): LongInt; overload;
function getascii(c: tunicodechar; p: punicodemap): ShortString; overload;
function getascii(c: tunicodechar; p: punicodemap; ABuffer: PAnsiChar;
                  ABufferLen: LongInt): LongInt; overload;

implementation

uses sysutils;

const
  { fpc's names, misspelling included, so a reader diffing against charset.pp
    finds them. Untyped rather than fpc's AnsiChar(63)/tunicodechar(63): the
    same constant is assigned to a ShortString in one getascii overload and to
    an AnsiChar in the other, and an untyped character literal reaches both. }
  UNKNOW_CHAR_A = '?';
  UNKNOW_CHAR_W = 63;

var
  mappings: punicodemap;
  { fpc makes the four cache variables threadvars. Plain vars here: the cache is
    an optimisation whose worst case under a race is a miss, and this unit has
    no other shared state. Written down because the divergence is deliberate. }
  strmapcache: ShortString;
  strmapcachep: punicodemap;
  intmapcache: Word;
  intmapcachep: punicodemap;
  finhp: punicodemap;   { the finalization walker, a unit var as in fpc }

procedure QuickSort(AList: preversecharmapping; L, R: LongInt);
var
  I, J: LongInt;
  P, Q: treversecharmapping;
begin
  repeat
    I := L;
    J := R;
    P := AList[(L + R) div 2];
    repeat
      while (P.unicode - AList[I].unicode) > 0 do Inc(I);
      while (P.unicode - AList[J].unicode) < 0 do Dec(J);
      if I <= J then
      begin
        Q := AList[I]; AList[I] := AList[J]; AList[J] := Q;
        Inc(I); Dec(J);
      end;
    until I > J;
    { fpc's tail-balancing: recurse into the SHORTER side and iterate on the
      longer one, which bounds the recursion depth at log2(n). Copied rather
      than simplified -- a plain "recurse left, iterate right" is O(n) deep on
      an already-sorted input, and a codepage table arrives sorted. }
    if J - L < R - I then
    begin
      if L < J then QuickSort(AList, L, J);
      L := I;
    end
    else
    begin
      if I < R then QuickSort(AList, I, R);
      R := J;
    end;
  until L >= R;
end;

{ Binary search over the sorted reverse table. Returns nil rather than an
  insertion point: a codepage that cannot represent a character is an ordinary
  answer here, not an error. }
function find(const c: tunicodechar; const AData: preversecharmapping;
              const ALen: LongInt): preversecharmapping; overload;
var
  l, h, m: LongInt;
  r: preversecharmapping;
begin
  if ALen = 0 then Exit(nil);
  r := AData;
  l := 0;
  h := ALen - 1;
  while l < h do
  begin
    m := (l + h) div 2;
    if r[m].unicode < c then l := m + 1 else h := m;
  end;
  if (l = h) and (r[l].unicode = c) then Result := @r[l] else Result := nil;
end;

function find(const c: tunicodechar; const p: punicodemap): preversecharmapping; overload;
begin
  Result := find(c, p^.reversemap, p^.reversemaplength);
end;

{ A codepage may encode one unicode point at several positions, so the sorted
  table can hold duplicates. WHICH ONE SURVIVES IS NOT "THE FIRST SEEN" -- fpc
  keeps the SMALLEST (char1, char2) pair, and that choice is what makes getascii
  deterministic: QuickSort is not stable, so among equal unicode keys the
  encounter order is an artefact of the partitioning and would otherwise make a
  character's encoding depend on the table's length. Selecting the minimum
  removes the sort from the answer entirely.

  fpc's own comment here says "keep the first mapping" while the code keeps the
  smallest; the code is the specification and the comment is not. }
function RemoveDuplicates(const AData: preversecharmapping; const ALen: LongInt;
                          out AResultLen: LongInt): preversecharmapping;
var
  i, c, actualCount: LongInt;
  r0, r, p, t: preversecharmapping;
begin
  AResultLen := 0;
  if ALen < 1 then Exit(nil);
  c := ALen;
  GetMem(r0, c * SizeOf(treversecharmapping));
  r := r0;
  p := AData;
  actualCount := 0;
  i := 0;
  while i < c do
  begin
    { The partial result is appended in ascending unicode order because the
      INPUT is sorted, so a binary search over it is valid mid-build. }
    t := find(p^.unicode, r0, actualCount);
    if t = nil then
    begin
      r^ := p^;
      actualCount := actualCount + 1;
      Inc(r);
    end
    else
      if (p^.char1 < t^.char1) or
         ((p^.char1 = t^.char1) and (p^.char2 < t^.char2)) then
        t^ := p^;
    i := i + 1;
    Inc(p);
  end;
  if c <> actualCount then ReAllocMem(r0, actualCount * SizeOf(treversecharmapping));
  AResultLen := actualCount;
  Result := r0;
end;

{ unicode -> codepage, built from the forward table. Only umf_noinfo entries
  participate: a lead byte is half a character and an undefined slot has nothing
  to map back to. Positions above 255 encode as a two-byte pair, which is what
  char2 <> 0 means to getascii. }
function buildreversemap(const AMapping: punicodecharmapping; const ALen: LongInt;
                         out AResultLen: LongInt): preversecharmapping;
var
  r0, r, t: preversecharmapping;
  i, c, actualCount, ti: LongInt;
  p: punicodecharmapping;
begin
  AResultLen := 0;
  if ALen < 1 then Exit(nil);
  p := AMapping;
  c := ALen;
  GetMem(r0, c * SizeOf(treversecharmapping));
  r := r0;
  actualCount := 0;
  i := 0;
  while i < c do
  begin
    if p^.flag = umf_noinfo then
    begin
      r^.unicode := p^.unicode;
      if i <= 255 then
      begin
        r^.char1 := i;
        r^.char2 := 0;
      end
      else
      begin
        r^.char1 := i div 256;
        r^.char2 := i mod 256;
      end;
      actualCount := actualCount + 1;
      Inc(r);
    end;
    Inc(p);
    i := i + 1;
  end;
  if c <> actualCount then ReAllocMem(r0, actualCount * SizeOf(treversecharmapping));
  if actualCount > 1 then
  begin
    QuickSort(r0, 0, actualCount - 1);
    t := RemoveDuplicates(r0, actualCount, ti);
    FreeMem(r0);
    r0 := t;
    actualCount := ti;
  end;
  AResultLen := actualCount;
  Result := r0;
end;

{ umf_unused, not zero-filled: an all-zero record would read as umf_noinfo
  mapping to U+0000, i.e. a table full of valid-looking NUL entries. }
procedure inititems(const p: punicodecharmapping; const ALen: LongInt);
var
  x: punicodecharmapping;
  i: LongInt;
begin
  x := p;
  for i := 0 to ALen - 1 do
  begin
    x^.unicode := 0;
    x^.flag := umf_unused;
    x^.reserved := 0;
    Inc(x);
  end;
end;

procedure freemapping(amapping: punicodemap);
begin
  if amapping = nil then Exit;
  if amapping^.map <> nil then FreeMem(amapping^.map);
  if amapping^.reversemap <> nil then FreeMem(amapping^.reversemap);
  Dispose(amapping);
end;

{ A Unicode.org-style .TXT mapping file: `0xNN<tab>0xUUUU<tab># comment`, with
  `#DBCS LEAD BYTE` marking a lead byte and a missing unicode column marking an
  undefined position. Lines that do not start `0x` are comments and are skipped.

  EVERY SCAN HERE IS BOUNDED AND FPC'S ARE NOT -- see the unit header for the
  reduction. The guards are not defensive padding; without them this routine
  reads the previous line's bytes and silently registers the wrong character. }
function loadunicodemapping(const cpname, f: ShortString; cp: Word): punicodemap;
var
  data: punicodecharmapping;
  datasize: LongInt;
  t: Text;
  s, hs: ShortString;
  scanpos, charpos, unicodevalue: LongInt;
  code: Word;
  flag: tunicodecharmappingflag;
  p: punicodemap;
  lastchar, rlen: LongInt;
begin
  lastchar := -1;
  Result := nil;
  datasize := 256;
  GetMem(data, SizeOf(tunicodecharmapping) * datasize);
  inititems(data, datasize);
  Assign(t, f);
  {$push}{$I-}
  Reset(t);
  {$pop}
  if IOResult <> 0 then
  begin
    FreeMem(data);
    Exit;
  end;
  while not Eof(t) do
  begin
    ReadLn(t, s);
    { Length(s) >= 2 before touching s[1] and s[2]: fpc indexes both
      unconditionally, so an empty line reads the length byte as data. }
    if (Length(s) >= 2) and (s[1] = '0') and (s[2] = 'x') then
    begin
      flag := umf_unused;
      scanpos := 3;
      hs := '$';
      while (scanpos <= Length(s)) and
            (s[scanpos] in ['0'..'9', 'A'..'F', 'a'..'f']) do
      begin
        hs := hs + s[scanpos];
        Inc(scanpos);
      end;
      Val(hs, charpos, code);
      if code <> 0 then
      begin
        FreeMem(data);
        Close(t);
        Exit;
      end;
      while (scanpos <= Length(s)) and not (s[scanpos] in ['0', '#']) do Inc(scanpos);
      if scanpos > Length(s) then
        { Ran out of line: no unicode column and no comment, so the position is
          undefined. fpc keeps scanning here, off the end of the string. }
        unicodevalue := $FFFF
      else if s[scanpos] = '#' then
      begin
        unicodevalue := $FFFF;
        hs := Copy(s, scanpos, Length(s) - scanpos + 1);
        if hs = '#DBCS LEAD BYTE' then flag := umf_leadbyte;
      end
      else
      begin
        Inc(scanpos);                  { the '0' of '0x' }
        if (scanpos <= Length(s)) and ((s[scanpos] = 'x') or (s[scanpos] = 'X')) then
          Inc(scanpos);
        hs := '$';
        while (scanpos <= Length(s)) and
              (s[scanpos] in ['0'..'9', 'A'..'F', 'a'..'f']) do
        begin
          hs := hs + s[scanpos];
          Inc(scanpos);
        end;
        Val(hs, unicodevalue, code);
        if code <> 0 then
        begin
          FreeMem(data);
          Close(t);
          Exit;
        end;
        flag := umf_noinfo;
      end;
      { Grow rather than refuse: a DBCS table indexes by the two-byte value and
        runs to 65535, and the 256 above is only the single-byte case. `>=`, and
        outside the branch above, for the two reasons in the unit header. }
      while charpos >= datasize do
      begin
        ReAllocMem(data, SizeOf(tunicodecharmapping) * datasize * 2);
        inititems(punicodecharmapping(PByte(data) + SizeOf(tunicodecharmapping) * datasize),
                  datasize);
        datasize := datasize * 2;
      end;
      data[charpos].flag := flag;
      data[charpos].unicode := tunicodechar(unicodevalue);
      data[charpos].reserved := 0;
      if charpos > lastchar then lastchar := charpos;
    end;
  end;
  Close(t);
  { A file with no mapping line at all yields nil rather than an empty map, so a
    caller cannot register something that answers 0 for every character. }
  if lastchar < 0 then
  begin
    FreeMem(data);
    Exit;
  end;
  New(p);
  p^.lastchar := lastchar;
  p^.cpname := cpname;
  p^.cp := cp;
  p^.internalmap := False;
  p^.next := nil;
  p^.map := data;
  p^.reversemap := buildreversemap(p^.map, p^.lastchar + 1, rlen);
  p^.reversemaplength := rlen;
  Result := p;
end;

function loadbinaryunicodemapping(const AData: Pointer; const ADataLength: Integer): punicodemap; overload;
var
  dataPointer: PByte;
  readedLength: LongInt;
  h: TSerializedMapHeader;
  r: punicodemap;

  function ReadBuffer(ADest: Pointer; ALength: LongInt): Boolean;
  begin
    ReadBuffer := (readedLength + ALength) <= ADataLength;
    if not ReadBuffer then Exit;
    Move(dataPointer^, ADest^, ALength);
    Inc(dataPointer, ALength);
    readedLength := readedLength + ALength;
  end;

begin
  Result := nil;
  readedLength := 0;
  dataPointer := AData;
  if not ReadBuffer(@h, SizeOf(h)) then Exit;
  New(r);
  FillChar(r^, SizeOf(tunicodemap), 0);
  r^.cpname := h.cpName;
  r^.cp := h.cp;
  r^.map := AllocMem(h.mapLength);
  if not ReadBuffer(r^.map, h.mapLength) then
  begin
    freemapping(r);
    Exit;
  end;
  r^.lastchar := h.lastChar;
  r^.reversemap := AllocMem(h.reverseMapLength);
  if not ReadBuffer(r^.reversemap, h.reverseMapLength) then
  begin
    freemapping(r);
    Exit;
  end;
  r^.reversemaplength := h.reverseMapLength div SizeOf(treversecharmapping);
  Result := r;
end;

function loadbinaryunicodemapping(const filename: ShortString): punicodemap; overload;
const
  BLOCK_SIZE = 16 * 1024;
var
  f: File of Byte;
  locSize, locReaded, c, locBlockSize: LongInt;
  locBuffer: PByte;
begin
  Result := nil;
  if filename = '' then Exit;
  Assign(f, filename);
  {$push}{$I-}
  Reset(f);
  {$pop}
  if IOResult <> 0 then Exit;
  locSize := FileSize(f);
  { Refuse a file that cannot even hold the header BEFORE allocating, so a
    truncated or empty file is a nil answer and not a zero-length GetMem. }
  if locSize < SizeOf(TSerializedMapHeader) then
  begin
    Close(f);
    Exit;
  end;
  GetMem(locBuffer, locSize);
  locBlockSize := BLOCK_SIZE;
  locReaded := 0;
  c := 0;
  while locReaded < locSize do
  begin
    if locBlockSize > (locSize - locReaded) then locBlockSize := locSize - locReaded;
    {$push}{$I-}
    BlockRead(f, locBuffer[locReaded], locBlockSize, c);
    {$pop}
    { c <= 0 as well as an IO error: a read that returns nothing would spin here
      forever, which is what a map file on a failing filesystem produces. }
    if (IOResult <> 0) or (c <= 0) then
    begin
      FreeMem(locBuffer);
      Close(f);
      Exit;
    end;
    locReaded := locReaded + c;
  end;
  Result := loadbinaryunicodemapping(locBuffer, locSize);
  FreeMem(locBuffer);
  Close(f);
end;

{ The byte order is part of the FILE NAME because the format is a straight image
  of the in-memory records, so a map written on one endianness is not readable
  on the other and must not be found by accident.

  fpc picks the suffix from {$IFDEF ENDIAN_LITTLE}; pxx defines neither
  ENDIAN_LITTLE nor ENDIAN_BIG (measured 2026-09-16), and guessing 'le' in an
  {$ELSE} would silently name the wrong file on a big-endian target. Asking the
  machine costs a word of stack and is exact on every target we have or will
  have. }
function EndianSuffix: ShortString;
var
  w: Word;
  b: PByte;
begin
  w := 1;
  b := @w;
  if b^ = 1 then Result := 'le' else Result := 'be';
end;

function loadbinaryunicodemapping(const directory, cpname: ShortString): punicodemap; overload;
var
  fileName: ShortString;
begin
  fileName := directory;
  if fileName <> '' then
    if fileName[Length(fileName)] <> DirectorySeparator then
      fileName := fileName + DirectorySeparator;
  fileName := fileName + cpname + '_' + EndianSuffix + BINARY_MAPPING_FILE_EXT;
  Result := loadbinaryunicodemapping(fileName);
end;

procedure registermapping(p: punicodemap);
begin
  p^.next := mappings;
  mappings := p;
end;

function registerbinarymapping(const directory, cpname: ShortString): Boolean;
var
  p: punicodemap;
begin
  Result := False;
  p := loadbinaryunicodemapping(directory, cpname);
  if p = nil then Exit;
  registermapping(p);
  Result := True;
end;

function getmap(const s: ShortString): punicodemap; overload;
var
  hp: punicodemap;
begin
  { The cached pointer is re-validated against its own cpname, not trusted on
    the strength of the key alone -- the registry is a mutable list and a stale
    pointer would otherwise answer for a map that has been replaced. }
  if (strmapcache = s) and (strmapcachep <> nil) and (strmapcachep^.cpname = s) then
    Exit(strmapcachep);
  hp := mappings;
  while hp <> nil do
  begin
    if hp^.cpname = s then
    begin
      strmapcache := s;
      strmapcachep := hp;
      Exit(hp);
    end;
    hp := hp^.next;
  end;
  Result := nil;
end;

function getmap(cp: Word): punicodemap; overload;
var
  hp: punicodemap;
begin
  if (intmapcache = cp) and (intmapcachep <> nil) and (intmapcachep^.cp = cp) then
    Exit(intmapcachep);
  hp := mappings;
  while hp <> nil do
  begin
    if hp^.cp = cp then
    begin
      intmapcache := cp;
      intmapcachep := hp;
      Exit(hp);
    end;
    hp := hp^.next;
  end;
  Result := nil;
end;

function mappingavailable(const s: ShortString): Boolean; overload;
begin
  Result := getmap(s) <> nil;
end;

function mappingavailable(cp: Word): Boolean; overload;
begin
  Result := getmap(cp) <> nil;
end;

function getunicode(c: AnsiChar; p: punicodemap): tunicodechar; overload;
begin
  if Ord(c) <= p^.lastchar then Result := p^.map[Ord(c)].unicode else Result := 0;
end;

{ ADest = nil asks for the LENGTH only, which is how a caller sizes its buffer
  before converting -- and the two passes must agree, so both walk lead bytes
  the same way. }
function getunicode(AAnsiStr: PAnsiChar; AAnsiLen: LongInt; AMap: punicodemap;
                    ADest: tunicodestring): LongInt; overload;
var
  i, c, k, destLen: LongInt;
  ps: PAnsiChar;
  pd: tunicodestring;
begin
  if (AAnsiStr = nil) or (AAnsiLen <= 0) then Exit(0);
  ps := AAnsiStr;
  c := AAnsiLen - 1;
  if ADest = nil then
  begin
    destLen := 0;
    i := 0;
    while i <= c do
    begin
      if Ord(ps^) <= AMap^.lastchar then
        if (AMap^.map[Ord(ps^)].flag = umf_leadbyte) and (i < c) then
        begin
          Inc(ps);
          i := i + 1;
        end;
      i := i + 1;
      Inc(ps);
      destLen := destLen + 1;
    end;
    Exit(destLen);
  end;
  pd := ADest;
  i := 0;
  while i <= c do
  begin
    if Ord(ps^) <= AMap^.lastchar then
    begin
      if AMap^.map[Ord(ps^)].flag = umf_leadbyte then
      begin
        { A lead byte with no trailer -- the string ends mid-character -- is one
          UNKNOW_CHAR_W, not a read past the end. }
        if i < c then
        begin
          k := Ord(ps^) * 256;
          Inc(ps);
          i := i + 1;
          k := k + Ord(ps^);
          if k <= AMap^.lastchar then pd^ := AMap^.map[k].unicode
          else pd^ := UNKNOW_CHAR_W;
        end
        else
          pd^ := UNKNOW_CHAR_W;
      end
      else
        pd^ := AMap^.map[Ord(ps^)].unicode;
    end
    else
      pd^ := UNKNOW_CHAR_W;
    i := i + 1;
    Inc(ps);
    Inc(pd);
  end;
  Result := (PtrUInt(pd) - PtrUInt(ADest)) div SizeOf(tunicodechar);
end;

function getascii(c: tunicodechar; p: punicodemap): ShortString; overload;
var
  rm: preversecharmapping;
begin
  rm := find(c, p);
  if rm <> nil then
  begin
    if rm^.char2 = 0 then
    begin
      SetLength(Result, 1);
      Byte(Result[1]) := rm^.char1;
    end
    else
    begin
      SetLength(Result, 2);
      Byte(Result[1]) := rm^.char1;
      Byte(Result[2]) := rm^.char2;
    end;
  end
  else
    Result := UNKNOW_CHAR_A;
end;

function getascii(c: tunicodechar; p: punicodemap; ABuffer: PAnsiChar;
                  ABufferLen: LongInt): LongInt; overload;
var
  rm: preversecharmapping;
begin
  if (ABuffer <> nil) and (ABufferLen <= 0) then Exit(-1);
  rm := find(c, p);
  if rm <> nil then
  begin
    if ABuffer = nil then
    begin
      if rm^.char2 = 0 then Result := 1 else Result := 2;
    end
    else if rm^.char2 = 0 then
    begin
      Byte(ABuffer^) := rm^.char1;
      Result := 1;
    end
    else if ABufferLen < 2 then
      Result := -1
    else
    begin
      Byte(ABuffer^) := rm^.char1;
      Byte((ABuffer + 1)^) := rm^.char2;
      Result := 2;
    end;
  end
  else
  begin
    { DELIBERATE DIVERGENCE, AND THE ONLY ONE IN THIS ROUTINE. fpc writes
      ABuffer^ here without checking it, so `getascii(c, p, nil, 0)` -- its own
      documented length query, which the arm above honours -- SEGVs whenever the
      character is not representable in the codepage. Measured 2026-09-16: fpc
      3.2.2 dies with runtime error 216 on exactly that call. nil is an intended
      input on this parameter, so honouring it in both arms completes fpc's
      contract rather than departing from it. }
    if ABuffer <> nil then ABuffer^ := UNKNOW_CHAR_A;
    Result := 1;
  end;
end;

initialization
  mappings := nil;
  strmapcache := '';
  strmapcachep := nil;
  intmapcache := 0;
  intmapcachep := nil;

finalization
  { internalmap marks a map whose tables are STATIC DATA in a generated unit,
    not heap blocks -- freeing those would be a wild free, which is why the flag
    exists and why it is checked here rather than at registration. }
  while mappings <> nil do
  begin
    finhp := mappings^.next;
    if not mappings^.internalmap then
    begin
      FreeMem(mappings^.map);
      FreeMem(mappings^.reversemap);
      Dispose(mappings);
    end;
    mappings := finhp;
  end;

end.
