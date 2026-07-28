unit mimic_reportlab_pdfbase;
{ `from reportlab.pdfbase import pdfmetrics` — text measurement. The one call an
  application makes is `pdfmetrics.stringWidth(text, fontName, fontSize)`, which
  the backend answers from the PDF standard-14 metrics it already carries.
  A T1 name shim; see mimic_reportlab_pdfgen for the policy.

  NOT here: registerFont / TTFont (embedded TrueType), font subsetting, the
  Font/Encoding object model. }

interface

uses '../vendor/pdfgen/pdfgen.c';

function stringWidth(const text: AnsiString; const fontName: AnsiString;
                     fontSize: Double): Double;

implementation

var
  MetricsDoc: Pointer;   { a scratch document: pdfgen's metrics need one }

function stringWidth(const text: AnsiString; const fontName: AnsiString;
                     fontSize: Double): Double;
var sz, w: Single;
begin
  sz := fontSize;
  w := 0.0;
  { the width comes back through an out-parameter; the result is a status }
  if pdf_get_font_text_width(MetricsDoc, fontName, text, sz, @w) < 0 then
    stringWidth := 0.0
  else
    stringWidth := w;
end;

initialization
  MetricsDoc := pdf_create(595.0, 842.0, nil);
end.
