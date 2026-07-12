{ SPDX-License-Identifier: Zlib }
unit ecdsa_p256;
{ ECDSA on NIST P-256 (secp256r1) with SHA-256 (ecdsa_secp256r1_sha256):
  verify, sign, keygen. Part of milestone M4 of feature-tls13-from-scratch.

  Two different arithmetics, on purpose:

  - The FIELD (mod p) — every coordinate operation inside the scalar multiply,
    which is the hot path (256 doublings plus up to 256 additions, ~10 field
    multiplies each) — runs on `p256field`: Montgomery/CIOS over four saturated
    64-bit limbs, no division anywhere. Points are kept in Jacobian coordinates
    so only ONE inversion is needed, at the end.

  - The SCALAR (mod n, the curve ORDER) — k^-1, e + r*d — stays on the generic
    `bignum` TBigInt. It is a handful of operations per signature, nowhere near
    hot, and n is not p so it would need its own Montgomery constants for no
    real gain.

  This split is where the speed comes from: the field used to run on TBigInt
  too (base-1e9 limbs, a full BigDivMod to reduce every multiply), which is why
  a verify cost ~480ms while x25519 in this same RTL does an ECDH in ~5ms off
  dedicated fixed-limb arithmetic.

  Inputs/outputs are unchanged: the public key as 64 raw bytes (Qx||Qy), the
  message, and the signature as r||s (32 bytes each).

  NB bignum quirk: a managed-record-returning call must not be passed straight as
  an argument to another call (bug-managed-record-result-self-arg) — every
  intermediate is bound to a temp here. }

interface

{ True iff (r||s) is a valid P-256/SHA-256 signature of `msg` under the public
  key `qxy` (64 bytes, Qx||Qy). `sig` is 64 bytes (r||s). }
function EcdsaP256Verify(const qxy, msg, sig: AnsiString): Boolean;

{ Public key Qx||Qy (64 bytes) from a 32-byte private scalar. '' on error. }
function EcdsaP256PubFromPriv(const priv: AnsiString): AnsiString;

{ Sign SHA-256(msg) with private scalar `priv` (32 bytes) and an explicit 32-byte
  nonce `k32`. Returns 64-byte r||s, or '' if r=0/s=0 (retry with a new nonce).
  NOTE: reusing or leaking k reveals the private key — the random-nonce wrapper
  below is what callers should use. }
function EcdsaP256SignK(const priv, msg, k32: AnsiString): AnsiString;

{ Sign with a fresh CSPRNG nonce (getrandom). Returns 64-byte r||s, '' on failure. }
function EcdsaP256Sign(const priv, msg: AnsiString): AnsiString;

{ Generate a keypair: priv = 32 bytes, pub = 64 bytes (Qx||Qy). False on failure. }
function EcdsaP256GenKey(var priv, pub: AnsiString): Boolean;

implementation

uses bignum, p256field, sha256, sysutils, random;

var
  N: TBigInt;            { curve order — scalar arithmetic only }
  GXf, GYf: TFe;         { generator, in the field representation }
  gInit: Boolean;

function Nyb(c: Char): Integer;
begin
  if (c >= '0') and (c <= '9') then Nyb := Ord(c) - Ord('0')
  else Nyb := Ord(c) - Ord('a') + 10;
end;

function HexToBig(const h: AnsiString): TBigInt;
var acc, t, d: TBigInt; i, v: Integer;
begin
  acc := BigFromInt(0);
  i := 1;
  while i + 1 <= Length(h) do
  begin
    v := (Nyb(h[i]) shl 4) or Nyb(h[i+1]);
    t := BigMulSmall(acc, 256);
    d := BigFromInt(v);
    acc := BigAdd(t, d);
    i := i + 2;
  end;
  Result := acc;
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

{ 64 hex chars -> the 32 raw big-endian bytes the field unit consumes }
function HexToBytes32(const h: AnsiString): AnsiString;
var s: AnsiString; i: Integer;
begin
  SetLength(s, 32);
  for i := 0 to 31 do
    s[i + 1] := Chr(Nyb(h[2 * i + 1]) * 16 + Nyb(h[2 * i + 2]));
  HexToBytes32 := s;
end;

procedure InitCurve;
var t: AnsiString;
begin
  if gInit then Exit;
  N := HexToBig('ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551');
  t := HexToBytes32('6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296');
  FeFromBytes(GXf, t);
  t := HexToBytes32('4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5');
  FeFromBytes(GYf, t);
  gInit := True;
end;

{ --- scalar arithmetic mod n (the curve ORDER). Not hot: a few ops per
      signature, so the generic bignum path is fine. --- }
function MAdd(const a, b, m: TBigInt): TBigInt;
var t: TBigInt;
begin
  t := BigAddSigned(a, b);
  if BigCompare(t, m) >= 0 then t := BigSubSigned(t, m);
  Result := t;
end;

function MMul(const a, b, m: TBigInt): TBigInt;
var t, q, r: TBigInt;
begin
  t := BigMul(a, b);
  BigDivMod(t, m, q, r);
  Result := r;
end;

{ a^-1 mod m, by the extended Euclidean algorithm.

  The obvious alternative is Fermat (a^(m-2), m prime), which is what this used
  to do — but that is a 256-bit modexp: ~256 squarings, each a full bignum
  multiply plus a reduction. Euclid converges in ~O(log m) divmods instead, and
  with BigDivMod now on Knuth D it is roughly 20x cheaper. It was the single
  biggest cost left in a sign/verify once the field moved to p256field.

  m must be prime (n is), so gcd(a, m) = 1 for any a in [1, m-1]. }
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

    { (t, newt) := (newt, t - q*newt) }
    prod := BigMul(q, newt);
    tmp  := BigSubSigned(t, prod);
    t    := newt;
    newt := tmp;

    { (r, newr) := (newr, r - q*newr) = (newr, rem) }
    r    := newr;
    newr := rem;
  end;

  { t may be negative — bring it back into [0, m) }
  if BigCompare(t, BigFromInt(0)) < 0 then t := BigAddSigned(t, m);
  Result := t;
end;

{ --- the curve, over the FIELD (mod p): all TFe, all Montgomery --- }

{ the point at infinity, in Jacobian coordinates: z = 0 }
procedure SetInfinity(var x, y, z: TFe);
begin
  FeSetOne(x); FeSetOne(y); FeSetZero(z);
end;

{ Jacobian doubling (a = -3): (x3,y3,z3) := 2*(x1,y1,z1). May alias inputs. }
procedure JacDouble(var x3, y3, z3: TFe; const x1, y1, z1: TFe);
var s, mm, t, u, yy, zz, nx, ny, nz, k: TFe;
begin
  if FeIsZero(z1) or FeIsZero(y1) then
  begin
    SetInfinity(x3, y3, z3);
    Exit;
  end;
  { S = 4*x1*y1^2 }
  FeSqr(yy, y1);
  FeMul(t, x1, yy);
  FeSetInt(k, 4); FeMul(s, k, t);
  { M = 3*(x1 - z1^2)*(x1 + z1^2) }
  FeSqr(zz, z1);
  FeSub(t, x1, zz);
  FeAdd(u, x1, zz);
  FeMul(mm, t, u);
  FeSetInt(k, 3); FeMul(mm, mm, k);
  { x3 = M^2 - 2*S }
  FeSqr(nx, mm);
  FeAdd(t, s, s);
  FeSub(nx, nx, t);
  { y3 = M*(S - x3) - 8*y1^4 }
  FeSub(t, s, nx);
  FeMul(ny, mm, t);
  FeSqr(t, yy);                       { y1^4 }
  FeSetInt(k, 8); FeMul(t, k, t);
  FeSub(ny, ny, t);
  { z3 = 2*y1*z1 }
  FeMul(nz, y1, z1);
  FeAdd(nz, nz, nz);
  x3 := nx; y3 := ny; z3 := nz;
end;

{ Jacobian add: (x3,y3,z3) := (x1,y1,z1) + (x2,y2,z2). May alias inputs. }
procedure JacAdd(var x3, y3, z3: TFe;
                 const x1, y1, z1, x2, y2, z2: TFe);
var z1z1, z2z2, u1, u2, s1, s2, hh, rr, h2, h3, t, u, nx, ny, nz: TFe;
begin
  if FeIsZero(z1) then begin x3 := x2; y3 := y2; z3 := z2; Exit; end;
  if FeIsZero(z2) then begin x3 := x1; y3 := y1; z3 := z1; Exit; end;
  FeSqr(z1z1, z1);
  FeSqr(z2z2, z2);
  FeMul(u1, x1, z2z2);
  FeMul(u2, x2, z1z1);
  FeMul(t, z2, z2z2);  FeMul(s1, y1, t);
  FeMul(t, z1, z1z1);  FeMul(s2, y2, t);
  if FeEqual(u1, u2) then
  begin
    if FeEqual(s1, s2) then JacDouble(x3, y3, z3, x1, y1, z1)
    else SetInfinity(x3, y3, z3);
    Exit;
  end;
  FeSub(hh, u2, u1);
  FeSub(rr, s2, s1);
  FeSqr(h2, hh);
  FeMul(h3, h2, hh);
  { x3 = rr^2 - h3 - 2*u1*h2 }
  FeSqr(nx, rr);
  FeSub(nx, nx, h3);
  FeMul(t, u1, h2);
  FeAdd(u, t, t);
  FeSub(nx, nx, u);
  { y3 = rr*(u1*h2 - x3) - s1*h3 }
  FeMul(t, u1, h2);
  FeSub(t, t, nx);
  FeMul(ny, rr, t);
  FeMul(u, s1, h3);
  FeSub(ny, ny, u);
  { z3 = hh*z1*z2 }
  FeMul(t, z1, z2);
  FeMul(nz, hh, t);
  x3 := nx; y3 := ny; z3 := nz;
end;

{ (rx,ry,rz) := k * (px,py,pz), k as a big-endian byte string. }
procedure ScalarMul(var rx, ry, rz: TFe; const kbytes: AnsiString;
                    const px, py, pz: TFe);
var i, bit, bytev: Integer;
begin
  SetInfinity(rx, ry, rz);
  for i := 1 to Length(kbytes) do
  begin
    bytev := Ord(kbytes[i]);
    for bit := 7 downto 0 do
    begin
      JacDouble(rx, ry, rz, rx, ry, rz);
      if ((bytev shr bit) and 1) <> 0 then
        JacAdd(rx, ry, rz, rx, ry, rz, px, py, pz);
    end;
  end;
end;

{ Jacobian -> affine x, as 32 big-endian bytes. Caller must have checked z <> 0.
  The single field inversion of the whole operation lives here. }
function AffineX(const x, z: TFe): AnsiString;
var zinv, zinv2, ax: TFe;
begin
  FeInv(zinv, z);
  FeSqr(zinv2, zinv);
  FeMul(ax, x, zinv2);
  AffineX := FeToBytes(ax);
end;

function EcdsaP256Verify(const qxy, msg, sig: AnsiString): Boolean;
var
  r, s, e, w, u1, u2, one: TBigInt;
  qxb, qyb, u1b, u2b, affxb: AnsiString;
  qx, qy, fone: TFe;
  r1x, r1y, r1z, r2x, r2y, r2z, rx, ry, rz: TFe;
  affx, affxModN, q1, rem: TBigInt;
begin
  Result := False;
  if (Length(qxy) <> 64) or (Length(sig) <> 64) then Exit;
  InitCurve;

  r := BytesToBig(Copy(sig, 1, 32));
  s := BytesToBig(Copy(sig, 33, 32));
  one := BigFromInt(1);
  { r,s in [1, n-1] }
  if (BigCompare(r, one) < 0) or (BigCompare(r, N) >= 0) then Exit;
  if (BigCompare(s, one) < 0) or (BigCompare(s, N) >= 0) then Exit;

  e := BytesToBig(Sha256(msg));      { 256-bit hash, no truncation needed for P-256 }
  BigDivMod(e, N, q1, rem); e := rem;

  w  := MInv(s, N);
  u1 := MMul(e, w, N);
  u2 := MMul(r, w, N);

  { public-key coordinates must be REAL field elements — a value >= p would be
    accepted-and-reduced silently, which is not a valid encoding }
  qxb := Copy(qxy, 1, 32);
  qyb := Copy(qxy, 33, 32);
  if not FeBytesInRange(qxb) then Exit;
  if not FeBytesInRange(qyb) then Exit;
  FeFromBytes(qx, qxb);
  FeFromBytes(qy, qyb);

  u1b := BigToBytes(u1, 32);
  u2b := BigToBytes(u2, 32);

  FeSetOne(fone);
  ScalarMul(r1x, r1y, r1z, u1b, GXf, GYf, fone);      { u1*G }
  ScalarMul(r2x, r2y, r2z, u2b, qx, qy, fone);        { u2*Q }
  JacAdd(rx, ry, rz, r1x, r1y, r1z, r2x, r2y, r2z);

  if FeIsZero(rz) then Exit;            { R = infinity -> invalid }

  affxb := AffineX(rx, rz);
  affx := BytesToBig(affxb);

  { valid iff (affx mod n) == r }
  BigDivMod(affx, N, q1, affxModN);
  Result := BigCompare(affxModN, r) = 0;
end;

function EcdsaP256PubFromPriv(const priv: AnsiString): AnsiString;
var
  d, q, rem: TBigInt;
  qxj, qyj, qzj, zinv, zinv2, zinv3, qx, qy, fone: TFe;
begin
  EcdsaP256PubFromPriv := '';
  if Length(priv) <> 32 then Exit;
  InitCurve;
  d := BytesToBig(priv); BigDivMod(d, N, q, rem); d := rem;   { d mod n }
  if BigIsZero(d) then Exit;
  FeSetOne(fone);
  ScalarMul(qxj, qyj, qzj, BigToBytes(d, 32), GXf, GYf, fone);   { Q = d*G }
  if FeIsZero(qzj) then Exit;
  { affine x = X/Z^2, y = Y/Z^3 — one inversion, shared }
  FeInv(zinv, qzj);
  FeSqr(zinv2, zinv);
  FeMul(zinv3, zinv2, zinv);
  FeMul(qx, qxj, zinv2);
  FeMul(qy, qyj, zinv3);
  EcdsaP256PubFromPriv := FeToBytes(qx) + FeToBytes(qy);
end;

function EcdsaP256SignK(const priv, msg, k32: AnsiString): AnsiString;
var
  d, k, r, e, kinv, rd, sum, s, q, rem, affx: TBigInt;
  rx, ry, rz, fone: TFe;
  affxb: AnsiString;
begin
  EcdsaP256SignK := '';
  if (Length(priv) <> 32) or (Length(k32) <> 32) then Exit;
  InitCurve;
  d := BytesToBig(priv); BigDivMod(d, N, q, rem); d := rem;
  k := BytesToBig(k32);  BigDivMod(k, N, q, rem); k := rem;
  if BigIsZero(k) then Exit;
  { R = k*G ; r = R.x mod n }
  FeSetOne(fone);
  ScalarMul(rx, ry, rz, BigToBytes(k, 32), GXf, GYf, fone);
  if FeIsZero(rz) then Exit;
  affxb := AffineX(rx, rz);
  affx := BytesToBig(affxb);
  BigDivMod(affx, N, q, r);
  if BigIsZero(r) then Exit;
  { e = SHA-256(msg) mod n }
  e := BytesToBig(Sha256(msg)); BigDivMod(e, N, q, rem); e := rem;
  { s = k^-1 * (e + r*d) mod n }
  kinv := MInv(k, N);
  rd   := MMul(r, d, N);
  sum  := MAdd(e, rd, N);
  s    := MMul(kinv, sum, N);
  if BigIsZero(s) then Exit;
  EcdsaP256SignK := BigToBytes(r, 32) + BigToBytes(s, 32);
end;

function EcdsaP256Sign(const priv, msg: AnsiString): AnsiString;
var k32, sig: AnsiString; tries: Integer;
begin
  EcdsaP256Sign := '';
  for tries := 1 to 16 do
  begin
    SetLength(k32, 32);
    if not OSEntropyBytes(@k32[1], 32) then Exit;
    sig := EcdsaP256SignK(priv, msg, k32);
    if sig <> '' then begin EcdsaP256Sign := sig; Exit; end;
  end;
end;

function EcdsaP256GenKey(var priv, pub: AnsiString): Boolean;
var tries: Integer; d, q, rem: TBigInt; p: AnsiString;
begin
  EcdsaP256GenKey := False;
  InitCurve;
  for tries := 1 to 16 do
  begin
    SetLength(p, 32);
    if not OSEntropyBytes(@p[1], 32) then Exit;
    d := BytesToBig(p); BigDivMod(d, N, q, rem); d := rem;
    if BigIsZero(d) then Continue;
    priv := BigToBytes(d, 32);
    pub := EcdsaP256PubFromPriv(priv);
    if pub <> '' then begin EcdsaP256GenKey := True; Exit; end;
  end;
end;

end.
