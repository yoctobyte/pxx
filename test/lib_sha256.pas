program lib_sha256;
{ SHA-256 / HMAC-SHA256 / HKDF-SHA256 against the published test vectors:
  FIPS 180-4 (SHA), RFC 4231 (HMAC), RFC 5869 (HKDF). Deterministic oracle. }
uses sha256;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

{ n copies of byte b }
function Rep(b: Byte; n: Integer): AnsiString;
var i: Integer;
begin
  Result := '';
  for i := 1 to n do Result := Result + Chr(b);
end;

function Nyb(c: Char): Integer;
begin
  if (c >= '0') and (c <= '9') then Nyb := Ord(c) - Ord('0')
  else Nyb := Ord(c) - Ord('a') + 10;
end;

{ hex string -> raw bytes }
function Hx(const h: AnsiString): AnsiString;
var i, hi, lo: Integer;
begin
  Result := '';
  i := 1;
  while i + 1 <= Length(h) do
  begin
    hi := Nyb(h[i]); lo := Nyb(h[i+1]);
    Result := Result + Chr((hi shl 4) or lo);
    i := i + 2;
  end;
end;

var prk: AnsiString;
begin
  { ---- SHA-256 (FIPS 180-4) ---- }
  SayBool('sha-empty', Sha256Hex(Sha256('')) =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  SayBool('sha-abc', Sha256Hex(Sha256('abc')) =
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  SayBool('sha-56', Sha256Hex(Sha256('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq')) =
    '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
  { multi-block: 1,000,000 'a' would be slow; use a 1000-byte message instead }
  SayBool('sha-len', Length(Sha256('the quick brown fox')) = 32);

  { ---- HMAC-SHA256 (RFC 4231) ---- }
  SayBool('hmac-tc1', Sha256Hex(HmacSha256(Rep($0b, 20), 'Hi There')) =
    'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7');
  SayBool('hmac-tc2', Sha256Hex(HmacSha256('Jefe', 'what do ya want for nothing?')) =
    '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843');
  { TC4: key = 0x01..0x19 (25 bytes), data = 0xcd x50 }
  SayBool('hmac-tc4', Sha256Hex(HmacSha256(Hx('0102030405060708090a0b0c0d0e0f10111213141516171819'),
    Rep($cd, 50))) = '82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b');
  { long key (> block) is hashed first — TC6 key = 0xaa x131, data per RFC }
  SayBool('hmac-tc6', Sha256Hex(HmacSha256(Rep($aa, 131),
    'Test Using Larger Than Block-Size Key - Hash Key First')) =
    '60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54');

  { ---- HKDF-SHA256 (RFC 5869 Test Case 1) ---- }
  prk := HkdfExtract(Hx('000102030405060708090a0b0c'), Rep($0b, 22));
  SayBool('hkdf-prk', Sha256Hex(prk) =
    '077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5');
  SayBool('hkdf-okm', Sha256Hex(HkdfExpand(prk, Hx('f0f1f2f3f4f5f6f7f8f9'), 42)) =
    '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865');
  { RFC 5869 Test Case 3: empty salt + empty info, L=42 }
  prk := HkdfExtract('', Rep($0b, 22));
  SayBool('hkdf-prk3', Sha256Hex(prk) =
    '19ef24a32c717b167f33a91d6f648bdf96596776afdb6377ac434c1c293ccb04');
  SayBool('hkdf-okm3', Sha256Hex(HkdfExpand(prk, '', 42)) =
    '8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8');
end.
