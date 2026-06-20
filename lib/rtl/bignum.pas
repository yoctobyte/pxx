unit bignum;
{ Arbitrary-precision signed integers. Schoolbook algorithms, correctness over
  speed. Limbs are base 1e9, little-endian, stored as Int64 (the partial
  products limb*limb ~1e18 fit a 64-bit intermediate).

  Track B; pinned stable (v11+; the record-fn codegen crash that blocked BigMul
  is fixed). }

interface

uses sysutils;   { IntToStr }

const
  BIG_BASE   = 1000000000;   { 1e9 per limb }
  BIG_DIGITS = 9;

type
  TBigInt = record
    neg:   Boolean;
    limbs: array of Int64;    { base 1e9, little-endian, no trailing zero limbs }
  end;

function BigFromInt(n: Int64): TBigInt;
function BigToStr(const a: TBigInt): AnsiString;
function BigCompareMag(const a, b: TBigInt): Integer;   { |a| vs |b|: -1/0/1 }
function BigMulSmall(const a: TBigInt; m: Int64): TBigInt;
function BigAdd(const a, b: TBigInt): TBigInt;           { unsigned magnitudes }
function BigSub(const a, b: TBigInt): TBigInt;           { unsigned |a| - |b|, assumes |a| >= |b| }
function BigMul(const a, b: TBigInt): TBigInt;           { signed bignum*bignum }

implementation

{ Drop trailing (most-significant) zero limbs; empty list represents zero. }
procedure Normalize(var a: TBigInt);
var n: Integer;
begin
  n := Length(a.limbs);
  while (n > 0) and (a.limbs[n - 1] = 0) do n := n - 1;
  SetLength(a.limbs, n);
  if n = 0 then a.neg := False;
end;

function BigFromInt(n: Int64): TBigInt;
var r: TBigInt; cnt: Integer; v: Int64;
begin
  r.neg := n < 0;
  if r.neg then n := -n;
  { count limbs }
  cnt := 0; v := n;
  while v > 0 do begin cnt := cnt + 1; v := v div BIG_BASE; end;
  SetLength(r.limbs, cnt);
  cnt := 0; v := n;
  while v > 0 do
  begin
    r.limbs[cnt] := v mod BIG_BASE;
    v := v div BIG_BASE;
    cnt := cnt + 1;
  end;
  Normalize(r);
  BigFromInt := r;
end;

function Pad9(v: Int64): AnsiString;
var s: AnsiString;
begin
  s := IntToStr(Integer(v));
  while Length(s) < BIG_DIGITS do s := '0' + s;
  Pad9 := s;
end;

function BigToStr(const a: TBigInt): AnsiString;
var i, n: Integer; s: AnsiString;
begin
  n := Length(a.limbs);
  if n = 0 then
  begin
    BigToStr := '0';
    Exit;
  end;
  s := IntToStr(Integer(a.limbs[n - 1]));   { top limb: no padding }
  i := n - 2;
  while i >= 0 do
  begin
    s := s + Pad9(a.limbs[i]);
    i := i - 1;
  end;
  if a.neg then s := '-' + s;
  BigToStr := s;
end;

function BigCompareMag(const a, b: TBigInt): Integer;
var na, nb, i: Integer;
begin
  na := Length(a.limbs); nb := Length(b.limbs);
  if na <> nb then
  begin
    if na > nb then BigCompareMag := 1 else BigCompareMag := -1;
    Exit;
  end;
  i := na - 1;
  while i >= 0 do
  begin
    if a.limbs[i] <> b.limbs[i] then
    begin
      if a.limbs[i] > b.limbs[i] then BigCompareMag := 1 else BigCompareMag := -1;
      Exit;
    end;
    i := i - 1;
  end;
  BigCompareMag := 0;
end;

function BigMulSmall(const a: TBigInt; m: Int64): TBigInt;
var r: TBigInt; i, na: Integer; carry, cur: Int64;
begin
  na := Length(a.limbs);
  if (na = 0) or (m = 0) then
  begin
    BigMulSmall := BigFromInt(0);
    Exit;
  end;
  r.neg := a.neg;
  if m < 0 then begin r.neg := not r.neg; m := -m; end;
  SetLength(r.limbs, na + 2);
  carry := 0;
  for i := 0 to na - 1 do
  begin
    cur := a.limbs[i] * m + carry;
    r.limbs[i] := cur mod BIG_BASE;
    carry := cur div BIG_BASE;
  end;
  i := na;
  while carry > 0 do
  begin
    r.limbs[i] := carry mod BIG_BASE;
    carry := carry div BIG_BASE;
    i := i + 1;
  end;
  while i < na + 2 do begin r.limbs[i] := 0; i := i + 1; end;
  Normalize(r);
  BigMulSmall := r;
end;

function BigSub(const a, b: TBigInt): TBigInt;
var r: TBigInt; i, na, nb, n: Integer; borrow, cur, av: Int64;
begin
  na := Length(a.limbs); nb := Length(b.limbs);
  if na > nb then n := na else n := nb;
  SetLength(r.limbs, n);
  borrow := 0;
  for i := 0 to n - 1 do
  begin
    if i < na then av := a.limbs[i] else av := 0;
    cur := av - borrow;
    if i < nb then cur := cur - b.limbs[i];
    if cur < 0 then
    begin
      cur := cur + BIG_BASE;
      borrow := 1;
    end
    else
      borrow := 0;
    r.limbs[i] := cur;
  end;
  r.neg := False;
  Normalize(r);
  BigSub := r;
end;

function BigMul(const a, b: TBigInt): TBigInt;
var r: TBigInt; i, j, na, nb: Integer; carry, cur: Int64;
begin
  na := Length(a.limbs); nb := Length(b.limbs);
  if (na = 0) or (nb = 0) then
  begin
    BigMul := BigFromInt(0);
    Exit;
  end;
  SetLength(r.limbs, na + nb);
  for i := 0 to na + nb - 1 do r.limbs[i] := 0;
  for i := 0 to na - 1 do
  begin
    carry := 0;
    for j := 0 to nb - 1 do
    begin
      cur := a.limbs[i] * b.limbs[j] + r.limbs[i + j] + carry;
      r.limbs[i + j] := cur mod BIG_BASE;
      carry := cur div BIG_BASE;
    end;
    r.limbs[i + nb] := r.limbs[i + nb] + carry;
  end;
  r.neg := a.neg <> b.neg;
  Normalize(r);
  BigMul := r;
end;

function BigAdd(const a, b: TBigInt): TBigInt;
var r: TBigInt; i, na, nb, n: Integer; carry, cur: Int64;
begin
  na := Length(a.limbs); nb := Length(b.limbs);
  if na > nb then n := na else n := nb;
  SetLength(r.limbs, n + 1);
  carry := 0;
  for i := 0 to n - 1 do
  begin
    cur := carry;
    if i < na then cur := cur + a.limbs[i];
    if i < nb then cur := cur + b.limbs[i];
    r.limbs[i] := cur mod BIG_BASE;
    carry := cur div BIG_BASE;
  end;
  r.limbs[n] := carry;
  r.neg := False;
  Normalize(r);
  BigAdd := r;
end;

end.
