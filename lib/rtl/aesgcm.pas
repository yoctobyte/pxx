unit aesgcm;
{ AES-128 + AES-128-GCM AEAD (NIST SP 800-38D / FIPS-197). Pure Pascal, no
  external library — a TLS 1.3 AEAD (TLS_AES_128_GCM_SHA256), the second half of
  milestone M2 of feature-tls13-from-scratch.

  Encrypt-only AES (GCM uses the forward cipher in CTR mode + GHASH). GHASH does a
  bit-serial GF(2^128) multiply (correct over fast; the handshake is low-volume,
  bulk throughput is a later kTLS concern). Byte buffers are AnsiString.
  Verified against the GCM spec test vectors in test/lib_aesgcm. }

interface

{ AES-128-GCM. key = 16 bytes, iv = 12 bytes (96-bit, the TLS case). }
function AesGcmSeal(const key, iv, aad, plaintext: AnsiString): AnsiString;   { ct || 16-byte tag }
function AesGcmOpen(const key, iv, aad, ciphertextAndTag: AnsiString;
                    var plaintext: AnsiString): Boolean;

{ Raw AES-128 single-block encrypt (16-byte key, 16-byte block). Exposed for
  tests / other modes. }
function AesEncryptBlock(const key, block: AnsiString): AnsiString;

implementation

const
  SBox: array[0..255] of Byte = (
    $63,$7c,$77,$7b,$f2,$6b,$6f,$c5,$30,$01,$67,$2b,$fe,$d7,$ab,$76,
    $ca,$82,$c9,$7d,$fa,$59,$47,$f0,$ad,$d4,$a2,$af,$9c,$a4,$72,$c0,
    $b7,$fd,$93,$26,$36,$3f,$f7,$cc,$34,$a5,$e5,$f1,$71,$d8,$31,$15,
    $04,$c7,$23,$c3,$18,$96,$05,$9a,$07,$12,$80,$e2,$eb,$27,$b2,$75,
    $09,$83,$2c,$1a,$1b,$6e,$5a,$a0,$52,$3b,$d6,$b3,$29,$e3,$2f,$84,
    $53,$d1,$00,$ed,$20,$fc,$b1,$5b,$6a,$cb,$be,$39,$4a,$4c,$58,$cf,
    $d0,$ef,$aa,$fb,$43,$4d,$33,$85,$45,$f9,$02,$7f,$50,$3c,$9f,$a8,
    $51,$a3,$40,$8f,$92,$9d,$38,$f5,$bc,$b6,$da,$21,$10,$ff,$f3,$d2,
    $cd,$0c,$13,$ec,$5f,$97,$44,$17,$c4,$a7,$7e,$3d,$64,$5d,$19,$73,
    $60,$81,$4f,$dc,$22,$2a,$90,$88,$46,$ee,$b8,$14,$de,$5e,$0b,$db,
    $e0,$32,$3a,$0a,$49,$06,$24,$5c,$c2,$d3,$ac,$62,$91,$95,$e4,$79,
    $e7,$c8,$37,$6d,$8d,$d5,$4e,$a9,$6c,$56,$f4,$ea,$65,$7a,$ae,$08,
    $ba,$78,$25,$2e,$1c,$a6,$b4,$c6,$e8,$dd,$74,$1f,$4b,$bd,$8b,$8a,
    $70,$3e,$b5,$66,$48,$03,$f6,$0e,$61,$35,$57,$b9,$86,$c1,$1d,$9e,
    $e1,$f8,$98,$11,$69,$d9,$8e,$94,$9b,$1e,$87,$e9,$ce,$55,$28,$df,
    $8c,$a1,$89,$0d,$bf,$e6,$42,$68,$41,$99,$2d,$0f,$b0,$54,$bb,$16);

  RCon: array[1..10] of Byte = ($01,$02,$04,$08,$10,$20,$40,$80,$1b,$36);

type
  TBlk = array[0..15] of Byte;
  TRoundKeys = array[0..175] of Byte;

{ Whole static-array `:=` does not copy on the pinned compiler
  (bug-fixed-array-assignment-no-copy) — copy element by element. }
procedure BlkCopy(var d: TBlk; const s: TBlk);
var i: Integer;
begin for i := 0 to 15 do d[i] := s[i]; end;

function XTime(b: Byte): Byte;
begin
  if (b and $80) <> 0 then XTime := ((b shl 1) xor $1b) and $ff
  else XTime := (b shl 1) and $ff;
end;

procedure ExpandKey(const key: AnsiString; var rk: TRoundKeys);
var i: Integer; t0, t1, t2, t3, u: Byte;
begin
  for i := 0 to 15 do rk[i] := Ord(key[i + 1]);
  i := 16;
  while i < 176 do
  begin
    t0 := rk[i-4]; t1 := rk[i-3]; t2 := rk[i-2]; t3 := rk[i-1];
    if (i mod 16) = 0 then
    begin
      { RotWord + SubWord + Rcon }
      u  := t0;
      t0 := SBox[t1] xor RCon[i div 16];
      t1 := SBox[t2];
      t2 := SBox[t3];
      t3 := SBox[u];
    end;
    rk[i]   := rk[i-16]   xor t0;
    rk[i+1] := rk[i-16+1] xor t1;
    rk[i+2] := rk[i-16+2] xor t2;
    rk[i+3] := rk[i-16+3] xor t3;
    i := i + 4;
  end;
end;

procedure EncryptBlk(const rk: TRoundKeys; var s: TBlk);
var round, c, i: Integer; t, u0, u1, u2, u3: Byte; tmp: TBlk;
begin
  for i := 0 to 15 do s[i] := s[i] xor rk[i];        { round 0 AddRoundKey }
  for round := 1 to 10 do
  begin
    for i := 0 to 15 do s[i] := SBox[s[i]];           { SubBytes }
    { ShiftRows (state is column-major: index = row + 4*col) }
    BlkCopy(tmp, s);
    s[1]  := tmp[5];  s[5]  := tmp[9];  s[9]  := tmp[13]; s[13] := tmp[1];
    s[2]  := tmp[10]; s[6]  := tmp[14]; s[10] := tmp[2];  s[14] := tmp[6];
    s[3]  := tmp[15]; s[7]  := tmp[3];  s[11] := tmp[7];  s[15] := tmp[11];
    if round < 10 then
      for c := 0 to 3 do                              { MixColumns }
      begin
        u0 := s[4*c]; u1 := s[4*c+1]; u2 := s[4*c+2]; u3 := s[4*c+3];
        t := u0 xor u1 xor u2 xor u3;
        s[4*c]   := u0 xor t xor XTime(u0 xor u1);
        s[4*c+1] := u1 xor t xor XTime(u1 xor u2);
        s[4*c+2] := u2 xor t xor XTime(u2 xor u3);
        s[4*c+3] := u3 xor t xor XTime(u3 xor u0);
      end;
    for i := 0 to 15 do s[i] := s[i] xor rk[round*16 + i];   { AddRoundKey }
  end;
end;

function AesEncryptBlock(const key, block: AnsiString): AnsiString;
var rk: TRoundKeys; s: TBlk; i: Integer;
begin
  ExpandKey(key, rk);
  for i := 0 to 15 do s[i] := Ord(block[i + 1]);
  EncryptBlk(rk, s);
  SetLength(Result, 16);
  for i := 0 to 15 do Result[i + 1] := Chr(s[i]);
end;

{ --- GHASH: GF(2^128) multiply, bit-serial (NIST bit order) --- }

procedure GfMul(var z: TBlk; const y: TBlk);     { z := z * y in GF(2^128) }
var v, x: TBlk; i, k, lsb: Integer;
begin
  BlkCopy(x, z);
  for k := 0 to 15 do z[k] := 0;
  BlkCopy(v, y);
  for i := 0 to 127 do
  begin
    if (x[i shr 3] and ($80 shr (i and 7))) <> 0 then
      for k := 0 to 15 do z[k] := z[k] xor v[k];
    lsb := v[15] and 1;
    for k := 15 downto 1 do v[k] := ((v[k] shr 1) or ((v[k-1] and 1) shl 7)) and $ff;
    v[0] := v[0] shr 1;
    if lsb <> 0 then v[0] := v[0] xor $e1;
  end;
end;

procedure GhashUpdate(var x: TBlk; const h: TBlk; const data: AnsiString);
var off, i, blen: Integer; blk: TBlk;
begin
  off := 1;
  while off <= Length(data) do
  begin
    blen := Length(data) - off + 1; if blen > 16 then blen := 16;
    for i := 0 to 15 do
      if i < blen then blk[i] := Ord(data[off + i]) else blk[i] := 0;
    for i := 0 to 15 do x[i] := x[i] xor blk[i];
    GfMul(x, h);
    off := off + 16;
  end;
end;

function Be64(n: Int64): AnsiString;
var i: Integer; v: Int64;
begin
  SetLength(Result, 8);
  v := n;
  for i := 8 downto 1 do begin Result[i] := Chr(v and $FF); v := v shr 8; end;
end;

procedure Inc32(var ctr: TBlk);
var i, c: Integer;
begin
  c := 1;
  for i := 15 downto 12 do
  begin
    c := c + ctr[i];
    ctr[i] := c and $FF;
    c := c shr 8;
  end;
end;

{ AES-CTR over plaintext, starting from counter `ctr` (advanced per block). }
function AesCtr(const rk: TRoundKeys; ctr: TBlk; const data: AnsiString): AnsiString;
var off, i, blen: Integer; ks: TBlk;
begin
  SetLength(Result, Length(data));
  off := 1;
  while off <= Length(data) do
  begin
    BlkCopy(ks, ctr);
    EncryptBlk(rk, ks);
    blen := Length(data) - off + 1; if blen > 16 then blen := 16;
    for i := 0 to blen - 1 do
      Result[off + i] := Chr(Ord(data[off + i]) xor ks[i]);
    Inc32(ctr);
    off := off + 16;
  end;
end;

function ZeroPad(n: Integer): AnsiString;
var r, k: Integer;
begin
  Result := '';
  r := n mod 16;
  if r <> 0 then for k := 1 to 16 - r do Result := Result + Chr(0);
end;

{ The GCM tag over a given ciphertext: S = GHASH(AAD|pad|C|pad|lens), then xor
  AES_K(J0). }
function GcmTag(const rk: TRoundKeys; const h, j0: TBlk;
               const aad, ciphertext: AnsiString): AnsiString;
var x, ej0: TBlk; i: Integer; lenblk: AnsiString;
begin
  { GhashUpdate already zero-pads each call's final partial block to a block
    boundary, so A and C are processed as the spec's A||pad and C||pad. }
  for i := 0 to 15 do x[i] := 0;
  GhashUpdate(x, h, aad);
  GhashUpdate(x, h, ciphertext);
  lenblk := Be64(Int64(Length(aad)) * 8) + Be64(Int64(Length(ciphertext)) * 8);
  GhashUpdate(x, h, lenblk);

  BlkCopy(ej0, j0);
  EncryptBlk(rk, ej0);
  SetLength(Result, 16);
  for i := 0 to 15 do Result[i + 1] := Chr(x[i] xor ej0[i]);
end;

{ Common setup: round keys, H = AES_K(0), J0 = IV||0^31||1, and the data counter
  inc32(J0). }
procedure GcmSetup(const key, iv: AnsiString; var rk: TRoundKeys;
                   var h, j0, ctr: TBlk);
var i: Integer;
begin
  ExpandKey(key, rk);
  for i := 0 to 15 do h[i] := 0;
  EncryptBlk(rk, h);
  for i := 0 to 15 do j0[i] := 0;
  for i := 0 to 11 do j0[i] := Ord(iv[i + 1]);
  j0[15] := 1;
  BlkCopy(ctr, j0);
  Inc32(ctr);
end;

function AesGcmSeal(const key, iv, aad, plaintext: AnsiString): AnsiString;
var rk: TRoundKeys; h, j0, ctr: TBlk; ct, tag: AnsiString;
begin
  GcmSetup(key, iv, rk, h, j0, ctr);
  ct  := AesCtr(rk, ctr, plaintext);
  tag := GcmTag(rk, h, j0, aad, ct);
  Result := ct + tag;
end;

function ConstEq(const a, b: AnsiString): Boolean;
var i, diff: Integer;
begin
  if Length(a) <> Length(b) then begin Result := False; Exit; end;
  diff := 0;
  for i := 1 to Length(a) do diff := diff or (Ord(a[i]) xor Ord(b[i]));
  Result := diff = 0;
end;

function AesGcmOpen(const key, iv, aad, ciphertextAndTag: AnsiString;
                    var plaintext: AnsiString): Boolean;
var rk: TRoundKeys; h, j0, ctr: TBlk; ct, tag, wantTag: AnsiString; clen: Integer;
begin
  plaintext := '';
  Result := False;
  if Length(ciphertextAndTag) < 16 then Exit;
  clen := Length(ciphertextAndTag) - 16;
  ct  := Copy(ciphertextAndTag, 1, clen);
  tag := Copy(ciphertextAndTag, clen + 1, 16);

  GcmSetup(key, iv, rk, h, j0, ctr);
  wantTag := GcmTag(rk, h, j0, aad, ct);     { GHASH over the ciphertext }
  if not ConstEq(tag, wantTag) then Exit;     { auth fail -> withhold plaintext }
  plaintext := AesCtr(rk, ctr, ct);           { CTR is symmetric: decrypt }
  Result := True;
end;

end.
