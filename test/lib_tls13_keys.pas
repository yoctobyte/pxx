program lib_tls13_keys;
{ TLS 1.3 key schedule (RFC 8446 §7.1) against the RFC 8448 worked example. }
uses tls13_keys, sha256;

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

var es, hs, ms, ecdhe, shs: AnsiString;
begin
  es := EarlySecret('');
  SayBool('early-secret', Sha256Hex(es) =
    '33ad0a1c607ec03b09e6cd9893680ce210adf300aa1f2660e1b22e10f170f92a');

  ecdhe := Hx('8bd4054fb55b9d63fdfbacf9f04b9f0d35e6d63f537563efd46272900f89492d');
  hs := HandshakeSecret(es, ecdhe);
  SayBool('handshake-secret', Sha256Hex(hs) =
    '1dc826e93606aa6fdc0aadc12f741b01046aa6b99f691ed221a9f0ca043fbeac');

  ms := MasterSecret(hs);
  SayBool('master-secret', Sha256Hex(ms) =
    '18df06843d13a08bf2a449844c5f8a478001bc4d4c627984d5a41da8d0402919');

  shs := Hx('b67b7d690cc16c4e75e54213cb2d37b4e9c912bcded9105d42befd59d391ad38');
  SayBool('traffic-key', Sha256Hex(TrafficKey(shs, 16)) = '3fce516009c21727d0f2e4e86ee403bc');
  SayBool('traffic-iv',  Sha256Hex(TrafficIv(shs))      = '5d313eb2671276ee13000b30');
end.
