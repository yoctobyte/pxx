unit sha512;
{ SHA-512 (FIPS 180-4). Pure Pascal, Int64 (treated as unsigned 64-bit) — needed
  by Ed25519 (lib/rtl/ed25519) and generally. M4 support for
  feature-tls13-from-scratch. Verified against the FIPS vectors in test (folded
  into lib_ed25519's harness). }

interface

{ 64-byte SHA-512 digest of `msg`, as a raw AnsiString. }
function Sha512(const msg: AnsiString): AnsiString;

implementation

const
  K: array[0..79] of Int64 = (
    $428a2f98d728ae22, $7137449123ef65cd, $b5c0fbcfec4d3b2f, $e9b5dba58189dbbc,
    $3956c25bf348b538, $59f111f1b605d019, $923f82a4af194f9b, $ab1c5ed5da6d8118,
    $d807aa98a3030242, $12835b0145706fbe, $243185be4ee4b28c, $550c7dc3d5ffb4e2,
    $72be5d74f27b896f, $80deb1fe3b1696b1, $9bdc06a725c71235, $c19bf174cf692694,
    $e49b69c19ef14ad2, $efbe4786384f25e3, $0fc19dc68b8cd5b5, $240ca1cc77ac9c65,
    $2de92c6f592b0275, $4a7484aa6ea6e483, $5cb0a9dcbd41fbd4, $76f988da831153b5,
    $983e5152ee66dfab, $a831c66d2db43210, $b00327c898fb213f, $bf597fc7beef0ee4,
    $c6e00bf33da88fc2, $d5a79147930aa725, $06ca6351e003826f, $142929670a0e6e70,
    $27b70a8546d22ffc, $2e1b21385c26c926, $4d2c6dfc5ac42aed, $53380d139d95b3df,
    $650a73548baf63de, $766a0abb3c77b2a8, $81c2c92e47edaee6, $92722c851482353b,
    $a2bfe8a14cf10364, $a81a664bbc423001, $c24b8b70d0f89791, $c76c51a30654be30,
    $d192e819d6ef5218, $d69906245565a910, $f40e35855771202a, $106aa07032bbd1b8,
    $19a4c116b8d2d0c8, $1e376c085141ab53, $2748774cdf8eeb99, $34b0bcb5e19b48a8,
    $391c0cb3c5c95a63, $4ed8aa4ae3418acb, $5b9cca4f7763e373, $682e6ff3d6b2b8a3,
    $748f82ee5defb2fc, $78a5636f43172f60, $84c87814a1f0ab72, $8cc702081a6439ec,
    $90befffa23631e28, $a4506cebde82bde9, $bef9a3f7b2c67915, $c67178f2e372532b,
    $ca273eceea26619c, $d186b8c721c0c207, $eada7dd6cde0eb1e, $f57d4f7fee6ed178,
    $06f067aa72176fba, $0a637dc5a2c898a6, $113f9804bef90dae, $1b710b35131c471b,
    $28db77f523047d84, $32caab7b40c72493, $3c9ebe0a15c9bebc, $431d67c49c100d4c,
    $4cc5d4becb3e42b6, $597f299cfc657e2a, $5fcb6fab3ad6faec, $6c44198c4a475817);

function Not64(x: Int64): Int64;
begin Not64 := -x - 1; end;     { `not` on an Int64 expr miscompiles }

function RotR(x: Int64; n: Integer): Int64;
begin RotR := (x shr n) or (x shl (64 - n)); end;

procedure Block(const data: AnsiString; off: Integer; var H: array of Int64);
var
  w: array[0..79] of Int64;
  a, b, c, d, e, f, g, hh, t1, t2, s0, s1, ch, maj: Int64;
  t, j: Integer;
begin
  for t := 0 to 15 do
  begin
    w[t] := 0;
    for j := 0 to 7 do
      w[t] := (w[t] shl 8) or Int64(Ord(data[off + t*8 + j]));
  end;
  for t := 16 to 79 do
  begin
    s0 := RotR(w[t-15], 1) xor RotR(w[t-15], 8) xor (w[t-15] shr 7);
    s1 := RotR(w[t-2], 19) xor RotR(w[t-2], 61) xor (w[t-2] shr 6);
    w[t] := w[t-16] + s0 + w[t-7] + s1;
  end;

  a := H[0]; b := H[1]; c := H[2]; d := H[3];
  e := H[4]; f := H[5]; g := H[6]; hh := H[7];

  for t := 0 to 79 do
  begin
    s1 := RotR(e, 14) xor RotR(e, 18) xor RotR(e, 41);
    ch := (e and f) xor (Not64(e) and g);
    t1 := hh + s1 + ch + K[t] + w[t];
    s0 := RotR(a, 28) xor RotR(a, 34) xor RotR(a, 39);
    maj := (a and b) xor (a and c) xor (b and c);
    t2 := s0 + maj;
    hh := g; g := f; f := e; e := d + t1;
    d := c; c := b; b := a; a := t1 + t2;
  end;

  H[0] := H[0] + a; H[1] := H[1] + b; H[2] := H[2] + c; H[3] := H[3] + d;
  H[4] := H[4] + e; H[5] := H[5] + f; H[6] := H[6] + g; H[7] := H[7] + hh;
end;

function Sha512(const msg: AnsiString): AnsiString;
var
  H: array[0..7] of Int64;
  data: AnsiString;
  padLen, i, j, nblocks: Integer;
  bitLen: Int64;
begin
  H[0] := Int64($6a09e667f3bcc908); H[1] := Int64($bb67ae8584caa73b);
  H[2] := Int64($3c6ef372fe94f82b); H[3] := Int64($a54ff53a5f1d36f1);
  H[4] := Int64($510e527fade682d1); H[5] := Int64($9b05688c2b3e6c1f);
  H[6] := Int64($1f83d9abfb41bd6b); H[7] := Int64($5be0cd19137e2179);

  bitLen := Int64(Length(msg)) * 8;

  { pad: 0x80, zeros to 112 mod 128, then 128-bit big-endian length (hi 64 = 0) }
  data := msg + Chr($80);
  padLen := (112 - (Length(data) mod 128) + 128) mod 128;
  for i := 1 to padLen do data := data + Chr(0);
  for i := 1 to 8 do data := data + Chr(0);          { high 64 bits of length }
  for i := 7 downto 0 do data := data + Chr((bitLen shr (i*8)) and $FF);

  nblocks := Length(data) div 128;
  for i := 0 to nblocks - 1 do
    Block(data, i*128 + 1, H);

  Result := '';
  for i := 0 to 7 do
    for j := 7 downto 0 do
      Result := Result + Chr((H[i] shr (j*8)) and $FF);
end;

end.
