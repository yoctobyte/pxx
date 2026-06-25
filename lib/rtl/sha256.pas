unit sha256;
{ SHA-256 (FIPS 180-4) + HMAC-SHA256 (RFC 2104) + HKDF-SHA256 (RFC 5869).

  Pure integer, no external library — the hash/KDF foundation for a from-scratch,
  library-free TLS 1.3 key schedule (feature-tls13-from-scratch) and generally
  useful (integrity, password KDF input, etc.). Byte buffers are carried as
  AnsiString (one byte per char), which is what the TLS key schedule manipulates;
  digests are returned as raw 32-byte strings (use Sha256Hex for text).

  Verified against the published test vectors (FIPS / RFC 4231 / RFC 5869) in
  test/lib_sha256. }

interface

const
  SHA256_DIGEST = 32;     { bytes }
  SHA256_BLOCK  = 64;     { bytes }

{ One-shot SHA-256: returns the 32-byte digest as a raw AnsiString. }
function Sha256(const msg: AnsiString): AnsiString;
{ Lowercase hex of a raw byte string (e.g. a digest). }
function Sha256Hex(const raw: AnsiString): AnsiString;

{ HMAC-SHA256(key, msg) — 32-byte raw MAC. }
function HmacSha256(const key, msg: AnsiString): AnsiString;

{ HKDF-SHA256 (RFC 5869). Extract derives a 32-byte PRK from salt+ikm; Expand
  stretches a PRK to `length` bytes bound to `info`. }
function HkdfExtract(const salt, ikm: AnsiString): AnsiString;
function HkdfExpand(const prk, info: AnsiString; outLen: Integer): AnsiString;

implementation

const
  K: array[0..63] of LongWord = (
    $428a2f98, $71374491, $b5c0fbcf, $e9b5dba5, $3956c25b, $59f111f1, $923f82a4, $ab1c5ed5,
    $d807aa98, $12835b01, $243185be, $550c7dc3, $72be5d74, $80deb1fe, $9bdc06a7, $c19bf174,
    $e49b69c1, $efbe4786, $0fc19dc6, $240ca1cc, $2de92c6f, $4a7484aa, $5cb0a9dc, $76f988da,
    $983e5152, $a831c66d, $b00327c8, $bf597fc7, $c6e00bf3, $d5a79147, $06ca6351, $14292967,
    $27b70a85, $2e1b2138, $4d2c6dfc, $53380d13, $650a7354, $766a0abb, $81c2c92e, $92722c85,
    $a2bfe8a1, $a81a664b, $c24b8b70, $c76c51a3, $d192e819, $d6990624, $f40e3585, $106aa070,
    $19a4c116, $1e376c08, $2748774c, $34b0bcb5, $391c0cb3, $4ed8aa4a, $5b9cca4f, $682e6ff3,
    $748f82ee, $78a5636f, $84c87814, $8cc70208, $90befffa, $a4506ceb, $bef9a3f7, $c67178f2);

function RotR(x: LongWord; n: Integer): LongWord;
begin
  Result := (x shr n) or (x shl (32 - n));
end;

{ Compress one 64-byte block (at 1-based offset `off` in `data`) into H[0..7]. }
procedure Sha256Block(const data: AnsiString; off: Integer; var H: array of LongWord);
var
  w: array[0..63] of LongWord;
  a, b, c, d, e, f, g, hh, t1, t2, s0, s1, ch, maj: LongWord;
  t: Integer;
begin
  for t := 0 to 15 do
    w[t] := (LongWord(Ord(data[off + t*4    ])) shl 24) or
            (LongWord(Ord(data[off + t*4 + 1])) shl 16) or
            (LongWord(Ord(data[off + t*4 + 2])) shl 8)  or
             LongWord(Ord(data[off + t*4 + 3]));
  for t := 16 to 63 do
  begin
    s0 := RotR(w[t-15], 7) xor RotR(w[t-15], 18) xor (w[t-15] shr 3);
    s1 := RotR(w[t-2], 17) xor RotR(w[t-2], 19) xor (w[t-2] shr 10);
    w[t] := w[t-16] + s0 + w[t-7] + s1;
  end;

  a := H[0]; b := H[1]; c := H[2]; d := H[3];
  e := H[4]; f := H[5]; g := H[6]; hh := H[7];

  for t := 0 to 63 do
  begin
    s1 := RotR(e, 6) xor RotR(e, 11) xor RotR(e, 25);
    ch := (e and f) xor ((not e) and g);
    t1 := hh + s1 + ch + K[t] + w[t];
    s0 := RotR(a, 2) xor RotR(a, 13) xor RotR(a, 22);
    maj := (a and b) xor (a and c) xor (b and c);
    t2 := s0 + maj;
    hh := g; g := f; f := e; e := d + t1;
    d := c; c := b; b := a; a := t1 + t2;
  end;

  H[0] := H[0] + a; H[1] := H[1] + b; H[2] := H[2] + c; H[3] := H[3] + d;
  H[4] := H[4] + e; H[5] := H[5] + f; H[6] := H[6] + g; H[7] := H[7] + hh;
end;

function BE32(x: LongWord): AnsiString;
begin
  SetLength(Result, 4);
  Result[1] := Chr((x shr 24) and $FF);
  Result[2] := Chr((x shr 16) and $FF);
  Result[3] := Chr((x shr 8) and $FF);
  Result[4] := Chr(x and $FF);
end;

function Sha256(const msg: AnsiString): AnsiString;
var
  H: array[0..7] of LongWord;
  data: AnsiString;
  msgLen, padLen, i, nblocks: Integer;
  bitLen: Int64;
begin
  H[0] := $6a09e667; H[1] := $bb67ae85; H[2] := $3c6ef372; H[3] := $a54ff53a;
  H[4] := $510e527f; H[5] := $9b05688c; H[6] := $1f83d9ab; H[7] := $5be0cd19;

  msgLen := Length(msg);
  bitLen := Int64(msgLen) * 8;

  { pad: 0x80, zeros to 56 mod 64, then 64-bit big-endian bit length }
  data := msg + Chr($80);
  padLen := (56 - (Length(data) mod 64) + 64) mod 64;
  for i := 1 to padLen do data := data + Chr(0);
  for i := 7 downto 0 do data := data + Chr((bitLen shr (i*8)) and $FF);

  nblocks := Length(data) div 64;
  for i := 0 to nblocks - 1 do
    Sha256Block(data, i*64 + 1, H);

  Result := '';
  for i := 0 to 7 do Result := Result + BE32(H[i]);
end;

function Sha256Hex(const raw: AnsiString): AnsiString;
const HEX = '0123456789abcdef';
var i, b: Integer;
begin
  Result := '';
  for i := 1 to Length(raw) do
  begin
    b := Ord(raw[i]);
    Result := Result + HEX[(b shr 4) + 1] + HEX[(b and $F) + 1];
  end;
end;

function XorPad(const key: AnsiString; pad: Byte): AnsiString;
var i: Integer;
begin
  SetLength(Result, SHA256_BLOCK);
  for i := 1 to SHA256_BLOCK do
  begin
    if i <= Length(key) then Result[i] := Chr(Ord(key[i]) xor pad)
    else Result[i] := Chr(pad);
  end;
end;

function HmacSha256(const key, msg: AnsiString): AnsiString;
var k0, ipad, opad: AnsiString;
begin
  { keys longer than the block are hashed first }
  if Length(key) > SHA256_BLOCK then k0 := Sha256(key) else k0 := key;
  ipad := XorPad(k0, $36);
  opad := XorPad(k0, $5c);
  Result := Sha256(opad + Sha256(ipad + msg));
end;

function HkdfExtract(const salt, ikm: AnsiString): AnsiString;
var s: AnsiString; i: Integer;
begin
  { empty salt -> a string of HashLen zero bytes (RFC 5869 §2.2) }
  if Length(salt) = 0 then
  begin
    s := '';
    for i := 1 to SHA256_DIGEST do s := s + Chr(0);
  end
  else s := salt;
  Result := HmacSha256(s, ikm);
end;

function HkdfExpand(const prk, info: AnsiString; outLen: Integer): AnsiString;
var t, okm: AnsiString; i, n: Integer;
begin
  okm := '';
  t := '';
  n := (outLen + SHA256_DIGEST - 1) div SHA256_DIGEST;   { ceil(L / HashLen) }
  for i := 1 to n do
  begin
    t := HmacSha256(prk, t + info + Chr(i and $FF));      { T(i) = HMAC(PRK, T(i-1)|info|i) }
    okm := okm + t;
  end;
  Result := Copy(okm, 1, outLen);
end;

end.
