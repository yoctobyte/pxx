unit mimic_reportlab_lib_utils;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ `from reportlab.lib.utils import ImageReader` — reportlab's wrapper around an
  image source, which a Canvas accepts wherever a filename would do.

  THE SUBSET: a filename. reportlab's ImageReader also takes a file object, a URL
  or a PIL image; here the backend embeds a file (pdfgen reads PNG/JPEG/BMP
  itself), so a non-path source fails loudly at drawImage rather than drawing
  nothing. A T1 name shim; see mimic_reportlab_pdfgen for the policy. }

interface

type
  ImageReader = class
  public
    fileName: AnsiString;
    constructor Create(const source: AnsiString);
    function getSize: AnsiString;
    function __str__: AnsiString;
  end;

implementation

constructor ImageReader.Create(const source: AnsiString);
begin
  fileName := source;
end;

function ImageReader.getSize: AnsiString;
begin
  { pdfgen measures the image itself when it embeds it; reportlab's callers use
    getSize to scale beforehand, which this subset does not support }
  getSize := '';
end;

function ImageReader.__str__: AnsiString;
begin
  { drawImage takes the path out of the object through its string form }
  __str__ := fileName;
end;

end.
