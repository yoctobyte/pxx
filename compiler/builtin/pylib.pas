{ SPDX-License-Identifier: Zlib }
unit pylib;

{ Python-runtime support types for the Nil-Python frontend. Every .npy program
  pulls this unit in automatically (see ParsePyProgram).

  TPyList is Python's list: a growable array of 16-byte variant slots with
  reference semantics (a class value IS the heap pointer). The slot layout is
  builtin.pas's TVariantRecord model: {VType: Int64; Payload: Int64}, VType 0
  meaning None. Slots are copied raw — correct under the default frozen-string
  model where string payloads are never freed; the managed-string build needs
  refcounting here (noted in feature-nilpy-list).

  append returns Self so the frontend can desugar a list literal [a, b, c]
  into one chained expression: TPyList.Create.append(a).append(b).append(c).
  The default indexed property makes xs[i] work through the ordinary
  default-property machinery, read and write, with Python negative-index
  semantics. }

interface

type
  TPyVarRec = record
    VType: Int64;
    Payload: Int64;
  end;
  PPyVarRec = ^TPyVarRec;
  PInt64 = ^Int64;

  { itertools.count shim: uforth allocates xt ids via
    next(Word._xt_counter). Generators come much later; a bare int counter
    covers the censused use. }
  TPyCounter = class
  public
    FNext: Int64;
    constructor Create(start: Int64);
    function nextval: Int64;
  end;

  TPyList = class
  public
    FLen: Integer;
    FCap: Integer;
    FItems: Pointer;
    constructor Create;
    function append(const v: Variant): TPyList;
    function get(i: Integer): Variant;
    procedure put(i: Integer; const v: Variant);
    function count: Integer;
    function pop: Variant;
    function pop_at(i: Integer): Variant;
    procedure insert(i: Integer; const v: Variant);
    procedure clear;
    property Items[i: Integer]: Variant read get write put; default;
  end;

function len(l: TPyList): Integer;
function next(c: TPyCounter): Int64;
function pycontains(l: TPyList; const v: Variant): Boolean;
function pyvartag(const v: Variant): Int64;
function pyvarobj(const v: Variant): Pointer;

{ str methods. The frontend desugars `s.upper()` into pystr_upper(s) — see
  PyParseStrMethod. ASCII-only for now: CPython's str.upper() is full-Unicode
  (and locale-independent), which needs a case-mapping table this unit does not
  carry yet. uforth's word names are ASCII plus emoji, and emoji are
  case-stable, so the corpus is unaffected; a non-ASCII byte passes through
  untouched rather than being mangled. Tracked in feature-nilpy-str-methods. }
function pystr_upper(const s: AnsiString): AnsiString;
function pystr_lower(const s: AnsiString): AnsiString;
function pystr_strip(const s: AnsiString): AnsiString;
function pystr_lstrip(const s: AnsiString): AnsiString;
function pystr_rstrip(const s: AnsiString): AnsiString;
function pystr_startswith(const s: AnsiString; const pre: AnsiString): Boolean;
function pystr_endswith(const s: AnsiString; const suf: AnsiString): Boolean;
function pystr_find(const s: AnsiString; const sub: AnsiString): Integer;
function pystr_isspace(const s: AnsiString): Boolean;
function pystr_ofchar(c: Char): AnsiString;
function pystr_at(const s: AnsiString; i: Integer): Char;

implementation

{ Python's whitespace set for the argument-less strip()/isspace():
  space, tab, newline, carriage return, vertical tab, form feed. }
function PyIsSpaceCh(c: Char): Boolean;
begin
  PyIsSpaceCh := (c = ' ') or (c = Chr(9)) or (c = Chr(10)) or
                 (c = Chr(11)) or (c = Chr(12)) or (c = Chr(13));
end;

function pystr_upper(const s: AnsiString): AnsiString;
var i: Integer;
    c: Char;
begin
  Result := '';
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if (c >= 'a') and (c <= 'z') then
      c := Chr(Ord(c) - 32);
    Result := Result + c;
  end;
end;

function pystr_lower(const s: AnsiString): AnsiString;
var i: Integer;
    c: Char;
begin
  Result := '';
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if (c >= 'A') and (c <= 'Z') then
      c := Chr(Ord(c) + 32);
    Result := Result + c;
  end;
end;

{ Char -> 1-length str. Python has no character type, so a tyChar base for a
  str method (a one-char literal, or s[i]) must become a real string. Done as an
  EXPLICIT call rather than leaning on the implicit char->string conversion,
  which keys on node SHAPE not type: the literal shape converted but the
  subscript shape did not, so s[0].upper() silently produced a NUL byte
  (project_string_conversion_shape_blindspot_pattern). }
function pystr_ofchar(c: Char): AnsiString;
begin
  Result := c;
end;

{ Python's s[i]: 0-BASED, and a NEGATIVE index counts from the end (s[-1] is the
  last character). Pascal's own subscript is 1-based with no negative form, so
  handing the index straight through read one character early and made s[0] a
  NUL — silently, on all 123 uforth subscript sites
  (bug-nilpy-str-index-off-by-one). Out of range raises IndexError like CPython,
  matching TPyList's existing PyListFix behaviour. }
function pystr_at(const s: AnsiString; i: Integer): Char;
var n: Integer;
begin
  n := Length(s);
  if i < 0 then i := n + i;
  if (i < 0) or (i >= n) then
  begin
    writeln('IndexError: string index out of range');
    Halt(1);
  end;
  Result := s[i + 1];
end;

function pystr_lstrip(const s: AnsiString): AnsiString;
var i, n: Integer;
begin
  n := Length(s);
  i := 1;
  while (i <= n) and PyIsSpaceCh(s[i]) do Inc(i);
  Result := Copy(s, i, n - i + 1);
end;

function pystr_rstrip(const s: AnsiString): AnsiString;
var n: Integer;
begin
  n := Length(s);
  while (n >= 1) and PyIsSpaceCh(s[n]) do Dec(n);
  Result := Copy(s, 1, n);
end;

function pystr_strip(const s: AnsiString): AnsiString;
begin
  Result := pystr_lstrip(pystr_rstrip(s));
end;

function pystr_startswith(const s: AnsiString; const pre: AnsiString): Boolean;
var i, n: Integer;
begin
  n := Length(pre);
  if n > Length(s) then begin Result := False; Exit; end;
  for i := 1 to n do
    if s[i] <> pre[i] then begin Result := False; Exit; end;
  Result := True;   { "".startswith("") is True in CPython, and falls out here }
end;

function pystr_endswith(const s: AnsiString; const suf: AnsiString): Boolean;
var i, n, base: Integer;
begin
  n := Length(suf);
  base := Length(s) - n;
  if base < 0 then begin Result := False; Exit; end;
  for i := 1 to n do
    if s[base + i] <> suf[i] then begin Result := False; Exit; end;
  Result := True;
end;

{ CPython's str.find: 0-BASED index of the first occurrence, -1 when absent.
  Deliberately not Pascal's Pos, which is 1-based and returns 0 when absent —
  returning that unadjusted would be silently off by one everywhere and would
  make "not found" read as "found at index 0". An empty needle finds at 0. }
function pystr_find(const s: AnsiString; const sub: AnsiString): Integer;
var i, j, n, m: Integer;
    hit: Boolean;
begin
  n := Length(s);
  m := Length(sub);
  if m = 0 then begin Result := 0; Exit; end;
  for i := 1 to n - m + 1 do
  begin
    hit := True;
    for j := 1 to m do
      if s[i + j - 1] <> sub[j] then begin hit := False; Break; end;
    if hit then begin Result := i - 1; Exit; end;
  end;
  Result := -1;
end;

{ CPython: "".isspace() is FALSE — an empty string has no characters to be
  whitespace, so the all-quantifier does not vacuously hold here. }
function pystr_isspace(const s: AnsiString): Boolean;
var i: Integer;
begin
  if Length(s) = 0 then begin Result := False; Exit; end;
  for i := 1 to Length(s) do
    if not PyIsSpaceCh(s[i]) then begin Result := False; Exit; end;
  Result := True;
end;

function pyvartag(const v: Variant): Int64;
begin
  Result := PPyVarRec(@v)^.VType;
end;

function pyvarobj(const v: Variant): Pointer;
begin
  Result := Pointer(PPyVarRec(@v)^.Payload);
end;

constructor TPyCounter.Create(start: Int64);
begin
  FNext := start;
end;

function TPyCounter.nextval: Int64;
begin
  Result := FNext;
  FNext := FNext + 1;
end;

function next(c: TPyCounter): Int64;
begin
  Result := c.nextval;
end;

procedure PyIndexError;
begin
  writeln('IndexError: list index out of range');
  Halt(1);
end;

constructor TPyList.Create;
begin
  FLen := 0;
  FCap := 0;
  FItems := nil;
end;

function TPyList.count: Integer;
begin
  Result := FLen;
end;

function len(l: TPyList): Integer;
begin
  Result := l.FLen;
end;

{ Translate a possibly-negative Python index; halt when out of range. }
function PyListFix(l: TPyList; i: Integer): Integer;
begin
  if i < 0 then i := i + l.FLen;
  if (i < 0) or (i >= l.FLen) then PyIndexError;
  Result := i;
end;

procedure PyListGrow(l: TPyList; need: Integer);
var
  newCap, k: Integer;
  newItems: Pointer;
  src, dst: PPyVarRec;
begin
  if need <= l.FCap then Exit;
  newCap := l.FCap * 2;
  if newCap < 8 then newCap := 8;
  if newCap < need then newCap := need;
  GetMem(newItems, newCap * 16);
  for k := 0 to l.FLen - 1 do
  begin
    src := PPyVarRec(NativeInt(l.FItems) + k * 16);
    dst := PPyVarRec(NativeInt(newItems) + k * 16);
    dst^.VType := src^.VType;
    dst^.Payload := src^.Payload;
  end;
  l.FItems := newItems;
  l.FCap := newCap;
end;

function TPyList.append(const v: Variant): TPyList;
var
  src, dst: PPyVarRec;
begin
  PyListGrow(Self, FLen + 1);
  src := PPyVarRec(@v);
  dst := PPyVarRec(NativeInt(FItems) + FLen * 16);
  dst^.VType := src^.VType;
  dst^.Payload := src^.Payload;
  FLen := FLen + 1;
  Result := Self;
end;

function TPyList.get(i: Integer): Variant;
var
  src, dst: PPyVarRec;
begin
  i := PyListFix(Self, i);
  src := PPyVarRec(NativeInt(FItems) + i * 16);
  dst := PPyVarRec(@Result);
  dst^.VType := src^.VType;
  dst^.Payload := src^.Payload;
end;

procedure TPyList.put(i: Integer; const v: Variant);
var
  src, dst: PPyVarRec;
begin
  i := PyListFix(Self, i);
  src := PPyVarRec(@v);
  dst := PPyVarRec(NativeInt(FItems) + i * 16);
  dst^.VType := src^.VType;
  dst^.Payload := src^.Payload;
end;

function TPyList.pop: Variant;
begin
  Result := get(FLen - 1);
  FLen := FLen - 1;
end;

function TPyList.pop_at(i: Integer): Variant;
var
  k: Integer;
  src, dst: PPyVarRec;
begin
  i := PyListFix(Self, i);
  Result := get(i);
  for k := i to FLen - 2 do
  begin
    src := PPyVarRec(NativeInt(FItems) + (k + 1) * 16);
    dst := PPyVarRec(NativeInt(FItems) + k * 16);
    dst^.VType := src^.VType;
    dst^.Payload := src^.Payload;
  end;
  FLen := FLen - 1;
end;

procedure TPyList.insert(i: Integer; const v: Variant);
var
  k: Integer;
  src, dst: PPyVarRec;
begin
  { Python allows insert at len (append position) and clamps beyond. }
  if i < 0 then i := i + FLen;
  if i < 0 then i := 0;
  if i > FLen then i := FLen;
  PyListGrow(Self, FLen + 1);
  for k := FLen - 1 downto i do
  begin
    src := PPyVarRec(NativeInt(FItems) + k * 16);
    dst := PPyVarRec(NativeInt(FItems) + (k + 1) * 16);
    dst^.VType := src^.VType;
    dst^.Payload := src^.Payload;
  end;
  src := PPyVarRec(@v);
  dst := PPyVarRec(NativeInt(FItems) + i * 16);
  dst^.VType := src^.VType;
  dst^.Payload := src^.Payload;
  FLen := FLen + 1;
end;

procedure TPyList.clear;
begin
  FLen := 0;
end;

{ Python `in` over a list/set-as-list. Same-tag equality only: ints/bools/
  chars by payload, floats by bits, strings by CONTENT (payload is the char
  pointer, length at ptr-8). Cross-tag numeric equality (1 == 1.0) is not
  modelled — the censused corpus uses string membership. }
function pycontains(l: TPyList; const v: Variant): Boolean;
var
  i, k: Integer;
  p, q: PPyVarRec;
  la, lb: Int64;
  a, b: PChar;
  same: Boolean;
begin
  Result := False;
  q := PPyVarRec(@v);
  for i := 0 to l.FLen - 1 do
  begin
    p := PPyVarRec(NativeInt(l.FItems) + i * 16);
    if p^.VType <> q^.VType then continue;
    if p^.VType = 6 then
    begin
      a := PChar(p^.Payload);
      b := PChar(q^.Payload);
      if (a = nil) or (b = nil) then
      begin
        if a = b then begin Result := True; Exit; end;
        continue;
      end;
      la := PInt64(NativeInt(p^.Payload) - 8)^;
      lb := PInt64(NativeInt(q^.Payload) - 8)^;
      if la <> lb then continue;
      same := True;
      for k := 0 to Integer(la) - 1 do
        if a[k] <> b[k] then begin same := False; break; end;
      if same then begin Result := True; Exit; end;
    end
    else if p^.Payload = q^.Payload then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

end.
