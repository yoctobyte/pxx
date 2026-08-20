unit mimic_reportlab_pdfbase_pdfmetrics;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ `from reportlab.pdfbase.pdfmetrics import stringWidth` — the same measurement
  mimic_reportlab_pdfbase exposes as `pdfmetrics.stringWidth`, reachable under
  its full dotted module name because that is the other spelling real code uses
  (songformatter's render backend imports it this way to place words at their
  PDF metrics). One implementation, two import paths. }

interface

uses mimic_reportlab_pdfbase;

function stringWidth(const text: AnsiString; const fontName: AnsiString;
                     fontSize: Double): Double;

implementation

function stringWidth(const text: AnsiString; const fontName: AnsiString;
                     fontSize: Double): Double;
begin
  stringWidth := mimic_reportlab_pdfbase.stringWidth(text, fontName, fontSize);
end;

end.
