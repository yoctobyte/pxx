unit ed25519;
{ Ed25519 signature verification (RFC 8032), a TweetNaCl crypto_sign_open port.
  Pure Pascal — 16-limb radix-2^16 field (Int64), Edwards point arithmetic,
  mod-L scalar reduction, SHA-512 hash. Verify only. Part of milestone M4 of
  feature-tls13-from-scratch (Ed25519 cert signatures).

  Same Int64/array gotchas as x25519: whole fixed-array `:=` doesn't copy (element
  loops), unit-init blocks may not run (constants built lazily). }

interface

{ True iff `sig` (64 bytes) is a valid Ed25519 signature of `msg` under the
  32-byte `pubkey`. }
function Ed25519Verify(const pubkey, msg, sig: AnsiString): Boolean;

implementation

uses sha512;

type
  TGf = array[0..15] of Int64;
  { A point's 4 extended coords (X,Y,Z,T) are kept as SEPARATE standalone TGf
    vars, never grouped into an array/record — passing an array that is a member
    of an aggregate by ref segfaults (bug-aggregate-member-array-as-var-param). }

const
  cD: array[0..15] of Int64 = ($78a3,$1359,$4dca,$75eb,$d8ab,$4141,$0a4d,$0070,$e898,$7779,$4079,$8cc7,$fe73,$2b6f,$6cee,$5203);
  cD2: array[0..15] of Int64 = ($f159,$26b2,$9b94,$ebd6,$b156,$8283,$149a,$00e0,$d130,$eef3,$80f2,$198e,$fce7,$56df,$d9dc,$2406);
  cX: array[0..15] of Int64 = ($d51a,$8f25,$2d60,$c956,$a7b2,$9525,$c760,$692c,$dc5c,$fdd6,$e231,$c0a4,$53fe,$cd6e,$36d3,$2169);
  cY: array[0..15] of Int64 = ($6658,$6666,$6666,$6666,$6666,$6666,$6666,$6666,$6666,$6666,$6666,$6666,$6666,$6666,$6666,$6666);
  cI: array[0..15] of Int64 = ($a0b0,$4a0e,$1b27,$c4ee,$e478,$ad2f,$1806,$2f43,$d7a7,$3dfb,$0099,$2b4d,$df0b,$4fc1,$2480,$2b83);
  cL: array[0..31] of Int64 = ($ed,$d3,$f5,$5c,$1a,$63,$12,$58,$d6,$9c,$f7,$a2,$de,$f9,$de,$14,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,$10);

var
  gfD, gfD2, gfX, gfY, gfI: TGf;
  gInit: Boolean;

procedure CopyConst(var g: TGf; const src: array of Int64);
var i: Integer;
begin for i := 0 to 15 do g[i] := src[i]; end;

procedure InitConsts;
begin
  if gInit then Exit;
  CopyConst(gfD, cD); CopyConst(gfD2, cD2); CopyConst(gfX, cX);
  CopyConst(gfY, cY); CopyConst(gfI, cI);
  gInit := True;
end;

function Asr64(x: Int64; n: Integer): Int64;
begin
  if x >= 0 then Asr64 := x shr n
  else Asr64 := not ((not x) shr n);
end;

procedure GfCopy(var d: TGf; const s: TGf);
var i: Integer;
begin for i := 0 to 15 do d[i] := s[i]; end;

procedure GfSet0(var d: TGf);
var i: Integer;
begin for i := 0 to 15 do d[i] := 0; end;

procedure GfSet1(var d: TGf);
var i: Integer;
begin d[0] := 1; for i := 1 to 15 do d[i] := 0; end;

procedure Car25519(var o: TGf);
var i: Integer; c: Int64;
begin
  for i := 0 to 15 do
  begin
    o[i] := o[i] + (Int64(1) shl 16);
    c := Asr64(o[i], 16);
    if i < 15 then o[i+1] := o[i+1] + (c - 1)
    else o[0] := o[0] + 38 * (c - 1);
    o[i] := o[i] - (c shl 16);
  end;
end;

procedure Sel25519(var p, q: TGf; b: Int64);
var t, c: Int64; i: Integer;
begin
  c := not (b - 1);
  for i := 0 to 15 do
  begin
    t := c and (p[i] xor q[i]);
    p[i] := p[i] xor t;
    q[i] := q[i] xor t;
  end;
end;

procedure Pack25519(var o: AnsiString; const n: TGf);
var t, m: TGf; i, j, b: Integer;
begin
  GfCopy(t, n);
  Car25519(t); Car25519(t); Car25519(t);
  for j := 0 to 1 do
  begin
    m[0] := t[0] - $ffed;
    for i := 1 to 14 do
    begin
      m[i]   := t[i] - $ffff - (Asr64(m[i-1], 16) and 1);
      m[i-1] := m[i-1] and $ffff;
    end;
    m[15] := t[15] - $7fff - (Asr64(m[14], 16) and 1);
    b := Asr64(m[15], 16) and 1;
    m[14] := m[14] and $ffff;
    Sel25519(t, m, 1 - b);
  end;
  SetLength(o, 32);
  for i := 0 to 15 do
  begin
    o[2*i + 1] := Chr(t[i] and $ff);
    o[2*i + 2] := Chr(Asr64(t[i], 8) and $ff);
  end;
end;

{ True if a <> b (as field elements). }
function Neq25519(const a, b: TGf): Boolean;
var pa, pb: AnsiString;
begin
  Pack25519(pa, a); Pack25519(pb, b);
  Neq25519 := pa <> pb;
end;

function Par25519(const a: TGf): Integer;
var d: AnsiString;
begin
  Pack25519(d, a);
  Par25519 := Ord(d[1]) and 1;
end;

procedure Unpack25519(var o: TGf; const n: AnsiString; off: Integer);
var i: Integer;
begin
  for i := 0 to 15 do
    o[i] := Ord(n[off + 2*i]) + (Int64(Ord(n[off + 2*i + 1])) shl 8);
  o[15] := o[15] and $7fff;
end;

procedure AddF(var o: TGf; const a, b: TGf);
var i: Integer;
begin for i := 0 to 15 do o[i] := a[i] + b[i]; end;

procedure SubF(var o: TGf; const a, b: TGf);
var i: Integer;
begin for i := 0 to 15 do o[i] := a[i] - b[i]; end;

procedure MulF(var o: TGf; const a, b: TGf);
var t: array[0..30] of Int64; i, j: Integer;
begin
  for i := 0 to 30 do t[i] := 0;
  for i := 0 to 15 do
    for j := 0 to 15 do
      t[i + j] := t[i + j] + a[i] * b[j];
  for i := 0 to 14 do t[i] := t[i] + 38 * t[i + 16];
  for i := 0 to 15 do o[i] := t[i];
  Car25519(o); Car25519(o);
end;

procedure SqF(var o: TGf; const a: TGf);
begin MulF(o, a, a); end;

procedure Inv25519(var o: TGf; const inp: TGf);
var c: TGf; a: Integer;
begin
  GfCopy(c, inp);
  for a := 253 downto 0 do
  begin
    SqF(c, c);
    if (a <> 2) and (a <> 4) then MulF(c, c, inp);
  end;
  GfCopy(o, c);
end;

procedure Pow2523(var o: TGf; const inp: TGf);
var c: TGf; a: Integer;
begin
  GfCopy(c, inp);
  for a := 250 downto 0 do
  begin
    SqF(c, c);
    if a <> 1 then MulF(c, c, inp);
  end;
  GfCopy(o, c);
end;

{ Edwards point add: P := P + Q (extended coords, each coord a separate TGf). }
procedure AddP(var pX, pY, pZ, pT: TGf; const qX, qY, qZ, qT: TGf);
var a, b, c, d, t, e, f, g, h: TGf;
begin
  SubF(a, pY, pX); SubF(t, qY, qX); MulF(a, a, t);
  AddF(b, pX, pY); AddF(t, qX, qY); MulF(b, b, t);
  MulF(c, pT, qT); MulF(c, c, gfD2);
  MulF(d, pZ, qZ); AddF(d, d, d);
  SubF(e, b, a); SubF(f, d, c); AddF(g, d, c); AddF(h, b, a);
  MulF(pX, e, f); MulF(pY, h, g); MulF(pZ, g, f); MulF(pT, e, h);
end;

procedure CSwap(var pX, pY, pZ, pT, qX, qY, qZ, qT: TGf; b: Int64);
begin
  Sel25519(pX, qX, b); Sel25519(pY, qY, b);
  Sel25519(pZ, qZ, b); Sel25519(pT, qT, b);
end;

procedure PackPoint(var r: AnsiString; const pX, pY, pZ, pT: TGf);
var tx, ty, zi: TGf;
begin
  Inv25519(zi, pZ);
  MulF(tx, pX, zi);
  MulF(ty, pY, zi);
  Pack25519(r, ty);
  r[32] := Chr(Ord(r[32]) xor (Par25519(tx) shl 7));
end;

procedure ScalarMult(var pX, pY, pZ, pT: TGf; var qX, qY, qZ, qT: TGf;
                     const sbytes: AnsiString; soff: Integer);
var i: Integer; b: Int64;
begin
  GfSet0(pX); GfSet1(pY); GfSet1(pZ); GfSet0(pT);
  for i := 255 downto 0 do
  begin
    b := (Ord(sbytes[soff + (i shr 3)]) shr (i and 7)) and 1;
    CSwap(pX, pY, pZ, pT, qX, qY, qZ, qT, b);
    AddP(qX, qY, qZ, qT, pX, pY, pZ, pT);
    AddP(pX, pY, pZ, pT, pX, pY, pZ, pT);
    CSwap(pX, pY, pZ, pT, qX, qY, qZ, qT, b);
  end;
end;

procedure ScalarBase(var pX, pY, pZ, pT: TGf; const sbytes: AnsiString; soff: Integer);
var qX, qY, qZ, qT: TGf;
begin
  GfCopy(qX, gfX); GfCopy(qY, gfY); GfSet1(qZ); MulF(qT, gfX, gfY);
  ScalarMult(pX, pY, pZ, pT, qX, qY, qZ, qT, sbytes, soff);
end;

{ Unpack the negated public key point. False on invalid encoding. }
function UnpackNeg(var rX, rY, rZ, rT: TGf; const pk: AnsiString): Boolean;
var t, chk, num, den, den2, den4, den6, one: TGf;
begin
  GfSet1(rZ);
  Unpack25519(rY, pk, 1);
  SqF(num, rY); MulF(den, num, gfD); SubF(num, num, rZ); AddF(den, rZ, den);
  SqF(den2, den); SqF(den4, den2); MulF(den6, den4, den2);
  MulF(t, den6, num); MulF(t, t, den);
  Pow2523(t, t); MulF(t, t, num); MulF(t, t, den); MulF(t, t, den); MulF(rX, t, den);
  SqF(chk, rX); MulF(chk, chk, den);
  if Neq25519(chk, num) then MulF(rX, rX, gfI);
  SqF(chk, rX); MulF(chk, chk, den);
  if Neq25519(chk, num) then begin Result := False; Exit; end;
  if Par25519(rX) = ((Ord(pk[32]) shr 7) and 1) then
  begin
    GfSet0(one);
    SubF(rX, one, rX);             { rX := -rX }
  end;
  MulF(rT, rX, rY);
  Result := True;
end;

{ Reduce a 64-byte little-endian scalar `h` mod L into a 32-byte result. }
function ReduceModL(const h: AnsiString): AnsiString;
var x: array[0..63] of Int64; carry: Int64; i, j: Integer;
begin
  for i := 0 to 63 do x[i] := Ord(h[i + 1]);
  for i := 63 downto 32 do
  begin
    carry := 0;
    for j := i - 32 to i - 13 do
    begin
      x[j] := x[j] + carry - 16 * x[i] * cL[j - (i - 32)];
      carry := Asr64(x[j] + 128, 8);
      x[j] := x[j] - (carry shl 8);
    end;
    x[i - 12] := x[i - 12] + carry;     { x[j] after loop, j = i-12 }
    x[i] := 0;
  end;
  carry := 0;
  for j := 0 to 31 do
  begin
    x[j] := x[j] + carry - (Asr64(x[31], 4)) * cL[j];
    carry := Asr64(x[j], 8);
    x[j] := x[j] and 255;
  end;
  for j := 0 to 31 do x[j] := x[j] - carry * cL[j];
  SetLength(Result, 32);
  for i := 0 to 31 do
  begin
    x[i + 1] := x[i + 1] + Asr64(x[i], 8);
    Result[i + 1] := Chr(x[i] and 255);
  end;
end;

function Ed25519Verify(const pubkey, msg, sig: AnsiString): Boolean;
var
  pX, pY, pZ, pT, qX, qY, qZ, qT: TGf;
  h, hr, t, r: AnsiString;
  i, diff: Integer;
begin
  Result := False;
  if (Length(pubkey) <> 32) or (Length(sig) <> 64) then Exit;
  InitConsts;

  if not UnpackNeg(qX, qY, qZ, qT, pubkey) then Exit;

  { h = SHA512(R || pubkey || msg), reduced mod L }
  h  := Copy(sig, 1, 32) + pubkey + msg;
  hr := ReduceModL(Sha512(h));

  ScalarMult(pX, pY, pZ, pT, qX, qY, qZ, qT, hr, 1);   { P = h * (-A) }
  ScalarBase(qX, qY, qZ, qT, sig, 33);                  { Q = S * B   (S = sig[32..63]) }
  AddP(pX, pY, pZ, pT, qX, qY, qZ, qT);                 { P = S*B - h*A }
  PackPoint(t, pX, pY, pZ, pT);

  { valid iff t == R (= sig[0..31]) }
  r := Copy(sig, 1, 32);
  diff := 0;
  for i := 1 to 32 do diff := diff or (Ord(t[i]) xor Ord(r[i]));
  Result := diff = 0;
end;

end.
