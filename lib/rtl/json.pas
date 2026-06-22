unit json;

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

uses sysutils;

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
  Self.FPos := Self.FPos + 1;          { consume '{' }
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

end.
