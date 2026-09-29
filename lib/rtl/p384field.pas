{ SPDX-License-Identifier: Zlib }
unit p384field;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Arithmetic in GF(p) for the NIST P-384 prime

    p = 2^384 - 2^128 - 2^96 + 2^32 - 1

  on six saturated 64-bit limbs (little-endian), in Montgomery form with
  R = 2^384. The sibling of p256field, written as LOOPS over the limb count
  rather than unrolled: P-384 is here for certificate verification (a few
  verifies per TLS handshake), not for bulk work.

  One difference from p256field that matters: P-384's n0' = -p^-1 mod 2^64 is
  NOT 1 (it is 2^32 + 1), so the reduction multiplier is m = t[0] * n0'.

  Constants were computed with Python from the FIPS 186-4 / SEC 2 curve
  parameters; see test/lib_ecdsa_p384.pas for the oracle.

  No side-channel claim, as for every unit of the from-scratch crypto (see the
  note in ecdsa_p256.pas): it is used to VERIFY public signatures. }

interface

uses wideint;

type
  { Little-endian: limb 0 is the least significant. Values are kept fully
    reduced (< p) at every public boundary. }
  TFe384 = array[0..5] of UInt64;

{ --- conversion --- }
procedure Fe384FromBytes(var r: TFe384; const s: AnsiString);  { 48 bytes, big-endian -> Montgomery form }
function  Fe384ToBytes(const a: TFe384): AnsiString;           { Montgomery form -> 48 bytes, big-endian }
procedure Fe384SetInt(var r: TFe384; v: UInt64);               { small integer -> Montgomery form }
procedure Fe384SetZero(var r: TFe384);
procedure Fe384SetOne(var r: TFe384);

{ --- field ops (operands and results in Montgomery form; may alias) --- }
procedure Fe384Add(var r: TFe384; const a, b: TFe384);
procedure Fe384Sub(var r: TFe384; const a, b: TFe384);
procedure Fe384Mul(var r: TFe384; const a, b: TFe384);
procedure Fe384Sqr(var r: TFe384; const a: TFe384);
procedure Fe384Inv(var r: TFe384; const a: TFe384);           { a^(p-2); Inv(0) = 0 }

function  Fe384IsZero(const a: TFe384): Boolean;
function  Fe384Equal(const a, b: TFe384): Boolean;

{ True if the 48 big-endian bytes are a value < p. }
function  Fe384BytesInRange(const s: AnsiString): Boolean;

implementation

const
  NL = 6;
  N0P = UInt64($0000000100000001);   { -p^-1 mod 2^64 }

procedure LoadP(var p: TFe384);
begin
  p[0] := UInt64($00000000FFFFFFFF); p[1] := UInt64($FFFFFFFF00000000);
  p[2] := UInt64($FFFFFFFFFFFFFFFE); p[3] := UInt64($FFFFFFFFFFFFFFFF);
  p[4] := UInt64($FFFFFFFFFFFFFFFF); p[5] := UInt64($FFFFFFFFFFFFFFFF);
end;

{ R^2 mod p, for converting into Montgomery form }
procedure LoadRR(var p: TFe384);
begin
  p[0] := UInt64($FFFFFFFE00000001); p[1] := UInt64($0000000200000000);
  p[2] := UInt64($FFFFFFFE00000000); p[3] := UInt64($0000000200000000);
  p[4] := UInt64($0000000000000001); p[5] := UInt64($0000000000000000);
end;

{ s := x + y*z + cin as the 128-bit (cout, s). Cannot overflow. }
procedure MulAdd(x, y, z, cin: UInt64; var s, cout: UInt64);
var lo, hi, t: UInt64;
begin
  lo := y * z;
  hi := MulHiU64(y, z);
  t := lo + x;
  if t < lo then hi := hi + 1;
  lo := t;
  t := lo + cin;
  if t < lo then hi := hi + 1;
  s := t;
  cout := hi;
end;

{ r := a - b over NL limbs; returns the borrow out (0 or 1). }
function SubN(var r: TFe384; const a, b: TFe384): UInt64;
var i: Integer; t, d, borrow, b1: UInt64;
begin
  borrow := 0;
  for i := 0 to NL - 1 do
  begin
    t := a[i] - b[i];
    b1 := 0;
    if a[i] < b[i] then b1 := 1;
    d := t - borrow;
    if t < borrow then b1 := 1;
    r[i] := d;
    borrow := b1;
  end;
  SubN := borrow;
end;

{ r := a + b over NL limbs; returns the carry out (0 or 1). }
function AddN(var r: TFe384; const a, b: TFe384): UInt64;
var i: Integer; s, s2, carry, c1: UInt64;
begin
  carry := 0;
  for i := 0 to NL - 1 do
  begin
    s := a[i] + b[i];
    c1 := 0;
    if s < a[i] then c1 := 1;
    s2 := s + carry;
    if s2 < s then c1 := 1;
    r[i] := s2;
    carry := c1;
  end;
  AddN := carry;
end;

{ Montgomery product: r := a*b*R^-1 mod p (CIOS). }
procedure MontMul(var r: TFe384; const a, b: TFe384);
var
  t: array[0..NL + 1] of UInt64;
  lo, p, d: TFe384;
  i, j: Integer;
  c, s, m, x: UInt64;
begin
  LoadP(p);
  for i := 0 to NL + 1 do t[i] := 0;
  for i := 0 to NL - 1 do
  begin
    { t := t + a*b[i] }
    c := 0;
    for j := 0 to NL - 1 do
    begin
      MulAdd(t[j], a[j], b[i], c, s, c);
      t[j] := s;
    end;
    x := t[NL] + c;
    if x < c then t[NL + 1] := t[NL + 1] + 1;
    t[NL] := x;

    { t := (t + m*p) / 2^64 }
    m := t[0] * N0P;
    MulAdd(t[0], m, p[0], 0, s, c);      { s is zero by construction }
    for j := 1 to NL - 1 do
    begin
      MulAdd(t[j], m, p[j], c, s, c);
      t[j - 1] := s;
    end;
    x := t[NL] + c;
    t[NL - 1] := x;
    if x < c then t[NL + 1] := t[NL + 1] + 1;
    t[NL] := t[NL + 1];
    t[NL + 1] := 0;
  end;

  { t < 2p: subtract p once unless t already fits }
  for i := 0 to NL - 1 do lo[i] := t[i];
  if (SubN(d, lo, p) = 1) and (t[NL] = 0) then r := lo
  else r := d;
end;

procedure Fe384Mul(var r: TFe384; const a, b: TFe384);
begin
  MontMul(r, a, b);
end;

procedure Fe384Sqr(var r: TFe384; const a: TFe384);
begin
  MontMul(r, a, a);
end;

procedure Fe384SetZero(var r: TFe384);
var i: Integer;
begin
  for i := 0 to NL - 1 do r[i] := 0;
end;

procedure Fe384SetOne(var r: TFe384);
begin
  { R mod p }
  r[0] := UInt64($FFFFFFFF00000001); r[1] := UInt64($00000000FFFFFFFF);
  r[2] := UInt64($0000000000000001); r[3] := 0; r[4] := 0; r[5] := 0;
end;

function Fe384IsZero(const a: TFe384): Boolean;
var i: Integer;
begin
  Result := True;
  for i := 0 to NL - 1 do if a[i] <> 0 then Result := False;
end;

function Fe384Equal(const a, b: TFe384): Boolean;
var i: Integer;
begin
  Result := True;
  for i := 0 to NL - 1 do if a[i] <> b[i] then Result := False;
end;

{ r := a + b mod p }
procedure Fe384Add(var r: TFe384; const a, b: TFe384);
var t, d, p: TFe384; carry: UInt64;
begin
  LoadP(p);
  carry := AddN(t, a, b);
  { subtract p if the sum overflowed, or if it is >= p (no borrow) }
  if (SubN(d, t, p) = 0) or (carry = 1) then r := d
  else r := t;
end;

{ r := a - b mod p }
procedure Fe384Sub(var r: TFe384; const a, b: TFe384);
var t, p: TFe384;
begin
  LoadP(p);
  if SubN(t, a, b) = 1 then AddN(r, t, p)   { went negative: add p back }
  else r := t;
end;

{ a^(p-2) mod p, square-and-multiply over the (public) bits of p-2. }
procedure Fe384Inv(var r: TFe384; const a: TFe384);
var e, acc, base: TFe384; i, bit: Integer; w: UInt64;
begin
  if Fe384IsZero(a) then
  begin
    Fe384SetZero(r);
    Exit;
  end;
  LoadP(e);
  e[0] := e[0] - 2;                   { p[0] = 2^32-1, so no borrow }
  Fe384SetOne(acc);
  base := a;
  for i := 0 to NL - 1 do
  begin
    w := e[i];
    for bit := 0 to 63 do
    begin
      if (w and 1) = 1 then Fe384Mul(acc, acc, base);
      Fe384Sqr(base, base);
      w := w shr 1;
    end;
  end;
  r := acc;
end;

{ --- byte conversion (48 bytes, big-endian) --- }

procedure BytesToLimbs(var t: TFe384; const s: AnsiString);
var i, j: Integer; w: UInt64;
begin
  for i := 0 to NL - 1 do
  begin
    w := 0;
    for j := 0 to 7 do
      w := (w shl 8) or UInt64(Ord(s[48 - 8 * (i + 1) + j + 1]));
    t[i] := w;
  end;
end;

function Fe384BytesInRange(const s: AnsiString): Boolean;
var t, p, d: TFe384;
begin
  if Length(s) <> 48 then
  begin
    Fe384BytesInRange := False;
    Exit;
  end;
  BytesToLimbs(t, s);
  LoadP(p);
  Fe384BytesInRange := SubN(d, t, p) = 1;    { t - p borrows iff t < p }
end;

procedure Fe384FromBytes(var r: TFe384; const s: AnsiString);
var t, rr: TFe384;
begin
  BytesToLimbs(t, s);
  LoadRR(rr);
  MontMul(r, t, rr);        { a * R^2 * R^-1 = a*R }
end;

function Fe384ToBytes(const a: TFe384): AnsiString;
var t, one: TFe384; s: AnsiString; i, j: Integer; w: UInt64;
begin
  Fe384SetZero(one); one[0] := 1;
  MontMul(t, a, one);       { strips the R factor }
  SetLength(s, 48);
  for i := 0 to NL - 1 do
  begin
    w := t[i];
    for j := 0 to 7 do
    begin
      s[48 - 8 * i - j] := Chr(Integer(w and $FF));
      w := w shr 8;
    end;
  end;
  Fe384ToBytes := s;
end;

procedure Fe384SetInt(var r: TFe384; v: UInt64);
var t, rr: TFe384;
begin
  Fe384SetZero(t);
  t[0] := v;
  LoadRR(rr);
  MontMul(r, t, rr);
end;

end.
