program lib_tls13_record;
{ TLS 1.3 record protection (RFC 8446 §5.2): nonce = iv XOR seq, AEAD wrap/unwrap
  over both ciphersuites, roundtrip + tamper-reject. }
uses tls13_record;

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

function ToHex(const r: AnsiString): AnsiString;
const HEX = '0123456789abcdef';
var i, b: Integer;
begin
  Result := '';
  for i := 1 to Length(r) do
  begin b := Ord(r[i]); Result := Result + HEX[(b shr 4)+1] + HEX[(b and $F)+1]; end;
end;

const MSG = 'hello tls13 record layer payload';

var iv, key, rec, pt: AnsiString; ct: Byte; ok: Boolean;
begin
  iv := Hx('5d313eb2671276ee13000b30');

  { nonce = iv for seq 0; low byte flips for seq 1 }
  SayBool('nonce-seq0', ToHex(Tls13Nonce(iv, 0)) = '5d313eb2671276ee13000b30');
  SayBool('nonce-seq1', ToHex(Tls13Nonce(iv, 1)) = '5d313eb2671276ee13000b31');

  { AES-128-GCM record roundtrip }
  key := Hx('3fce516009c21727d0f2e4e86ee403bc');
  rec := Tls13Seal(TLS_AES_128_GCM, key, iv, 3, CT_HANDSHAKE, MSG);
  ok := Tls13Open(TLS_AES_128_GCM, key, iv, 3, rec, pt, ct);
  SayBool('aesgcm-roundtrip', ok and (pt = MSG) and (ct = CT_HANDSHAKE) and (Ord(rec[1]) = 23));
  rec[Length(rec)] := Chr(Ord(rec[Length(rec)]) xor 1);
  SayBool('aesgcm-tamper-reject', not Tls13Open(TLS_AES_128_GCM, key, iv, 3, rec, pt, ct));

  { ChaCha20-Poly1305 record roundtrip (32-byte key) }
  key := Hx('3fce516009c21727d0f2e4e86ee403bc3fce516009c21727d0f2e4e86ee403bc');
  rec := Tls13Seal(TLS_CHACHA20_POLY1305, key, iv, 7, CT_APPLICATION_DATA, MSG);
  ok := Tls13Open(TLS_CHACHA20_POLY1305, key, iv, 7, rec, pt, ct);
  SayBool('chacha-roundtrip', ok and (pt = MSG) and (ct = CT_APPLICATION_DATA));
  rec[10] := Chr(Ord(rec[10]) xor 1);
  SayBool('chacha-tamper-reject', not Tls13Open(TLS_CHACHA20_POLY1305, key, iv, 7, rec, pt, ct));
end.
