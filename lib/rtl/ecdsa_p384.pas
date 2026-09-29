{ SPDX-License-Identifier: Zlib }
unit ecdsa_p384;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ ECDSA signature VERIFICATION on NIST P-384 (secp384r1). Verify only: this is
  here so X.509 can check certificates signed by a P-384 key, which most public
  CAs' ECDSA hierarchies are (Let's Encrypt's Root YE / YE2, ISRG Root X2,
  Sectigo's E46, USERTrust ECC, GTS Root R4). Without it such a chain failed
  CLOSED: X509VerifySig answered FALSE and the native TLS client refused
  letsencrypt.org and github.com.

  Built as ecdsa_p256 is: the field on p384field (Montgomery over six 64-bit
  limbs), points in Jacobian coordinates with a = -3, one inversion at the end,
  and the scalar arithmetic mod n on bignum's TBigInt.

  The public key is checked to be a point on the curve before it is used.

  Verified against Python's cryptography (test/lib_ecdsa_p384.pas). No
  side-channel claim (see ecdsa_p256.pas); nothing secret passes through a
  verify. }

interface

{ True iff (r||s) (96 bytes) is a valid P-384 signature, under the public key
  qxy (96 bytes, Qx||Qy), of a message whose hash is `digest`. The digest may be
  any length; as FIPS 186-4 says, its leftmost 384 bits are used. }
function EcdsaP384VerifyHash(const qxy, digest, sig: AnsiString): Boolean;

{ The same over `msg`, hashed with SHA-384 (ecdsa_secp384r1_sha384). }
function EcdsaP384Verify(const qxy, msg, sig: AnsiString): Boolean;

implementation

uses bignum, p384field, sha512, sysutils;

var
  N: TBigInt;              { curve order }
  GXf, GYf, Bf: TFe384;    { generator and the curve's b, in Montgomery form }
  gInit: Boolean;

function Nyb(c: Char): Integer;
begin
  if (c >= '0') and (c <= '9') then Nyb := Ord(c) - Ord('0')
  else Nyb := Ord(c) - Ord('a') + 10;
end;

function HexToBytes(const h: AnsiString): AnsiString;
var i: Integer;
begin
  SetLength(Result, Length(h) div 2);
  for i := 0 to Length(h) div 2 - 1 do
    Result[i + 1] := Chr(Nyb(h[2 * i + 1]) * 16 + Nyb(h[2 * i + 2]));
end;

function BytesToBig(const s: AnsiString): TBigInt;
var acc, t, d: TBigInt; i: Integer;
begin
  acc := BigFromInt(0);
  for i := 1 to Length(s) do
  begin
    t := BigMulSmall(acc, 256);
    d := BigFromInt(Ord(s[i]));
    acc := BigAdd(t, d);
  end;
  Result := acc;
end;

{ a (0 <= a < 256^k) as k big-endian bytes. }
function BigToBytes(a: TBigInt; k: Integer): AnsiString;
var q, r, b256: TBigInt; i: Integer;
begin
  SetLength(Result, k);
  b256 := BigFromInt(256);
  for i := k downto 1 do
  begin
    BigDivMod(a, b256, q, r);
    Result[i] := Chr(StrToInt(BigToStr(r)) and $FF);
    a := q;
  end;
end;

procedure InitCurve;
var t: AnsiString;
begin
  if gInit then Exit;
  N := BytesToBig(HexToBytes(
    'ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973'));
  t := HexToBytes('aa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a385502f25dbf55296c3a545e3872760ab7');
  Fe384FromBytes(GXf, t);
  t := HexToBytes('3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c00a60b1ce1d7e819d7a431d7c90ea0e5f');
  Fe384FromBytes(GYf, t);
  t := HexToBytes('b3312fa7e23ee7e4988e056be3f82d19181d9c6efe8141120314088f5013875ac656398d8a2ed19d2a85c8edd3ec2aef');
  Fe384FromBytes(Bf, t);
  gInit := True;
end;

{ --- scalars mod n --- }

function MMul(const a, b, m: TBigInt): TBigInt;
var t, q, r: TBigInt;
begin
  t := BigMul(a, b);
  BigDivMod(t, m, q, r);
  Result := r;
end;

{ a^-1 mod m (m prime), extended Euclid -- see ecdsa_p256's MInv. }
function MInv(const a, m: TBigInt): TBigInt;
var r, newr, t, newt, q, rem, tmp, prod: TBigInt;
begin
  t    := BigFromInt(0);
  newt := BigFromInt(1);
  r    := m;
  newr := a;
  while not BigIsZero(newr) do
  begin
    BigDivMod(r, newr, q, rem);
    prod := BigMul(q, newt);
    tmp  := BigSubSigned(t, prod);
    t    := newt;
    newt := tmp;
    r    := newr;
    newr := rem;
  end;
  if BigCompare(t, BigFromInt(0)) < 0 then t := BigAddSigned(t, m);
  Result := t;
end;

{ --- the curve over the field (Jacobian, a = -3) --- }

procedure SetInfinity(var x, y, z: TFe384);
begin
  Fe384SetOne(x); Fe384SetOne(y); Fe384SetZero(z);
end;

procedure JacDouble(var x3, y3, z3: TFe384; const x1, y1, z1: TFe384);
var s, mm, t, u, yy, zz, nx, ny, nz, k: TFe384;
begin
  if Fe384IsZero(z1) or Fe384IsZero(y1) then
  begin
    SetInfinity(x3, y3, z3);
    Exit;
  end;
  { S = 4*x1*y1^2 }
  Fe384Sqr(yy, y1);
  Fe384Mul(t, x1, yy);
  Fe384SetInt(k, 4); Fe384Mul(s, k, t);
  { M = 3*(x1 - z1^2)*(x1 + z1^2) }
  Fe384Sqr(zz, z1);
  Fe384Sub(t, x1, zz);
  Fe384Add(u, x1, zz);
  Fe384Mul(mm, t, u);
  Fe384SetInt(k, 3); Fe384Mul(mm, mm, k);
  { x3 = M^2 - 2*S }
  Fe384Sqr(nx, mm);
  Fe384Add(t, s, s);
  Fe384Sub(nx, nx, t);
  { y3 = M*(S - x3) - 8*y1^4 }
  Fe384Sub(t, s, nx);
  Fe384Mul(ny, mm, t);
  Fe384Sqr(t, yy);
  Fe384SetInt(k, 8); Fe384Mul(t, k, t);
  Fe384Sub(ny, ny, t);
  { z3 = 2*y1*z1 }
  Fe384Mul(nz, y1, z1);
  Fe384Add(nz, nz, nz);
  x3 := nx; y3 := ny; z3 := nz;
end;

procedure JacAdd(var x3, y3, z3: TFe384; const x1, y1, z1, x2, y2, z2: TFe384);
var z1z1, z2z2, u1, u2, s1, s2, hh, rr, h2, h3, t, u, nx, ny, nz: TFe384;
begin
  if Fe384IsZero(z1) then begin x3 := x2; y3 := y2; z3 := z2; Exit; end;
  if Fe384IsZero(z2) then begin x3 := x1; y3 := y1; z3 := z1; Exit; end;
  Fe384Sqr(z1z1, z1);
  Fe384Sqr(z2z2, z2);
  Fe384Mul(u1, x1, z2z2);
  Fe384Mul(u2, x2, z1z1);
  Fe384Mul(t, z2, z2z2);  Fe384Mul(s1, y1, t);
  Fe384Mul(t, z1, z1z1);  Fe384Mul(s2, y2, t);
  if Fe384Equal(u1, u2) then
  begin
    if Fe384Equal(s1, s2) then JacDouble(x3, y3, z3, x1, y1, z1)
    else SetInfinity(x3, y3, z3);
    Exit;
  end;
  Fe384Sub(hh, u2, u1);
  Fe384Sub(rr, s2, s1);
  Fe384Sqr(h2, hh);
  Fe384Mul(h3, h2, hh);
  { x3 = rr^2 - h3 - 2*u1*h2 }
  Fe384Sqr(nx, rr);
  Fe384Sub(nx, nx, h3);
  Fe384Mul(t, u1, h2);
  Fe384Add(u, t, t);
  Fe384Sub(nx, nx, u);
  { y3 = rr*(u1*h2 - x3) - s1*h3 }
  Fe384Mul(t, u1, h2);
  Fe384Sub(t, t, nx);
  Fe384Mul(ny, rr, t);
  Fe384Mul(u, s1, h3);
  Fe384Sub(ny, ny, u);
  { z3 = hh*z1*z2 }
  Fe384Mul(t, z1, z2);
  Fe384Mul(nz, hh, t);
  x3 := nx; y3 := ny; z3 := nz;
end;

{ u1*G + u2*Q in one pass (Shamir's trick): one doubling per bit instead of two
  full scalar multiplies. Scalars are 48 big-endian bytes. }
procedure DoubleScalarMul(var rx, ry, rz: TFe384; const k1, k2: AnsiString;
                          const qx, qy: TFe384);
var
  i, bit, b1, b2: Integer;
  one, gqx, gqy, gqz: TFe384;
begin
  Fe384SetOne(one);
  JacAdd(gqx, gqy, gqz, GXf, GYf, one, qx, qy, one);     { G + Q }
  SetInfinity(rx, ry, rz);
  for i := 1 to 48 do
    for bit := 7 downto 0 do
    begin
      JacDouble(rx, ry, rz, rx, ry, rz);
      b1 := (Ord(k1[i]) shr bit) and 1;
      b2 := (Ord(k2[i]) shr bit) and 1;
      if (b1 = 1) and (b2 = 1) then JacAdd(rx, ry, rz, rx, ry, rz, gqx, gqy, gqz)
      else if b1 = 1 then JacAdd(rx, ry, rz, rx, ry, rz, GXf, GYf, one)
      else if b2 = 1 then JacAdd(rx, ry, rz, rx, ry, rz, qx, qy, one);
    end;
end;

{ y^2 = x^3 - 3x + b }
function OnCurve(const x, y: TFe384): Boolean;
var lhs, rhs, t, three: TFe384;
begin
  Fe384Sqr(lhs, y);
  Fe384Sqr(t, x);
  Fe384Mul(rhs, t, x);
  Fe384SetInt(three, 3);
  Fe384Mul(t, three, x);
  Fe384Sub(rhs, rhs, t);
  Fe384Add(rhs, rhs, Bf);
  OnCurve := Fe384Equal(lhs, rhs);
end;

function EcdsaP384VerifyHash(const qxy, digest, sig: AnsiString): Boolean;
var
  r, s, e, w, u1, u2, one, affx, q1, affxModN: TBigInt;
  qxb, qyb, h: AnsiString;
  qx, qy, rx, ry, rz, zinv, zinv2, ax: TFe384;
begin
  Result := False;
  if (Length(qxy) <> 96) or (Length(sig) <> 96) then Exit;
  InitCurve;

  r := BytesToBig(Copy(sig, 1, 48));
  s := BytesToBig(Copy(sig, 49, 48));
  one := BigFromInt(1);
  if (BigCompare(r, one) < 0) or (BigCompare(r, N) >= 0) then Exit;
  if (BigCompare(s, one) < 0) or (BigCompare(s, N) >= 0) then Exit;

  { the leftmost 384 bits of the digest; a shorter digest is used whole }
  h := digest;
  if Length(h) > 48 then h := Copy(h, 1, 48);
  e := BytesToBig(h);

  w  := MInv(s, N);
  u1 := MMul(e, w, N);
  u2 := MMul(r, w, N);

  qxb := Copy(qxy, 1, 48);
  qyb := Copy(qxy, 49, 48);
  if not Fe384BytesInRange(qxb) then Exit;
  if not Fe384BytesInRange(qyb) then Exit;
  Fe384FromBytes(qx, qxb);
  Fe384FromBytes(qy, qyb);
  if not OnCurve(qx, qy) then Exit;

  DoubleScalarMul(rx, ry, rz, BigToBytes(u1, 48), BigToBytes(u2, 48), qx, qy);
  if Fe384IsZero(rz) then Exit;           { R = infinity -> invalid }

  Fe384Inv(zinv, rz);
  Fe384Sqr(zinv2, zinv);
  Fe384Mul(ax, rx, zinv2);
  affx := BytesToBig(Fe384ToBytes(ax));
  BigDivMod(affx, N, q1, affxModN);
  Result := BigCompare(affxModN, r) = 0;
end;

function EcdsaP384Verify(const qxy, msg, sig: AnsiString): Boolean;
begin
  Result := EcdsaP384VerifyHash(qxy, Sha384(msg), sig);
end;

end.
