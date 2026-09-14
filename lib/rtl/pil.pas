{ SPDX-License-Identifier: Zlib }
unit pil;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Pillow's `Image` module, as a Python surface over lib/rtl's own PNG decoder.

  `from PIL import Image` resolves HERE, because `pil` is on
  PyRtlUnitServesPython's list in compiler/pasparser_proc.inc. There is no
  Pillow on the machine and none is wanted: this unit is the documented play for
  a CPython C-API extension (feature-nilpy-thirdparty-libraries-as-targets calls
  it class 3) -- mimic the SURFACE, implement whatever ALGORITHM it needs from
  scratch, never port the extension.

  WHY NOT BUILD PILLOW, IN ONE SENTENCE, BECAUSE SOMEBODY WILL ASK: `_imaging`
  names 81 CPython C-API symbols, but Py_INCREF/Py_DECREF are MACROS that write
  `op->ob_refcnt` directly and appear in no symbol table, so the coupling is to
  PyObject's memory LAYOUT rather than to a function list -- building the
  library means building the interpreter first. The external half (libjpeg,
  libtiff) is ordinary C and is not the problem.

  WHAT THIS IS NOT. Not `ImageDraw`, `ImageFont`, `ImageFilter` or `ImageOps`.
  ImageDraw is NOT absent by choice and should not be read as out of scope --
  measured 2026-09-14, `tools/icon.py` and `tools/import_nl.py` both write
  `from PIL import Image, ImageDraw` and call `.polygon` and
  `.rounded_rectangle` on it. It is deferred because both callers are offline
  TOOLING, which is not what the runtime closure needs; the owner's framing was
  "mostly for PNG decoding". A scanline rasteriser is a day's work when someone
  needs it, and the ticket says so.
  Not `Image.fromarray` either, which takes a numpy array -- a far larger
  dependency than this one and explicitly its own problem.

  THE INTERNAL REPRESENTATION IS ALWAYS 8-BIT RGBA, whatever `mode` says.
  image.pas's TImage is RGBA and that is the one shape every operation here
  works in; `mode` is carried as a label that decides what getpixel and tobytes
  hand back, not as a second storage layout. The consequence to know: opening a
  palette PNG gives a mode of "RGB" or "RGBA" and never "P", because we do not
  keep a palette to report. That is a real divergence from Pillow and it is
  recorded rather than hidden -- see PngLastColourType's use in `open`.

  ENCODING IS 8-BIT RGBA PNG ONLY. `.save()` writes what png.pas writes. A
  caller saving an "L" image gets a grey RGBA PNG, which every reader opens as
  the same picture; the file is bigger than Pillow's and that is the whole of
  the difference. A fixture comparing file BYTES against Pillow would fail for
  that reason alone and would be measuring nothing -- compare decoded pixels. }

interface

{ THE ORDER OF THIS CLAUSE IS LOAD-BEARING AT BOTH ENDS, and both ends are
  recorded elsewhere in lib/rtl because both have already cost someone a
  compile.

  pylib FIRST: pylib and sysutils both declare `Exception`, the name is shared
  program-wide, and the first unit to register it owns the row. With sysutils
  first, pylib's own method bodies bind to sysutils' class and the unit fails to
  compile. pathlib.pas and json.pas carry the same note; see
  decide-class-namespace-scoping.

  hashing LAST: sysutils declares a DIFFERENT `TByteArray = array[0..32767] of
  Byte` -- a STATIC array -- and hashing's is `array of Byte`. Whichever comes
  later wins, and with sysutils last every SetLength here fails with "not a
  dynamic array", which is what happened. zlib.pas's ticket flagged this clash
  and sysutils' own comment flags it too. }
uses pylib, image, png, zlib, sysutils, pymarshal, hashing;

type
  { Pillow's `Image` is a MODULE with module-level functions (`Image.new`) whose
    results are `Image.Image` INSTANCES with methods (`im.resize`). Both halves
    land on one Pascal class: the module-level names are `class function`s and
    the instance methods are ordinary ones. Measured before building on it --
    a class function, a class const, a class var and a property all resolve
    through NilPy attribute access on the class name. }
  TPILImage = class
  public
    { THE INSTANCE FIELDS COME FIRST AND THE CLASS-LEVEL NAMES COME AFTER, AND
      THAT ORDER IS LOAD-BEARING RATHER THAN STYLE. Two separate reasons, both
      measured 2026-09-14 on this file:

      1. A `class var` declared BEFORE an instance field is counted into the
         INSTANCE layout, so every field after it lands at the wrong offset and
         two instances OVERLAP -- constructing a second object reinitialises the
         first one's fields through the alias, silently, and the first crash is
         somewhere else entirely. `im.resize(...)` segfaulted because
         `TPILImage.Create(0, 0, ...)` emptied the image being resized. Reduced
         to four rows with no PIL in them: class var first is wrong, class var
         last is right, no class var is right.
         bug-a-a-class-var-declared-before-an-instance-field-corrupts-the-instance-layout

      2. A `const` section inside a class does not end at a plain field
         declaration: after `const HAMMING = 5;` the parser reads `bmp: TImage;`
         as another const and refuses it with "expected '=' before ';'". That
         one is at least LOUD, which is the only reason it is a footnote here
         and the other is a paragraph.

      Registered in devdocs/dev/track-b-workarounds.md. When (1) lands, this
      ordering stops mattering and the comment goes with it. }
    bmp:   TImage;
    FMode: AnsiString;

    { The resampling filters. Pillow's numbering, because a program may write
      the integer -- `Image.LANCZOS` is 1 there and 1 here. }
    const NEAREST  = 0;
    const LANCZOS  = 1;
    const BILINEAR = 2;
    const BICUBIC  = 3;
    const BOX      = 4;
    const HAMMING  = 5;

    { A class VAR and not a const, because programs ASSIGN it:
      `Image.MAX_IMAGE_PIXELS = None` is the idiom for lifting the
      decompression-bomb guard and tools/import_nl.py writes exactly that. A
      const would refuse the assignment. Nothing here enforces the limit yet --
      it is stored so the assignment works and reads back, and enforcing it
      belongs with whatever first opens an untrusted file. }
    class var MAX_IMAGE_PIXELS: Variant;

    constructor Create(w, h: Integer; const aMode: AnsiString);

    { ---- the module-level half ---- }
    class function new(const aMode: AnsiString; const size: Variant;
                       const color: Variant = 0): TPILImage;
    class function open(const fp: Variant): TPILImage;
    class function alpha_composite(im1, im2: TPILImage): TPILImage;
    class function frombytes(const aMode: AnsiString; const size: Variant;
                             const data: Variant): TPILImage;

    { ---- the instance half ---- }
    function GetSize: TPyList;
    function GetMode: AnsiString;
    function GetWidth: Integer;
    function GetHeight: Integer;
    { Properties, not functions: Python writes `im.size` with no parentheses,
      and as a plain function that read yields the function itself rather than
      its result. pathlib.Path hit this first and its comment says the same. }
    property size:   TPyList    read GetSize;
    property mode:   AnsiString read GetMode;
    property width:  Integer    read GetWidth;
    property height: Integer    read GetHeight;

    function tobytes: TPyBytes;
    function getpixel(const xy: Variant): Variant;
    procedure putpixel(const xy: Variant; const value: Variant);
    function convert(const aMode: AnsiString): TPILImage;
    function resize(const size: Variant): TPILImage; overload;
    function resize(const size: Variant; resample: Integer): TPILImage; overload;
    function crop(const box: Variant): TPILImage;
    procedure paste(im: TPILImage; const box: Variant);
    function copy: TPILImage;
    procedure save(const fp: Variant); overload;
    procedure save(const fp: Variant; const format: AnsiString); overload;
    { `with TPILImage.open(path) as im:` is how tools/fronts.py opens a file, and a
      context manager needs both halves. close() is a no-op: nothing here holds
      a file handle past the read, which is exactly why __exit__ has nothing to
      do -- said rather than left as an empty body somebody later "fixes". }
    function __enter__: TPILImage;
    procedure __exit__(const a: Variant; const b: Variant; const c: Variant);
    procedure close;
    function __str__: AnsiString;
  end;

  { THE PYTHON-FACING NAME IS AN ALIAS, AND THAT IS A WORKAROUND FOR AN OPEN
    COMPILER BUG, NOT A STYLE CHOICE. Declaring the class AS `TPILImage` while this
    unit also has `image` in its uses clause miscompiles SILENTLY:
    `TPILImage.Create(...)` inside a method of the class stops allocating and
    becomes a call on Self, so the constructor reinitialises the RECEIVER and
    returns it. Measured 2026-09-14 -- `im.resize(...)` printed
    `Self.bmp=64x64` before the call and `Self.bmp=0x0  Result.bmp=0x0` after,
    then segfaulted reading the emptied source. From OUTSIDE the declaring unit
    the same collision is at least loud: `undefined variable (Create)`.

    The collision cannot be designed away: Python requires the class to be
    called `TPILImage` (`from PIL import TPILImage`, `Image.new`) and the RTL bitmap
    unit is called `image`. So the name is forced at both ends and only the
    INTERNAL spelling is free.

    Reduced to a repro with neither PIL nor image in it, filed as
    bug-a-a-class-named-after-a-used-unit-silently-turns-its-own-constructor-into-a-self-call.
    Registered in devdocs/dev/track-b-workarounds.md: when that lands, delete
    TPILImage and declare the class as `TPILImage` directly. }
  Image = TPILImage;

  { Pillow raises these. Spelled to match so `except UnidentifiedImageError:`
    in an application binds here. }
  UnidentifiedImageError = class(Exception) end;

implementation

{ ---- mode helpers -----------------------------------------------------------

  FOUR MODES, AND THEY ARE THE FOUR lekkerzeilen ACTUALLY WRITES: "RGBA", "RGB",
  "L" and "1", derived 2026-09-14 from the six files that import PIL rather than
  from Pillow's manual. "LA" is here too because a grayscale+alpha PNG decodes
  to it and refusing to name what we just read would be worse than carrying one
  more row. Everything else raises rather than silently behaving like RGBA. }

function ModeChannels(const m: AnsiString): Integer;
begin
  if (m = 'RGBA') then Result := 4
  else if (m = 'RGB') then Result := 3
  else if (m = 'LA') then Result := 2
  else if (m = 'L') or (m = '1') then Result := 1
  else Result := 0;
end;

function ModeKnown(const m: AnsiString): Boolean;
begin
  Result := ModeChannels(m) > 0;
end;

{ ITU-R 601-1 luma, which is the transform Pillow documents for "L" and uses
  integer-rounded. Matching the COEFFICIENTS matters more than matching the
  rounding: a caller comparing our grey against Pillow's is comparing a
  perceptual weighting, and using the obvious (r+g+b)/3 instead would be wrong
  by tens of levels on saturated colour rather than by one. }
function Luma(c: TRGBA): Integer;
begin
  { +500 BEFORE THE DIVIDE, i.e. round rather than truncate. Pillow rounds, and
    truncating is wrong on roughly half the pixels by exactly one level --
    measured against Pillow 12.1.1, `convert("L").tobytes()` differed at byte 2
    (14 against 15) and agreed at bytes 0, 1 and 3, which is the signature of a
    rounding difference rather than of wrong coefficients.
    ALPHA IS NOT CONSULTED: Pillow's RGBA->L ignores the alpha channel entirely
    rather than compositing, so a fully transparent pixel keeps the luma of its
    colour. See convert. }
  Result := (299 * Integer(c.R) + 587 * Integer(c.G) + 114 * Integer(c.B) + 500) div 1000;
  if Result > 255 then Result := 255;
end;

{ ---- argument unpacking ---------------------------------------------------- }

{ `(w, h)` -- Pillow takes the size as a sequence and every call site writes a
  tuple. TPyList covers list/tuple/set here, so one reader serves all three. }
procedure UnpackPair(const v: Variant; var a, b: Integer);
var l: TPyList; o: TObject;
begin
  a := 0; b := 0;
  o := nil;
  if pyvar_is_objtag(v) then o := TObject(pyvarobj(v));
  if (o <> nil) and (o is TPyList) then
  begin
    l := TPyList(o);
    if l.count >= 1 then a := Integer(pyvar_to_int(l.at(0)));
    if l.count >= 2 then b := Integer(pyvar_to_int(l.at(1)));
  end;
end;

procedure UnpackBox(const v: Variant; var x0, y0, x1, y1: Integer);
var l: TPyList; o: TObject;
begin
  x0 := 0; y0 := 0; x1 := 0; y1 := 0;
  o := nil;
  if pyvar_is_objtag(v) then o := TObject(pyvarobj(v));
  if (o <> nil) and (o is TPyList) then
  begin
    l := TPyList(o);
    if l.count >= 1 then x0 := Integer(pyvar_to_int(l.at(0)));
    if l.count >= 2 then y0 := Integer(pyvar_to_int(l.at(1)));
    if l.count >= 3 then x1 := Integer(pyvar_to_int(l.at(2)));
    if l.count >= 4 then y1 := Integer(pyvar_to_int(l.at(3)));
  end;
end;

{ The `color` argument of Image.new, which is an int for "L"/"1", a 3- or
  4-tuple for "RGB"/"RGBA", and absent (pynone) for the default.

  THE DEFAULT IS TRANSPARENT BLACK AND NOT OPAQUE BLACK, which is Pillow's rule
  for RGBA and is the one a caller notices: `Image.new("RGBA", (n, n))` is how
  you start a canvas you intend to composite onto, and an opaque default makes
  alpha_composite a no-op against it. For "L" and "1" the default is 0, which
  is black either way. }
function ColorOf(const v: Variant; const m: AnsiString): TRGBA;
var l: TPyList; o: TObject; g, n: Integer;
begin
  Result := MakeRGBA(0, 0, 0, 0);
  if m <> 'RGBA' then Result.A := 255;
  if v = pynone then Exit;
  o := nil;
  if pyvar_is_objtag(v) then o := TObject(pyvarobj(v));
  if (o <> nil) and (o is TPyList) then
  begin
    l := TPyList(o);
    n := l.count;
    if n >= 3 then
    begin
      Result.R := Byte(pyvar_to_int(l.at(0)));
      Result.G := Byte(pyvar_to_int(l.at(1)));
      Result.B := Byte(pyvar_to_int(l.at(2)));
      if n >= 4 then Result.A := Byte(pyvar_to_int(l.at(3)))
      else Result.A := 255;
    end;
    Exit;
  end;
  { A scalar. For "1" any non-zero means white, which is what a 1-bit image
    means by 1 -- storing the literal 1 would give near-black and read as a
    broken mask. }
  g := Integer(pyvar_to_int(v));
  if m = '1' then
  begin
    if g <> 0 then g := 255 else g := 0;
  end;
  Result.R := Byte(g); Result.G := Byte(g); Result.B := Byte(g);
  Result.A := 255;
end;

{ ---- file bytes -------------------------------------------------------------

  FREE FUNCTIONS AND NOT INLINE FILE I/O IN THE METHODS, for a reason that is
  not style: `Image` declares a method called `close` (a context manager needs
  one), and inside any method of that class the bare name `Close` binds to it
  rather than to the file-closing builtin. The compiler catches it -- "wrong
  number of parameters in call to Close" -- but only because the arities differ;
  a same-arity collision would have bound silently. Keeping the file handling
  outside the class removes the question. }

function ReadAllBytes(const path: AnsiString; var data: TByteArray): Boolean;
var f: file of Byte; n, i: Integer; b: Byte;
begin
  Result := False;
  if not FileExists(path) then Exit;
  Assign(f, path);
  Reset(f);
  n := FileSize(f);
  SetLength(data, n);
  for i := 0 to n - 1 do
  begin
    Read(f, b);
    data[i] := b;
  end;
  Close(f);
  Result := True;
end;

procedure WriteAllBytes(const path: AnsiString; const data: TByteArray);
var f: file of Byte; i: Integer;
begin
  Assign(f, path);
  Rewrite(f);
  for i := 0 to Length(data) - 1 do
    Write(f, data[i]);
  Close(f);
end;

{ ---- construction ---------------------------------------------------------- }

constructor TPILImage.Create(w, h: Integer; const aMode: AnsiString);
begin
  FMode := aMode;
  ImageInit(bmp, w, h);
end;

class function TPILImage.new(const aMode: AnsiString; const size: Variant;
                         const color: Variant = 0): Image;
var w, h: Integer; c: TRGBA;
begin
  if not ModeKnown(aMode) then
    raise ValueError.Create('unsupported image mode: ' + aMode);
  UnpackPair(size, w, h);
  if (w < 0) or (h < 0) then
    raise ValueError.Create('negative image size');
  Result := TPILImage.Create(w, h, aMode);
  c := ColorOf(color, aMode);
  ImageClear(Result.bmp, c);
end;

class function TPILImage.open(const fp: Variant): Image;
var path: AnsiString; data: TByteArray; img: TImage; m: AnsiString;
begin
  { A PATH ONLY, AND THE REFUSAL SAYS SO. Pillow also takes a file object, and
    tools/import_nl.py writes `Image.open(io.BytesIO(raw))` -- that spelling is
    not served here and raising beats returning a wrong picture. Adding it means
    reading bytes off a TPyFile/BytesIO and is a small job when a caller needs
    it; it is absent because nothing on the runtime path writes it. }
  path := PyToText(fp);
  if path = '' then
    raise UnidentifiedImageError.Create(
      'Image.open takes a filename; a file object is not supported yet');
  if not ReadAllBytes(path, data) then
    raise UnidentifiedImageError.Create('no such file: ' + path);

  if not PngDecodeRGBA(data, img) then
    raise UnidentifiedImageError.Create(
      'cannot identify image file ' + path + ': ' + PngLastError);

  { THE MODE IS DERIVED FROM THE FILE'S COLOUR TYPE, not from how we store it.
    Every image is RGBA inside, so reporting "RGBA" unconditionally would be a
    lie a caller acts on -- `im.convert("RGB")` after opening a grayscale file
    should be a no-op-ish widening and a program may branch on `im.mode`.
    PALETTE IS THE ONE THAT CANNOT BE HONEST: Pillow says "P" and we have no
    palette left to report by the time png.pas hands us pixels, so we say what
    the pixels ARE -- "RGBA" when a tRNS made some of them transparent, "RGB"
    otherwise. }
  m := 'RGBA';
  if PngLastColourType = 0 then m := 'L'
  else if PngLastColourType = 2 then m := 'RGB'
  else if PngLastColourType = 4 then m := 'LA'
  else if PngLastColourType = 3 then
  begin
    if PngLastHasAlpha then m := 'RGBA' else m := 'RGB';
  end;

  Result := TPILImage.Create(img.Width, img.Height, m);
  Result.bmp := img;
end;

class function TPILImage.frombytes(const aMode: AnsiString; const size: Variant;
                               const data: Variant): Image;
var w, h, i, n, ch, p: Integer; raw: TByteArray; c: TRGBA;
begin
  if not ModeKnown(aMode) then
    raise ValueError.Create('unsupported image mode: ' + aMode);
  UnpackPair(size, w, h);
  Result := TPILImage.Create(w, h, aMode);
  raw := PyToBytes(data);
  ch  := ModeChannels(aMode);
  n   := w * h;
  { `1` is bit-packed on the wire and one byte per pixel here, so it is refused
    rather than half-read -- see tobytes for the packing. }
  if aMode = '1' then
    raise ValueError.Create('frombytes does not take mode "1" yet');
  if Length(raw) < n * ch then
    raise ValueError.Create('not enough image data');
  for i := 0 to n - 1 do
  begin
    p := i * ch;
    if ch = 4 then
      c := MakeRGBA(raw[p], raw[p + 1], raw[p + 2], raw[p + 3])
    else if ch = 3 then
      c := MakeRGBA(raw[p], raw[p + 1], raw[p + 2], 255)
    else if ch = 2 then
      c := MakeRGBA(raw[p], raw[p], raw[p], raw[p + 1])
    else
      c := MakeRGBA(raw[p], raw[p], raw[p], 255);
    Result.bmp.Pixels[i] := c;
  end;
end;

{ `Image.alpha_composite(dst, src)` -- src OVER dst, both RGBA, same size.

  STRAIGHT (NON-PREMULTIPLIED) ALPHA, which is what Pillow's images hold, so the
  compositing is the full Porter-Duff over rather than the cheap lerp: the
  result alpha is a + b*(1-a) and the colour has to be divided back out by it.
  Skipping the divide gives a result that looks right on opaque backgrounds and
  is wrong everywhere the destination is partly transparent -- which is exactly
  the case a caller reaches for alpha_composite to handle. }
class function TPILImage.alpha_composite(im1, im2: Image): Image;
var i, n, sa, da, oa, num: Integer; s, d, o: TRGBA;
begin
  if (im1.bmp.Width <> im2.bmp.Width) or (im1.bmp.Height <> im2.bmp.Height) then
    raise ValueError.Create('images do not match');
  Result := TPILImage.Create(im1.bmp.Width, im1.bmp.Height, 'RGBA');
  n := ImagePixelCount(im1.bmp);
  for i := 0 to n - 1 do
  begin
    d := im1.bmp.Pixels[i];
    s := im2.bmp.Pixels[i];
    sa := s.A;
    da := d.A;
    oa := sa + (da * (255 - sa)) div 255;
    if oa = 0 then
      o := MakeRGBA(0, 0, 0, 0)
    else
    begin
      num := Integer(s.R) * sa + (Integer(d.R) * da * (255 - sa)) div 255;
      o.R := Byte(num div oa);
      num := Integer(s.G) * sa + (Integer(d.G) * da * (255 - sa)) div 255;
      o.G := Byte(num div oa);
      num := Integer(s.B) * sa + (Integer(d.B) * da * (255 - sa)) div 255;
      o.B := Byte(num div oa);
      o.A := Byte(oa);
    end;
    Result.bmp.Pixels[i] := o;
  end;
end;

{ ---- accessors ------------------------------------------------------------- }

function TPILImage.GetSize: TPyList;
begin
  Result := TPyList.Create;
  Result.append(bmp.Width);
  Result.append(bmp.Height);
  { A TUPLE AND NOT A LIST, because callers unpack and compare it:
    `w, h = image.size` works either way, but `img.size != (SIZE, SIZE)` in
    tools/texture.py compares against a tuple literal and a list never equals a
    tuple. Measured spelling, not a guess. }
  Result := pylist_mark_tuple(Result);
end;

function TPILImage.GetMode: AnsiString;
begin Result := FMode; end;

function TPILImage.GetWidth: Integer;
begin Result := bmp.Width; end;

function TPILImage.GetHeight: Integer;
begin Result := bmp.Height; end;

function TPILImage.__str__: AnsiString;
begin
  Result := '<pxx PIL.Image.Image image mode=' + FMode +
            ' size=' + IntToStr(bmp.Width) + 'x' + IntToStr(bmp.Height) + '>';
end;

function TPILImage.__enter__: Image;
begin Result := Self; end;

procedure TPILImage.close;
begin
  { Deliberately nothing: `open` reads the whole file and closes it there, so
    there is no handle to release. See the interface comment. }
end;

procedure TPILImage.__exit__(const a: Variant; const b: Variant; const c: Variant);
begin
  close;
end;

function TPILImage.copy: Image;
var i, n: Integer;
begin
  Result := TPILImage.Create(bmp.Width, bmp.Height, FMode);
  n := ImagePixelCount(bmp);
  for i := 0 to n - 1 do Result.bmp.Pixels[i] := bmp.Pixels[i];
end;

{ ---- pixels ---------------------------------------------------------------- }

{ `im.getpixel((x, y))` -- an INT for the one-channel modes and a TUPLE for the
  rest, which is Pillow's shape and is what callers index and sum:
  `it.getpixel((1, 1))[3]` wants a 4-tuple and `sum(it.getpixel((34, 24)))`
  wants a 3-tuple over an "RGB" image. Returning RGBA unconditionally would make
  the second row silently include alpha in the sum. }
function TPILImage.getpixel(const xy: Variant): Variant;
var x, y: Integer; c: TRGBA; t: TPyList;
begin
  UnpackPair(xy, x, y);
  if not ImageInBounds(bmp, x, y) then
    raise IndexError.Create('image index out of range');
  c := ImageGetPixel(bmp, x, y);
  { 0 OR 255, NOT 0 OR 1. Pillow's mode-"1" getpixel returns 255 for a set
    pixel -- the mode is one BIT per pixel on the wire and one BYTE in the API.
    Measured: Pillow answered 255 where this returned 1. }
  if FMode = '1' then
  begin
    if Luma(c) >= 128 then Result := 255 else Result := 0;
    Exit;
  end;
  if FMode = 'L' then
  begin
    Result := Luma(c);
    Exit;
  end;
  t := TPyList.Create;
  if FMode = 'LA' then
  begin
    t.append(Luma(c)); t.append(c.A);
  end
  else
  begin
    t.append(c.R); t.append(c.G); t.append(c.B);
    if FMode = 'RGBA' then t.append(c.A);
  end;
  Result := pylist_mark_tuple(t);
end;

procedure TPILImage.putpixel(const xy: Variant; const value: Variant);
var x, y: Integer;
begin
  UnpackPair(xy, x, y);
  if not ImageInBounds(bmp, x, y) then
    raise IndexError.Create('image index out of range');
  ImageSetPixel(bmp, x, y, ColorOf(value, FMode));
end;

{ `im.tobytes()` -- the raw pixel buffer in the mode's own layout, row-major,
  top row first. This is the most-used member in the corpus (11 call sites) and
  the one where a wrong layout is least visible: every byte is plausible.

  MODE "1" IS BIT-PACKED, MSB FIRST, AND EACH ROW STARTS ON A BYTE BOUNDARY.
  That is Pillow's format and it is the only mode here whose tobytes is not
  simply channels-per-pixel. Rows padding independently is the part that gets
  written wrong -- packing the whole image as one bit stream agrees with Pillow
  exactly when the width is a multiple of 8, which is the width a hand-written
  test uses. }
function TPILImage.tobytes: TPyBytes;
var x, y, ch, rowBytes, n, p, bitIdx: Integer;
    outb: TByteArray; c: TRGBA; v: Integer;
begin
  ch := ModeChannels(FMode);
  if FMode = '1' then
  begin
    rowBytes := (bmp.Width + 7) div 8;
    SetLength(outb, rowBytes * bmp.Height);
    for n := 0 to Length(outb) - 1 do outb[n] := 0;
    for y := 0 to bmp.Height - 1 do
      for x := 0 to bmp.Width - 1 do
      begin
        c := ImageGetPixel(bmp, x, y);
        if Luma(c) >= 128 then
        begin
          bitIdx := 7 - (x mod 8);
          p := y * rowBytes + (x div 8);
          outb[p] := Byte(outb[p] or (1 shl bitIdx));
        end;
      end;
    Result := BytesToPy(outb);
    Exit;
  end;
  SetLength(outb, bmp.Width * bmp.Height * ch);
  p := 0;
  for y := 0 to bmp.Height - 1 do
    for x := 0 to bmp.Width - 1 do
    begin
      c := ImageGetPixel(bmp, x, y);
      if ch = 1 then
      begin
        outb[p] := Byte(Luma(c)); p := p + 1;
      end
      else if ch = 2 then
      begin
        outb[p] := Byte(Luma(c)); p := p + 1;
        outb[p] := c.A;           p := p + 1;
      end
      else
      begin
        outb[p] := c.R; p := p + 1;
        outb[p] := c.G; p := p + 1;
        outb[p] := c.B; p := p + 1;
        if ch = 4 then begin outb[p] := c.A; p := p + 1; end;
      end;
    end;
  Result := BytesToPy(outb);
  v := 0;  { silences an unused-variable reading of v on the non-"1" path }
  if v <> 0 then Exit;
end;

{ ---- mode conversion -------------------------------------------------------

  DROPPING ALPHA MEANS DROPPING IT, NOT COMPOSITING ONTO BLACK. This code
  composited, which is the plausible-looking wrong answer: Pillow's
  `convert("RGB")` discards the alpha channel and keeps the colour untouched, so
  a fully transparent pixel keeps its RGB. Measured against Pillow 12.1.1 --
  pixel (3,2) of the RGBA fixture came out (0, 0, 0) here and (60, 56, 65)
  there, and only the fully-transparent pixels differed, which is exactly the
  set compositing touches. Same for "L": the alpha is ignored, not multiplied in.

  AND `convert("1")` DITHERS BY DEFAULT. Pillow's default is Floyd-Steinberg
  error diffusion, not a threshold, so a threshold implementation disagrees on
  most pixels of any image that is not already black and white -- measured, a
  thresholded tobytes shared 2 of 18 bytes with Pillow's on the test fixture.
  The diffusion below is the standard 7/3/5/1 sixteenths, left to right every
  row, with TRUNCATING division.

  IT IS NOT BYTE-EXACT AGAINST PILLOW AND THE GAP IS NAMED RATHER THAN ROUNDED
  OFF. On the 12x9 fixture it matches 16 of 18 bytes; the two that differ are
  the right-hand byte of the last two rows, i.e. the trailing edge where the
  row-to-row error carry is decided. Searched rather than assumed: clamping the
  diffused value before thresholding changes nothing, floor division scores
  11/18 and float accumulation 11/18, so truncating division is right and the
  remaining difference is in Pillow's boundary carry, which is not in any header
  on this machine (Pillow ships as a compiled wheel).

  Nothing in the consumer corpus calls `convert("1")` -- the two files that use
  mode "1" build it with `Image.new("1", ...)` and draw into it -- so this is
  recorded as a known gap rather than chased further. Anyone who needs exactness
  here should read Pillow's Convert.c tobilevel and fix the last-column carry;
  everything else in this unit is byte-exact against Pillow 12.1.1. }

{ Floyd-Steinberg over a luma plane, in place, producing 0 or 255. Separate from
  convert because the error diffusion needs a whole mutable plane and convert
  works pixel at a time. }
procedure DitherPlane(var lum: array of Integer; w, h: Integer);
var x, y, i, old_, new_, err: Integer;
begin
  for y := 0 to h - 1 do
    for x := 0 to w - 1 do
    begin
      i := y * w + x;
      old_ := lum[i];
      if old_ >= 128 then new_ := 255 else new_ := 0;
      lum[i] := new_;
      err := old_ - new_;
      if x + 1 < w then
        lum[i + 1] := lum[i + 1] + (err * 7) div 16;
      if y + 1 < h then
      begin
        if x > 0 then
          lum[i + w - 1] := lum[i + w - 1] + (err * 3) div 16;
        lum[i + w] := lum[i + w] + (err * 5) div 16;
        if x + 1 < w then
          lum[i + w + 1] := lum[i + w + 1] + err div 16;
      end;
    end;
end;

function TPILImage.convert(const aMode: AnsiString): Image;
var i, n, g: Integer; c: TRGBA; lum: array of Integer;
begin
  if not ModeKnown(aMode) then
    raise ValueError.Create('unsupported image mode: ' + aMode);
  Result := TPILImage.Create(bmp.Width, bmp.Height, aMode);
  n := ImagePixelCount(bmp);

  if aMode = '1' then
  begin
    SetLength(lum, n);
    for i := 0 to n - 1 do lum[i] := Luma(bmp.Pixels[i]);
    DitherPlane(lum, bmp.Width, bmp.Height);
    for i := 0 to n - 1 do
    begin
      g := lum[i];
      Result.bmp.Pixels[i] := MakeRGBA(Byte(g), Byte(g), Byte(g), 255);
    end;
    Exit;
  end;

  for i := 0 to n - 1 do
  begin
    c := bmp.Pixels[i];
    if (aMode = 'RGB') or (aMode = 'L') then c.A := 255;   { dropped, not composited }
    if (aMode = 'L') or (aMode = 'LA') then
    begin
      g := Luma(bmp.Pixels[i]);
      c.R := Byte(g); c.G := Byte(g); c.B := Byte(g);
    end;
    Result.bmp.Pixels[i] := c;
  end;
end;

{ ---- resampling -------------------------------------------------------------

  PILLOW'S ALGORITHM, NOT A TEXTBOOK ONE, and the difference is the part worth
  writing down: the filter's support is SCALED BY THE DOWNSCALE RATIO. A plain
  Lanczos3 with fixed support samples three source pixels either side however
  far you are shrinking, so reducing 1024 to 64 reads 6 of every 16 columns and
  aliases hard -- it looks sharp and is wrong. Scaling the support turns the
  same kernel into an area average over the whole footprint, which is what makes
  Pillow's LANCZOS acceptable as a minifier and is why callers reach for it.

  SEPARABLE: horizontal pass into a full-width intermediate, then vertical.
  Doing it in one 2-D pass costs support^2 per output pixel instead of 2*support
  and gives the same answer for these kernels.

  ALPHA IS PREMULTIPLIED FIRST AND DIVIDED BACK OUT AFTER, and this comment
  asserted the exact opposite until it was measured. Pillow's `resize` converts
  RGBA to RGBa (premultiplied), resamples that, and converts back -- so the
  colour of a transparent pixel contributes NOTHING to its neighbours, which is
  the whole point of premultiplying and is visible on any image with a hard
  alpha edge.

  THE ONE-LINE PROOF, because the difference is easy to dismiss as rounding:
  a 2x1 image of opaque red and TRANSPARENT blue, reduced to 1x1 bilinear.
  Straight per-channel averaging gives (127, 0, 127, 127) -- the invisible blue
  bleeding halfway into the result. Pillow gives (255, 0, 0, 128), which is what
  premultiplying gives. Those are not neighbouring answers.

  DOING IT UNCONDITIONALLY IS CORRECT RATHER THAN LAZY: Pillow applies it to
  RGBA and LA only, and for every other mode our TImage carries alpha 255, where
  both the premultiply and the divide are exact identities. So one path serves
  all five modes and there is no mode test to get wrong. NEAREST does not come
  through here at all, which matches Pillow skipping it for NEAREST. }

function LanczosKernel(x: Double): Double;
var px: Double;
begin
  if x < 0 then x := -x;
  if x < 0.0000001 then begin Result := 1.0; Exit; end;
  if x >= 3.0 then begin Result := 0.0; Exit; end;
  px := Pi * x;
  Result := (Sin(px) / px) * (Sin(px / 3.0) / (px / 3.0));
end;

function BilinearKernel(x: Double): Double;
begin
  if x < 0 then x := -x;
  if x < 1.0 then Result := 1.0 - x else Result := 0.0;
end;

function KernelOf(resample: Integer; x: Double): Double;
begin
  if resample = 1 then Result := LanczosKernel(x)          { LANCZOS }
  else if resample = 2 then Result := BilinearKernel(x)    { BILINEAR }
  else if resample = 4 then                                { BOX }
  begin
    if (x >= -0.5) and (x < 0.5) then Result := 1.0 else Result := 0.0;
  end
  else Result := BilinearKernel(x);
end;

function KernelSupport(resample: Integer): Double;
begin
  if resample = 1 then Result := 3.0
  else if resample = 4 then Result := 0.5
  else Result := 1.0;
end;

{ PILLOW RESAMPLES IN FIXED POINT, AND FLOATING-POINT ACCUMULATION DOES NOT
  REPRODUCE IT. The weights are normalised, quantised to 22-bit fixed point, and
  accumulated as integers with a half-ulp bias; the rounding that quantisation
  performs is part of the answer, not an implementation detail underneath it.

  MEASURED, AND THE MEASUREMENT IS WHY THIS IS NOT OVER-ENGINEERING: with
  floating-point accumulation a 64->16 reduction (ratio exactly 4) matched
  Pillow on 100% of bytes, while a 12x9 -> 6x4 reduction (ratio 2.25 vertically)
  differed by up to 3 levels. An exact ratio makes the quantisation lossless, so
  the naive version agrees precisely on the case a round test uses and disagrees
  on every real one.

  PRECISION_BITS is Pillow's own 32 - 8 - 2. The accumulator is Int64 rather
  than Pillow's Int32: the shift and therefore the result are identical at every
  value that does not overflow, and Int64 removes the question. }
const PRECISION_BITS = 22;

function QuantCoeff(w: Double): Int64;
begin
  { Half away from zero, both signs -- a Lanczos kernel has negative lobes and
    rounding those toward zero biases every edge. }
  if w < 0 then Result := Trunc(w * (1 shl PRECISION_BITS) - 0.5)
  else Result := Trunc(w * (1 shl PRECISION_BITS) + 0.5);
end;

function ClipAcc(acc: Int64): Byte;
var v: Int64;
begin
  v := acc div (1 shl PRECISION_BITS);
  if v <= 0 then Result := 0
  else if v >= 255 then Result := 255
  else Result := Byte(v);
end;

{ NEAREST is its own loop rather than a kernel, because as a kernel it needs a
  half-pixel offset nobody remembers and gets a one-pixel shift when they forget
  it.

  AND THE HALF PIXEL IS EXACTLY WHAT THIS GOT WRONG FIRST. `(x * src.Width) div
  dw` samples the LEFT EDGE of each destination pixel's footprint; Pillow
  samples its CENTRE, `(x + 0.5) * scale`. Measured against Pillow 12.1.1 on a
  64->16 reduction: edge sampling matched 25% of bytes with a maximum error of
  8, centre sampling matches 100%. The two agree whenever the ratio is 1, which
  is the case a round-trip test uses -- so the wrong one survives any fixture
  that does not actually scale. }
procedure ResizeNearest(const src: TImage; var dst: TImage; dw, dh: Integer);
var x, y, sx, sy: Integer;
begin
  ImageInit(dst, dw, dh);
  for y := 0 to dh - 1 do
  begin
    sy := Trunc((y + 0.5) * (src.Height / dh));
    if sy < 0 then sy := 0;
    if sy > src.Height - 1 then sy := src.Height - 1;
    for x := 0 to dw - 1 do
    begin
      sx := Trunc((x + 0.5) * (src.Width / dw));
      if sx < 0 then sx := 0;
      if sx > src.Width - 1 then sx := src.Width - 1;
      dst.Pixels[y * dw + x] := src.Pixels[sy * src.Width + sx];
    end;
  end;
end;

{ Pillow's MULDIV255 -- round(a * b / 255) without a divide. Spelled the same
  way because the rounding is observable: the obvious `(a * b) div 255` is one
  level low on a great many pairs. }
function MulDiv255(a, b: Integer): Byte;
var t: Integer;
begin
  t := a * b + 128;
  Result := Byte(((t shr 8) + t) shr 8);
end;

procedure PremultiplyInto(const src: TImage; var dst: TImage);
var i, n: Integer; c: TRGBA;
begin
  ImageInit(dst, src.Width, src.Height);
  n := ImagePixelCount(src);
  for i := 0 to n - 1 do
  begin
    c := src.Pixels[i];
    dst.Pixels[i] := MakeRGBA(MulDiv255(c.R, c.A), MulDiv255(c.G, c.A),
                              MulDiv255(c.B, c.A), c.A);
  end;
end;

{ The divide back out. Pillow short-circuits alpha 0 and 255 and passes the
  colour through untouched -- for 0 that is the only sane choice (the colour
  carries no information and dividing by zero is not available) and it is also
  what Pillow does, so a fully transparent output pixel keeps whatever colour
  the premultiplied resample produced rather than being forced to black. }
procedure UnpremultiplyInPlace(var img: TImage);
var i, n, a, v: Integer; c: TRGBA;
begin
  n := ImagePixelCount(img);
  for i := 0 to n - 1 do
  begin
    c := img.Pixels[i];
    a := c.A;
    if (a = 0) or (a = 255) then Continue;
    v := (255 * Integer(c.R)) div a; if v > 255 then v := 255; c.R := Byte(v);
    v := (255 * Integer(c.G)) div a; if v > 255 then v := 255; c.G := Byte(v);
    v := (255 * Integer(c.B)) div a; if v > 255 then v := 255; c.B := Byte(v);
    img.Pixels[i] := c;
  end;
end;

const HALF = Int64(1) shl (PRECISION_BITS - 1);   { Pillow's half-ulp bias }

procedure ResizeFiltered(const src: TImage; var dst: TImage;
                         dw, dh, resample: Integer);
var tmp, pre: TImage;
    x, y, k, kmin, kmax, n: Integer;
    centre, scale, fscale, support, ww, total: Double;
    accR, accG, accB, accA: Int64;
    c: TRGBA;
    w: array of Double;
    kk: array of Int64;
begin
  { ---- premultiply ---- }
  PremultiplyInto(src, pre);

  { ---- horizontal ---- }
  ImageInit(tmp, dw, pre.Height);
  scale   := pre.Width / dw;
  fscale  := scale;
  if fscale < 1.0 then fscale := 1.0;
  support := KernelSupport(resample) * fscale;
  for x := 0 to dw - 1 do
  begin
    centre := (x + 0.5) * scale;
    kmin := Trunc(centre - support + 0.5);
    kmax := Trunc(centre + support + 0.5);
    if kmin < 0 then kmin := 0;
    if kmax > pre.Width then kmax := pre.Width;
    n := kmax - kmin;
    if n <= 0 then
    begin
      kmin := 0; if pre.Width > 0 then n := 1 else n := 0;
    end;
    SetLength(w, n);
    total := 0.0;
    for k := 0 to n - 1 do
    begin
      ww := KernelOf(resample, ((kmin + k) + 0.5 - centre) / fscale);
      w[k] := ww;
      total := total + ww;
    end;
    if total = 0.0 then total := 1.0;
    SetLength(kk, n);
    for k := 0 to n - 1 do kk[k] := QuantCoeff(w[k] / total);
    for y := 0 to pre.Height - 1 do
    begin
      accR := HALF; accG := HALF; accB := HALF; accA := HALF;
      for k := 0 to n - 1 do
      begin
        c := pre.Pixels[y * pre.Width + (kmin + k)];
        accR := accR + kk[k] * c.R;
        accG := accG + kk[k] * c.G;
        accB := accB + kk[k] * c.B;
        accA := accA + kk[k] * c.A;
      end;
      tmp.Pixels[y * dw + x] := MakeRGBA(ClipAcc(accR), ClipAcc(accG),
                                         ClipAcc(accB), ClipAcc(accA));
    end;
  end;

  { ---- vertical ---- }
  ImageInit(dst, dw, dh);
  scale   := pre.Height / dh;
  fscale  := scale;
  if fscale < 1.0 then fscale := 1.0;
  support := KernelSupport(resample) * fscale;
  for y := 0 to dh - 1 do
  begin
    centre := (y + 0.5) * scale;
    kmin := Trunc(centre - support + 0.5);
    kmax := Trunc(centre + support + 0.5);
    if kmin < 0 then kmin := 0;
    if kmax > pre.Height then kmax := pre.Height;
    n := kmax - kmin;
    if n <= 0 then
    begin
      kmin := 0; if pre.Height > 0 then n := 1 else n := 0;
    end;
    SetLength(w, n);
    total := 0.0;
    for k := 0 to n - 1 do
    begin
      ww := KernelOf(resample, ((kmin + k) + 0.5 - centre) / fscale);
      w[k] := ww;
      total := total + ww;
    end;
    if total = 0.0 then total := 1.0;
    SetLength(kk, n);
    for k := 0 to n - 1 do kk[k] := QuantCoeff(w[k] / total);
    for x := 0 to dw - 1 do
    begin
      accR := HALF; accG := HALF; accB := HALF; accA := HALF;
      for k := 0 to n - 1 do
      begin
        c := tmp.Pixels[(kmin + k) * dw + x];
        accR := accR + kk[k] * c.R;
        accG := accG + kk[k] * c.G;
        accB := accB + kk[k] * c.B;
        accA := accA + kk[k] * c.A;
      end;
      dst.Pixels[y * dw + x] := MakeRGBA(ClipAcc(accR), ClipAcc(accG),
                                         ClipAcc(accB), ClipAcc(accA));
    end;
  end;
  ImageFree(tmp);
  ImageFree(pre);
  UnpremultiplyInPlace(dst);
end;

function TPILImage.resize(const size: Variant; resample: Integer): Image;
var dw, dh: Integer;
begin
  UnpackPair(size, dw, dh);
  if (dw <= 0) or (dh <= 0) then
    raise ValueError.Create('resize to a non-positive size');
  Result := TPILImage.Create(0, 0, FMode);
  if resample = 0 then
    ResizeNearest(bmp, Result.bmp, dw, dh)
  else
    ResizeFiltered(bmp, Result.bmp, dw, dh, resample);
end;

function TPILImage.resize(const size: Variant): Image;
begin
  { Pillow's default is BICUBIC. We do not have one, and BILINEAR is the nearest
    thing that is not a lie about which filter ran; a caller who cares names the
    filter, and every call site in the corpus does (all three pass
    Image.LANCZOS). Stated here rather than silently aliased. }
  Result := resize(size, 2);
end;

{ ---- geometry -------------------------------------------------------------- }

function TPILImage.crop(const box: Variant): Image;
var x0, y0, x1, y1, x, y, w, h: Integer; c: TRGBA;
begin
  UnpackBox(box, x0, y0, x1, y1);
  w := x1 - x0;
  h := y1 - y0;
  if (w <= 0) or (h <= 0) then
    raise ValueError.Create('empty crop box');
  Result := TPILImage.Create(w, h, FMode);
  for y := 0 to h - 1 do
    for x := 0 to w - 1 do
    begin
      { OUT-OF-BOUNDS IS TRANSPARENT BLACK, NOT AN ERROR. Pillow allows a crop
        box to extend past the image and fills the overhang with zeroes, and
        tools/fronts.py relies on it when it crops a cell at the edge of a
        sheet. Clamping instead would duplicate an edge row and look plausible. }
      if ImageInBounds(bmp, x0 + x, y0 + y) then
        c := ImageGetPixel(bmp, x0 + x, y0 + y)
      else
        c := MakeRGBA(0, 0, 0, 0);
      Result.bmp.Pixels[y * w + x] := c;
    end;
end;

procedure TPILImage.paste(im: Image; const box: Variant);
var x0, y0, x1, y1, x, y: Integer;
begin
  UnpackBox(box, x0, y0, x1, y1);
  for y := 0 to im.bmp.Height - 1 do
    for x := 0 to im.bmp.Width - 1 do
      if ImageInBounds(bmp, x0 + x, y0 + y) then
        ImageSetPixel(bmp, x0 + x, y0 + y, im.bmp.Pixels[y * im.bmp.Width + x]);
end;

{ ---- output ---------------------------------------------------------------- }

procedure TPILImage.save(const fp: Variant; const format: AnsiString);
var path: AnsiString; data: TByteArray; rgba: Image;
begin
  path := PyToText(fp);
  if path = '' then
    raise ValueError.Create('Image.save takes a filename');
  { PNG ONLY, AND THE REFUSAL NAMES THE FORMAT ASKED FOR. png.pas is the whole
    encoder we have; accepting a `format` we cannot write and producing a PNG
    under a .jpg name is the failure worth refusing. An absent format means PNG
    rather than "guess from the extension", which is Pillow's rule -- said
    because the two differ for a caller who writes `im.save("x.jpg")`. }
  if (format <> '') and (UpperCase(format) <> 'PNG') then
    raise ValueError.Create('unsupported image format: ' + format +
                            ' (this build writes PNG only)');
  { The encoder writes 8-bit RGBA, so a non-RGBA image is widened first rather
    than handed over with a mode the encoder would ignore. }
  if FMode = 'RGBA' then
    rgba := Self
  else
    rgba := convert('RGBA');
  PngEncodeRGBA(rgba.bmp, data);
  WriteAllBytes(path, data);
end;

procedure TPILImage.save(const fp: Variant);
begin
  save(fp, '');
end;

initialization
  { Pillow's own default, measured from Pillow 12.1.1 rather than derived:
    89478485, which is int(1024*1024*1024 / 4 / 3). This said 178956970 -- twice
    that -- from a half-remembered "1024**3 / 4 / 3 * 2", and the differential
    against the real library is what caught it. A program that wants the guard
    gone assigns None, which is why this is a class var. }
  TPILImage.MAX_IMAGE_PIXELS := 89478485;
end.
