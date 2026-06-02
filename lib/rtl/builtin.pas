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

function StrInt(v: Int64; width: Integer): string;
function FloatToStr(v: Double): string;
procedure Val(const s: string; var v: Int64; var code: Integer);

implementation

function StrInt(v: Int64; width: Integer): string;
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

function FloatToStr(v: Double): string;
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

procedure Val(const s: string; var v: Int64; var code: Integer);
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

end.
