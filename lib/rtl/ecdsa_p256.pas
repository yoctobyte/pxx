{ SPDX-License-Identifier: Zlib }
unit ecdsa_p256;
{ ECDSA signature verification on NIST P-256 (secp256r1) with SHA-256
  (ecdsa_secp256r1_sha256). Pure Pascal over lib/rtl/bignum + lib/rtl/sha256 —
  part of milestone M4 of feature-tls13-from-scratch.

  Verify only. Jacobian point coordinates (one inversion at the end). Field /
  scalar arithmetic via bignum, so it is correctness-first, not fast (a verify is
  a few seconds). Inputs: the public key as 64 raw bytes (Qx||Qy), the message,
  and the signature as r||s (32 bytes each).

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

uses bignum, sha256, sysutils, random;

var
  P, N, A, B, GX, GY: TBigInt;
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

procedure InitCurve;
begin
  if gInit then Exit;
  P  := HexToBig('ffffffff00000001000000000000000000000000ffffffffffffffffffffffff');
  N  := HexToBig('ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551');
  A  := HexToBig('ffffffff00000001000000000000000000000000fffffffffffffffffffffffc'); { p-3 }
  B  := HexToBig('5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b');
  GX := HexToBig('6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296');
  GY := HexToBig('4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5');
  gInit := True;
end;

{ modular arithmetic over a modulus m (operands assumed in [0, m)) }
function MAdd(const a, b, m: TBigInt): TBigInt;
var t: TBigInt;
begin
  t := BigAddSigned(a, b);
  if BigCompare(t, m) >= 0 then t := BigSubSigned(t, m);
  Result := t;
end;

function MSub(const a, b, m: TBigInt): TBigInt;
var t, zero: TBigInt;
begin
  t := BigSubSigned(a, b);
  zero := BigFromInt(0);
  if BigCompare(t, zero) < 0 then t := BigAddSigned(t, m);
  Result := t;
end;

function MMul(const a, b, m: TBigInt): TBigInt;
var t, q, r: TBigInt;
begin
  t := BigMul(a, b);
  BigDivMod(t, m, q, r);
  Result := r;
end;

function MInt(v: Int64; const m: TBigInt): TBigInt;
var t, q, r: TBigInt;
begin
  t := BigFromInt(v);
  BigDivMod(t, m, q, r);
  Result := r;
end;

{ a^-1 mod m, via Fermat (m prime): a^(m-2) }
function MInv(const a, m: TBigInt): TBigInt;
var e, two: TBigInt;
begin
  two := BigFromInt(2);
  e := BigSubSigned(m, two);
  Result := BigModPow(a, e, m);
end;

function IsZero(const a: TBigInt): Boolean;
begin Result := BigIsZero(a); end;

{ Jacobian doubling (a = -3): (x3,y3,z3) := 2*(x1,y1,z1). May alias inputs. }
procedure JacDouble(var x3, y3, z3: TBigInt; const x1, y1, z1: TBigInt);
var s, mm, t, u, yy, zz, nx, ny, nz: TBigInt;
begin
  if IsZero(z1) or IsZero(y1) then
  begin
    x3 := BigFromInt(1); y3 := BigFromInt(1); z3 := BigFromInt(0);   { infinity }
    Exit;
  end;
  { S = 4*x1*y1^2 }
  yy := MMul(y1, y1, P);
  t  := MMul(x1, yy, P);
  s  := MInt(4, P); s := MMul(s, t, P);
  { M = 3*(x1 - z1^2)*(x1 + z1^2) }
  zz := MMul(z1, z1, P);
  t  := MSub(x1, zz, P);
  u  := MAdd(x1, zz, P);
  mm := MMul(t, u, P);
  t  := MInt(3, P); mm := MMul(mm, t, P);
  { x3 = M^2 - 2*S }
  nx := MMul(mm, mm, P);
  t  := MAdd(s, s, P);
  nx := MSub(nx, t, P);
  { y3 = M*(S - x3) - 8*y1^4 }
  t  := MSub(s, nx, P);
  ny := MMul(mm, t, P);
  t  := MMul(yy, yy, P);              { y1^4 }
  u  := MInt(8, P); t := MMul(u, t, P);
  ny := MSub(ny, t, P);
  { z3 = 2*y1*z1 }
  nz := MMul(y1, z1, P);
  t  := MInt(2, P); nz := MMul(t, nz, P);
  x3 := nx; y3 := ny; z3 := nz;
end;

{ Jacobian add: (x3,y3,z3) := (x1,y1,z1) + (x2,y2,z2). May alias inputs. }
procedure JacAdd(var x3, y3, z3: TBigInt;
                 const x1, y1, z1, x2, y2, z2: TBigInt);
var z1z1, z2z2, u1, u2, s1, s2, hh, rr, h2, h3, t, u, nx, ny, nz: TBigInt;
begin
  if IsZero(z1) then begin x3 := x2; y3 := y2; z3 := z2; Exit; end;
  if IsZero(z2) then begin x3 := x1; y3 := y1; z3 := z1; Exit; end;
  z1z1 := MMul(z1, z1, P);
  z2z2 := MMul(z2, z2, P);
  u1 := MMul(x1, z2z2, P);
  u2 := MMul(x2, z1z1, P);
  t  := MMul(z2, z2z2, P);  s1 := MMul(y1, t, P);
  t  := MMul(z1, z1z1, P);  s2 := MMul(y2, t, P);
  if BigCompare(u1, u2) = 0 then
  begin
    if BigCompare(s1, s2) = 0 then JacDouble(x3, y3, z3, x1, y1, z1)
    else begin x3 := BigFromInt(1); y3 := BigFromInt(1); z3 := BigFromInt(0); end;
    Exit;
  end;
  hh := MSub(u2, u1, P);
  rr := MSub(s2, s1, P);
  h2 := MMul(hh, hh, P);
  h3 := MMul(h2, hh, P);
  { x3 = rr^2 - h3 - 2*u1*h2 }
  nx := MMul(rr, rr, P);
  nx := MSub(nx, h3, P);
  t  := MMul(u1, h2, P);
  u  := MAdd(t, t, P);
  nx := MSub(nx, u, P);
  { y3 = rr*(u1*h2 - x3) - s1*h3 }
  t  := MMul(u1, h2, P);
  t  := MSub(t, nx, P);
  ny := MMul(rr, t, P);
  u  := MMul(s1, h3, P);
  ny := MSub(ny, u, P);
  { z3 = hh*z1*z2 }
  t  := MMul(z1, z2, P);
  nz := MMul(hh, t, P);
  x3 := nx; y3 := ny; z3 := nz;
end;

{ (rx,ry,rz) := k * (px,py,pz), k as a big-endian byte string. }
procedure ScalarMul(var rx, ry, rz: TBigInt; const kbytes: AnsiString;
                    const px, py, pz: TBigInt);
var i, bit: Integer; bytev: Integer;
begin
  rx := BigFromInt(1); ry := BigFromInt(1); rz := BigFromInt(0);   { infinity }
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

function EcdsaP256Verify(const qxy, msg, sig: AnsiString): Boolean;
var
  r, s, e, w, u1, u2, qx, qy, one, zero: TBigInt;
  r1x, r1y, r1z, r2x, r2y, r2z, rx, ry, rz: TBigInt;
  zinv, zinv2, affx, affxModN: TBigInt;
  u1b, u2b: AnsiString;
  q1, rem: TBigInt;
begin
  Result := False;
  if (Length(qxy) <> 64) or (Length(sig) <> 64) then Exit;
  InitCurve;

  r := BytesToBig(Copy(sig, 1, 32));
  s := BytesToBig(Copy(sig, 33, 32));
  zero := BigFromInt(0); one := BigFromInt(1);
  { r,s in [1, n-1] }
  if (BigCompare(r, one) < 0) or (BigCompare(r, N) >= 0) then Exit;
  if (BigCompare(s, one) < 0) or (BigCompare(s, N) >= 0) then Exit;

  e := BytesToBig(Sha256(msg));      { 256-bit hash, no truncation needed for P-256 }
  BigDivMod(e, N, q1, rem); e := rem;

  w  := MInv(s, N);
  u1 := MMul(e, w, N);
  u2 := MMul(r, w, N);

  qx := BytesToBig(Copy(qxy, 1, 32));
  qy := BytesToBig(Copy(qxy, 33, 32));

  u1b := BigToBytes(u1, 32);
  u2b := BigToBytes(u2, 32);

  one := BigFromInt(1);
  ScalarMul(r1x, r1y, r1z, u1b, GX, GY, one);      { u1*G }
  ScalarMul(r2x, r2y, r2z, u2b, qx, qy, one);      { u2*Q }
  JacAdd(rx, ry, rz, r1x, r1y, r1z, r2x, r2y, r2z);

  if IsZero(rz) then Exit;            { R = infinity -> invalid }

  { affine x = X / Z^2 }
  zinv  := MInv(rz, P);
  zinv2 := MMul(zinv, zinv, P);
  affx  := MMul(rx, zinv2, P);

  { valid iff (affx mod n) == r }
  BigDivMod(affx, N, q1, affxModN);
  Result := BigCompare(affxModN, r) = 0;
end;

function EcdsaP256PubFromPriv(const priv: AnsiString): AnsiString;
var d, one, qxj, qyj, qzj, zinv, zinv2, zinv3, qx, qy, q, rem: TBigInt;
begin
  EcdsaP256PubFromPriv := '';
  if Length(priv) <> 32 then Exit;
  InitCurve;
  d := BytesToBig(priv); BigDivMod(d, N, q, rem); d := rem;   { d mod n }
  if BigIsZero(d) then Exit;
  one := BigFromInt(1);
  ScalarMul(qxj, qyj, qzj, BigToBytes(d, 32), GX, GY, one);   { Q = d*G }
  if IsZero(qzj) then Exit;
  zinv  := MInv(qzj, P);
  zinv2 := MMul(zinv, zinv, P);
  zinv3 := MMul(zinv2, zinv, P);
  qx := MMul(qxj, zinv2, P);       { affine x = X/Z^2 }
  qy := MMul(qyj, zinv3, P);       { affine y = Y/Z^3 }
  EcdsaP256PubFromPriv := BigToBytes(qx, 32) + BigToBytes(qy, 32);
end;

function EcdsaP256SignK(const priv, msg, k32: AnsiString): AnsiString;
var d, k, one, rx, ry, rz, zinv, zinv2, affx, r, e, kinv, rd, sum, s, q, rem: TBigInt;
begin
  EcdsaP256SignK := '';
  if (Length(priv) <> 32) or (Length(k32) <> 32) then Exit;
  InitCurve;
  one := BigFromInt(1);
  d := BytesToBig(priv); BigDivMod(d, N, q, rem); d := rem;
  k := BytesToBig(k32);  BigDivMod(k, N, q, rem); k := rem;
  if BigIsZero(k) then Exit;
  { R = k*G ; r = R.x mod n }
  ScalarMul(rx, ry, rz, BigToBytes(k, 32), GX, GY, one);
  if IsZero(rz) then Exit;
  zinv := MInv(rz, P); zinv2 := MMul(zinv, zinv, P); affx := MMul(rx, zinv2, P);
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
