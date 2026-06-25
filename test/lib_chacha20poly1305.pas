program lib_chacha20poly1305;
{ ChaCha20-Poly1305 against RFC 8439 test vectors:
  - Poly1305 MAC          (§2.5.2)
  - ChaCha20 keystream    (via the §2.8.2 plaintext, counter 1)
  - AEAD seal ciphertext+tag (§2.8.2)
  - AEAD open roundtrip + tamper-reject. }
uses chacha20poly1305;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

function Nyb(c: Char): Integer;
begin
  if (c >= '0') and (c <= '9') then Nyb := Ord(c) - Ord('0')
  else Nyb := Ord(c) - Ord('a') + 10;
end;

function Hx(const h: AnsiString): AnsiString;     { hex -> bytes }
var i, hi, lo: Integer;
begin
  Result := ''; i := 1;
  while i + 1 <= Length(h) do
  begin hi := Nyb(h[i]); lo := Nyb(h[i+1]); Result := Result + Chr((hi shl 4) or lo); i := i + 2; end;
end;

function ToHex(const raw: AnsiString): AnsiString; { bytes -> hex }
const HEX = '0123456789abcdef';
var i, b: Integer;
begin
  Result := '';
  for i := 1 to Length(raw) do
  begin b := Ord(raw[i]); Result := Result + HEX[(b shr 4)+1] + HEX[(b and $F)+1]; end;
end;

var
  key, nonce, aad, pt, seal, plain, tampered: AnsiString;
  clen: Integer;
  ok: Boolean;
begin
  { ---- Poly1305 (RFC 8439 §2.5.2) ---- }
  SayBool('poly-tag', ToHex(Poly1305(
    Hx('85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b'),
    'Cryptographic Forum Research Group')) = 'a8061dc1305136c6c22b8baf0c0127a9');

  { ---- AEAD (RFC 8439 §2.8.2) ---- }
  key   := Hx('808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f');
  nonce := Hx('070000004041424344454647');
  aad   := Hx('50515253c0c1c2c3c4c5c6c7');
  pt    := 'Ladies and Gentlemen of the class of ''99: If I could offer you only one tip for the future, sunscreen would be it.';

  { ChaCha20 keystream check: first 16 ciphertext bytes (counter 1) }
  SayBool('chacha-first16', ToHex(Copy(ChaCha20(key, 1, nonce, pt), 1, 16)) =
    'd31a8d34648e60db7b86afbc53ef7ec2');

  seal := Chacha20Poly1305Seal(key, nonce, aad, pt);
  clen := Length(seal) - 16;
  SayBool('aead-ct-first16', ToHex(Copy(seal, 1, 16)) = 'd31a8d34648e60db7b86afbc53ef7ec2');
  SayBool('aead-tag', ToHex(Copy(seal, clen + 1, 16)) = '1ae10b594f09e26a7e902ecbd0600691');
  SayBool('aead-ctlen', clen = Length(pt));

  { ---- open: roundtrip + tamper reject ---- }
  ok := Chacha20Poly1305Open(key, nonce, aad, seal, plain);
  SayBool('open-ok', ok and (plain = pt));

  tampered := seal;
  tampered[Length(tampered)] := Chr(Ord(tampered[Length(tampered)]) xor 1);   { flip a tag bit }
  ok := Chacha20Poly1305Open(key, nonce, aad, tampered, plain);
  SayBool('open-tamper-reject', (not ok) and (plain = ''));
end.
