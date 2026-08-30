unit mimic_string;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `string` module — the constants and `capwords`.

  It exists first of all so that `import string` in a `.npy` stops resolving to
  the C header `string.h`. A NilPy import may legitimately name a C header (the
  wrapper-free NilPy-to-C arc: `import sqlite3`, `import stdlib`), and the
  resolver tries a `mimic_` shim BEFORE a host header for exactly this reason —
  but that ordering is inert while no shim of the name exists, so `import
  string` pulled /usr/include/string.h and the failure surfaced later as
  `undefined variable (ascii_lowercase)`, pointing at the attribute instead of
  at the import. bug-nilpy-python-import-resolves-against-c-headers

  Values are CPython's own, verified against 3.12 rather than typed from
  memory — `punctuation` in particular is easy to get subtly wrong (it is
  ASCII 33..47, 58..64, 91..96, 123..126, in that order) and nothing would
  notice until a tokeniser behaved differently.

  `whitespace` is space, tab, newline, carriage return, vertical tab, formfeed —
  written by code point, since three of the six have no readable spelling in a
  Pascal string literal. }

interface

const
  ascii_lowercase: AnsiString = 'abcdefghijklmnopqrstuvwxyz';
  ascii_uppercase: AnsiString = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  ascii_letters: AnsiString =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  digits: AnsiString = '0123456789';
  hexdigits: AnsiString = '0123456789abcdefABCDEF';
  octdigits: AnsiString = '01234567';
  punctuation: AnsiString = '!"#$%&' + #39 + '()*+,-./:;<=>?@[\]^_`{|}~';
  whitespace: AnsiString = ' ' + #9 + #10 + #13 + #11 + #12;
  { digits + letters + punctuation + whitespace, IN THAT ORDER — CPython builds
    it by concatenation and code compares against it, so the order is part of
    the value. Spelled out rather than concatenated from the constants above,
    because a const expression over other AnsiString consts is not something to
    rely on here. }
  printable: AnsiString =
    '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ' +
    '!"#$%&' + #39 + '()*+,-./:;<=>?@[\]^_`{|}~' + ' ' + #9 + #10 + #13 + #11 + #12;

type
  { `string.Template` — the `$`-placeholder class.

    THE MAPPING FORM ONLY, AND THAT IS FORCED RATHER THAN PREFERRED.
    CPython's signature is `substitute(self, mapping, /, **kws)` with an empty
    default mapping, so both `t.substitute(<dict>)` and `t.substitute(who=...)`
    are valid
    there. Only the first is expressible here, because NilPy binds a keyword
    argument to a DECLARED PARAMETER NAME, and a Template's keyword names are
    the caller's own placeholders — unknown when this unit is compiled. There
    is no parameter for `who` to bind to, so the literal-keyword form is
    rejected at compile time with

      error: Nil Python: Template.substitute has no parameter named 'who'

    which is the loud failure python-compat-tiers.md asks for: state the subset,
    fail outside it, never approximate. The mapping form is not a lesser
    substitute — it is ordinary CPython and equals the keyword form exactly.

    `t.substitute(**values)` — the spelling `logging.StringTemplateStyle` uses —
    is ALSO rejected today, but for an unrelated reason that is not about this
    class: `**` unpacking is a parse error at ANY method call in this dialect,
    pure-Python classes included. Filed as
    bug-n-double-star-unpacking-is-rejected-at-a-method-call (Track N). When
    that closes, `**values` will reach `mapping` as a dict and this class needs
    no change — which is why the parameter is a Variant dict and not something
    narrower.

    Behaviour below was derived by DIFFING CPython 3.12, not from the docs, on
    this module's own precedent: `capwords(s, sep)` looked like a variation of
    `capwords(s)` and is a different function, and three of five edge cases
    would have shipped wrong from the plausible reading. Two here would have
    too, and neither is in the prose documentation:

      - `safe_substitute` KEEPS THE BRACES on an unresolved braced
        placeholder: the dollar, the braces AND the name all survive, rather
        than collapsing to the bare `$who` form. The braced and bare forms are
        not normalised to each other on the way out.

        (This comment spells braces in WORDS throughout, and that is not
        squeamishness: comments in this dialect NEST, so a literal open-brace
        in prose opens a second comment that never closes, and a literal
        close-brace ends the first one early — quotes protect neither. Both
        failed here, the open-brace one reporting `unterminated comment` 48
        lines above the character that caused it. The test file carries the
        real spellings, where they are ordinary Python strings.)
      - an unterminated braced placeholder — an opening brace and a name with
        no closing brace — is a ValueError from `substitute` EVEN WHEN that
        name IS present in the mapping. The placeholder is malformed, and
        CPython never looks the key up.

    `delimiter` and `idpattern` are CPython class attributes and are
    deliberately NOT overridable here — out of scope for a first cut, said
    plainly rather than left ambiguous. }
  Template = class
  public
    template: AnsiString;
    constructor Create(const tpl: AnsiString);
    { the one scanner behind both public methods; `safe` selects only the
      failure behaviour, so the placeholder rules cannot drift between them }
    function Render(const mapping: Variant; safe: Boolean): AnsiString;
    { raises KeyError for a missing key, ValueError for a malformed placeholder }
    function substitute(const mapping: Variant): AnsiString;
    { raises neither; leaves the original text of anything it cannot resolve }
    function safe_substitute(const mapping: Variant): AnsiString;
  end;

{ `string.capwords(s)` — split on whitespace, capitalise each word, join with a
  single space. NOT the same as `s.title()`, which upper-cases after every
  non-letter: `capwords("don't")` is "Don't" while `"don't".title()` is
  "Don'T". Python ships both for that reason, so the difference is the point of
  having this. }
function capwords(const s: AnsiString): AnsiString; overload;

{ `string.capwords(s, sep)` — a DIFFERENT function, not a variation. CPython is
  `(sep or ' ').join(map(str.capitalize, s.split(sep)))`, and with an explicit
  sep the split neither collapses runs nor strips: measured against 3.12,
  capwords('a--b', '-') is 'A--B' and capwords('-a-', '-') is '-A-', where the
  no-sep form would have dropped the empty fields. sep may be multi-character
  ('a__b', '__' -> 'A__B').

  Each field goes through str.capitalize(), which upper-cases the first
  character and LOWER-CASES THE REST — so capwords('a b-c d', '-') is
  'A b-C d', with the b after the space left alone because it is not the start
  of a field. }
function capwords(const s, sep: AnsiString): AnsiString; overload;

implementation

uses pylib, sysutils;

{ ---------------------------------------------------------------- Template }

constructor Template.Create(const tpl: AnsiString);
begin
  template := tpl;
end;

{ CPython's idpattern is `(?a:[_a-z][_a-z0-9]*)` under re.IGNORECASE, i.e.
  ASCII-only and case-insensitive — so `[_A-Za-z][_A-Za-z0-9]*`. The scan is
  greedy: `$x_y` with both `x_y` and `x` in the mapping resolves `x_y`. }
function IsIdentStart(c: Char): Boolean;
begin
  IsIdentStart := (c = '_') or ((c >= 'a') and (c <= 'z'))
                            or ((c >= 'A') and (c <= 'Z'));
end;

function IsIdentCont(c: Char): Boolean;
begin
  IsIdentCont := IsIdentStart(c) or ((c >= '0') and (c <= '9'));
end;

function DictOf(const m: Variant): TPyDict;
begin
  DictOf := nil;
  if pyvar_is_objtag(m) then
    if TObject(pyvarobj(m)) is TPyDict then
      DictOf := TPyDict(pyvarobj(m));
end;

{ The ONE scanner behind both methods, with `safe` selecting only what happens
  on the two failure paths. Written once deliberately: substitute and
  safe_substitute differ *solely* in their handling of a missing key and a
  malformed placeholder, and two parallel scanners would be two places for the
  dollar-dollar, empty-braces and greedy-identifier rules to drift apart. }
function Template.Render(const mapping: Variant; safe: Boolean): AnsiString;
var
  i, n, start: Integer;
  d: TPyDict;
  name: AnsiString;
  braced: Boolean;
  openAt: Integer;
begin
  Result := '';
  d := DictOf(mapping);
  n := Length(template);
  i := 1;
  while i <= n do
  begin
    if template[i] <> '$' then
    begin
      Result := Result + template[i];
      Inc(i);
      Continue;
    end;

    { `$$` is a literal '$' and is consumed WHOLE — it is not a placeholder
      introducer, so `$$who` is the text "$who" and never a lookup of `who`. }
    if (i < n) and (template[i + 1] = '$') then
    begin
      Result := Result + '$';
      i := i + 2;
      Continue;
    end;

    openAt := i;   { where this placeholder began, for the safe-path copy }
    braced := (i < n) and (template[i + 1] = '{');

    if braced then
    begin
      start := i + 2;
      if (start <= n) and IsIdentStart(template[start]) then
      begin
        i := start + 1;
        while (i <= n) and IsIdentCont(template[i]) do Inc(i);
        { the closing brace must be there. An opening brace and a name with
          no closing brace is malformed EVEN IF that name is in the mapping —
          CPython never reaches the lookup. }
        if (i <= n) and (template[i] = '}') then
        begin
          name := Copy(template, start, i - start);
          Inc(i);            { step past the closing brace }
        end
        else
          name := '';        { unterminated -> malformed }
      end
      else
        name := '';          { empty braces, or a digit first -> malformed }
    end
    else
    begin
      start := i + 1;
      if (start <= n) and IsIdentStart(template[start]) then
      begin
        i := start + 1;
        while (i <= n) and IsIdentCont(template[i]) do Inc(i);
        name := Copy(template, start, i - start);
      end
      else
        name := '';          { a bare '$' at end, or '$ ', or '$1abc' }
    end;

    if name = '' then
    begin
      { malformed placeholder }
      if safe then
      begin
        { copy the '$' alone and resume AFTER it, so the rest of the text is
          rescanned normally — CPython's safe_substitute leaves '$' in place
          and carries on, which is why '$ ' stays '$ ' rather than being eaten. }
        Result := Result + '$';
        i := openAt + 1;
      end
      else
        raise ValueError.Create('Invalid placeholder in string: line 1, col ' +
                                IntToStr(openAt));
      Continue;
    end;

    if (d <> nil) and (d.indexof(name) >= 0) then
      Result := Result + pystr_of(d.fetch(name))
    else
    begin
      if safe then
        { the ORIGINAL text, braces included: a braced placeholder keeps its
          dollar, its braces AND its name, and does NOT collapse to the bare
          dollar-name form }
        Result := Result + Copy(template, openAt, i - openAt)
      else
        raise KeyError.Create(name);
    end;
  end;
end;

function Template.substitute(const mapping: Variant): AnsiString;
begin
  substitute := Render(mapping, False);
end;

function Template.safe_substitute(const mapping: Variant): AnsiString;
begin
  safe_substitute := Render(mapping, True);
end;

{ first char up, the rest down — str.capitalize(), shared by both forms }
function CapitalizeField(const w: AnsiString): AnsiString;
var k: Integer;
begin
  Result := w;
  if Length(Result) = 0 then Exit;
  if (Result[1] >= 'a') and (Result[1] <= 'z') then
    Result[1] := Chr(Ord(Result[1]) - 32);
  for k := 2 to Length(Result) do
    if (Result[k] >= 'A') and (Result[k] <= 'Z') then
      Result[k] := Chr(Ord(Result[k]) + 32);
end;

function capwords(const s, sep: AnsiString): AnsiString;
var i, start, sl, n: Integer; first: Boolean;
begin
  Result := '';
  sl := Length(sep);
  n := Length(s);
  if sl = 0 then begin Result := CapitalizeField(s); Exit; end;
  first := True;
  start := 1;
  i := 1;
  while i <= n - sl + 1 do
  begin
    if Copy(s, i, sl) = sep then
    begin
      if not first then Result := Result + sep;
      Result := Result + CapitalizeField(Copy(s, start, i - start));
      first := False;
      i := i + sl;
      start := i;
    end
    else Inc(i);
  end;
  { the final field, which is '' when s ends with sep — and CPython keeps it }
  if not first then Result := Result + sep;
  Result := Result + CapitalizeField(Copy(s, start, n - start + 1));
end;

function capwords(const s: AnsiString): AnsiString;
var i, k, n: Integer; word: AnsiString; first: Boolean;
begin
  Result := '';
  first := True;
  i := 1;
  n := Length(s);
  while i <= n do
  begin
    { skip the run of whitespace — capwords collapses it, which is why the
      result is joined with a single space rather than rebuilt in place }
    while (i <= n) and ((s[i] = ' ') or (s[i] = #9) or (s[i] = #10) or
                        (s[i] = #13) or (s[i] = #11) or (s[i] = #12)) do Inc(i);
    if i > n then Break;
    word := '';
    while (i <= n) and not ((s[i] = ' ') or (s[i] = #9) or (s[i] = #10) or
                            (s[i] = #13) or (s[i] = #11) or (s[i] = #12)) do
    begin
      word := word + s[i];
      Inc(i);
    end;
    { capitalise: first character up, the REST DOWN — `capwords("HELLO")` is
      "Hello", not "HELLO" }
    if Length(word) > 0 then
    begin
      if (word[1] >= 'a') and (word[1] <= 'z') then
        word[1] := Chr(Ord(word[1]) - 32);
      { `k`, not `i` — `i` is the OUTER scan position and reusing it here
        would restart the scan inside the word just consumed. }
      for k := 2 to Length(word) do
        if (word[k] >= 'A') and (word[k] <= 'Z') then
          word[k] := Chr(Ord(word[k]) + 32);
    end;
    if not first then Result := Result + ' ';
    Result := Result + word;
    first := False;
  end;
end;

end.
