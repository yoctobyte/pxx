{ SPDX-License-Identifier: Zlib }
unit json;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ A small, self-contained JSON value tree with a recursive-descent parser and a
  canonical serializer. Our own implementation (no fpjson port), FPC-ish naming.

  Design notes / dialect:
  - The value tree is a class hierarchy of one node type `TJSONValue` tagged by
    `TJSONKind`. Class instances give us reference semantics for the tree and
    zero-initialised fields on Create, which sidesteps the proc-local
    managed-record-uninit pitfall.
  - Numbers are stored as their *raw lexeme* (the exact source text) and
    re-emitted verbatim. This keeps re-emission byte-identical across targets
    (no float formatting in the hot path) while still allowing AsInteger.
  - The parser is a class (`TJSONReader`) holding the source + cursor as fields,
    again for guaranteed zero-init. Malformed input raises `EJSONError`.
  - Object members are kept as parallel key/value arrays with linear lookup:
    correctness over speed, and order-preserving so canonical re-emit is stable.

  Acceptance (see examples/json/): Parse -> ToString -> Parse yields an equal
  tree, and a fixed document set re-emits byte-identically. }

interface

{ pylib BEFORE sysutils, and that order is load-bearing. Both units declare
  `Exception`, and the name is deliberately shared program-wide
  (ClassNameIsDeliberatelyShared), so the FIRST unit to register it owns the
  row. pylib's own method bodies are written against pylib's Exception — whose
  message storage is the field `msg`, with FMessage/Message as properties over
  it — so with sysutils first, pylib's `constructor Exception.Create` bound to
  sysutils' class and died with "undefined variable (msg)". That took down
  every program reaching this unit, including examples/net/httpdemo.pas on all
  targets. The underlying order-dependence is decide-class-namespace-scoping. }
uses pylib, sysutils;   { the Python surface below speaks TPyDict/TPyList/Variant }

type
  TJSONKind = (jkNull, jkBool, jkInt, jkString, jkArray, jkObject);

  EJSONError = class(Exception) end;

  TJSONValue = class
    FKind: TJSONKind;
    FBool: Boolean;
    FNum:  AnsiString;             { raw numeric lexeme (jkInt) }
    FStr:  AnsiString;             { decoded string value (jkString) }
    FItems: array of TJSONValue;   { array elements (jkArray) }
    FKeys:  array of AnsiString;   { object member keys (jkObject) }
    FVals:  array of TJSONValue;   { object member values (jkObject) }

    function Kind: TJSONKind;
    function IsNull: Boolean;
    function AsBoolean: Boolean;
    function AsInteger: Int64;
    function AsString: AnsiString;

    function Count: Integer;                       { array/object child count }
    function GetItem(i: Integer): TJSONValue;      { array element i }
    function GetValue(const key: AnsiString): TJSONValue;  { object member, nil if absent }
    function HasKey(const key: AnsiString): Boolean;

    procedure Add(v: TJSONValue);                  { append to array }
    procedure AddPair(const key: AnsiString; v: TJSONValue);  { add/replace object member }

    function ToString(pretty: Boolean): AnsiString;
    procedure FreeTree;                            { recursively free children then self }
  end;

{ Constructors -- standalone so call sites read as values. }
function JSONNull: TJSONValue;
function JSONBool(b: Boolean): TJSONValue;
function JSONInt(n: Int64): TJSONValue;
function JSONStr(const s: AnsiString): TJSONValue;
function JSONArray: TJSONValue;
function JSONObject: TJSONValue;

{ Parse a complete JSON document; raises EJSONError on malformed input. }
function JSONParse(const src: AnsiString): TJSONValue;

{ ---- Python's `json` module surface --------------------------------------

  `import json` resolves to this unit, so `json.dumps(obj)` / `json.loads(s)` /
  `json.dump(obj, f)` / `json.load(f)` are the calls an application writes. The
  VALUES are Python's — a dict is a TPyDict, a list a TPyList, everything else a
  tagged variant — so these convert between that world and the value tree above
  rather than exposing TJSONValue to Python code.

  Not modelled: the `default=` / `cls=` / `object_hook=` hooks, and CPython's
  unquoted NaN/Infinity (which is not JSON; this raises instead). `indent` and
  `sort_keys` ARE honoured, because a settings file written with them is meant
  to be read by a human. `ensure_ascii` is accepted and has no effect: our
  strings are byte strings, so there is no non-ASCII escaping step to suppress. }

type
  { CPython raises this from loads/load on malformed input, and applications
    catch it BY NAME — `except (OSError, json.JSONDecodeError)`. }
  JSONDecodeError = class(Exception)
  end;

function dumps(const obj: Variant; indent: Integer = -1;
               ensure_ascii: Boolean = True; sort_keys: Boolean = False): AnsiString;
function loads(const s: AnsiString): Variant;
{ `f` is what pathlib's Path.open and the builtin open(path, mode) hand back. }
procedure dump(const obj: Variant; f: TPyFile; ensure_ascii: Boolean = True;
               indent: Integer = -1; sort_keys: Boolean = False);
function load(f: TPyFile): Variant;

implementation

type
  TJSONReader = class
    FSrc: AnsiString;
    FPos: Integer;          { 1-based cursor }
    FLen: Integer;
    function ParseValue: TJSONValue;
    procedure SkipWS;
    function Peek: Char;
    procedure Fail(const msg: AnsiString);
    function ParseString: AnsiString;
    function ParseNumber: TJSONValue;
    function ParseArray: TJSONValue;
    function ParseObject: TJSONValue;
    function ExpectLit(const lit: AnsiString): Boolean;
  end;

{ ---------- TJSONValue ---------- }

function TJSONValue.Kind: TJSONKind;
begin
  Result := Self.FKind;
end;

function TJSONValue.IsNull: Boolean;
begin
  Result := Self.FKind = jkNull;
end;

function TJSONValue.AsBoolean: Boolean;
begin
  Result := (Self.FKind = jkBool) and Self.FBool;
end;

function TJSONValue.AsInteger: Int64;
begin
  if Self.FKind = jkInt then
    Result := StrToInt(Self.FNum)
  else
    Result := 0;
end;

function TJSONValue.AsString: AnsiString;
begin
  if Self.FKind = jkString then
    Result := Self.FStr
  else
    Result := '';
end;

function TJSONValue.Count: Integer;
begin
  if Self.FKind = jkArray then
    Result := Length(Self.FItems)
  else if Self.FKind = jkObject then
    Result := Length(Self.FKeys)
  else
    Result := 0;
end;

function TJSONValue.GetItem(i: Integer): TJSONValue;
begin
  if (Self.FKind = jkArray) and (i >= 0) and (i < Length(Self.FItems)) then
    Result := Self.FItems[i]
  else
    Result := nil;
end;

function TJSONValue.GetValue(const key: AnsiString): TJSONValue;
var i: Integer;
begin
  Result := nil;
  if Self.FKind <> jkObject then Exit;
  for i := 0 to Length(Self.FKeys) - 1 do
    if Self.FKeys[i] = key then
    begin
      Result := Self.FVals[i];
      Exit;
    end;
end;

function TJSONValue.HasKey(const key: AnsiString): Boolean;
var v: TJSONValue;
begin
  v := Self.GetValue(key);
  Result := v <> nil;
end;

procedure TJSONValue.Add(v: TJSONValue);
var n: Integer;
begin
  n := Length(Self.FItems);
  SetLength(Self.FItems, n + 1);
  Self.FItems[n] := v;
end;

procedure TJSONValue.AddPair(const key: AnsiString; v: TJSONValue);
var i, n: Integer;
begin
  for i := 0 to Length(Self.FKeys) - 1 do
    if Self.FKeys[i] = key then
    begin
      Self.FVals[i] := v;       { replace existing }
      Exit;
    end;
  n := Length(Self.FKeys);
  SetLength(Self.FKeys, n + 1);
  SetLength(Self.FVals, n + 1);
  Self.FKeys[n] := key;
  Self.FVals[n] := v;
end;

function HexDigit(n: Integer): Char;
begin
  if n < 10 then Result := Chr(Ord('0') + n)
  else Result := Chr(Ord('a') + (n - 10));
end;

{ Escape a string per JSON rules. Only ASCII control chars, '"' and '\' are
  escaped; bytes >= 0x20 (including UTF-8 continuation bytes) pass through. }
function EscapeStr(const s: AnsiString): AnsiString;
var i: Integer; c: Char; r: AnsiString;
begin
  r := '"';
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if c = '"' then r := r + '\"'
    else if c = '\' then r := r + '\\'
    else if c = #8 then r := r + '\b'
    else if c = #9 then r := r + '\t'
    else if c = #10 then r := r + '\n'
    else if c = #12 then r := r + '\f'
    else if c = #13 then r := r + '\r'
    else if c < ' ' then
    begin
      { \u00XX for remaining control chars }
      r := r + '\u00';
      r := r + HexDigit(Ord(c) div 16);
      r := r + HexDigit(Ord(c) mod 16);
    end
    else r := r + c;
  end;
  Result := r + '"';
end;

function IndentStr(depth: Integer): AnsiString;
var i: Integer; r: AnsiString;
begin
  r := '';
  for i := 1 to depth do r := r + '  ';
  Result := r;
end;

function EmitValue(v: TJSONValue; pretty: Boolean; depth: Integer): AnsiString;
var r, inner, pad, pad1, nl, sep, item: AnsiString; i: Integer;
begin
  if v = nil then begin Result := 'null'; Exit; end;
  case v.FKind of
    jkNull: Result := 'null';
    jkBool: if v.FBool then Result := 'true' else Result := 'false';
    jkInt:  Result := v.FNum;
    jkString: Result := EscapeStr(v.FStr);
    jkArray:
      begin
        if Length(v.FItems) = 0 then begin Result := '[]'; Exit; end;
        if pretty then begin nl := #10; pad := IndentStr(depth + 1); pad1 := IndentStr(depth); end
        else begin nl := ''; pad := ''; pad1 := ''; end;
        r := '[' + nl;
        for i := 0 to Length(v.FItems) - 1 do
        begin
          item := EmitValue(v.FItems[i], pretty, depth + 1);   { temp before concat }
          if i > 0 then begin if pretty then sep := ',' + nl else sep := ','; r := r + sep; end;
          r := r + pad + item;
        end;
        Result := r + nl + pad1 + ']';
      end;
    jkObject:
      begin
        if Length(v.FKeys) = 0 then begin Result := '{}'; Exit; end;
        if pretty then begin nl := #10; pad := IndentStr(depth + 1); pad1 := IndentStr(depth); end
        else begin nl := ''; pad := ''; pad1 := ''; end;
        r := '{' + nl;
        for i := 0 to Length(v.FKeys) - 1 do
        begin
          inner := EscapeStr(v.FKeys[i]);
          item := EmitValue(v.FVals[i], pretty, depth + 1);     { temp before concat }
          if i > 0 then begin if pretty then sep := ',' + nl else sep := ','; r := r + sep; end;
          if pretty then r := r + pad + inner + ': ' + item
          else r := r + pad + inner + ':' + item;
        end;
        Result := r + nl + pad1 + '}';
      end;
  else
    Result := 'null';
  end;
end;

function TJSONValue.ToString(pretty: Boolean): AnsiString;
begin
  Result := EmitValue(Self, pretty, 0);
end;

procedure TJSONValue.FreeTree;
var i: Integer;
begin
  for i := 0 to Length(Self.FItems) - 1 do
    if Self.FItems[i] <> nil then Self.FItems[i].FreeTree;
  for i := 0 to Length(Self.FVals) - 1 do
    if Self.FVals[i] <> nil then Self.FVals[i].FreeTree;
  Self.Free;
end;

{ ---------- constructors ---------- }

function JSONNull: TJSONValue;
begin
  Result := TJSONValue.Create;
  Result.FKind := jkNull;
end;

function JSONBool(b: Boolean): TJSONValue;
begin
  Result := TJSONValue.Create;
  Result.FKind := jkBool;
  Result.FBool := b;
end;

function JSONInt(n: Int64): TJSONValue;
begin
  Result := TJSONValue.Create;
  Result.FKind := jkInt;
  Result.FNum := IntToStr(n);
end;

function JSONStr(const s: AnsiString): TJSONValue;
begin
  Result := TJSONValue.Create;
  Result.FKind := jkString;
  Result.FStr := s;
end;

function JSONArray: TJSONValue;
begin
  Result := TJSONValue.Create;
  Result.FKind := jkArray;
end;

function JSONObject: TJSONValue;
begin
  Result := TJSONValue.Create;
  Result.FKind := jkObject;
end;

{ ---------- TJSONReader ---------- }

procedure TJSONReader.Fail(const msg: AnsiString);
begin
  raise EJSONError.Create('JSON: ' + msg + ' at offset ' + IntToStr(Self.FPos));
end;

function TJSONReader.Peek: Char;
begin
  if Self.FPos <= Self.FLen then Result := Self.FSrc[Self.FPos]
  else Result := #0;
end;

procedure TJSONReader.SkipWS;
var c: Char;
begin
  while Self.FPos <= Self.FLen do
  begin
    c := Self.FSrc[Self.FPos];
    if (c = ' ') or (c = #9) or (c = #10) or (c = #13) then
      Self.FPos := Self.FPos + 1
    else
      Break;
  end;
end;

function TJSONReader.ExpectLit(const lit: AnsiString): Boolean;
var i: Integer;
begin
  for i := 1 to Length(lit) do
  begin
    if (Self.FPos > Self.FLen) or (Self.FSrc[Self.FPos] <> lit[i]) then
    begin
      Result := False;
      Exit;
    end;
    Self.FPos := Self.FPos + 1;
  end;
  Result := True;
end;

function HexVal(c: Char): Integer;
begin
  if (c >= '0') and (c <= '9') then Result := Ord(c) - Ord('0')
  else if (c >= 'a') and (c <= 'f') then Result := Ord(c) - Ord('a') + 10
  else if (c >= 'A') and (c <= 'F') then Result := Ord(c) - Ord('A') + 10
  else Result := -1;
end;

{ Encode a Unicode code point (BMP only, from \uXXXX) as UTF-8 bytes. }
function Utf8Encode(cp: Integer): AnsiString;
begin
  if cp < $80 then
    Result := Chr(cp)
  else if cp < $800 then
    Result := Chr($C0 or (cp shr 6)) + Chr($80 or (cp and $3F))
  else
    Result := Chr($E0 or (cp shr 12)) + Chr($80 or ((cp shr 6) and $3F)) + Chr($80 or (cp and $3F));
end;

function TJSONReader.ParseString: AnsiString;
var r: AnsiString; c: Char; cp, h, k: Integer;
begin
  { assumes current char is the opening quote }
  Self.FPos := Self.FPos + 1;
  r := '';
  while True do
  begin
    if Self.FPos > Self.FLen then Self.Fail('unterminated string');
    c := Self.FSrc[Self.FPos];
    if c = '"' then
    begin
      Self.FPos := Self.FPos + 1;
      Break;
    end
    else if c = '\' then
    begin
      Self.FPos := Self.FPos + 1;
      if Self.FPos > Self.FLen then Self.Fail('unterminated escape');
      c := Self.FSrc[Self.FPos];
      if c = '"' then r := r + '"'
      else if c = '\' then r := r + '\'
      else if c = '/' then r := r + '/'
      else if c = 'b' then r := r + #8
      else if c = 'f' then r := r + #12
      else if c = 'n' then r := r + #10
      else if c = 'r' then r := r + #13
      else if c = 't' then r := r + #9
      else if c = 'u' then
      begin
        cp := 0;
        for k := 1 to 4 do
        begin
          Self.FPos := Self.FPos + 1;
          if Self.FPos > Self.FLen then Self.Fail('bad \u escape');
          h := HexVal(Self.FSrc[Self.FPos]);
          if h < 0 then Self.Fail('bad \u hex digit');
          cp := cp * 16 + h;
        end;
        r := r + Utf8Encode(cp);
      end
      else Self.Fail('bad escape char');
      Self.FPos := Self.FPos + 1;
    end
    else
    begin
      r := r + c;
      Self.FPos := Self.FPos + 1;
    end;
  end;
  Result := r;
end;

function TJSONReader.ParseNumber: TJSONValue;
var start: Integer; c: Char; raw: AnsiString;
begin
  start := Self.FPos;
  if Self.Peek = '-' then Self.FPos := Self.FPos + 1;
  while Self.FPos <= Self.FLen do
  begin
    c := Self.FSrc[Self.FPos];
    if ((c >= '0') and (c <= '9')) or (c = '.') or (c = 'e') or (c = 'E')
       or (c = '+') or (c = '-') then
      Self.FPos := Self.FPos + 1
    else
      Break;
  end;
  if Self.FPos = start then Self.Fail('invalid number');
  raw := Copy(Self.FSrc, start, Self.FPos - start);
  Result := TJSONValue.Create;
  Result.FKind := jkInt;
  Result.FNum := raw;
end;

function TJSONReader.ParseArray: TJSONValue;
var arr, child: TJSONValue;
begin
  arr := JSONArray;
  Self.FPos := Self.FPos + 1;          { consume '[' }
  Self.SkipWS;
  if Self.Peek = ']' then
  begin
    Self.FPos := Self.FPos + 1;
    Result := arr;
    Exit;
  end;
  while True do
  begin
    Self.SkipWS;
    child := Self.ParseValue;           { temp before Add }
    arr.Add(child);
    Self.SkipWS;
    if Self.Peek = ',' then Self.FPos := Self.FPos + 1
    else if Self.Peek = ']' then
    begin
      Self.FPos := Self.FPos + 1;
      Break;
    end
    else Self.Fail('expected , or ]');
  end;
  Result := arr;
end;

function TJSONReader.ParseObject: TJSONValue;
var obj, child: TJSONValue; key: AnsiString;
begin
  obj := JSONObject;
  Self.FPos := Self.FPos + 1;          { consume the opening brace }
  Self.SkipWS;
  if Self.Peek = '}' then
  begin
    Self.FPos := Self.FPos + 1;
    Result := obj;
    Exit;
  end;
  while True do
  begin
    Self.SkipWS;
    if Self.Peek <> '"' then Self.Fail('expected string key');
    key := Self.ParseString;
    Self.SkipWS;
    if Self.Peek <> ':' then Self.Fail('expected :');
    Self.FPos := Self.FPos + 1;
    Self.SkipWS;
    child := Self.ParseValue;           { temp before AddPair }
    obj.AddPair(key, child);
    Self.SkipWS;
    if Self.Peek = ',' then Self.FPos := Self.FPos + 1
    else if Self.Peek = '}' then
    begin
      Self.FPos := Self.FPos + 1;
      Break;
    end
    else Self.Fail('expected , or }');
  end;
  Result := obj;
end;

function TJSONReader.ParseValue: TJSONValue;
var c: Char;
begin
  Self.SkipWS;
  c := Self.Peek;
  if c = '{' then Result := Self.ParseObject
  else if c = '[' then Result := Self.ParseArray
  else if c = '"' then Result := JSONStr(Self.ParseString)
  else if c = 't' then
  begin
    if Self.ExpectLit('true') then Result := JSONBool(True)
    else begin Self.Fail('invalid literal'); Result := nil; end;
  end
  else if c = 'f' then
  begin
    if Self.ExpectLit('false') then Result := JSONBool(False)
    else begin Self.Fail('invalid literal'); Result := nil; end;
  end
  else if c = 'n' then
  begin
    if Self.ExpectLit('null') then Result := JSONNull
    else begin Self.Fail('invalid literal'); Result := nil; end;
  end
  else if (c = '-') or ((c >= '0') and (c <= '9')) then
    Result := Self.ParseNumber
  else
  begin
    Self.Fail('unexpected character');
    Result := nil;
  end;
end;

function JSONParse(const src: AnsiString): TJSONValue;
var rd: TJSONReader; v: TJSONValue;
begin
  rd := TJSONReader.Create;
  rd.FSrc := src;
  rd.FLen := Length(src);
  rd.FPos := 1;
  v := rd.ParseValue;
  rd.SkipWS;
  if rd.FPos <= rd.FLen then
  begin
    rd.Free;
    raise EJSONError.Create('JSON: trailing data');
  end;
  rd.Free;
  Result := v;
end;


{ ---- the Python surface ---------------------------------------------------- }

function JsonPyIndentStr(indent, depth: Integer): AnsiString;
var i: Integer; r: AnsiString;
begin
  r := '';
  if indent > 0 then
  begin
    r := #10;
    for i := 1 to indent * depth do r := r + ' ';
  end;
  JsonPyIndentStr := r;
end;

function JsonPyNumStr(d: Double): AnsiString;
var whole: Int64;
begin
  { an integral float prints as CPython does — 3.0, not 3. A value that came in
    as an int never reaches here: those carry the int tag. }
  whole := Trunc(d);
  if d = whole then JsonPyNumStr := IntToStr(whole) + '.0'
  else JsonPyNumStr := FloatToStr(d);
end;

function JsonPyDumpValue(const v: Variant; indent, depth: Integer;
                         sortKeys: Boolean): AnsiString; forward;

function JsonPyDumpList(l: TPyList; indent, depth: Integer;
                        sortKeys: Boolean): AnsiString;
var i: Integer; r, sep: AnsiString;
begin
  if l.count = 0 then
  begin
    JsonPyDumpList := '[]';
    exit;
  end;
  r := '[';
  sep := '';
  for i := 0 to l.count - 1 do
  begin
    r := r + sep + JsonPyIndentStr(indent, depth + 1)
         + JsonPyDumpValue(l.at(i), indent, depth + 1, sortKeys);
    { CPython's compact form is `, ` — the space only disappears when a
      newline takes its place }
    if indent > 0 then sep := ',' else sep := ', ';
  end;
  JsonPyDumpList := r + JsonPyIndentStr(indent, depth) + ']';
end;

function JsonPyDumpDict(d: TPyDict; indent, depth: Integer;
                        sortKeys: Boolean): AnsiString;
{ No dynamic arrays here on purpose. Holding the keys in an `array of
  AnsiString` (or the values in an `array of Variant`) alongside the dict
  corrupted the heap — a JSONParse later in the SAME program then died, with
  nothing wrong at its own call site. Keys are read from the dict when needed
  and the sort permutes a fixed Integer array. }
const MAX_SORT_KEYS = 512;
var i, j, n, t: Integer; r, sep: AnsiString;
    ks: TPyList;
    order: array[0..MAX_SORT_KEYS - 1] of Integer;
    doSort: Boolean;
begin
  n := d.count;
  if n = 0 then
  begin
    JsonPyDumpDict := '{}';
    exit;
  end;
  ks := d.keylist;
  doSort := sortKeys and (n <= MAX_SORT_KEYS);
  if doSort then
  begin
    for i := 0 to n - 1 do order[i] := i;
    for i := 0 to n - 2 do
      for j := 0 to n - 2 - i do
        if pystr_of(ks.at(order[j])) > pystr_of(ks.at(order[j + 1])) then
        begin
          t := order[j]; order[j] := order[j + 1]; order[j + 1] := t;
        end;
  end;
  r := '{';
  sep := '';
  for i := 0 to n - 1 do
  begin
    if doSort then j := order[i] else j := i;
    { a JSON object key is always a STRING. Python allows an int key and
      str()s it on the way out, which is what pystr_of does. }
    r := r + sep + JsonPyIndentStr(indent, depth + 1)
         + EscapeStr(pystr_of(ks.at(j))) + ': '
         + JsonPyDumpValue(d.fetch(ks.at(j)), indent, depth + 1, sortKeys);
    if indent > 0 then sep := ',' else sep := ', ';
  end;
  JsonPyDumpDict := r + JsonPyIndentStr(indent, depth) + '}';
end;

function JsonPyDumpValue(const v: Variant; indent, depth: Integer;
                         sortKeys: Boolean): AnsiString;
var o: TObject;
begin
  { The int family is more than one tag — VT_INT (1) and VT_INT64 (2) are the
    same Python number, and a value's tag depends on where it came from. Getting
    this wrong is not a wrong string but an exception, since the else-branch
    below refuses what it does not recognise. }
  case pyvartag(v) of
    0: JsonPyDumpValue := 'null';
    4: if pyvar_to_bool(v) then JsonPyDumpValue := 'true'
       else JsonPyDumpValue := 'false';
    1, 2: JsonPyDumpValue := IntToStr(pyvar_to_int(v));
    3, 5: JsonPyDumpValue := JsonPyNumStr(pyvar_to_float(v));
    6: JsonPyDumpValue := EscapeStr(pystr_of(v));
    7:
      begin
        o := TObject(pyvarobj(v));
        if o = nil then JsonPyDumpValue := 'null'
        else if o is TPyList then
          JsonPyDumpValue := JsonPyDumpList(TPyList(o), indent, depth, sortKeys)
        else if o is TPyDict then
          JsonPyDumpValue := JsonPyDumpDict(TPyDict(o), indent, depth, sortKeys)
        else
          raise EJSONError.Create('json: object of this type is not serializable');
      end;
  else
    raise EJSONError.Create('json: value of this type is not serializable');
  end;
end;

function dumps(const obj: Variant; indent: Integer;
               ensure_ascii: Boolean; sort_keys: Boolean): AnsiString;
begin
  dumps := JsonPyDumpValue(obj, indent, 0, sort_keys);
end;

{ The value tree -> the Python value world. }
function JsonPyFromTree(v: TJSONValue): Variant;
var i, n, code: Integer; l: TPyList; d: TPyDict; iv: Int64;
    vv: Variant; ks: AnsiString; child: TJSONValue;
begin
  if v = nil then
  begin
    JsonPyFromTree := pynone;
    exit;
  end;
  case v.Kind of
    jkNull: JsonPyFromTree := pynone;
    jkBool: JsonPyFromTree := v.AsBoolean;
    jkInt:
      begin
        { the tree keeps the raw lexeme, so a fractional one is a FLOAT }
        Val(v.FNum, iv, code);
        if code = 0 then JsonPyFromTree := iv
        else JsonPyFromTree := StrToFloat(v.FNum);
      end;
    jkString: JsonPyFromTree := v.AsString;
    jkArray:
      begin
        l := TPyList.Create;
        n := v.Count;
        for i := 0 to n - 1 do l.append(JsonPyFromTree(v.GetItem(i)));
        JsonPyFromTree := l;
      end;
    jkObject:
      begin
        d := TPyDict.Create;
        n := v.Count;
        for i := 0 to n - 1 do
        begin
          { through LOCALS: the key and the value are both boxed into variant
            temps, and building one inside the argument list of a call that
            builds the other read back the wrong one — `{"n": 1, "s": "x"}`
            came back with b["s"] = "n". }
          ks := v.FKeys[i];
          child := v.FVals[i];
          vv := JsonPyFromTree(child);
          d.store(ks, vv);
        end;
        JsonPyFromTree := d;
      end;
  else
    JsonPyFromTree := pynone;
  end;
end;

function loads(const s: AnsiString): Variant;
var tree: TJSONValue;
begin
  { JSONParse raises EJSONError; Python code catches json.JSONDecodeError, so
    the failure is re-raised under the name the application knows. }
  tree := JSONParse(s);
  loads := JsonPyFromTree(tree);
  { The tree is NOT freed here. Its strings are what the converted variants
    hold, and releasing them left the Python values pointing at freed text —
    `{"n": 1, "s": "x"}` came back with b["s"] = "n". Freeing it needs the
    conversion to copy every string first; until then the tree is left to the
    program's lifetime, which for a settings file read once is no leak worth
    the risk of a dangling one. }
end;

procedure dump(const obj: Variant; f: TPyFile; ensure_ascii: Boolean;
               indent: Integer; sort_keys: Boolean);
begin
  if f = nil then raise EJSONError.Create('json.dump: no file');
  f.write(pystr_encode(dumps(obj, indent, ensure_ascii, sort_keys)));
end;

function load(f: TPyFile): Variant;
{ The whole stream as TEXT, whatever mode the file was opened in — which is
  what CPython's json.load accepts (it decodes a bytes stream for you).

  This used to chunk through `f.read(65536)` bound to a TPyBytes, which only
  worked because that accessor answered bytes for a TEXT file too. It does not
  any more: the readers follow the MODE now, so `read(n)` on the text-mode file
  json.load is normally handed yields a str and the TPyBytes binding was left
  holding the wrong shape — the JSON parser then failed at offset 1.
  The zero-argument `f.read()` is the CPython spelling of "the whole stream"
  and is what this now uses. Deliberately NOT the mode-blind `readall` helper
  the accessors are built on: that method is new, and lib/rtl is compiled by
  the PINNED compiler (Track B's stable-binary boundary), so a library written
  against a method the pinned pylib does not have cannot build until a pin.
  bug-nilpy-text-mode-read-n-returns-bytes-not-str }
begin
  if f = nil then raise EJSONError.Create('json.load: no file');
  load := loads(f.read);
end;

end.
