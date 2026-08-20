unit mimic_tkinter_font;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ `import tkinter.font as tkfont` — Tk's font measurement.

  THE SUBSET: `Font(root=..., font=<spec>).metrics(<what>)`, which is how an
  application asks Tk for a font's ascent/descent/linespace. The spec is
  whatever Tk itself accepts — a font name, or a `{family} size style` list —
  and it is handed straight to `font metrics`, so nothing is reinterpreted here.

  NOT here: font CREATION with family/size/weight keywords, .measure(), .actual(),
  families(), names(). Each would be a line of Tcl; they are left out until
  something needs them rather than guessed at. }

interface

uses tk, pylib;

type
  Font = class
  public
    spec: AnsiString;
    { `root=` is the widget the font is measured against. Tk measures against
      the interpreter, not the widget, so it is accepted and unused — an
      application passes it because CPython's tkinter wants it. }
    constructor Create(root: Variant; const font: AnsiString);
    { metrics("descent") / ("ascent") / ("linespace") — the pixel counts Tk
      reports for this font. }
    function metrics(const what: AnsiString): Integer;
  end;

implementation

constructor Font.Create(root: Variant; const font: AnsiString);
begin
  spec := font;
end;

function Font.metrics(const what: AnsiString): Integer;
var r: AnsiString; i, v: Integer; neg: Boolean;
begin
  metrics := 0;
  if spec = '' then Exit;
  r := TkEval('font metrics {' + spec + '} -' + what);
  { Tk answers a bare integer here }
  v := 0; neg := False;
  for i := 1 to Length(r) do
  begin
    if (i = 1) and (r[i] = '-') then neg := True
    else if r[i] in ['0'..'9'] then v := v * 10 + (Ord(r[i]) - Ord('0'))
    else Break;
  end;
  if neg then metrics := -v else metrics := v;
end;

end.
