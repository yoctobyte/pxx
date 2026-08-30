unit mimic_reportlab_lib_utils;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ `from reportlab.lib.utils import ImageReader` — reportlab's wrapper around an
  image source, which a Canvas accepts wherever a filename would do.

  THE SUBSET: a filename. reportlab's ImageReader also takes a file object, a URL
  or a PIL image; here the backend embeds a file (pdfgen reads PNG/JPEG/BMP
  itself), so a non-path source fails loudly at drawImage rather than drawing
  nothing. A T1 name shim; see mimic_reportlab_pdfgen for the policy. }

interface

uses pylib, classes, sysutils;

type
  ImageReader = class
  public
    fileName: AnsiString;
    constructor Create(const source: AnsiString);
    { reportlab returns a (width, height) PAIR, which callers unpack:
        w, h = img.getSize()
      This used to be declared `: AnsiString` returning ''. That is not a
      narrowed feature, it is a wrong TYPE, and the difference matters: a
      narrowed feature fails at run time where the caller asked for it, whereas
      a wrong type fails at COMPILE time in the caller and takes the whole
      module down with it -- including modules that never call it on a path
      that runs. A stub may refuse to do the work; it may not lie about its
      shape. bug-b-imagereader-getsize-returns-a-string-where-reportlab-returns-a-pair }
    function getSize: TPyList;
    function __str__: AnsiString;
  end;

implementation

{ Two values in a TPyList — the same shape a NilPy tuple has, and the same
  spelling mimic_reportlab_lib_pagesizes uses for the pagesize pairs.
  INTEGERS here, unlike pagesizes: reportlab's ImageReader.getSize hands back
  PIL's `image.size`, which is a pair of ints, and a caller that prints one or
  passes it to something PIL-shaped would see `1024.0` where CPython shows
  `1024`. Arithmetic is unaffected either way -- Variant widens -- so this is
  fidelity at the boundary, not a correctness fix. }
function Pair(w, h: Integer): TPyList;
var l: TPyList;
begin
  l := TPyList.Create;
  l.append(w);
  l.append(h);
  Pair := l;
end;

{ ---- image header dimensions ----

  Read here rather than borrowed from the vendored pdfgen, deliberately.
  pdfgen exposes pdf_parse_image_header, which is exactly this function and
  would have been the obvious reuse -- but under pxx it returns byte-swapped
  garbage: an 8x4 PNG measures 134217728 x 67108864. pdfgen selects its
  byte-order at compile time, its `__has_include(<endian.h>)` probe is skipped
  because pxx's C preprocessor does not support __has_include, and its fallback
  test then compares two macros that endian.h would have defined -- both absent,
  so `0 == 0` is true and it concludes BIG endian on a little-endian host.
  See bug-c-has-include-unsupported-so-pdfgen-selects-big-endian.

  So these read the bytes directly, big-endian where the format says so, with
  no dependency on that path. They are the minimum that answers the question,
  not a general decoder: dimensions only, and any file we cannot measure is a
  loud refusal rather than a plausible number. }

function BE16(const b: array of Byte; i: Integer): LongWord;
begin
  BE16 := (LongWord(b[i]) shl 8) or LongWord(b[i + 1]);
end;

function BE32(const b: array of Byte; i: Integer): LongWord;
begin
  BE32 := (LongWord(b[i]) shl 24) or (LongWord(b[i + 1]) shl 16) or
          (LongWord(b[i + 2]) shl 8) or LongWord(b[i + 3]);
end;

function LE32(const b: array of Byte; i: Integer): LongWord;
begin
  LE32 := LongWord(b[i]) or (LongWord(b[i + 1]) shl 8) or
          (LongWord(b[i + 2]) shl 16) or (LongWord(b[i + 3]) shl 24);
end;

{ JPEG: walk the segment chain to the frame header. The dimensions live in the
  SOFn segment, whose position depends on what came before it, so this cannot be
  a fixed offset the way PNG and BMP can. }
function JpegSize(fs: TFileStream; var w, h: LongWord): Boolean;
var
  seg: array[0..8] of Byte;
  marker: Byte;
  segLen: LongWord;
  pos: Int64;
begin
  JpegSize := False;
  pos := 2;                                  { past SOI }
  while pos + 4 <= fs.Size do
  begin
    fs.Position := pos;
    if fs.Read(seg[0], 4) <> 4 then Exit;
    if seg[0] <> $FF then Exit;              { not a marker: chain is broken }
    marker := seg[1];
    segLen := BE16(seg, 2);
    if segLen < 2 then Exit;
    { SOF0..SOF15 carry the frame size; C4 (DHT), C8 (JPG) and CC (DAC) share
      the range and do not. }
    if (marker >= $C0) and (marker <= $CF) and
       (marker <> $C4) and (marker <> $C8) and (marker <> $CC) then
    begin
      fs.Position := pos + 4;
      if fs.Read(seg[0], 5) <> 5 then Exit;
      h := BE16(seg, 1);                     { precision, then height, width }
      w := BE16(seg, 3);
      JpegSize := True;
      Exit;
    end;
    pos := pos + 2 + Int64(segLen);
  end;
end;

function ImageSize(const path: AnsiString; var w, h: LongWord): Boolean;
var
  fs: TFileStream;
  hdr: array[0..31] of Byte;
  n: Integer;
  sh: LongInt;
begin
  ImageSize := False;
  w := 0; h := 0;
  fs := nil;
  try
    fs := TFileStream.Create(path, fmOpenRead);
    n := fs.Read(hdr[0], 32);
    if n < 26 then Exit;

    { PNG: 8-byte signature, then the IHDR chunk; width/height are big-endian
      at 16 and 20. }
    if (hdr[0] = $89) and (hdr[1] = Ord('P')) and (hdr[2] = Ord('N')) and
       (hdr[3] = Ord('G')) then
    begin
      w := BE32(hdr, 16);
      h := BE32(hdr, 20);
      ImageSize := (w > 0) and (h > 0);
      Exit;
    end;

    { BMP: little-endian, width at 18 and height at 22. A negative height means
      a top-down bitmap; the magnitude is still the height. }
    if (hdr[0] = Ord('B')) and (hdr[1] = Ord('M')) then
    begin
      w := LE32(hdr, 18);
      sh := LongInt(LE32(hdr, 22));
      if sh < 0 then h := LongWord(-sh) else h := LongWord(sh);
      ImageSize := (w > 0) and (h > 0);
      Exit;
    end;

    { JPEG: SOI, then a segment walk. }
    if (hdr[0] = $FF) and (hdr[1] = $D8) then
    begin
      ImageSize := JpegSize(fs, w, h) and (w > 0) and (h > 0);
      Exit;
    end;
  finally
    if fs <> nil then fs.Free;
  end;
end;

constructor ImageReader.Create(const source: AnsiString);
begin
  fileName := source;
end;

function ImageReader.getSize: TPyList;
var w, h: LongWord;
begin
  { A loud refusal, not a (0, 0) that unpacks. Zeros would compile, unpack and
    then silently scale a drawing to nothing -- the same defect this method is
    being fixed for, one level down: right shape, wrong answer, no diagnostic.
    The unit's policy is that what it cannot do, it says so. }
  if not ImageSize(fileName, w, h) then
    raise Exception.Create('reportlab shim: could not read image dimensions '
      + 'from "' + fileName + '" — ImageReader.getSize measures PNG, JPEG and '
      + 'BMP headers, which is what pdfgen can embed');
  getSize := Pair(Integer(w), Integer(h));
end;

function ImageReader.__str__: AnsiString;
begin
  { drawImage takes the path out of the object through its string form }
  __str__ := fileName;
end;

end.
