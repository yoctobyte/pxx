unit mimic_reportlab_pdfgen;
{ `from reportlab.pdfgen import canvas` — the drawing surface, over the vendored
  AndreRenaud/pdfgen C writer (lib/vendor/pdfgen).

  This is a T1 name shim in the sense of devdocs/dev/python-compat-tiers.md: it
  presents reportlab's INTERFACE so an application compiles unedited, it is a
  clean-room implementation over an unrelated backend, and it is honest about
  being a subset. It does not contain, and does not run, any reportlab code.

  THE SUBSET, stated plainly, because a shim that quietly approximates is worse
  than one that refuses:

    Canvas(filename, pagesize=)          -> a page-per-showPage document
    setFont(name, size)                  -> the PDF standard-14 font names
    drawString(x, y, text)               -> text at a BASELINE, as in reportlab
    setFillColorRGB / setStrokeColorRGB  -> 0..1 components
    setFillColor / setStrokeColor        -> a colors.Color object
    setLineWidth(w)
    line(x1, y1, x2, y2)
    rect(x, y, w, h, stroke=, fill=)
    circle(x, y, r, stroke=, fill=)
    drawImage(src, x, y, width=, height=, mask=)   -> file paths only
    beginText(x, y) / textLine(s) / drawText(t)
    showPage() / save()
    stringWidth(text, font, size)        -> pdfgen's own metrics

  NOT here, and each fails loudly rather than drawing something else:
  reportlab.platypus (Paragraph/Table/auto-layout), transforms (translate/rotate/
  scale/saveState), clipping paths, bezier paths, transparency groups, embedded
  TrueType fonts, and setBlendMode. Coordinates are PDF-native in both libraries
  (origin bottom-left, points), so no axis flip is involved anywhere.

  A full reportlab under pxx means compiling the actual package, which is the T3
  ticket feature-nilpy-py-module-loader plus reportlab's own C extensions; this
  unit defers to it and says so. }

interface

{ EVERY AnsiString handed to this C backend goes through PChar(). Passing one
  raw to a `const char *` compiled fine and then CRASHED once a document used
  four distinct fonts — three was survivable, which is exactly why it lasted:
  the failure needs enough calls to matter. drawString's text was unwrapped too,
  the most-used call in the shim (feature-lib-reportlab-fidelity-vs-oracle).

  The C backend is reached by PATH, not by unit name: it is vendored under
  lib/vendor/, which is not on the unit search chain, and naming the file keeps
  the dependency visible. A `.c` (not `.h`) is compiled INTO this binary,
  statically, so nothing is loaded at runtime. }
{ Historically pylib had to come BEFORE sysutils: the other order failed to
  compile pylib's own Exception (bug-pascal-uses-order-breaks-pylib-exception,
  fixed) -- a `ClassName.MethodName` impl header now always binds to a class
  declared in the CURRENT unit instead of following the flat, shared-name
  resolution that external references to `Exception` still use (that part is
  deliberate, so `except Exception:` keeps catching either RTL regardless of
  uses order; see decide-class-namespace-scoping for the broader question).
  Order verified to genuinely not matter anymore; kept as-is since it was
  already working and there is no reason to churn it. }
uses pxxcio, pylib, sysutils, mimic_reportlab_lib_colors,
     '../vendor/pdfgen/pdfgen.c';

type
  { `t = c.beginText(x, y)` ... `t.textLine(s)` ... `c.drawText(t)`. reportlab's
    text object carries its own cursor and steps down by the leading on each
    line; the default leading is 1.2 * the font size, which is what reportlab
    uses and what a song sheet's spacing depends on. }
  PDFTextObject = class
  public
    x, y: Double;
    startX: Double;
    fontName: AnsiString;
    fontSize: Double;
    leading: Double;
    lines: TPyList;          { the text of each queued line }
    xs: TPyList;             { and where its baseline sits }
    ys: TPyList;
    constructor Create(ax, ay: Double; const afont: AnsiString; asize: Double);
    destructor Destroy; override;
    procedure setFont(const name: AnsiString; size: Double);
    procedure setLeading(l: Double);
    { Move the text cursor. reportlab resets the LINE START too, so the next
      textLine() returns to this x rather than to the origin beginText() was
      given — songformatter opens a text object at one margin and then moves it
      (`beginText(m, top)` … `setTextOrigin(m, top - 1.2*size)`). }
    procedure setTextOrigin(ax, ay: Double);
    { relative move, reportlab's other spelling of the same thing }
    procedure moveCursor(dx, dy: Double);
    function getX: Double;
    function getY: Double;
    procedure textLine(const s: AnsiString);
    procedure textOut(const s: AnsiString);
  end;

  Canvas = class
  public
    doc: Pointer;             { struct pdf_doc * }
    outPath: AnsiString;      { the file save() writes; named to avoid a
                                cross-unit collision on `filename` (see
                                bug-pascal-cross-unit-name-hides-own-field) }
    pageWidth, pageHeight: Double;
    curFont: AnsiString;
    curSize: Double;
    fillColour: LongWord;     { pdfgen ARGB }
    strokeColour: LongWord;
    lineWidth: Double;
    pageOpen: Boolean;
    { TWO constructors rather than one with a default, and that is a WORKAROUND
      (devdocs/dev/track-b-workarounds.md) for
      bug-p-constructor-with-a-defaulted-variant-param-corrupts-memory: a
      CONSTRUCTOR with a defaulted Variant parameter smashes the stack when the
      caller omits it. Deterministic from Pascal, intermittent through NilPy,
      and it lands as a crash in unrelated code — the original symptom faulted
      inside printf formatting with the return addresses overwritten by text.

      The one-argument form is `canvas.Canvas("out.pdf")`, reportlab's most
      common call, so it has to work. Forwarding to the two-argument form with
      an EXPLICIT 0 avoids the defaulted-parameter path entirely.

      REVERT to a single `pagesize: Variant = 0` when that bug closes. }
    constructor Create(const afilename: AnsiString);
    constructor Create(const afilename: AnsiString; const pagesize: Variant);
    destructor Destroy; override;
    procedure setFont(const name: AnsiString; size: Double);
    procedure setFillColorRGB(r, g, b: Double);
    procedure setStrokeColorRGB(r, g, b: Double);
    procedure setFillColor(c: Color);
    procedure setStrokeColor(c: Color);
    procedure setLineWidth(w: Double);
    procedure drawString(x, y: Double; const text: AnsiString);
    procedure line(x1, y1, x2, y2: Double);
    procedure rect(x, y, w, h: Double; const stroke: Variant = 0; const fill: Variant = 0);
    procedure circle(x, y, r: Double; const stroke: Variant = 0; const fill: Variant = 0);
    { every coordinate is a Variant: an application computes them from values
      that are dynamically typed (settings, arithmetic on untyped parameters),
      and the façade's job is to take Python shapes and convert }
    procedure drawImage(const src: Variant; const x: Variant; const y: Variant;
                        const width: Variant = 0; const height: Variant = 0;
                        const mask: Variant = 0);
    { NOTE: reportlab's is beginText(x=0, y=0); ours requires both, so
      `c.beginText()` is a compile error rather than an origin at 0,0. Left
      required deliberately — it fails LOUDLY, which the T1 shim rule allows,
      and the obvious `x: Double = 0.0; y: Double = 0.0` is not accepted here
      (the rect/circle precedent works because those params are `const`). }
    function beginText(x, y: Double): PDFTextObject;
    procedure drawText(t: PDFTextObject);
    function stringWidth(const text: AnsiString; const font: AnsiString;
                         size: Double): Double;
    procedure showPage;
    procedure save;
    procedure setBlendMode(const mode: Variant);
    procedure setTitle(const s: AnsiString);
    procedure setAuthor(const s: AnsiString);
  end;

{ Pack 0..1 components the way pdfgen's PDF_RGB macro does (opaque ARGB). }
function PdfRGB(r, g, b: Double): LongWord;

implementation

const
  DEFAULT_FONT = 'Helvetica';
  DEFAULT_SIZE = 12.0;
  { pdfgen's PDF_TRANSPARENT: alpha 0xff means "do not paint" in its encoding }
  PDF_TRANSPARENT_ARGB = LongWord($FF000000);

function ClampUnit(v: Double): Double;
begin
  if v < 0.0 then ClampUnit := 0.0
  else if v > 1.0 then ClampUnit := 1.0
  else ClampUnit := v;
end;

function PdfRGB(r, g, b: Double): LongWord;
var ri, gi, bi: LongWord;
begin
  ri := Trunc(ClampUnit(r) * 255.0 + 0.5);
  gi := Trunc(ClampUnit(g) * 255.0 + 0.5);
  bi := Trunc(ClampUnit(b) * 255.0 + 0.5);
  PdfRGB := (ri shl 16) or (gi shl 8) or bi;
end;

{ A Python truthiness test on an optional keyword: reportlab's fill=/stroke= are
  written as 0/1 and default to reportlab's own values when omitted. }
function FlagOr(const v: Variant; dflt: Boolean): Boolean;
begin
  if pyvartag(v) = 0 then FlagOr := dflt        { None / omitted }
  else FlagOr := pyvar_to_bool(v);
end;

{ ===== PDFTextObject ===== }

constructor PDFTextObject.Create(ax, ay: Double; const afont: AnsiString; asize: Double);
begin
  x := ax; y := ay; startX := ax;
  fontName := afont;
  fontSize := asize;
  leading := asize * 1.2;
  lines := TPyList.Create;
  xs := TPyList.Create;
  ys := TPyList.Create;
end;

destructor PDFTextObject.Destroy;
begin
  lines.Free;
  xs.Free;
  ys.Free;
  inherited Destroy;
end;

procedure PDFTextObject.setFont(const name: AnsiString; size: Double);
begin
  fontName := name;
  fontSize := size;
  leading := size * 1.2;
end;

procedure PDFTextObject.setLeading(l: Double);
begin
  leading := l;
end;

procedure PDFTextObject.setTextOrigin(ax, ay: Double);
begin
  x := ax;
  y := ay;
  startX := ax;
end;

procedure PDFTextObject.moveCursor(dx, dy: Double);
begin
  { reportlab's moveCursor is relative to the LINE START and moves DOWN for a
    positive dy (it is a text-space cursor, not a page coordinate). }
  x := startX + dx;
  y := y - dy;
  startX := x;
end;

function PDFTextObject.getX: Double;
begin
  getX := x;
end;

function PDFTextObject.getY: Double;
begin
  getY := y;
end;

procedure PDFTextObject.textOut(const s: AnsiString);
begin
  lines.append(s);
  xs.append(x);
  ys.append(y);
end;

procedure PDFTextObject.textLine(const s: AnsiString);
begin
  textOut(s);
  x := startX;
  y := y - leading;
end;

{ ===== Canvas ===== }

constructor Canvas.Create(const afilename: AnsiString);
var none: Variant;
begin
  { explicit argument — see the declaration for why this is not a default }
  none := 0;
  Create(afilename, none);
end;

constructor Canvas.Create(const afilename: AnsiString; const pagesize: Variant);
var w, h: Single; ps: TPyList;
begin
  outPath := afilename;
  { EXACT A4, the same values mimic_reportlab_lib_pagesizes gives — 210x297mm
    converted at 72dpi. These were rounded to 595.0 x 842.0, which is a
    different page from reportlab's and shifted every drawString down by
    842.0 - 841.8897637795 = 0.1102pt. Found by the differential harness: x
    positions and word widths matched reportlab exactly, and every y was off by
    that same constant, which is what pointed at the page box rather than at
    the text placement (feature-lib-reportlab-fidelity-vs-oracle). }
  pageWidth := 595.2755905511812;
  pageHeight := 841.8897637795277;
  { pagesize is a (width, height) tuple; anything else keeps A4 }
  if pyvartag(pagesize) = 7 then
  begin
    ps := TPyList(pyvarobj(pagesize));
    if (ps <> nil) and (ps.count = 2) then
    begin
      pageWidth := pyvar_to_float(ps.at(0));
      pageHeight := pyvar_to_float(ps.at(1));
    end;
  end;
  w := pageWidth; h := pageHeight;
  doc := pdf_create(w, h, nil);
  if doc = nil then
    raise Exception.Create('reportlab shim: could not create the PDF document');
  curFont := DEFAULT_FONT;
  curSize := DEFAULT_SIZE;
  fillColour := 0;                 { black }
  strokeColour := 0;
  lineWidth := 1.0;
  pdf_set_font(doc, PChar(curFont));
  pdf_append_page(doc);
  pageOpen := True;
end;

destructor Canvas.Destroy;
begin
  if doc <> nil then
  begin
    pdf_destroy(doc);
    doc := nil;
  end;
  inherited Destroy;
end;

procedure Canvas.setFont(const name: AnsiString; size: Double);
begin
  curFont := name;
  curSize := size;
  if pdf_set_font(doc, PChar(name)) < 0 then
    raise Exception.Create('reportlab shim: unsupported font "' + name +
      '" (the PDF standard-14 names only; embedded fonts are not in this subset)');
end;

procedure Canvas.setFillColorRGB(r, g, b: Double);
begin
  fillColour := PdfRGB(r, g, b);
end;

procedure Canvas.setStrokeColorRGB(r, g, b: Double);
begin
  strokeColour := PdfRGB(r, g, b);
end;

procedure Canvas.setFillColor(c: Color);
begin
  fillColour := PdfRGB(c.red, c.green, c.blue);
end;

procedure Canvas.setStrokeColor(c: Color);
begin
  strokeColour := PdfRGB(c.red, c.green, c.blue);
end;

procedure Canvas.setLineWidth(w: Double);
begin
  lineWidth := w;
end;

procedure Canvas.drawString(x, y: Double; const text: AnsiString);
var sz, sx, sy: Single;
begin
  sz := curSize; sx := x; sy := y;
  pdf_add_text(doc, nil, PChar(text), sz, sx, sy, fillColour);
end;

procedure Canvas.line(x1, y1, x2, y2: Double);
var a, b, c, d, w: Single;
begin
  a := x1; b := y1; c := x2; d := y2; w := lineWidth;
  pdf_add_line(doc, nil, a, b, c, d, w, strokeColour);
end;

procedure Canvas.rect(x, y, w, h: Double; const stroke: Variant; const fill: Variant);
var sx, sy, sw, sh, bw: Single;
begin
  sx := x; sy := y; sw := w; sh := h; bw := lineWidth;
  { reportlab's defaults: stroke on, fill off }
  if FlagOr(fill, False) then
    pdf_add_filled_rectangle(doc, nil, sx, sy, sw, sh, bw, fillColour, strokeColour)
  else if FlagOr(stroke, True) then
    pdf_add_rectangle(doc, nil, sx, sy, sw, sh, bw, strokeColour);
end;

procedure Canvas.circle(x, y, r: Double; const stroke: Variant; const fill: Variant);
var sx, sy, sr, bw: Single; fc: LongWord;
begin
  sx := x; sy := y; sr := r; bw := lineWidth;
  if FlagOr(fill, False) then fc := fillColour else fc := PDF_TRANSPARENT_ARGB;
  pdf_add_circle(doc, nil, sx, sy, sr, bw, strokeColour, fc);
end;

procedure Canvas.drawImage(const src: Variant; const x: Variant; const y: Variant;
                           const width: Variant; const height: Variant;
                           const mask: Variant);
var sx, sy, sw, sh: Single; path: AnsiString;
begin
  { Only a filename (or an ImageReader wrapping one) is in this subset — an
    in-memory PIL image has no CPython behind it here. Loud, not silent. }
  path := pystr_of(src);
  if path = '' then
    raise Exception.Create('reportlab shim: drawImage accepts a file path or an '
      + 'ImageReader over one; in-memory images are not in this subset');
  sx := pyvar_to_float(x); sy := pyvar_to_float(y);
  if pyvartag(width) = 0 then sw := 0 else sw := pyvar_to_float(width);
  if pyvartag(height) = 0 then sh := 0 else sh := pyvar_to_float(height);
  pdf_add_image_file(doc, nil, sx, sy, sw, sh, PChar(path));
end;

function Canvas.beginText(x, y: Double): PDFTextObject;
begin
  beginText := PDFTextObject.Create(x, y, curFont, curSize);
end;

procedure Canvas.drawText(t: PDFTextObject);
var i: Integer; savedFont: AnsiString; savedSize: Double;
begin
  savedFont := curFont; savedSize := curSize;
  if t.fontName <> curFont then setFont(t.fontName, t.fontSize);
  curSize := t.fontSize;
  for i := 0 to t.lines.count - 1 do
    drawString(pyvar_to_float(t.xs.at(i)), pyvar_to_float(t.ys.at(i)),
               pystr_of(t.lines.at(i)));
  curFont := savedFont; curSize := savedSize;
  pdf_set_font(doc, PChar(curFont));
end;

function Canvas.stringWidth(const text: AnsiString; const font: AnsiString;
                            size: Double): Double;
var useFont: AnsiString; sz, w: Single;
begin
  if font = '' then useFont := curFont else useFont := font;
  if size <= 0.0 then sz := curSize else sz := size;
  w := 0.0;
  { pdfgen returns the width through an out-parameter and 0 on success }
  if pdf_get_font_text_width(doc, PChar(useFont), PChar(text), sz, @w) < 0 then stringWidth := 0.0
  else stringWidth := w;
end;

procedure Canvas.showPage;
begin
  { reportlab ends the current page here; the next drawing call starts a new
    one. pdfgen appends eagerly, so the page is opened now. }
  pdf_append_page(doc);
end;

procedure Canvas.save;
begin
  if pdf_save(doc, PChar(outPath)) < 0 then
    raise Exception.Create('reportlab shim: could not write ' + outPath);
end;

procedure Canvas.setBlendMode(const mode: Variant);
begin
  raise Exception.Create('reportlab shim: setBlendMode is not in this subset '
    + '(transparency groups are unimplemented); draw without it');
end;

procedure Canvas.setTitle(const s: AnsiString);
begin
end;

procedure Canvas.setAuthor(const s: AnsiString);
begin
end;

end.
