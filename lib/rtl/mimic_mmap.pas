{ SPDX-License-Identifier: Zlib }
unit mimic_mmap;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `mmap` module — the READ-ONLY subset, as a private snapshot.

  `import mmap` resolves here through the NilPy import resolver's `mimic_`
  fallback. The subset is what That Space Program's SPK ephemeris reader
  (tsp/ephem/spk.py) does with it, and nothing beyond:

      buf = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
      len(buf); bytes(buf[a:b]); struct.unpack_from(fmt, buf, off); buf.close()

  ## A SNAPSHOT, NOT A VIEW — and why that is the same answer for this subset

  The file's bytes are READ into memory at construction instead of mapped: the
  PAL has anonymous mappings only, on every target, and a file mapping would be
  a new PAL entry on each backend for a program that only reads. For
  ACCESS_READ and ACCESS_COPY the two are indistinguishable to a program that
  does not change the file underneath its own mapping: READ cannot write
  through, and COPY is by definition a private copy. What a snapshot costs is
  residency (the whole length is read up front, where a mapping pages in on
  demand) — measured by nobody yet, and a 32 MB ephemeris is the size in play.

  ACCESS_WRITE and ACCESS_DEFAULT are REFUSED, not approximated: both are
  shared, write-through mappings in CPython, and a snapshot would take the
  writes and never deliver them to the file. That is a silent wrong answer, so
  it is a loud error instead.

  ## `mmap` IS A TPyBytes

  So `len`, slicing, `bytes(m[a:b])`, indexing and `struct.unpack_from(fmt, m,
  off)` are the bytes paths that already exist, with no second implementation to
  drift from them. The one method of its own is `close`. Where CPython raises
  on a closed map, this one is an empty buffer — NilPy accepting what CPython
  rejects, which is the direction nilpy-semantics-divergences.md allows.

  NilPy lets a program write into a TPyBytes whatever its access mode; CPython
  raises TypeError on a write to an ACCESS_READ map. Same direction, same note. }

interface

uses pylib, sysutils, platform, platform_types;

const
  { CPython's values, so a program that prints or compares them agrees }
  ACCESS_DEFAULT = 0;
  ACCESS_READ    = 1;
  ACCESS_WRITE   = 2;
  ACCESS_COPY    = 3;

type
  mmap = class(TPyBytes)
  public
    closed: Boolean;
    { mmap(fileno, length, access=ACCESS_DEFAULT). `length` 0 maps the whole
      file, as in CPython. The file position is left where it was, which is
      what a real mapping does too. }
    constructor Create(fileno: Int64; length: Int64; access: Integer = ACCESS_DEFAULT);
    procedure close;
  end;

implementation

constructor mmap.Create(fileno: Int64; length: Int64; access: Integer = ACCESS_DEFAULT);
var info: TPalFileStat;
    size, got, r, pos: Int64;
    chunk: Integer;
    p: PByte;
begin
  inherited Create(0);
  closed := False;
  if (access <> ACCESS_READ) and (access <> ACCESS_COPY) then
    raise ValueError.Create('mmap: only ACCESS_READ and ACCESS_COPY are supported '
      + 'by this shim; the mapping is a private snapshot, so a write could not '
      + 'reach the file');
  if length < 0 then
    raise OverflowError.Create('memory mapped length must be positive');
  if PalFstat(Integer(fileno), info) <> 0 then
    raise OSError.Create('[Errno 9] Bad file descriptor');
  size := info.Size;
  if length = 0 then
  begin
    if size = 0 then raise ValueError.Create('cannot mmap an empty file');
    length := size;
  end
  else if length > size then
    raise ValueError.Create('mmap length is greater than file size');
  if length > High(Integer) - 1 then
    raise OverflowError.Create('mmap: a mapping over 2 GiB does not fit a bytes object here');

  { the inherited Create(0) set up the finaliser hook and a one-byte buffer;
    replace the buffer with one of the right size, NUL-terminated as every
    TPyBytes is }
  FreeMem(FData);
  GetMem(FData, length + 1);
  FLen := Integer(length);
  p := PByte(NativeInt(FData) + length);
  p^ := 0;

  pos := PalSeek(Integer(fileno), 0, 1);
  if PalSeek(Integer(fileno), 0, 0) < 0 then
    raise OSError.Create('mmap: cannot seek to the start of the file');
  got := 0;
  while got < length do
  begin
    if length - got > $40000000 then chunk := $40000000
    else chunk := Integer(length - got);
    r := PalRead(Integer(fileno), Pointer(NativeInt(FData) + got), chunk);
    if r <= 0 then
      raise OSError.Create('mmap: the file ended or failed after '
        + IntToStr(got) + ' of ' + IntToStr(length) + ' bytes');
    got := got + r;
  end;
  if pos >= 0 then PalSeek(Integer(fileno), pos, 0);
end;

procedure mmap.close;
var p: PByte;
begin
  if closed then Exit;
  closed := True;
  { give the memory back now (a closed 32 MB map should not wait for the last
    reference to go), and leave a valid empty buffer for the finaliser to free }
  FreeMem(FData);
  GetMem(FData, 1);
  p := PByte(FData);
  p^ := 0;
  FLen := 0;
end;

end.
