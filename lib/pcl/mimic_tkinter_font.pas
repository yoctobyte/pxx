unit mimic_tkinter_font;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ `import tkinter.font as tkfont` — Tk's fonts.
  THE SUBSET: `Font(family=, size=, weight=, slant=)` or `Font(font=<spec>)`,
  then .measure(text) (pixel width, how a label is ellipsised or a column
  sized), .metrics(what) (ascent/descent/linespace) and .actual(option). A Font
  is also accepted as any widget's `font=` (tkinter.pas reads `spec`).
  The spec is a Tk font description -- `{DejaVu Sans} 11 bold` -- handed
  straight to Tk's `font` command, so nothing is reinterpreted here. CPython
  creates a NAMED Tk font; this keeps the description instead, which measures
  and draws the same. NOT here: configure() on a live font (a named font
  would redraw every widget using it), families(), names(). }

interface

uses tk, pylib;

type
  Font = class
  public
    spec: AnsiString;
    { `root=` is the widget the font is measured against. Tk measures against
      the interpreter, not the widget, so it is accepted and unused — an
      application passes it because CPython's tkinter wants it.
      `font=` is a spec string or the (family, size, style...) tuple;
      family/size/weight/slant build one when it is absent. }
    constructor Create(root: Variant = 0; const font: Variant = 0;
                       const family: AnsiString = ''; size: Integer = 0;
                       const weight: AnsiString = '';
                       const slant: AnsiString = '');
    { metrics("descent") / ("ascent") / ("linespace") — the pixel counts Tk
      reports for this font. }
    function metrics(const what: AnsiString): Integer;
    { the width in pixels `text` takes in this font }
    function measure(const text: AnsiString): Integer;
    { actual("family") / ("size") / ("weight"): what Tk resolved the spec to }
    function actual(const option: AnsiString): AnsiString;
  end;

{ A font option's Tk words from a spec string or a (family, size, style...)
  tuple: each string element braced, so a family with a space stays one word. }
function TkFontSpecOf(const f: Variant): AnsiString;

implementation

function TkFontIntStr(v: Int64): AnsiString;
var neg: Boolean;
begin
  Result := '';
  neg := v < 0;
  if neg then v := -v;
  repeat
    Result := Chr(Ord('0') + (v mod 10)) + Result;
    v := v div 10;
  until v = 0;
  if neg then Result := '-' + Result;
end;

function TkFontSpecOf(const f: Variant): AnsiString;
var l: TPyList; i: Integer; el: Variant;
begin
  Result := '';
  case pyvartag(f) of
    5, 6: Result := pystr_of(f);
    7:
      begin
        if TObject(pyvarobj(f)) is Font then
        begin
          Result := Font(pyvarobj(f)).spec;
          Exit;
        end;
        if not (TObject(pyvarobj(f)) is TPyList) then Exit;
        l := TPyList(pyvarobj(f));
        for i := 0 to l.count - 1 do
        begin
          if i > 0 then Result := Result + ' ';
          el := l.at(i);
          if (pyvartag(el) = 5) or (pyvartag(el) = 6) then
            Result := Result + '{' + pystr_of(el) + '}'
          else Result := Result + TkFontIntStr(pyvar_to_int(el));
        end;
      end;
  end;
end;

constructor Font.Create(root: Variant; const font: Variant;
                        const family: AnsiString; size: Integer;
                        const weight, slant: AnsiString);
begin
  spec := TkFontSpecOf(font);
  if spec <> '' then Exit;
  if family <> '' then spec := '{' + family + '}' else spec := 'TkDefaultFont';
  if size <> 0 then spec := spec + ' ' + TkFontIntStr(size)
  else if (weight <> '') or (slant <> '') then spec := spec + ' 0';
  if weight <> '' then spec := spec + ' ' + weight;
  if slant <> '' then spec := spec + ' ' + slant;
end;

function TkFontStrInt(const r: AnsiString): Integer;
var i, v: Integer; neg: Boolean;
begin
  v := 0; neg := False;
  for i := 1 to Length(r) do
  begin
    if (i = 1) and (r[i] = '-') then neg := True
    else if r[i] in ['0'..'9'] then v := v * 10 + (Ord(r[i]) - Ord('0'))
    else Break;
  end;
  if neg then Result := -v else Result := v;
end;

function Font.metrics(const what: AnsiString): Integer;
begin
  metrics := 0;
  if spec = '' then Exit;
  { Tk answers a bare integer here }
  metrics := TkFontStrInt(TkEval('font metrics {' + spec + '} -' + what));
end;

function Font.measure(const text: AnsiString): Integer;
begin
  measure := TkFontStrInt(TkEval('font measure {' + spec + '} {' + text + '}'));
end;

function Font.actual(const option: AnsiString): AnsiString;
begin
  actual := TkEval('font actual {' + spec + '} -' + option);
end;

end.
