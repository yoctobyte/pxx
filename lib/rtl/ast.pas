{ SPDX-License-Identifier: Zlib }
unit ast;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `ast` module for the Nil-Python frontend — the `literal_eval` slice.

  Named `ast` so `import ast` needs no frontend change: NilPy turns `import X`
  into the unit resolver's `uses X`, so `ast.literal_eval(s)` resolves through
  ordinary unit scoping (same construction as lib/rtl/re.pas).

  WHAT THIS IS. `literal_eval` only — the safe evaluator for a string holding a
  Python LITERAL, which is what real programs reach for `ast` for (settings
  files, config values, a repr() round-trip). songformatter's driver is a colour
  written back as `str([0.7, 0.7, 0.5])` and read as a list of floats.

  Grammar accepted, which is CPython's for literal_eval minus the parts nothing
  needs yet: numbers (int and float, with a leading sign), strings ('...' and
  "..."), True / False / None, lists, tuples, dicts, and nesting of those. NOT
  accepted, and refused loudly rather than guessed: sets, complex numbers, the
  `+`/`-` binary form CPython allows for complex, and f-strings. The full
  `ast` module — parse(), NodeVisitor, the node classes — is a different and
  much larger thing; it is not here and this unit does not pretend otherwise
  (feature-nilpy-ast-module would be that).

  A parse error raises, as CPython does (ValueError / SyntaxError there; one
  exception type here, carrying the offending text). }

interface

uses pylib, sysutils;

{ `ast.literal_eval(s)` — the value the literal denotes. A list or tuple comes
  back as a TPyList and a dict as a TPyDict, boxed in the variant, which is what
  the rest of NilPy already uses for those. }
function literal_eval(const s: AnsiString): Variant;

implementation

var
  gSrc: AnsiString;
  gPos: Integer;

{ Box a container into the variant the caller receives. pylib does this inline
  wherever it builds one (VT_OBJECT = tag 7, payload = the instance pointer,
  plus the retain that makes the slot an owner); there is no exported helper
  for it, so the same three lines live here. }
function BoxObj(o: TObject): Variant;
begin
  PPyVarRec(@Result)^.VType := 7;
  PPyVarRec(@Result)^.Payload := Int64(NativeInt(Pointer(o)));
  PXXObjRetain(Pointer(o));
end;

procedure LitError(const what: AnsiString);
begin
  raise Exception.Create('ast.literal_eval: ' + what + ' in ' + gSrc);
end;

procedure SkipWs;
begin
  while (gPos <= Length(gSrc)) and
        ((gSrc[gPos] = ' ') or (gSrc[gPos] = #9) or (gSrc[gPos] = #10) or
         (gSrc[gPos] = #13)) do
    Inc(gPos);
end;

function ParseValue: Variant; forward;

{ A quoted string. Python's escapes that matter for a literal round-trip: the
  quote itself, a backslash, and the three whitespace ones. An unknown escape
  keeps the character, which is what CPython does for a non-escape in a plain
  (non-raw) string too. }
function ParseStr: AnsiString;
var q: Char;
begin
  Result := '';
  q := gSrc[gPos];
  Inc(gPos);
  while (gPos <= Length(gSrc)) and (gSrc[gPos] <> q) do
  begin
    if (gSrc[gPos] = '\') and (gPos < Length(gSrc)) then
    begin
      Inc(gPos);
      case gSrc[gPos] of
        'n': Result := Result + #10;
        't': Result := Result + #9;
        'r': Result := Result + #13;
      else
        Result := Result + gSrc[gPos];
      end;
    end
    else
      Result := Result + gSrc[gPos];
    Inc(gPos);
  end;
  if gPos > Length(gSrc) then LitError('unterminated string');
  Inc(gPos);                                  { the closing quote }
end;

{ An int or a float. The distinction is Python's: a '.' or an exponent makes it
  a float, and the two must stay apart because a caller doing arithmetic on the
  result sees the difference. }
function ParseNum: Variant;
var start: Integer; txt: AnsiString; isFloat: Boolean;
begin
  start := gPos;
  isFloat := False;
  if (gPos <= Length(gSrc)) and ((gSrc[gPos] = '-') or (gSrc[gPos] = '+')) then Inc(gPos);
  while gPos <= Length(gSrc) do
  begin
    if (gSrc[gPos] >= '0') and (gSrc[gPos] <= '9') then Inc(gPos)
    else if gSrc[gPos] = '.' then begin isFloat := True; Inc(gPos); end
    else if (gSrc[gPos] = 'e') or (gSrc[gPos] = 'E') then
    begin
      isFloat := True;
      Inc(gPos);
      if (gPos <= Length(gSrc)) and ((gSrc[gPos] = '-') or (gSrc[gPos] = '+')) then Inc(gPos);
    end
    else
      Break;
  end;
  txt := Copy(gSrc, start, gPos - start);
  if (txt = '') or (txt = '-') or (txt = '+') then LitError('expected a number');
  if isFloat then Result := StrToFloat(txt) else Result := StrToInt64(txt);
end;

function ParseSeq(closer: Char): TPyList;
var v: Variant;
begin
  Result := TPyList.Create;
  Inc(gPos);                                  { the opening bracket }
  SkipWs;
  while (gPos <= Length(gSrc)) and (gSrc[gPos] <> closer) do
  begin
    v := ParseValue;
    Result.append(v);
    SkipWs;
    if (gPos <= Length(gSrc)) and (gSrc[gPos] = ',') then
    begin
      Inc(gPos);
      SkipWs;
    end
    else if (gPos <= Length(gSrc)) and (gSrc[gPos] <> closer) then
      LitError('expected , or a closing bracket');
  end;
  if gPos > Length(gSrc) then LitError('unterminated sequence');
  Inc(gPos);                                  { the closer }
end;

function ParseDict: TPyDict;
var k, v: Variant;
begin
  Result := TPyDict.Create;
  Inc(gPos);                                  { the opening brace }
  SkipWs;
  while (gPos <= Length(gSrc)) and (gSrc[gPos] <> '}') do
  begin
    k := ParseValue;
    SkipWs;
    if (gPos > Length(gSrc)) or (gSrc[gPos] <> ':') then LitError('expected :');
    Inc(gPos);
    SkipWs;
    v := ParseValue;
    Result.setitem(k, v);
    SkipWs;
    if (gPos <= Length(gSrc)) and (gSrc[gPos] = ',') then
    begin
      Inc(gPos);
      SkipWs;
    end
    else if (gPos <= Length(gSrc)) and (gSrc[gPos] <> '}') then
      LitError('expected a comma or a closing brace');
  end;
  if gPos > Length(gSrc) then LitError('unterminated dict');
  Inc(gPos);                                  { the closing brace }
end;

function ParseValue: Variant;
var l: TPyList; d: TPyDict; c: Char;
begin
  SkipWs;
  if gPos > Length(gSrc) then LitError('unexpected end');
  c := gSrc[gPos];
  if (c = '''') or (c = '"') then
    Result := ParseStr
  else if c = '[' then
  begin
    l := ParseSeq(']');
    Result := BoxObj(l);
  end
  else if c = '(' then
  begin
    l := ParseSeq(')');                       { a tuple is a TPyList here }
    Result := BoxObj(l);
  end
  else if c = '{' then
  begin
    d := ParseDict;
    Result := BoxObj(d);
  end
  else if (c = 'T') and (Copy(gSrc, gPos, 4) = 'True') then
  begin
    Inc(gPos, 4);
    Result := True;
  end
  else if (c = 'F') and (Copy(gSrc, gPos, 5) = 'False') then
  begin
    Inc(gPos, 5);
    Result := False;
  end
  else if (c = 'N') and (Copy(gSrc, gPos, 4) = 'None') then
  begin
    Inc(gPos, 4);
    Result := pynone;
  end
  else if ((c >= '0') and (c <= '9')) or (c = '-') or (c = '+') or (c = '.') then
    Result := ParseNum
  else
  begin
    LitError('unsupported literal');
    Result := pynone;
  end;
end;

function literal_eval(const s: AnsiString): Variant;
begin
  gSrc := s;
  gPos := 1;
  Result := ParseValue;
  SkipWs;
  if gPos <= Length(gSrc) then LitError('trailing text');
end;

end.
