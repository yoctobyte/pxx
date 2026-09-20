{ SPDX-License-Identifier: Zlib }
unit mimic_wave;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `wave` module — uncompressed RIFF/WAVE (PCM) read and write.

  `import wave` RESOLVES here through the NilPy import resolver's `mimic_`
  fallback, so no file in the tree carries the stdlib's name and `--no-shims`
  can turn the substitution into an error. See devdocs/dev/python-compat-tiers.md.

  WHY THIS EXISTS. TSP's `tsp/voice.py:29` imports `wave` **unguarded** — there
  is no `try:`/`except ImportError:` for the compiler to fold away, unlike the
  `ctypes` imports in `tsp/platform/`. So it is the one wall on TSP's board that
  no application edit and no marker module can route around, and it is small.
  Board: devdocs/dev/tsp-compile-wall-inventory-2026-09-20.md, row 2.

  THE SUBSET, stated plainly, so nobody discovers it at run time.
  Present: `wave.open(path, mode)` for the four CPython mode spellings, used
  directly or as a context manager; `getnchannels`, `getsampwidth`,
  `getframerate`, `getnframes`, `getcomptype`, `getcompname`, `getparams`;
  `setnchannels`, `setsampwidth`, `setframerate`, `setnframes`, `setcomptype`,
  `setparams`; `readframes`, `writeframes`, `writeframesraw`, `rewind`, `tell`,
  `setpos`, `close`. Uncompressed PCM only — `comptype` is always `'NONE'`, which
  is what CPython's own `wave` is in practice: it refuses everything else too.
  Absent: `getmarkers`/`getmark`/`setmark` (CPython's are stubs that return None
  or raise), reading from an already-open file object (the argument is a PATH),
  and iteration. A caller reaching past this gets an unknown-method error rather
  than a silently wrong buffer.

  ONE CLASS FOR BOTH DIRECTIONS, and that is forced rather than chosen.
  CPython has `Wave_read` and `Wave_write`, and `wave.open()` returns whichever
  the mode calls for. A Pascal function has ONE return type, so two classes
  would need `open` to return a common base — and then every method a caller
  uses has to be declared on that base anyway, which is this class. The two
  CPython names are declared below as ALIASES so `wave.Wave_read` resolves; what
  they do not give you is two distinct types, so `type(w).__name__` answers
  `TWaveFile` and an `isinstance` between them cannot discriminate. Using a
  read method on a write handle raises, which is the behaviour that actually
  matters and is CPython's.

  THE BYTE ORDER IS WRITTEN OUT EXPLICITLY, NOT CAST. RIFF is little-endian by
  specification, and this compiler cross-compiles to big-endian targets — so
  every header field is assembled and read byte by byte. A record cast would be
  correct on x86-64 and silently wrong on one of the cross targets, which is
  exactly the class CLAUDE.md records as structurally invisible to a dev loop
  that only ever runs on the 64-bit host. The FRAME data is not touched: it is
  host order in CPython too, and `array.array` reinterprets it the same way at
  both ends (lib/rtl/mimic_array.pas, which is what TSP's `scaled_copy` uses).

  WRITING BUFFERS IN MEMORY AND FLUSHES AT close(). CPython streams and patches
  the two length fields by seeking back. Buffering is simpler, has no seek, and
  cannot leave a half-written header behind if the program dies — and the
  clips this exists for are seconds long. The cost is real and is stated rather
  than hidden: a caller writing a multi-gigabyte file holds it all in RAM. If
  that ever matters, stream and patch; the format layout is all in WriteHeader. }

interface

uses pylib, sysutils;

type
  { `wave.Error`. Spelled to match so `except wave.Error:` in an application
    binds here rather than sliding past to a bare `except`. }
  Error = class(Exception) end;

  { What `getparams()` returns and `setparams()` takes.

    CPython's is a NAMED TUPLE, so both `p.nchannels` and `p[0]` work there and
    only the first works here. That is the whole divergence and it is in the
    accepting direction for the idiom real code uses — read params off one file,
    hand them to another — which is exactly TSP's `scaled_copy`. Indexing or
    unpacking one raises rather than answering something plausible. }
  TWaveParams = class
  public
    nchannels: Integer;
    sampwidth: Integer;
    framerate: Integer;
    nframes: Integer;
    comptype: AnsiString;
    compname: AnsiString;
    constructor Create(nc, sw, fr, nf: Integer;
                       const ct, cn: AnsiString);
    function __str__: AnsiString;
  end;

  TWaveFile = class
  public
    FWriting: Boolean;
    FPath: AnsiString;
    FClosed: Boolean;

    FNChannels: Integer;
    FSampWidth: Integer;      { BYTES per sample, as CPython's is }
    FFrameRate: Integer;
    FNFrames: Integer;        { declared count; read mode derives it }

    { read state — the whole `data` chunk, and a byte cursor into it }
    FData: PByte;
    FDataLen: Integer;
    FPos: Integer;

    { write state — accumulated frames }
    FOut: PByte;
    FOutLen: Integer;
    FOutCap: Integer;

    constructor Create(const path: AnsiString; writing: Boolean);
    destructor Destroy; override;
    { Chunk walk, split out of the constructor only so the buffer it reads from
      can be freed in one place. Not part of the Python surface. }
    procedure ParseHeader(whole: PByte; wlen: Integer);

    function getnchannels: Integer;
    function getsampwidth: Integer;
    function getframerate: Integer;
    function getnframes: Integer;
    function getcomptype: AnsiString;
    function getcompname: AnsiString;
    function getparams: TWaveParams;

    procedure setnchannels(n: Integer);
    procedure setsampwidth(n: Integer);
    procedure setframerate(n: Integer);
    procedure setnframes(n: Integer);
    procedure setcomptype(const ct: AnsiString; const cn: AnsiString);
    procedure setparams(p: TWaveParams);

    function readframes(n: Integer): TPyBytes;
    procedure writeframes(b: TPyBytes);
    { CPython distinguishes these only by whether the header length is updated
      as it goes; buffered, they are the same operation. Both are here because
      real code writes either. }
    procedure writeframesraw(b: TPyBytes);
    procedure rewind;
    function tell: Integer;
    procedure setpos(pos: Integer);
    procedure close;

    function __enter__: TWaveFile;
    procedure __exit__(const a: Variant; const b: Variant; const c: Variant);
    function __str__: AnsiString;
  end;

  { The two CPython class names. One type behind both — see the unit comment. }
  Wave_read = TWaveFile;
  Wave_write = TWaveFile;

{ `wave.open(path, mode)`. CPython's default mode is `'rb'`, and it accepts
  `'r'`/`'rb'`/`'w'`/`'wb'`; anything else is an Error there and here. }
function open(const path: AnsiString): TWaveFile; overload;
function open(const path: AnsiString; const mode: AnsiString): TWaveFile; overload;
{ CPython keeps `wave.openfp` as a deprecated alias. One line, and it means a
  program that still calls it compiles rather than walling on a name. }
function openfp(const path: AnsiString; const mode: AnsiString): TWaveFile;

implementation

{ ---- little-endian field access ---------------------------------------------

  Byte by byte in both directions, for the cross-target reason in the unit
  comment. Kept as four tiny routines rather than inline arithmetic so there is
  ONE spelling of each conversion: the sibling-spelling failure this tree keeps
  rediscovering is a second copy that never got the fix. }

function RdU16(p: PByte; ofs: Integer): Integer;
begin
  RdU16 := Integer(p[ofs]) or (Integer(p[ofs + 1]) shl 8);
end;

function RdU32(p: PByte; ofs: Integer): LongInt;
begin
  RdU32 := LongInt(p[ofs]) or (LongInt(p[ofs + 1]) shl 8) or
           (LongInt(p[ofs + 2]) shl 16) or (LongInt(p[ofs + 3]) shl 24);
end;

procedure WrU16(p: PByte; ofs: Integer; v: LongInt);
begin
  p[ofs]     := Byte(v and $FF);
  p[ofs + 1] := Byte((v shr 8) and $FF);
end;

procedure WrU32(p: PByte; ofs: Integer; v: LongInt);
begin
  p[ofs]     := Byte(v and $FF);
  p[ofs + 1] := Byte((v shr 8) and $FF);
  p[ofs + 2] := Byte((v shr 16) and $FF);
  p[ofs + 3] := Byte((v shr 24) and $FF);
end;

function TagAt(p: PByte; ofs: Integer): AnsiString;
var i: Integer;
begin
  TagAt := '';
  for i := 0 to 3 do TagAt := TagAt + Chr(p[ofs + i]);
end;

procedure WrTag(p: PByte; ofs: Integer; const t: AnsiString);
var i: Integer;
begin
  for i := 0 to 3 do p[ofs + i] := Byte(Ord(t[i + 1]));
end;

{ ---- TWaveParams ------------------------------------------------------------ }

constructor TWaveParams.Create(nc, sw, fr, nf: Integer;
                               const ct, cn: AnsiString);
begin
  nchannels := nc;
  sampwidth := sw;
  framerate := fr;
  nframes   := nf;
  comptype  := ct;
  compname  := cn;
end;

function TWaveParams.__str__: AnsiString;
begin
  { CPython renders the namedtuple; matching the shape means a print() in a
    debugging session reads the same in both runtimes. }
  __str__ := '_wave_params(nchannels=' + IntToStr(nchannels) +
             ', sampwidth=' + IntToStr(sampwidth) +
             ', framerate=' + IntToStr(framerate) +
             ', nframes=' + IntToStr(nframes) +
             ', comptype=''' + comptype + ''', compname=''' + compname + ''')';
end;

{ ---- reading ---------------------------------------------------------------- }

{ The whole file, or nil. Loud about a file it cannot open, because a silent
  empty buffer would decode as a zero-length clip and play as nothing. }
function ReadWholeFile(const path: AnsiString; var len: Integer): PByte;
const BLOCK = 64 * 1024;
var
  f: File of Byte;
  total, got, want, done: LongInt;
  buf: PByte;
begin
  ReadWholeFile := nil;
  len := 0;
  if path = '' then Exit;
  Assign(f, path);
  {$push}{$I-}
  Reset(f);
  {$pop}
  if IOResult <> 0 then Exit;
  total := FileSize(f);
  { 44 is the smallest possible canonical header (RIFF + fmt + data). Refuse
    BEFORE allocating, so a truncated or empty file is a nil answer and never a
    zero-length GetMem. }
  if total < 44 then
  begin
    CloseFile(f);
    Exit;
  end;
  GetMem(buf, total);
  done := 0;
  while done < total do
  begin
    want := BLOCK;
    if want > (total - done) then want := total - done;
    got := 0;
    {$push}{$I-}
    BlockRead(f, buf[done], want, got);
    {$pop}
    { got <= 0 as well as an IO error: a read returning nothing would spin here
      forever, which is what a file on a failing filesystem produces. }
    if (IOResult <> 0) or (got <= 0) then
    begin
      FreeMem(buf);
      CloseFile(f);
      Exit;
    end;
    done := done + got;
  end;
  CloseFile(f);
  len := total;
  ReadWholeFile := buf;
end;

constructor TWaveFile.Create(const path: AnsiString; writing: Boolean);
var
  whole: PByte;
  wlen: Integer;
begin
  FPath := path;
  FWriting := writing;
  FClosed := False;
  FNChannels := 0;
  FSampWidth := 0;
  FFrameRate := 0;
  FNFrames := 0;
  FData := nil;
  FDataLen := 0;
  FPos := 0;
  FOut := nil;
  FOutLen := 0;
  FOutCap := 0;
  if writing then Exit;

  wlen := 0;
  whole := ReadWholeFile(path, wlen);
  if whole = nil then
    raise Error.Create('wave: cannot read ' + path);
  try
    ParseHeader(whole, wlen);
  finally
    FreeMem(whole);
  end;
end;

{ Walk the chunk list for `fmt ` and `data`. Skipping unknown chunks is the
  whole reason this is a loop and not a fixed offset: a real WAV from a real
  encoder carries LIST/INFO/fact chunks before the data, and a 44-byte
  assumption reads those as samples. }
procedure TWaveFile.ParseHeader(whole: PByte; wlen: Integer);
var
  ofs, csize, fmtTag: Integer;
  tag: AnsiString;
  sawFmt, sawData: Boolean;
begin
  if (TagAt(whole, 0) <> 'RIFF') or (TagAt(whole, 8) <> 'WAVE') then
    raise Error.Create('wave: file does not start with RIFF id: ' + FPath);
  sawFmt := False;
  sawData := False;
  ofs := 12;
  while (ofs + 8) <= wlen do
  begin
    tag := TagAt(whole, ofs);
    csize := RdU32(whole, ofs + 4);
    { A chunk claiming more than the file holds is a truncated file, not a
      reason to read past the buffer. }
    if csize < 0 then Break;
    if (ofs + 8 + csize) > wlen then csize := wlen - ofs - 8;
    if tag = 'fmt ' then
    begin
      if csize < 16 then
        raise Error.Create('wave: fmt chunk is too short in ' + FPath);
      fmtTag := RdU16(whole, ofs + 8);
      { 1 = PCM, 0xFFFE = WAVE_FORMAT_EXTENSIBLE, whose first 16 fmt bytes are
        laid out identically and whose subformat is PCM in every file that a
        16-bit recorder produces. CPython's wave refuses EXTENSIBLE outright;
        accepting it is upward compatibility, not a divergence that can make a
        correct program wrong. }
      if (fmtTag <> 1) and (fmtTag <> $FFFE) then
        raise Error.Create('wave: unknown format tag ' + IntToStr(fmtTag) +
                           ' (only uncompressed PCM is supported)');
      FNChannels := RdU16(whole, ofs + 10);
      FFrameRate := RdU32(whole, ofs + 12);
      FSampWidth := (RdU16(whole, ofs + 22) + 7) div 8;
      sawFmt := True;
    end
    else if tag = 'data' then
    begin
      FDataLen := csize;
      if csize > 0 then
      begin
        GetMem(FData, csize);
        Move(whole[ofs + 8], FData^, csize);
      end;
      sawData := True;
    end;
    { Chunks are padded to an even length and the pad byte is NOT counted in
      the size field. Getting this wrong shifts every later chunk by one and
      is the classic way a WAV reader reports garbage on a perfectly good
      file. }
    ofs := ofs + 8 + csize;
    if (csize and 1) <> 0 then Inc(ofs);
  end;
  if not sawFmt then
    raise Error.Create('wave: no fmt chunk in ' + FPath);
  if not sawData then
    raise Error.Create('wave: no data chunk in ' + FPath);
  if (FNChannels <= 0) or (FSampWidth <= 0) then
    raise Error.Create('wave: degenerate fmt chunk in ' + FPath);
  FNFrames := FDataLen div (FNChannels * FSampWidth);
  FPos := 0;
end;

destructor TWaveFile.Destroy;
begin
  if FData <> nil then begin FreeMem(FData); FData := nil; end;
  if FOut <> nil then begin FreeMem(FOut); FOut := nil; end;
  inherited Destroy;
end;

{ ---- accessors -------------------------------------------------------------- }

function TWaveFile.getnchannels: Integer; begin getnchannels := FNChannels; end;
function TWaveFile.getsampwidth: Integer; begin getsampwidth := FSampWidth; end;
function TWaveFile.getframerate: Integer; begin getframerate := FFrameRate; end;
function TWaveFile.getcomptype: AnsiString; begin getcomptype := 'NONE'; end;
function TWaveFile.getcompname: AnsiString; begin getcompname := 'not compressed'; end;

function TWaveFile.getnframes: Integer;
begin
  { On a WRITE handle CPython answers what has actually been written so far,
    not what setnframes was told — and `scaled_copy`-shaped code relies on
    neither, so the honest answer is the written one. }
  if FWriting then
  begin
    if (FNChannels > 0) and (FSampWidth > 0) then
      getnframes := FOutLen div (FNChannels * FSampWidth)
    else
      getnframes := 0;
  end
  else
    getnframes := FNFrames;
end;

function TWaveFile.getparams: TWaveParams;
begin
  getparams := TWaveParams.Create(FNChannels, FSampWidth, FFrameRate,
                                  getnframes, 'NONE', 'not compressed');
end;

procedure TWaveFile.setnchannels(n: Integer);
begin
  if n <= 0 then raise Error.Create('wave: bad # of channels');
  FNChannels := n;
end;

procedure TWaveFile.setsampwidth(n: Integer);
begin
  if (n < 1) or (n > 4) then raise Error.Create('wave: bad sample width');
  FSampWidth := n;
end;

procedure TWaveFile.setframerate(n: Integer);
begin
  if n <= 0 then raise Error.Create('wave: bad frame rate');
  FFrameRate := n;
end;

procedure TWaveFile.setnframes(n: Integer);
begin
  { Buffered, so this is advisory: close() writes the count it actually has.
    CPython's is advisory in the same way — it patches the real count on close
    too. Recorded because a caller CAN read it back and see a different number
    than it set, and that is correct in both runtimes. }
  FNFrames := n;
end;

procedure TWaveFile.setcomptype(const ct: AnsiString; const cn: AnsiString);
begin
  if (ct <> 'NONE') and (ct <> '') then
    raise Error.Create('wave: unsupported compression type ' + ct);
end;

procedure TWaveFile.setparams(p: TWaveParams);
begin
  if p = nil then raise Error.Create('wave: setparams(nil)');
  setnchannels(p.nchannels);
  setsampwidth(p.sampwidth);
  setframerate(p.framerate);
  setcomptype(p.comptype, p.compname);
  setnframes(p.nframes);
end;

{ ---- frames -----------------------------------------------------------------

  THE COPIES HERE GO BYTE BY BYTE THROUGH TPyBytes.at/.put RATHER THAN A BULK
  Move, AND THAT IS A DECISION RATHER THAN AN OVERSIGHT. A `Move` through
  `TPyBytes.FData` would be a few lines and would look free. The clips this unit
  exists for are ~100 KB (a voice line at 16-bit mono), so the difference is
  under a millisecond and nobody can measure it; the byte loop makes no
  assumption about TPyBytes' internal layout, where a Move does. Revisit if a
  caller ever brings a large file -- the unit comment names buffering as the
  standing cost and this is the other half of it. }

function TWaveFile.readframes(n: Integer): TPyBytes;
var
  fsz, want, i: Integer;
  b: TPyBytes;
begin
  if FWriting then raise Error.Create('wave: readframes on a write handle');
  if FClosed then raise Error.Create('wave: readframes on a closed file');
  fsz := FNChannels * FSampWidth;
  if (n <= 0) or (fsz <= 0) then
  begin
    readframes := TPyBytes.Create(0);
    Exit;
  end;
  want := n * fsz;
  if want > (FDataLen - FPos) then want := FDataLen - FPos;
  if want < 0 then want := 0;
  b := TPyBytes.Create(want);
  for i := 0 to want - 1 do
    b.put(i, Integer(FData[FPos + i]));
  FPos := FPos + want;
  readframes := b;
end;

procedure TWaveFile.writeframesraw(b: TPyBytes);
var
  need, newcap, i: Integer;
  grown: PByte;
begin
  if not FWriting then raise Error.Create('wave: writeframes on a read handle');
  if FClosed then raise Error.Create('wave: writeframes on a closed file');
  if b = nil then Exit;
  if b.FLen <= 0 then Exit;
  need := FOutLen + b.FLen;
  if need > FOutCap then
  begin
    { Double, so appending frame by frame is linear rather than quadratic —
      a caller that writes one frame at a time is ordinary Python. }
    newcap := FOutCap;
    if newcap < 4096 then newcap := 4096;
    while newcap < need do newcap := newcap * 2;
    GetMem(grown, newcap);
    if FOutLen > 0 then Move(FOut^, grown^, FOutLen);
    if FOut <> nil then FreeMem(FOut);
    FOut := grown;
    FOutCap := newcap;
  end;
  for i := 0 to b.FLen - 1 do
    FOut[FOutLen + i] := Byte(b.at(i));
  FOutLen := need;
end;

procedure TWaveFile.writeframes(b: TPyBytes);
begin
  writeframesraw(b);
end;

procedure TWaveFile.rewind;
begin
  if FWriting then raise Error.Create('wave: rewind on a write handle');
  FPos := 0;
end;

function TWaveFile.tell: Integer;
begin
  { FRAMES, not bytes — CPython's unit, and the one a caller passes back to
    setpos. Returning bytes here would be a plausible wrong number that only
    diverges once sampwidth is not 1. }
  if (FNChannels > 0) and (FSampWidth > 0) then
  begin
    if FWriting then tell := FOutLen div (FNChannels * FSampWidth)
                else tell := FPos div (FNChannels * FSampWidth);
  end
  else
    tell := 0;
end;

procedure TWaveFile.setpos(pos: Integer);
var fsz: Integer;
begin
  if FWriting then raise Error.Create('wave: setpos on a write handle');
  fsz := FNChannels * FSampWidth;
  if (pos < 0) or (fsz <= 0) or ((pos * fsz) > FDataLen) then
    raise Error.Create('wave: position out of range');
  FPos := pos * fsz;
end;

{ ---- writing out ------------------------------------------------------------ }

procedure TWaveFile.close;
{ HDRSIZE, not HDR, because Pascal is case-insensitive and `hdr` below is the
  buffer itself. Every file-close in here is CloseFile for the same family of
  reason: this METHOD is called `close`, so a bare `Close(f)` resolves to it
  and not to System's. Both were caught at compile time; both are the kind of
  collision that only exists because the Python-facing name is forced. }
const HDRSIZE = 44;
var
  f: File of Byte;
  hdr: PByte;
  byteRate, blockAlign: LongInt;
  padded: Boolean;
  zero: Byte;
begin
  if FClosed then Exit;
  FClosed := True;
  if not FWriting then
  begin
    if FData <> nil then begin FreeMem(FData); FData := nil; end;
    FDataLen := 0;
    Exit;
  end;
  if (FNChannels <= 0) or (FSampWidth <= 0) or (FFrameRate <= 0) then
    raise Error.Create('wave: sampwidth, nchannels and framerate must be ' +
                       'set before closing ' + FPath);
  blockAlign := FNChannels * FSampWidth;
  byteRate := FFrameRate * blockAlign;
  { An odd data length gets a pad byte, and the pad is not counted in the data
    chunk's own size — but IS counted in the RIFF size. Both readers we care
    about tolerate the absence; writing it is what the spec says and costs a
    byte. }
  padded := (FOutLen and 1) <> 0;

  GetMem(hdr, HDRSIZE);
  WrTag(hdr, 0, 'RIFF');
  WrU32(hdr, 4, 36 + FOutLen + Ord(padded));
  WrTag(hdr, 8, 'WAVE');
  WrTag(hdr, 12, 'fmt ');
  WrU32(hdr, 16, 16);              { PCM fmt chunk body size }
  WrU16(hdr, 20, 1);               { WAVE_FORMAT_PCM }
  WrU16(hdr, 22, FNChannels);
  WrU32(hdr, 24, FFrameRate);
  WrU32(hdr, 28, byteRate);
  WrU16(hdr, 32, blockAlign);
  WrU16(hdr, 34, FSampWidth * 8);
  WrTag(hdr, 36, 'data');
  WrU32(hdr, 40, FOutLen);

  Assign(f, FPath);
  {$push}{$I-}
  Rewrite(f);
  {$pop}
  if IOResult <> 0 then
  begin
    FreeMem(hdr);
    raise Error.Create('wave: cannot write ' + FPath);
  end;
  {$push}{$I-}
  BlockWrite(f, hdr^, HDRSIZE);
  if FOutLen > 0 then BlockWrite(f, FOut^, FOutLen);
  if padded then
  begin
    zero := 0;
    BlockWrite(f, zero, 1);
  end;
  {$pop}
  FreeMem(hdr);
  if IOResult <> 0 then
  begin
    CloseFile(f);
    raise Error.Create('wave: write failed on ' + FPath);
  end;
  CloseFile(f);
end;

{ ---- context manager --------------------------------------------------------

  Both halves, because `with wave.open(...) as w:` is how every caller in the
  corpus opens one and a manager missing __enter__ binds the EXPRESSION while
  __exit__ never runs — silently, per bug-nilpy-with-statement-skips-enter-and-
  exit. Here that would mean a written file with no header on disk, so the
  protocol is load-bearing rather than decorative. }

function TWaveFile.__enter__: TWaveFile;
begin
  __enter__ := Self;
end;

procedure TWaveFile.__exit__(const a: Variant; const b: Variant; const c: Variant);
begin
  close;
end;

function TWaveFile.__str__: AnsiString;
begin
  if FWriting then
    __str__ := '<wave.Wave_write ' + FPath + '>'
  else
    __str__ := '<wave.Wave_read ' + FPath + '>';
end;

{ ---- module level ------------------------------------------------------------ }

function open(const path: AnsiString; const mode: AnsiString): TWaveFile;
begin
  if (mode = 'r') or (mode = 'rb') then
    open := TWaveFile.Create(path, False)
  else if (mode = 'w') or (mode = 'wb') then
    open := TWaveFile.Create(path, True)
  else
    raise Error.Create('wave: mode must be ''rb'' or ''wb'', got ''' + mode + '''');
end;

function open(const path: AnsiString): TWaveFile;
begin
  open := open(path, 'rb');
end;

function openfp(const path: AnsiString; const mode: AnsiString): TWaveFile;
begin
  openfp := open(path, mode);
end;

end.
