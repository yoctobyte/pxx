unit mimic_reportlab_pdfbase;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ `from reportlab.pdfbase import pdfmetrics` — text measurement. The one call an
  application makes is `pdfmetrics.stringWidth(text, fontName, fontSize)`, which
  the backend answers from the PDF standard-14 metrics it already carries.
  A T1 name shim; see mimic_reportlab_pdfgen for the policy.

  NOT here: registerFont / TTFont (embedded TrueType), font subsetting, the
  Font/Encoding object model. }

interface

{ pxxcio supplies the heap bridge the C backend allocates through —
  without it the link leaves __pxx_malloc unresolved. }
uses pxxcio, pylib, '../vendor/pdfgen/pdfgen.c';

function stringWidth(const text: AnsiString; const fontName: AnsiString;
                     fontSize: Double): Double;

{ The names an application may select. reportlab returns everything registered,
  which for a build with no registerFont() call is the PDF standard-14 set —
  and registering a TrueType font is outside this subset, so that is the whole
  list. songformatter checks membership before accepting a font directive. }
function getRegisteredFontNames: TPyList;

implementation

var
  MetricsDoc: Pointer;   { a scratch document: pdfgen's metrics need one }

function stringWidth(const text: AnsiString; const fontName: AnsiString;
                     fontSize: Double): Double;
var sz, w: Single;
begin
  { An EMPTY string is zero wide, and asking pdfgen would crash: an empty
    AnsiString is a nil handle here, so the `const char *` parameter arrives as
    NULL and the C walks it. songformatter measures the empty prefix before
    placing the first word of every line, which is how a live preview turned
    into a SIGSEGV on the first string it drew. }
  if (Length(text) = 0) or (Length(fontName) = 0) then
  begin
    stringWidth := 0.0;
    exit;
  end;
  sz := fontSize;
  w := 0.0;
  { the width comes back through an out-parameter; the result is a status }
  if pdf_get_font_text_width(MetricsDoc, fontName, text, sz, @w) < 0 then
    stringWidth := 0.0
  else
    stringWidth := w;
end;

function getRegisteredFontNames: TPyList;
var r: TPyList;
begin
  r := TPyList.Create;
  r.append('Courier');
  r.append('Courier-Bold');
  r.append('Courier-Oblique');
  r.append('Courier-BoldOblique');
  r.append('Helvetica');
  r.append('Helvetica-Bold');
  r.append('Helvetica-Oblique');
  r.append('Helvetica-BoldOblique');
  r.append('Times-Roman');
  r.append('Times-Bold');
  r.append('Times-Italic');
  r.append('Times-BoldItalic');
  r.append('Symbol');
  r.append('ZapfDingbats');
  getRegisteredFontNames := r;
end;

initialization
  MetricsDoc := pdf_create(595.0, 842.0, nil);
end.
