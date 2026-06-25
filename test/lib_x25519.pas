program lib_x25519;
{ X25519 against RFC 7748 §5.2 (single-shot) + §6.1 (Diffie-Hellman) vectors. }
uses x25519;

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
  aPriv, aPub, bPriv, bPub, sAB, sBA: AnsiString;
begin
  { RFC 7748 §5.2 vector 1 }
  SayBool('rfc-vec1', ToHex(X25519(
    Hx('a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4'),
    Hx('e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c'))) =
    'c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552');

  { RFC 7748 §5.2 vector 2 }
  SayBool('rfc-vec2', ToHex(X25519(
    Hx('4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d'),
    Hx('e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493'))) =
    '95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957');

  { RFC 7748 §6.1 Diffie-Hellman }
  aPriv := Hx('77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a');
  bPriv := Hx('5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb');

  aPub := X25519Base(aPriv);
  bPub := X25519Base(bPriv);
  SayBool('alice-pub', ToHex(aPub) = '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a');
  SayBool('bob-pub',   ToHex(bPub) = 'de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f');

  sAB := X25519(aPriv, bPub);
  sBA := X25519(bPriv, aPub);
  SayBool('shared-value', ToHex(sAB) = '4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742');
  SayBool('shared-agree', sAB = sBA);
end.
