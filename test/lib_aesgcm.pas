program lib_aesgcm;
{ AES-128 (FIPS-197) + AES-128-GCM against the GCM spec test vectors. }
uses aesgcm;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

function Nyb(c: Char): Integer;
begin
  if (c >= '0') and (c <= '9') then Nyb := Ord(c) - Ord('0')
  else Nyb := Ord(c) - Ord('a') + 10;
end;

function Hx(const h: AnsiString): AnsiString;
var i, hi, lo: Integer;
begin
  Result := ''; i := 1;
  while i + 1 <= Length(h) do
  begin hi := Nyb(h[i]); lo := Nyb(h[i+1]); Result := Result + Chr((hi shl 4) or lo); i := i + 2; end;
end;

function ToHex(const raw: AnsiString): AnsiString;
const HEX = '0123456789abcdef';
var i, b: Integer;
begin
  Result := '';
  for i := 1 to Length(raw) do
  begin b := Ord(raw[i]); Result := Result + HEX[(b shr 4)+1] + HEX[(b and $F)+1]; end;
end;

var
  k0, iv0, k3, iv3, p3, a4, seal, pt: AnsiString;
  ok: Boolean;
begin
  { AES-128 ECB known-answer (FIPS-197 appendix B / C.1) }
  SayBool('aes-ecb', ToHex(AesEncryptBlock(
    Hx('000102030405060708090a0b0c0d0e0f'),
    Hx('00112233445566778899aabbccddeeff'))) = '69c4e0d86a7b0430d8cdb78070b4c55a');

  k0  := Hx('00000000000000000000000000000000');
  iv0 := Hx('000000000000000000000000');

  { GCM test case 1: empty P, empty A }
  SayBool('gcm-tc1-tag', ToHex(AesGcmSeal(k0, iv0, '', '')) =
    '58e2fccefa7e3061367f1d57a4e7455a');

  { GCM test case 2: P = one zero block }
  SayBool('gcm-tc2', ToHex(AesGcmSeal(k0, iv0, '', Hx('00000000000000000000000000000000'))) =
    '0388dace60b6a392f328c2b971b2fe78ab6e47d42cec13bdf53a67b21257bddf');

  { GCM test case 3: 64-byte P, empty A }
  k3  := Hx('feffe9928665731c6d6a8f9467308308');
  iv3 := Hx('cafebabefacedbaddecaf888');
  p3  := Hx('d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255');
  seal := AesGcmSeal(k3, iv3, '', p3);
  SayBool('gcm-tc3-ct', ToHex(Copy(seal, 1, Length(p3))) =
    '42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091473f5985');
  SayBool('gcm-tc3-tag', ToHex(Copy(seal, Length(seal)-15, 16)) =
    '4d5c2af327cd64a62cf35abd2ba6fab4');

  { GCM test case 4: 60-byte P + 20-byte AAD }
  p3 := Hx('d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39');
  a4 := Hx('feedfacedeadbeeffeedfacedeadbeefabaddad2');
  seal := AesGcmSeal(k3, iv3, a4, p3);
  SayBool('gcm-tc4-tag', ToHex(Copy(seal, Length(seal)-15, 16)) =
    '5bc94fbc3221a5db94fae95ae7121a47');

  { open: roundtrip + tamper reject }
  ok := AesGcmOpen(k3, iv3, a4, seal, pt);
  SayBool('open-ok', ok and (pt = p3));
  seal[Length(seal)] := Chr(Ord(seal[Length(seal)]) xor 1);
  ok := AesGcmOpen(k3, iv3, a4, seal, pt);
  SayBool('open-tamper-reject', (not ok) and (pt = ''));
end.
