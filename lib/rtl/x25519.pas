{ SPDX-License-Identifier: Zlib }
unit x25519;
{ X25519 (Curve25519 ECDH, RFC 7748). Pure Pascal, no external library — the M3
  key-exchange step of feature-tls13-from-scratch.

  A faithful port of TweetNaCl's crypto_scalarmult: field elements are 16 limbs of
  radix 2^16 (`TGf`), all arithmetic in Int64. NB: TweetNaCl relies on the C `>>`
  being an *arithmetic* (sign-preserving) shift on signed i64; Pascal `shr` is
  logical, so every such shift goes through Asr64. Scalars/points/outputs are
  32-byte AnsiString. Verified against the RFC 7748 vectors in test/lib_x25519. }

interface

{ scalar * point, both 32 bytes; returns the 32-byte u-coordinate. }
function X25519(const scalar, point: AnsiString): AnsiString;
{ scalar * basepoint (u=9): the public key for a private scalar. }
function X25519Base(const scalar: AnsiString): AnsiString;

implementation

type
  TGf = array[0..15] of Int64;

{ arithmetic (sign-preserving) shift right — Pascal shr is logical. }
function Asr64(x: Int64; n: Integer): Int64;
begin
  if x >= 0 then Asr64 := x shr n
  else Asr64 := not ((not x) shr n);
end;

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

{ constant-time conditional swap of p and q when b = 1 }
procedure Sel25519(var p, q: TGf; b: Int64);
var t, c: Int64; i: Integer;
begin
  c := not (b - 1);        { 0 when b=0, all-ones when b=1 }
  for i := 0 to 15 do
  begin
    t := c and (p[i] xor q[i]);
    p[i] := p[i] xor t;
    q[i] := q[i] xor t;
  end;
end;

procedure Unpack25519(var o: TGf; const n: AnsiString);
var i: Integer;
begin
  for i := 0 to 15 do
    o[i] := Ord(n[2*i + 1]) + (Int64(Ord(n[2*i + 2])) shl 8);
  o[15] := o[15] and $7fff;
end;

function Pack25519(const n: TGf): AnsiString;
var t, m: TGf; i, j, b: Integer;
begin
  for i := 0 to 15 do t[i] := n[i];
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
  SetLength(Result, 32);
  for i := 0 to 15 do
  begin
    Result[2*i + 1] := Chr(t[i] and $ff);
    Result[2*i + 2] := Chr(Asr64(t[i], 8) and $ff);
  end;
end;

procedure AddGf(var o: TGf; const a, b: TGf);
var i: Integer;
begin for i := 0 to 15 do o[i] := a[i] + b[i]; end;

procedure SubGf(var o: TGf; const a, b: TGf);
var i: Integer;
begin for i := 0 to 15 do o[i] := a[i] - b[i]; end;

{ o = a * b mod 2^255-19. Reads a,b fully into t before writing o, so o may
  alias a or b. }
procedure MulGf(var o: TGf; const a, b: TGf);
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

procedure SqGf(var o: TGf; const a: TGf);
begin MulGf(o, a, a); end;

{ o = 1/i mod 2^255-19, via i^(p-2) (Fermat). }
procedure Inv25519(var o: TGf; const inp: TGf);
var c: TGf; a: Integer;
begin
  for a := 0 to 15 do c[a] := inp[a];
  for a := 253 downto 0 do
  begin
    SqGf(c, c);
    if (a <> 2) and (a <> 4) then MulGf(c, c, inp);
  end;
  for a := 0 to 15 do o[a] := c[a];
end;

function X25519(const scalar, point: AnsiString): AnsiString;
var
  z: array[0..31] of Byte;
  x, a, b, c, d, e, f, g121665: TGf;
  i, pos: Integer; r: Int64;
begin
  for i := 0 to 15 do g121665[i] := 0;
  g121665[0] := $DB41; g121665[1] := 1;

  for i := 0 to 31 do z[i] := Ord(scalar[i + 1]);
  z[31] := (z[31] and 127) or 64;      { clamp }
  z[0]  := z[0] and 248;

  Unpack25519(x, point);
  for i := 0 to 15 do begin b[i] := x[i]; a[i] := 0; c[i] := 0; d[i] := 0; end;
  a[0] := 1; d[0] := 1;

  for pos := 254 downto 0 do
  begin
    r := (z[pos shr 3] shr (pos and 7)) and 1;
    Sel25519(a, b, r);
    Sel25519(c, d, r);
    AddGf(e, a, c);
    SubGf(a, a, c);
    AddGf(c, b, d);
    SubGf(b, b, d);
    SqGf(d, e);
    SqGf(f, a);
    MulGf(a, c, a);
    MulGf(c, b, e);
    AddGf(e, a, c);
    SubGf(a, a, c);
    SqGf(b, a);
    SubGf(c, d, f);
    MulGf(a, c, g121665);
    AddGf(a, a, d);
    MulGf(c, c, a);
    MulGf(a, d, f);
    MulGf(d, b, x);
    SqGf(b, e);
    Sel25519(a, b, r);
    Sel25519(c, d, r);
  end;

  Inv25519(c, c);
  MulGf(a, a, c);
  Result := Pack25519(a);
end;

function X25519Base(const scalar: AnsiString): AnsiString;
var bp: AnsiString; i: Integer;
begin
  SetLength(bp, 32);
  bp[1] := Chr(9);
  for i := 2 to 32 do bp[i] := Chr(0);
  Result := X25519(scalar, bp);
end;

end.
