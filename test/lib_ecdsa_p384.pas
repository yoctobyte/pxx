program lib_ecdsa_p384;
{ ECDSA P-384 verification (lib/rtl/ecdsa_p384) against signatures made by
  Python's cryptography (the rows below come from test/lib_ecdsa_p384.py; the
  SHA-256 rows are a P-384 key signing a SHA-256 digest, which X.509 allows),
  plus the field unit against values Python computed, SHA-384 against hashlib,
  and the inputs a verifier must reject. }
uses p384field, ecdsa_p384, sha512, sha256;

var nOk, nFail: Integer;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then begin writeln(tag, '=ok'); nOk := nOk + 1; end
  else begin writeln(tag, '=FAIL'); nFail := nFail + 1; end;
end;

function Nyb(c: Char): Integer;
begin
  if (c >= '0') and (c <= '9') then Nyb := Ord(c) - Ord('0')
  else Nyb := Ord(c) - Ord('a') + 10;
end;

function Hx(const h: AnsiString): AnsiString;
var i: Integer;
begin
  Result := ''; i := 1;
  while i < Length(h) do begin Result := Result + Chr(Nyb(h[i]) * 16 + Nyb(h[i+1])); i := i + 2; end;
end;

function ToHex(const raw: AnsiString): AnsiString;
const HEX = '0123456789abcdef';
var i, b: Integer;
begin
  Result := '';
  for i := 1 to Length(raw) do
  begin b := Ord(raw[i]); Result := Result + HEX[(b shr 4)+1] + HEX[(b and $F)+1]; end;
end;

function Flip(const s: AnsiString; pos: Integer): AnsiString;
begin
  Result := s;
  Result[pos] := Chr(Ord(Result[pos]) xor 1);
end;

var row: Integer; prevQ: AnsiString;

procedure V(const qh, mh, sh, hname: AnsiString);
var q, m, sg, d, tag: AnsiString;
begin
  row := row + 1;
  q := Hx(qh); m := Hx(mh); sg := Hx(sh);
  if hname = 'sha384' then d := Sha384(m) else d := Sha256(m);
  Str(row, tag); tag := 'row' + tag + '-' + hname;
  SayBool(tag + '-valid', EcdsaP384VerifyHash(q, d, sg));
  if hname = 'sha384' then SayBool(tag + '-valid-msg-api', EcdsaP384Verify(q, m, sg));
  SayBool(tag + '-other-msg', not EcdsaP384VerifyHash(q, Sha384(m + 'x'), sg));
  SayBool(tag + '-r-flipped', not EcdsaP384VerifyHash(q, d, Flip(sg, 48)));
  SayBool(tag + '-s-flipped', not EcdsaP384VerifyHash(q, d, Flip(sg, 96)));
  SayBool(tag + '-off-curve-key', not EcdsaP384VerifyHash(Flip(q, 96), d, sg));
  if prevQ <> '' then SayBool(tag + '-other-key', not EcdsaP384VerifyHash(prevQ, d, sg));
  prevQ := q;
end;

var
  nHex, zero48, a, b: AnsiString;
  fa, fb, fr: TFe384;
begin
  nOk := 0; nFail := 0; row := 0; prevQ := '';

  { SHA-384 (FIPS 180-4 examples; hashlib agrees) }
  SayBool('sha384-empty', ToHex(Sha384('')) =
    '38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b');
  SayBool('sha384-abc', ToHex(Sha384('abc')) =
    'cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7');

  { field: Gx*Gy, Gx-Gy and 1/Gx mod p, computed with Python }
  a := Hx('aa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a385502f25dbf55296c3a545e3872760ab7');
  b := Hx('3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c00a60b1ce1d7e819d7a431d7c90ea0e5f');
  Fe384FromBytes(fa, a); Fe384FromBytes(fb, b);
  Fe384Mul(fr, fa, fb); SayBool('field-mul', ToHex(Fe384ToBytes(fr)) =
    '332e559389c970313cb29c4b55af5783821971a99c250daf84dc5d3cc441cb0a482e90de9d3ccd96b3c8c48b2ad3f025');
  Fe384Sub(fr, fb, fa); SayBool('field-sub-wraps', ToHex(Fe384ToBytes(fr)) =
    '8b901427d79b2737ceecd1a09f722eb58ad6e25a9cf278e48fe2ef33339c8e86b55dbf6f5e2958313feebf451e7403a7');
  Fe384Inv(fr, fa); SayBool('field-inv', ToHex(Fe384ToBytes(fr)) =
    '1ce18121749aa29a393faddf4e55522af8c67dabdfa413aac45da5c5f0781147133e1c96ca2a8234440fbf89e7e96410');
  SayBool('field-p-not-in-range', not Fe384BytesInRange(Hx(
    'fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000ffffffff')));

  { signatures from cryptography }
  V('25896f0cf27b4719871e3b90c4b82c7e6c605d36b77de8be92914a68b45a811acaefed272469804114de9436d5501c8b3f2578d575338f77b7c4fcbd4833388a0cb0732287d5d62d47814efc389a3952419f3b4b01da05436b8fe30cfe69ef52', '', 'bc959b9920e5db960f3dadfb03caa6ce3eb7c1bddc0a396a6ff35dbdbada1aceaed78179dd8c6829d08cf4c9b2f292d237ce3c920aac578aaef04a7321dafa6de2671ac3b4b7fd83392939ab9bf2c209ac4be1250438ddf5cb8d03a3248b4aa7', 'sha384');
  V('da5dade8b8546213ce4fb0820f4b95789b2fb680ee0172bf0298e2e19783e4b1c2e59bbaf01fb2b505f9628d1d54b96c41448b12a4a4ae92a59f4cff62d845021f88be70c4af09eda3a60e1e103bb4b56d5c9dbcc91deea3c94c9bfab5157d2e', '616263', 'd7a92e8efaa07750d8c5fcd8c0f06de34dda505f924a36284e5668016a474cd3aa2c393edb87eff0c489cad2a5c231c6205cdd4c398e1be9a59447621c3ab95f1e91f70765ba86f0178b15f78c96b66ebeca991ad939a7181bb88c6053b305e2', 'sha256');
  V('37164b4e24abe56b020734e294671dd85be7f19241ae5175e25c66de6435bf0a5dfcfebb14110625b5736e1db5c0111bd84667f3edb735780e730a0b39bdd34bc1e2b704a2340d81df5429966fcbedad092f4b581af17dc1c3334830f0ce9257', '7878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878787878', '8f842e554c86f4467ce78e0daa34d3ed46e29e4db8e0a0b7d84d9952256d26c8834ed5576c294c0a3b59cea3d3f8ec691101ad29cf14b340b63610179a4ea500532619f70435b5384df63cfdaa2c12a7a50fcd34d1603d0d059eb0e04f6377ad', 'sha384');
  V('87c6b0971a459b1959afe962a65a508c5245314c96d50540eda12b8059fb819ffa7e18dd64b59a6451ab10fd4c2cc8a6b73d3c991a6b14802e7cb97da0a69d7128d286081dbd53e7a0d0c0c96beb9fee6a7e139a881ff5d3c48f82e76483d56f', '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff', 'b3913f91e4282779c87ba4d7c1c04bb8f40dd208090e6026a43d7ee68211c6da27f1fda920a27303556220936c6b373317a88793bf9689514e9603278556e2763e6fb3086ac535c7b90c4f8c9e7580e1fe959d9a7ab6556bae53f7803a350e32', 'sha256');

  { r = 0 and s = n are out of range whatever the key }
  nHex := 'ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973';
  zero48 := Hx('000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000');
  SayBool('r-zero', not EcdsaP384VerifyHash(prevQ, Sha384(''), zero48 + Hx(nHex)));
  SayBool('s-is-n', not EcdsaP384VerifyHash(prevQ, Sha384(''), Hx(nHex) + Hx(nHex)));
  SayBool('short-key', not EcdsaP384VerifyHash(Copy(prevQ, 1, 95), Sha384(''), zero48 + zero48));

  writeln('ok=', nOk, ' fail=', nFail);
end.
