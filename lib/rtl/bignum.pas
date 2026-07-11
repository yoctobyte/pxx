{ SPDX-License-Identifier: Zlib }
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
function BigFromStr(const s: AnsiString): TBigInt;       { base-10, optional leading '-' }
function BigToStr(const a: TBigInt): AnsiString;
function BigCompareMag(const a, b: TBigInt): Integer;   { |a| vs |b|: -1/0/1 }
function BigCompare(const a, b: TBigInt): Integer;      { signed a vs b: -1/0/1 }
function BigIsZero(const a: TBigInt): Boolean;
function BigNegate(const a: TBigInt): TBigInt;          { signed negation (zero stays +) }
function BigMulSmall(const a: TBigInt; m: Int64): TBigInt;
function BigAdd(const a, b: TBigInt): TBigInt;           { unsigned magnitudes }
function BigSub(const a, b: TBigInt): TBigInt;           { unsigned |a| - |b|, assumes |a| >= |b| }
function BigMul(const a, b: TBigInt): TBigInt;           { signed bignum*bignum }
function BigAddSigned(const a, b: TBigInt): TBigInt;     { signed a + b }
function BigSubSigned(const a, b: TBigInt): TBigInt;     { signed a - b }
procedure BigDivMod(const a, b: TBigInt; var q, r: TBigInt);  { trunc-toward-zero: q*b + r = a, sign(r)=sign(a) }
function BigModPow(const base, exp, m: TBigInt): TBigInt;     { (base^exp) mod m, exp >= 0 }

{ Operator layer — thin wrappers over the signed function API above
  (feature-lib-bignum-operators). TBigInt is a managed record (dynarray
  limbs), so chained operator expressions (`c := a * b + a`) deliberately
  exercise the managed-temp lifetime path. No `/` overload: TBigInt is an
  integer type, use div/mod. }
operator + (a, b: TBigInt) r: TBigInt;
operator - (a, b: TBigInt) r: TBigInt;
operator * (a, b: TBigInt) r: TBigInt;
operator div (a, b: TBigInt) q: TBigInt;
operator mod (a, b: TBigInt) r: TBigInt;
operator = (a, b: TBigInt) eq: Boolean;
operator <> (a, b: TBigInt) ne: Boolean;
operator < (a, b: TBigInt) lt: Boolean;
operator <= (a, b: TBigInt) le: Boolean;
operator > (a, b: TBigInt) gt: Boolean;
operator >= (a, b: TBigInt) ge: Boolean;

implementation

operator + (a, b: TBigInt) r: TBigInt;
begin
  r := BigAddSigned(a, b);
end;

operator - (a, b: TBigInt) r: TBigInt;
begin
  r := BigSubSigned(a, b);
end;

operator * (a, b: TBigInt) r: TBigInt;
begin
  r := BigMul(a, b);
end;

operator div (a, b: TBigInt) q: TBigInt;
var rem: TBigInt;
begin
  BigDivMod(a, b, q, rem);
end;

operator mod (a, b: TBigInt) r: TBigInt;
var quo: TBigInt;
begin
  BigDivMod(a, b, quo, r);
end;

operator = (a, b: TBigInt) eq: Boolean;
begin
  eq := BigCompare(a, b) = 0;
end;

operator <> (a, b: TBigInt) ne: Boolean;
begin
  ne := BigCompare(a, b) <> 0;
end;

operator < (a, b: TBigInt) lt: Boolean;
begin
  lt := BigCompare(a, b) < 0;
end;

operator <= (a, b: TBigInt) le: Boolean;
begin
  le := BigCompare(a, b) <= 0;
end;

operator > (a, b: TBigInt) gt: Boolean;
begin
  gt := BigCompare(a, b) > 0;
end;

operator >= (a, b: TBigInt) ge: Boolean;
begin
  ge := BigCompare(a, b) >= 0;
end;

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

function BigIsZero(const a: TBigInt): Boolean;
begin
  BigIsZero := Length(a.limbs) = 0;
end;

function BigNegate(const a: TBigInt): TBigInt;
var r: TBigInt;
begin
  r := a;                       { copies limbs ref + sign }
  if not BigIsZero(r) then r.neg := not a.neg else r.neg := False;
  BigNegate := r;
end;

function BigCompare(const a, b: TBigInt): Integer;
begin
  if a.neg <> b.neg then
  begin
    if a.neg then BigCompare := -1 else BigCompare := 1;   { neg < pos; zero is never neg }
    Exit;
  end;
  { same sign }
  if a.neg then
    BigCompare := -BigCompareMag(a, b)     { both negative: larger magnitude is smaller }
  else
    BigCompare := BigCompareMag(a, b);
end;

function BigAddSigned(const a, b: TBigInt): TBigInt;
var r: TBigInt; c: Integer;
begin
  if a.neg = b.neg then
  begin
    r := BigAdd(a, b);                 { same sign: add magnitudes, keep sign }
    if not BigIsZero(r) then r.neg := a.neg;
  end
  else
  begin
    c := BigCompareMag(a, b);          { differing signs: subtract smaller mag }
    if c = 0 then
      r := BigFromInt(0)
    else if c > 0 then
    begin
      r := BigSub(a, b);
      if not BigIsZero(r) then r.neg := a.neg;
    end
    else
    begin
      r := BigSub(b, a);
      if not BigIsZero(r) then r.neg := b.neg;
    end;
  end;
  BigAddSigned := r;
end;

function BigSubSigned(const a, b: TBigInt): TBigInt;
var nb: TBigInt;
begin
  nb := BigNegate(b);
  BigSubSigned := BigAddSigned(a, nb);
end;

function BigFromStr(const s: AnsiString): TBigInt;
var r, t, dig: TBigInt; i, n: Integer; neg: Boolean; d: Int64;
begin
  r := BigFromInt(0);
  n := Length(s);
  i := 1;
  neg := False;
  if (n >= 1) and ((s[1] = '-') or (s[1] = '+')) then
  begin
    neg := s[1] = '-';
    i := 2;
  end;
  while i <= n do
  begin
    d := Ord(s[i]) - Ord('0');
    if (d >= 0) and (d <= 9) then
    begin
      { temps on purpose: a managed-return call passed straight as an arg to
        another call corrupts loop state on pinned stable -- see
        bug-nested-managed-return-call-arg }
      t := BigMulSmall(r, 10);
      dig := BigFromInt(d);
      r := BigAdd(t, dig);
    end;
    i := i + 1;
  end;
  if not BigIsZero(r) then r.neg := neg;
  BigFromStr := r;
end;

{ Long division, base 1e9. Magnitude division of |a| by |b|; quotient truncates
  toward zero, remainder takes the dividend's sign (FPC div/mod semantics).
  Quotient limbs found by binary search per position (correctness over speed). }
procedure BigDivMod(const a, b: TBigInt; var q, r: TBigInt);
var rem, qq, prod, shifted, dlimb: TBigInt; na, i: Integer; lo, hi, mid, d: Int64;
begin
  qq := BigFromInt(0);
  rem := BigFromInt(0);
  na := Length(a.limbs);
  if BigIsZero(b) or (na = 0) then
  begin
    q := BigFromInt(0);
    r := BigFromInt(0);
    Exit;
  end;

  SetLength(qq.limbs, na);
  for i := 0 to na - 1 do qq.limbs[i] := 0;

  i := na - 1;
  while i >= 0 do
  begin
    { rem := rem * BASE + a.limbs[i]  (temps: see bug-nested-managed-return-call-arg) }
    shifted := BigMulSmall(rem, BIG_BASE);
    dlimb := BigFromInt(a.limbs[i]);
    rem := BigAdd(shifted, dlimb);
    { largest d in [0, BASE-1] with |b|*d <= rem }
    lo := 0; hi := BIG_BASE - 1;
    while lo < hi do
    begin
      mid := (lo + hi + 1) div 2;
      prod := BigMulSmall(b, mid);
      prod.neg := False;
      if BigCompareMag(prod, rem) <= 0 then lo := mid else hi := mid - 1;
    end;
    d := lo;
    qq.limbs[i] := d;
    if d > 0 then
    begin
      prod := BigMulSmall(b, d);
      prod.neg := False;
      rem := BigSub(rem, prod);     { rem >= prod by construction }
    end;
    i := i - 1;
  end;

  qq.neg := a.neg <> b.neg;
  Normalize(qq);
  rem.neg := a.neg;
  Normalize(rem);
  q := qq;
  r := rem;
end;

{ (base^exp) mod m via square-and-multiply. exp treated as non-negative
  magnitude; result is the least non-negative residue (sign of m ignored). }
function BigModPow(const base, exp, m: TBigInt): TBigInt;
var result, b, e, q, two, prod: TBigInt; odd: Boolean;
begin
  if BigIsZero(m) then
  begin
    BigModPow := BigFromInt(0);
    Exit;
  end;
  result := BigFromInt(1);
  two := BigFromInt(2);

  { b := base mod m (non-negative) }
  BigDivMod(base, m, q, b);
  b.neg := False;

  e := exp;
  e.neg := False;

  { temps for every managed-return result before it's passed on -- see
    bug-nested-managed-return-call-arg }
  while not BigIsZero(e) do
  begin
    odd := (e.limbs[0] mod 2) = 1;
    if odd then
    begin
      prod := BigMul(result, b);
      BigDivMod(prod, m, q, result);
      result.neg := False;
    end;
    prod := BigMul(b, b);
    BigDivMod(prod, m, q, b);
    b.neg := False;
    BigDivMod(e, two, e, q);     { e := e div 2 (quotient -> e, remainder discarded into q) }
  end;

  BigModPow := result;
end;

end.
