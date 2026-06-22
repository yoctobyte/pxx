unit builtin;

{ Conversion helpers backing the Str and Val built-ins. The compiler pulls this
  unit in automatically, but only when a program actually uses Str or Val (a
  token pre-scan in ParseProgram), so programs that never call them pay nothing
  in code size. Pure Pascal — no syscalls, a small speed penalty versus inline
  asm, which is fine for these historic routines.

  - Str(x[:w[:d]], s) is rewritten by the parser to s := StrInt(x, w); the
    decimals field is parsed but ignored (integer Str only for now).
  - Val(s, n, code) is an ordinary call resolved straight to the Val below;
    it has no special ':' syntax, so it needs no parser rewrite.

  Dialect notes: plain functions, so named-result is fine but Result is used;
  strings are built by concatenation; no single-char-literal pitfalls remain. }

interface

function StrInt(v: Int64; width: Integer): AnsiString;
function FloatToStr(v: Double): AnsiString;
function StrFloat(v: Double; width: Integer; decimals: Integer): AnsiString;
procedure Val(const s: AnsiString; var v: Int64; var code: Integer);
procedure ValFloat(const s: AnsiString; var v: Double; var code: Integer);
function VariantToStr(const v: Variant): AnsiString;
function PCharToString(p: PChar): AnsiString;

{ Substring intrinsic backing bare `Copy(s, index[, count])` on a string with no
  user `Copy` in scope — so frozen/managed string Copy works with no `uses`
  (the lib `sysutils.Copy` is the same routine for the explicit-uses path). FPC
  semantics: 1-based index clamped to >= 1, count clamped to the string end. }
function __pxxStrCopy(const s: AnsiString; index, count: Integer): AnsiString;

{ Bare `Delete(s, index, count)` / `Insert(src, s, index)` lower to these (see
  ParseStatementAST), so the standard in-place string mutators work with no
  `uses`. FPC semantics: 1-based index; Delete is a no-op when out of range;
  Insert clamps index into [1, Length(s)+1]. Built on __pxxStrCopy so the
  managed refcounting is the ordinary assignment path. }
procedure __pxxStrDelete(var s: AnsiString; index, count: Integer);
procedure __pxxStrInsert(const src: AnsiString; var s: AnsiString; index: Integer);

{ Bare `Abs(x)` / `Sqr(x)` lower to these (see ParseFactor) so the System
  intrinsics work with no `uses` and the argument is evaluated once (the naive
  e*e / if e<0 fold would double-evaluate a side-effecting argument). }
function __pxxAbsInt(x: Int64): Int64;
function __pxxAbsDbl(d: Double): Double;
function __pxxSqrInt(x: Int64): Int64;
function __pxxSqrDbl(d: Double): Double;

{ The heap allocator and managed-string helpers (PXXAlloc/Free/Realloc,
  PXXStr*) moved to the `builtinheap` unit so heap-only / string-only programs
  do not pull in the Str/Val/Variant routines below. }

implementation

type
  TVariantRecord = record
    VType: Int64;
    Payload: Int64;
  end;
  PVariantRecord = ^TVariantRecord;
  PDouble = ^Double;
  PAnsiString = ^AnsiString;

function VariantToStr(const v: Variant): AnsiString;
var
  p: PVariantRecord;
begin
  p := @v;
  if p^.VType = 1 then
    Result := StrInt(p^.Payload, 0)
  else if p^.VType = 3 then
    Result := FloatToStr(PDouble(@p^.Payload)^)
  else if p^.VType = 5 then
    Result := Chr(p^.Payload)
  else if p^.VType = 6 then
    Result := PAnsiString(@p^.Payload)^
  else if p^.VType = 0 then
    Result := 'None'
  else
    Result := '';
end;


function StrInt(v: Int64; width: Integer): AnsiString;
var
  neg: Boolean;
  digits: string;
  n: Int64;
  d: Integer;
begin
  digits := '';
  if v = 0 then
    digits := '0'
  else
  begin
    neg := v < 0;
    n := v;
    if neg then n := -n;
    while n > 0 do
    begin
      d := n mod 10;
      digits := Chr(Ord('0') + d) + digits;
      n := n div 10;
    end;
    if neg then digits := '-' + digits;
  end;
  Result := digits;
  while Length(Result) < width do
    Result := ' ' + Result;
end;

function FloatToStr(v: Double): AnsiString;
{ Python-style natural decimal: [-]int.frac with trailing zeros trimmed but at
  least one fractional digit (5.0 -> "5.0"). Uses the Trunc/Frac/Round float
  intrinsics so all digit extraction is integer arithmetic. Mirrors the
  EmitWriteFloatNat codegen path used by writeln. }
var
  neg: Boolean;
  intpart, fracpart, divisor, rem, d: Int64;
  digits: string;
  i: Integer;
begin
  neg := v < 0;
  if neg then v := -v;
  intpart := Trunc(v);
  fracpart := Round(Frac(v) * 1000000000000000.0);   { scale fractional part to 15 digits }
  if fracpart >= 1000000000000000 then
  begin
    fracpart := fracpart - 1000000000000000;
    intpart := intpart + 1;
  end;
  Result := StrInt(intpart, 0);
  if neg then Result := '-' + Result;
  Result := Result + '.';
  digits := '';
  rem := fracpart;
  divisor := 100000000000000;                          { 1e14 }
  for i := 0 to 14 do
  begin
    d := rem div divisor;
    rem := rem mod divisor;
    digits := digits + Chr(Ord('0') + d);
    divisor := divisor div 10;
    if rem = 0 then break;                             { trailing zeros trimmed }
  end;
  Result := Result + digits;
end;

function StrFloat(v: Double; width: Integer; decimals: Integer): AnsiString;
{ Format a Double like write(v:width:decimals). decimals < 0 -> natural form
  (FloatToStr); decimals >= 0 -> fixed, round-to-nearest, exactly `decimals`
  fractional digits (0 -> rounded integer, no point). Then right-justify to
  width with spaces. Matches the writeln float formatter for normal-range values. }
var
  neg: Boolean;
  pw, scaled, ip, fp: Int64;
  i: Integer;
  frac: string;
begin
  if decimals < 0 then
    Result := FloatToStr(v)
  else
  begin
    neg := v < 0;
    if neg then v := -v;
    pw := 1;
    for i := 1 to decimals do pw := pw * 10;
    scaled := Round(v * pw);              { round-to-nearest, Int64 }
    ip := scaled div pw;
    fp := scaled mod pw;
    Result := StrInt(ip, 0);
    if decimals > 0 then
    begin
      frac := StrInt(fp, 0);
      while Length(frac) < decimals do frac := '0' + frac;
      Result := Result + '.' + frac;
    end;
    if neg then Result := '-' + Result;
  end;
  while Length(Result) < width do
    Result := ' ' + Result;
end;

procedure Val(const s: AnsiString; var v: Int64; var code: Integer);
var
  i, len: Integer;
  neg, started: Boolean;
  n: Int64;
  c: Char;
begin
  v := 0;
  code := 0;
  n := 0;
  neg := False;
  started := False;
  len := Length(s);
  i := 1;
  while (i <= len) and (s[i] = ' ') do
    Inc(i);
  if (i <= len) and ((s[i] = '-') or (s[i] = '+')) then
  begin
    neg := s[i] = '-';
    Inc(i);
  end;
  while i <= len do
  begin
    c := s[i];
    if (c >= '0') and (c <= '9') then
    begin
      n := n * 10 + (Ord(c) - Ord('0'));
      started := True;
      Inc(i);
    end
    else
      break;
  end;
  if (not started) or (i <= len) then
  begin
    { 1-based position of the first character that stopped the conversion }
    code := i;
    v := 0;
    Exit;
  end;
  if neg then n := -n;
  v := n;
  code := 0;
end;

procedure ValFloat(const s: AnsiString; var v: Double; var code: Integer);
{ Parse [sign] digits [.digits] [(e|E)[sign]digits] into a Double. code = 0 on
  success, else the 1-based position of the first offending character (FPC
  convention). Pure float arithmetic — no libc. }
var
  i, len, ndig: Integer;
  neg, eneg, started: Boolean;
  mant, scale: Double;
  exp, expval, d: Integer;
  c: Char;
begin
  v := 0;
  code := 0;
  mant := 0;
  neg := False;
  started := False;
  len := Length(s);
  i := 1;
  while (i <= len) and (s[i] = ' ') do Inc(i);
  if (i <= len) and ((s[i] = '-') or (s[i] = '+')) then
  begin
    neg := s[i] = '-';
    Inc(i);
  end;
  { integer part. NOTE: float literals (10.0/1.0) are used throughout — a plain
    integer literal assigned/multiplied into a Double currently misses the
    int->float conversion (see feature-int-to-float-assign); 0.0 is safe because
    its bit pattern is identical. }
  while (i <= len) and (s[i] >= '0') and (s[i] <= '9') do
  begin
    mant := mant * 10.0 + (Ord(s[i]) - Ord('0'));
    started := True;
    Inc(i);
  end;
  { fractional part }
  scale := 1.0;
  if (i <= len) and (s[i] = '.') then
  begin
    Inc(i);
    while (i <= len) and (s[i] >= '0') and (s[i] <= '9') do
    begin
      mant := mant * 10.0 + (Ord(s[i]) - Ord('0'));
      scale := scale * 10.0;
      started := True;
      Inc(i);
    end;
  end;
  { exponent }
  exp := 0;
  eneg := False;
  if (i <= len) and ((s[i] = 'e') or (s[i] = 'E')) then
  begin
    Inc(i);
    if (i <= len) and ((s[i] = '-') or (s[i] = '+')) then
    begin
      eneg := s[i] = '-';
      Inc(i);
    end;
    ndig := 0;
    while (i <= len) and (s[i] >= '0') and (s[i] <= '9') do
    begin
      exp := exp * 10 + (Ord(s[i]) - Ord('0'));
      Inc(ndig);
      Inc(i);
    end;
    if ndig = 0 then started := False;
  end;
  if (not started) or (i <= len) then
  begin
    code := i;
    v := 0;
    Exit;
  end;
  mant := mant / scale;
  if neg then mant := -mant;
  { apply exponent by repeated multiply/divide (exact powers of ten) }
  expval := exp;
  while expval > 0 do
  begin
    if eneg then mant := mant / 10.0 else mant := mant * 10.0;
    Dec(expval);
  end;
  v := mant;
  code := 0;
end;

function PCharToString(p: PChar): AnsiString;
var
  i: Integer;
  c: Char;
begin
  Result := '';
  if p <> nil then
  begin
    i := 0;
    c := p[i];
    while c <> #0 do
    begin
      Result := Result + c;
      i := i + 1;
      c := p[i];
    end;
  end;
end;

function __pxxStrCopy(const s: AnsiString; index, count: Integer): AnsiString;
var i, n, last: Integer; r: AnsiString;
begin
  n := Length(s);
  if index < 1 then index := 1;
  if count < 0 then count := 0;
  { Cap count to the chars available from index BEFORE forming `last`, so the
    2-arg form's sentinel count (MaxInt) cannot overflow `index + count - 1`. }
  if index > n then count := 0
  else if count > n - index + 1 then count := n - index + 1;
  last := index + count - 1;
  r := '';
  i := index;
  while i <= last do
  begin
    r := r + s[i];
    i := i + 1;
  end;
  Result := r;
end;

procedure __pxxStrDelete(var s: AnsiString; index, count: Integer);
begin
  if (count <= 0) or (index < 1) or (index > Length(s)) then Exit;
  { __pxxStrCopy clamps count to the string end, so an over-long count is fine. }
  s := __pxxStrCopy(s, 1, index - 1) + __pxxStrCopy(s, index + count, Length(s));
end;

procedure __pxxStrInsert(const src: AnsiString; var s: AnsiString; index: Integer);
begin
  if index < 1 then index := 1;
  if index > Length(s) + 1 then index := Length(s) + 1;
  s := __pxxStrCopy(s, 1, index - 1) + src + __pxxStrCopy(s, index, Length(s));
end;

function __pxxAbsInt(x: Int64): Int64;
begin
  if x < 0 then Result := -x else Result := x;
end;

function __pxxAbsDbl(d: Double): Double;
begin
  if d < 0 then Result := -d else Result := d;
end;

function __pxxSqrInt(x: Int64): Int64;
begin
  Result := x * x;
end;

function __pxxSqrDbl(d: Double): Double;
begin
  Result := d * d;
end;

end.
