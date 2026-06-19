unit sysutils;
{ Canonical SysUtils-style helpers. Now that the compiler loads a real
  lib/rtl/sysutils on `uses sysutils` (bug-sysutils-unit-hard-skipped fixed,
  v10), the conversion helpers live here -- their FPC-correct home -- rather than
  the interim lib/rtl/strutils. Pure Pascal, FPC-compatible names. Track B. }

interface

{ Int64 -> decimal string (covers Integer via widening). Handles negatives. }
function IntToStr(value: Int64): AnsiString;

{ 1-based substring; count clamped to the end; out-of-range index -> ''. }
function Copy(const s: AnsiString; index, count: Integer): AnsiString;

{ Strip characters <= ' ' (spaces, tabs, control) from both ends. }
function Trim(const s: AnsiString): AnsiString;

{ Parse a decimal integer. StrToIntDef returns def on any malformed input;
  StrToInt returns 0 on malformed. Leading spaces and a +/- sign are allowed. }
function StrToIntDef(const s: AnsiString; def: Integer): Integer;
function StrToInt(const s: AnsiString): Integer;

{ NOTE: no Val here -- `Val` is an intercepted builtin name and the builtin
  mis-lowers (wrong error code + segfault); a user Val is shadowed by it. See
  bug-builtin-val-miscompiles. Use StrToIntDef / StrToInt instead. }

{ ASCII case conversion. }
function UpperCase(const s: AnsiString): AnsiString;
function LowerCase(const s: AnsiString): AnsiString;

implementation

function IntToStr(value: Int64): AnsiString;
var s: AnsiString; neg: Boolean; d: Int64;
begin
  if value = 0 then
  begin
    Result := '0';
    Exit;
  end;
  neg := value < 0;
  if neg then value := -value;
  s := '';
  while value > 0 do
  begin
    d := value mod 10;
    s := Chr(Ord('0') + Integer(d)) + s;
    value := value div 10;
  end;
  if neg then s := '-' + s;
  Result := s;
end;

function Copy(const s: AnsiString; index, count: Integer): AnsiString;
var i, n, last: Integer; r: AnsiString;
begin
  n := Length(s);
  if index < 1 then index := 1;
  if count < 0 then count := 0;
  last := index + count - 1;
  if last > n then last := n;
  r := '';
  i := index;
  while i <= last do
  begin
    r := r + s[i];
    i := i + 1;
  end;
  Result := r;
end;

function Trim(const s: AnsiString): AnsiString;
var a, b: Integer;
begin
  a := 1;
  b := Length(s);
  while (a <= b) and (s[a] <= ' ') do a := a + 1;
  while (b >= a) and (s[b] <= ' ') do b := b - 1;
  Result := Copy(s, a, b - a + 1);
end;

function StrToIntDef(const s: AnsiString; def: Integer): Integer;
var v, i, sign: Integer; c: Char; started: Boolean;
begin
  Result := def;
  v := 0; sign := 1; i := 1; started := False;
  while (i <= Length(s)) and (s[i] = ' ') do i := i + 1;
  if (i <= Length(s)) and ((s[i] = '-') or (s[i] = '+')) then
  begin
    if s[i] = '-' then sign := -1;
    i := i + 1;
  end;
  while i <= Length(s) do
  begin
    c := s[i];
    if (c >= '0') and (c <= '9') then
    begin
      v := v * 10 + (Ord(c) - Ord('0'));
      started := True;
      i := i + 1;
    end
    else
      Exit;            { malformed -> def }
  end;
  if started then Result := sign * v;
end;

function StrToInt(const s: AnsiString): Integer;
begin
  Result := StrToIntDef(s, 0);
end;

function UpperCase(const s: AnsiString): AnsiString;
var i: Integer; r: AnsiString; c: Char;
begin
  r := '';
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if (c >= 'a') and (c <= 'z') then c := Chr(Ord(c) - 32);
    r := r + c;
  end;
  Result := r;
end;

function LowerCase(const s: AnsiString): AnsiString;
var i: Integer; r: AnsiString; c: Char;
begin
  r := '';
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if (c >= 'A') and (c <= 'Z') then c := Chr(Ord(c) + 32);
    r := r + c;
  end;
  Result := r;
end;

end.
