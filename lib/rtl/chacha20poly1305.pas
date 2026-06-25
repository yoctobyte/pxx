unit chacha20poly1305;
{ ChaCha20 + Poly1305 + the ChaCha20-Poly1305 AEAD (RFC 8439). Pure Pascal, no
  external library — a TLS 1.3 AEAD (TLS_CHACHA20_POLY1305_SHA256) and the M2
  step of feature-tls13-from-scratch.

  ChaCha20 is 32-bit ARX (fast, table-free). Poly1305 uses the standard 5x26-bit
  limb representation with Int64 products (poly1305-donna style) — self-contained,
  no bignum. Byte buffers are AnsiString (one byte per char). Verified against the
  RFC 8439 vectors in test/lib_chacha20poly1305. }

interface

{ ChaCha20 keystream/cipher. key = 32 bytes, nonce = 12 bytes, counter = initial
  block counter (RFC uses 1 for payload; 0 generates the Poly1305 key). XORs data
  with the keystream — same call encrypts and decrypts. }
function ChaCha20(const key: AnsiString; counter: LongWord;
                  const nonce, data: AnsiString): AnsiString;

{ Poly1305 one-time MAC. key = 32 bytes (r||s). Returns the 16-byte tag. }
function Poly1305(const key, msg: AnsiString): AnsiString;

{ AEAD seal: returns ciphertext || 16-byte tag. key=32, nonce=12. }
function Chacha20Poly1305Seal(const key, nonce, aad, plaintext: AnsiString): AnsiString;

{ AEAD open: verifies the trailing tag over aad+ciphertext; on success sets
  plaintext and returns True, else returns False (plaintext = ''). }
function Chacha20Poly1305Open(const key, nonce, aad, ciphertextAndTag: AnsiString;
                             var plaintext: AnsiString): Boolean;

implementation

function RotL32(x: LongWord; n: Integer): LongWord;
begin
  Result := (x shl n) or (x shr (32 - n));
end;

function Le32(const s: AnsiString; off: Integer): LongWord;   { 1-based off }
begin
  Result :=  LongWord(Ord(s[off])) or
            (LongWord(Ord(s[off+1])) shl 8) or
            (LongWord(Ord(s[off+2])) shl 16) or
            (LongWord(Ord(s[off+3])) shl 24);
end;

function PutLe32(x: LongWord): AnsiString;
begin
  SetLength(Result, 4);
  Result[1] := Chr(x and $FF);
  Result[2] := Chr((x shr 8) and $FF);
  Result[3] := Chr((x shr 16) and $FF);
  Result[4] := Chr((x shr 24) and $FF);
end;

procedure QuarterRound(var s: array of LongWord; a, b, c, d: Integer);
begin
  s[a] := s[a] + s[b]; s[d] := RotL32(s[d] xor s[a], 16);
  s[c] := s[c] + s[d]; s[b] := RotL32(s[b] xor s[c], 12);
  s[a] := s[a] + s[b]; s[d] := RotL32(s[d] xor s[a], 8);
  s[c] := s[c] + s[d]; s[b] := RotL32(s[b] xor s[c], 7);
end;

{ One 64-byte ChaCha20 block as a string. }
function ChaCha20BlockStr(const key: AnsiString; counter: LongWord; const nonce: AnsiString): AnsiString;
var st, w: array[0..15] of LongWord; i: Integer;
begin
  st[0] := $61707865; st[1] := $3320646e; st[2] := $79622d32; st[3] := $6b206574;
  for i := 0 to 7 do st[4 + i] := Le32(key, 1 + i*4);
  st[12] := counter;
  st[13] := Le32(nonce, 1);
  st[14] := Le32(nonce, 5);
  st[15] := Le32(nonce, 9);

  for i := 0 to 15 do w[i] := st[i];
  for i := 1 to 10 do
  begin
    QuarterRound(w, 0, 4, 8,  12); QuarterRound(w, 1, 5, 9,  13);
    QuarterRound(w, 2, 6, 10, 14); QuarterRound(w, 3, 7, 11, 15);
    QuarterRound(w, 0, 5, 10, 15); QuarterRound(w, 1, 6, 11, 12);
    QuarterRound(w, 2, 7, 8,  13); QuarterRound(w, 3, 4, 9,  14);
  end;

  Result := '';
  for i := 0 to 15 do Result := Result + PutLe32(w[i] + st[i]);
end;

function ChaCha20(const key: AnsiString; counter: LongWord;
                  const nonce, data: AnsiString): AnsiString;
var ks: AnsiString; i, n, blk, j, baseI: Integer;
begin
  n := Length(data);
  SetLength(Result, n);
  blk := 0;
  i := 0;
  while i < n do
  begin
    ks := ChaCha20BlockStr(key, counter + LongWord(blk), nonce);
    baseI := i;
    for j := 1 to 64 do
    begin
      if baseI + j > n then Break;
      Result[baseI + j] := Chr(Ord(data[baseI + j]) xor Ord(ks[j]));
    end;
    i := i + 64;
    blk := blk + 1;
  end;
end;

{ --- Poly1305 (RFC 8439) over native 5x26-bit limbs (poly1305-donna style);
      no bignum, all arithmetic in Int64. --- }

function Poly1305(const key, msg: AnsiString): AnsiString;
var
  r0, r1, r2, r3, r4, s1, s2, s3, s4: Int64;
  h0, h1, h2, h3, h4: Int64;
  d0, d1, d2, d3, d4, c: Int64;
  t0, t1, t2, t3: Int64;
  g0, g1, g2, g3, g4: Int64;
  f0, f1, f2, f3: Int64;
  off, blen, hibit: Integer;
  blk: AnsiString;
const
  M26 = $3ffffff;
begin
  t0 := Le32(key, 1); t1 := Le32(key, 5); t2 := Le32(key, 9); t3 := Le32(key, 13);
  { r, with the clamp folded into the masks }
  r0 :=  t0                         and $3ffffff;
  r1 := ((t0 shr 26) or (t1 shl 6)) and $3ffff03;
  r2 := ((t1 shr 20) or (t2 shl 12)) and $3ffc0ff;
  r3 := ((t2 shr 14) or (t3 shl 18)) and $3f03fff;
  r4 :=  (t3 shr 8)                 and $00fffff;
  s1 := r1 * 5; s2 := r2 * 5; s3 := r3 * 5; s4 := r4 * 5;

  h0 := 0; h1 := 0; h2 := 0; h3 := 0; h4 := 0;

  off := 1;
  while off <= Length(msg) do
  begin
    blen := Length(msg) - off + 1;
    if blen > 16 then blen := 16;
    blk := Copy(msg, off, blen);
    if blen < 16 then
    begin
      blk := blk + Chr(1);                          { 0x01 byte after the data }
      while Length(blk) < 16 do blk := blk + Chr(0);
      hibit := 0;
    end
    else hibit := 1 shl 24;

    t0 := Le32(blk, 1); t1 := Le32(blk, 5); t2 := Le32(blk, 9); t3 := Le32(blk, 13);
    h0 := h0 + ( t0                          and M26);
    h1 := h1 + (((t0 shr 26) or (t1 shl 6))  and M26);
    h2 := h2 + (((t1 shr 20) or (t2 shl 12)) and M26);
    h3 := h3 + (((t2 shr 14) or (t3 shl 18)) and M26);
    h4 := h4 + ((t3 shr 8) or hibit);

    { d = h * r mod (2^130-5), schoolbook with the *5 reduction baked in }
    d0 := h0*r0 + h1*s4 + h2*s3 + h3*s2 + h4*s1;
    d1 := h0*r1 + h1*r0 + h2*s4 + h3*s3 + h4*s2;
    d2 := h0*r2 + h1*r1 + h2*r0 + h3*s4 + h4*s3;
    d3 := h0*r3 + h1*r2 + h2*r1 + h3*r0 + h4*s4;
    d4 := h0*r4 + h1*r3 + h2*r2 + h3*r1 + h4*r0;

    c := d0 shr 26; h0 := d0 and M26;
    d1 := d1 + c; c := d1 shr 26; h1 := d1 and M26;
    d2 := d2 + c; c := d2 shr 26; h2 := d2 and M26;
    d3 := d3 + c; c := d3 shr 26; h3 := d3 and M26;
    d4 := d4 + c; c := d4 shr 26; h4 := d4 and M26;
    h0 := h0 + c * 5; c := h0 shr 26; h0 := h0 and M26;
    h1 := h1 + c;

    off := off + 16;
  end;

  { fully carry h }
  c := h1 shr 26; h1 := h1 and M26; h2 := h2 + c;
  c := h2 shr 26; h2 := h2 and M26; h3 := h3 + c;
  c := h3 shr 26; h3 := h3 and M26; h4 := h4 + c;
  c := h4 shr 26; h4 := h4 and M26; h0 := h0 + c * 5;
  c := h0 shr 26; h0 := h0 and M26; h1 := h1 + c;

  { g = h - p (where p = 2^130-5) }
  g0 := h0 + 5; c := g0 shr 26; g0 := g0 and M26;
  g1 := h1 + c; c := g1 shr 26; g1 := g1 and M26;
  g2 := h2 + c; c := g2 shr 26; g2 := g2 and M26;
  g3 := h3 + c; c := g3 shr 26; g3 := g3 and M26;
  g4 := h4 + c - (1 shl 26);

  { if g >= 0 then h >= p: use g (= h-p), else keep h }
  if g4 >= 0 then
  begin
    h0 := g0; h1 := g1; h2 := g2; h3 := g3; h4 := g4 and M26;
  end;

  { pack 5x26 -> 4x32, then add s = key[16..31] with carry }
  f0 := ( h0        or (h1 shl 26)) and $ffffffff;
  f1 := ((h1 shr 6) or (h2 shl 20)) and $ffffffff;
  f2 := ((h2 shr 12) or (h3 shl 14)) and $ffffffff;
  f3 := ((h3 shr 18) or (h4 shl 8)) and $ffffffff;

  f0 := f0 + Le32(key, 17); c := f0 shr 32; f0 := f0 and $ffffffff;
  f1 := f1 + Le32(key, 21) + c; c := f1 shr 32; f1 := f1 and $ffffffff;
  f2 := f2 + Le32(key, 25) + c; c := f2 shr 32; f2 := f2 and $ffffffff;
  f3 := f3 + Le32(key, 29) + c; f3 := f3 and $ffffffff;

  Result := PutLe32(LongWord(f0)) + PutLe32(LongWord(f1)) +
            PutLe32(LongWord(f2)) + PutLe32(LongWord(f3));
end;

{ --- AEAD --- }

function Pad16(n: Integer): AnsiString;
var r, i: Integer;
begin
  Result := '';
  r := n mod 16;
  if r <> 0 then for i := 1 to 16 - r do Result := Result + Chr(0);
end;

function Le64(n: Integer): AnsiString;
var i: Integer; v: Int64;
begin
  SetLength(Result, 8);
  v := n;
  for i := 1 to 8 do begin Result[i] := Chr(v and $FF); v := v shr 8; end;
end;

function Poly1305KeyGen(const key, nonce: AnsiString): AnsiString;
begin
  Result := Copy(ChaCha20BlockStr(key, 0, nonce), 1, 32);
end;

function Chacha20Poly1305Seal(const key, nonce, aad, plaintext: AnsiString): AnsiString;
var otk, ct, mac, tag: AnsiString;
begin
  otk := Poly1305KeyGen(key, nonce);
  ct  := ChaCha20(key, 1, nonce, plaintext);
  mac := aad + Pad16(Length(aad)) + ct + Pad16(Length(ct)) +
         Le64(Length(aad)) + Le64(Length(ct));
  tag := Poly1305(otk, mac);
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

function Chacha20Poly1305Open(const key, nonce, aad, ciphertextAndTag: AnsiString;
                             var plaintext: AnsiString): Boolean;
var otk, ct, mac, tag, want: AnsiString; clen: Integer;
begin
  plaintext := '';
  Result := False;
  if Length(ciphertextAndTag) < 16 then Exit;
  clen := Length(ciphertextAndTag) - 16;
  ct  := Copy(ciphertextAndTag, 1, clen);
  tag := Copy(ciphertextAndTag, clen + 1, 16);
  otk := Poly1305KeyGen(key, nonce);
  mac := aad + Pad16(Length(aad)) + ct + Pad16(clen) +
         Le64(Length(aad)) + Le64(clen);
  want := Poly1305(otk, mac);
  if not ConstEq(tag, want) then Exit;            { auth fail — do not release }
  plaintext := ChaCha20(key, 1, nonce, ct);
  Result := True;
end;

end.
