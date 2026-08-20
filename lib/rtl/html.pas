{ Python's `html`, the two functions programs actually call.

  NilPy maps `import X` onto the Pascal unit resolver, so a unit NAMED for the
  module IS the module — see devdocs/dev/python-compat-tiers.md.

  THE SUBSET:
    html.escape(s, quote=True)   -> &, <, > always; " and ' when quote is true,
                                    exactly as CPython does (and in that order,
                                    so an escaped & is not re-escaped).
    html.unescape(s)             -> the five named entities escape produces,
                                    plus the numeric forms &#NN; / &#xHH;.
  Not here: the full HTML5 named-entity table (2231 names), which unescape()
  covers in CPython. An unknown entity is left VERBATIM rather than guessed at,
  which is also what a browser does with an unrecognised one.

  Defers to feature-nilpy-py-module-loader (T3). }
unit html;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
interface

{ Two ARITIES rather than one defaulted parameter: a unit-QUALIFIED call from
  NilPy (`html.escape(s)`) does not fill a Pascal default, so the one-argument
  form has to exist as its own overload — the same shape TPyDict.get uses for
  `get(k)` / `get(k, d)`. }
function escape(const s: AnsiString): AnsiString; overload;
function escape(const s: AnsiString; quote: Boolean): AnsiString; overload;
function unescape(const s: AnsiString): AnsiString;

implementation

function escape(const s: AnsiString): AnsiString;
begin
  escape := escape(s, True);
end;

function escape(const s: AnsiString; quote: Boolean): AnsiString;
var i: Integer; r: AnsiString; c: Char;
begin
  r := '';
  for i := 1 to Length(s) do
  begin
    c := s[i];
    { & FIRST — replacing it after the others would re-escape their own & }
    if c = '&' then r := r + '&amp;'
    else if c = '<' then r := r + '&lt;'
    else if c = '>' then r := r + '&gt;'
    else if quote and (c = '"') then r := r + '&quot;'
    else if quote and (c = '''') then r := r + '&#x27;'
    else r := r + c;
  end;
  escape := r;
end;

function HtmlHexVal(c: Char): Integer;
begin
  if (c >= '0') and (c <= '9') then HtmlHexVal := Ord(c) - Ord('0')
  else if (c >= 'a') and (c <= 'f') then HtmlHexVal := Ord(c) - Ord('a') + 10
  else if (c >= 'A') and (c <= 'F') then HtmlHexVal := Ord(c) - Ord('A') + 10
  else HtmlHexVal := -1;
end;

function unescape(const s: AnsiString): AnsiString;
var i, j, v, d: Integer; r, name: AnsiString; ok: Boolean;
begin
  r := '';
  i := 1;
  while i <= Length(s) do
  begin
    if s[i] <> '&' then
    begin
      r := r + s[i];
      Inc(i);
      Continue;
    end;
    { find the terminating ';' within a sane distance }
    j := i + 1;
    while (j <= Length(s)) and (j - i <= 10) and (s[j] <> ';') do Inc(j);
    if (j > Length(s)) or (s[j] <> ';') then
    begin
      r := r + s[i];
      Inc(i);
      Continue;
    end;
    name := Copy(s, i + 1, j - i - 1);
    ok := True;
    if name = 'amp' then r := r + '&'
    else if name = 'lt' then r := r + '<'
    else if name = 'gt' then r := r + '>'
    else if name = 'quot' then r := r + '"'
    else if name = 'apos' then r := r + ''''
    else if (Length(name) > 1) and (name[1] = '#') then
    begin
      v := 0;
      if (Length(name) > 2) and ((name[2] = 'x') or (name[2] = 'X')) then
      begin
        for d := 3 to Length(name) do
        begin
          if HtmlHexVal(name[d]) < 0 then ok := False
          else v := v * 16 + HtmlHexVal(name[d]);
        end;
      end
      else
      begin
        for d := 2 to Length(name) do
        begin
          if (name[d] < '0') or (name[d] > '9') then ok := False
          else v := v * 10 + (Ord(name[d]) - Ord('0'));
        end;
      end;
      { only the Latin-1 range is spelled back as one byte; anything wider would
        need the UTF-8 encoder and is left verbatim rather than truncated }
      if ok and (v > 0) and (v < 256) then r := r + Chr(v) else ok := False;
    end
    else
      ok := False;
    if not ok then
    begin
      { an entity this subset does not know: leave it EXACTLY as written, which
        is what a browser does with an unrecognised one }
      r := r + Copy(s, i, j - i + 1);
    end;
    i := j + 1;
  end;
  unescape := r;
end;

end.
