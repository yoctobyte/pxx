program devtest_tls13_handshake;
{ Dev-only: a from-scratch TLS 1.3 client handshake against a loopback
  `openssl s_server -tls1_3`, wiring the M1-M6 units. Phase 1: ClientHello ->
  ServerHello -> X25519 ECDHE -> handshake key schedule -> decrypt the server's
  first encrypted flight (EncryptedExtensions...). Driven by tls13-handshake-devtest.
  Usage: devtest_tls13_handshake <port> }
uses sysutils, net, x25519, sha256, tls13_keys, tls13_record, tls13_hs;

function ToHex(const r: AnsiString): AnsiString;
const HEX = '0123456789abcdef';
var i, b: Integer;
begin
  Result := '';
  for i := 1 to Length(r) do
  begin b := Ord(r[i]); Result := Result + HEX[(b shr 4)+1] + HEX[(b and $F)+1]; end;
end;

var
  sock: TNetSocket;
  port: Integer;
  priv, pub, clientRandom: AnsiString;
  chMsg, chRecord: AnsiString;
  i: Integer;

{ read exactly n bytes }
function RecvN(s: TNetSocket; n: Integer): AnsiString;
var got: Int64; buf: array[0..4095] of Byte; need, chunk, k: Integer;
begin
  Result := '';
  need := n;
  while need > 0 do
  begin
    chunk := need; if chunk > 4096 then chunk := 4096;
    got := NetRecv(s, @buf[0], chunk);
    if got <= 0 then Exit;
    for k := 0 to got - 1 do Result := Result + Chr(buf[k]);
    need := need - Integer(got);
  end;
end;

{ read one TLS record: returns contentType + payload }
function ReadRecord(s: TNetSocket; var ctype: Byte; var payload: AnsiString): Boolean;
var hdr: AnsiString; len: Integer;
begin
  Result := False;
  hdr := RecvN(s, 5);
  if Length(hdr) <> 5 then Exit;
  ctype := Ord(hdr[1]);
  len := (Ord(hdr[4]) shl 8) or Ord(hdr[5]);
  payload := RecvN(s, len);
  Result := Length(payload) = len;
end;

var
  ctype: Byte; payload, shBody: AnsiString;
  cipher: Integer; serverKeyShare, ecdhe: AnsiString;
  es, hs, hsHash, sHsSecret, cHsSecret, sKey, sIv: AnsiString;
  mt: Byte; np: Integer;
  rec, ptext: AnsiString; rct: Byte; seq: Int64;
  transcript: AnsiString;
begin
  if ParamCount >= 1 then port := StrToInt(ParamStr(1)) else port := 28790;

  { fixed client key material (deterministic; s_server does not care) }
  priv := ''; for i := 1 to 32 do priv := priv + Chr(i);
  pub := X25519Base(priv);
  clientRandom := ''; for i := 1 to 32 do clientRandom := clientRandom + Chr(100 + i);

  sock := NetTcpConnect(NetLoopback(port));
  if sock < 0 then begin writeln('connect=FAIL'); writeln('FAIL'); Halt(1); end;
  writeln('connect=ok');

  chMsg := BuildClientHello(clientRandom, pub, 'localhost');
  { wrap as a plaintext handshake record (type 22) }
  chRecord := Chr(22) + Chr($03) + Chr($03) +
              Chr((Length(chMsg) shr 8) and $ff) + Chr(Length(chMsg) and $ff) + chMsg;
  if NetSend(sock, @chRecord[1], Length(chRecord)) < 0 then
  begin writeln('send=FAIL'); writeln('FAIL'); Halt(1); end;
  writeln('clienthello-sent=ok len=', Length(chMsg));
  transcript := chMsg;

  { read records until we get the ServerHello (handshake, type 22) }
  if not ReadRecord(sock, ctype, payload) then begin writeln('read=FAIL'); writeln('FAIL'); Halt(1); end;
  while ctype = 20 do                         { skip change_cipher_spec if it comes first }
    if not ReadRecord(sock, ctype, payload) then begin writeln('FAIL'); Halt(1); end;
  if ctype <> 22 then begin writeln('expected ServerHello, got ctype=', ctype); writeln('FAIL'); Halt(1); end;

  HsRead(payload, 1, mt, shBody, np);
  if mt <> HS_SERVER_HELLO then begin writeln('not ServerHello, mt=', mt); writeln('FAIL'); Halt(1); end;
  if not ParseServerHello(shBody, cipher, serverKeyShare) then
  begin writeln('serverhello-parse=FAIL'); writeln('FAIL'); Halt(1); end;
  writeln('serverhello=ok cipher=', cipher, ' keyshare=', ToHex(Copy(serverKeyShare,1,8)), '...');
  transcript := transcript + payload;          { ClientHello || ServerHello }

  { X25519 ECDHE }
  ecdhe := X25519(priv, serverKeyShare);
  writeln('ecdhe=', ToHex(Copy(ecdhe,1,8)), '...');

  { handshake key schedule }
  es := EarlySecret('');
  hs := HandshakeSecret(es, ecdhe);
  hsHash := TranscriptHash(transcript);
  sHsSecret := DeriveSecret(hs, 's hs traffic', hsHash);
  cHsSecret := DeriveSecret(hs, 'c hs traffic', hsHash);

  if cipher = CS_CHACHA20_POLY1305 then sKey := TrafficKey(sHsSecret, 32)
  else sKey := TrafficKey(sHsSecret, 16);
  sIv := TrafficIv(sHsSecret);
  writeln('server-hs-key=', ToHex(sKey));

  { decrypt the server's encrypted flight (skip CCS records) }
  seq := 0;
  if not ReadRecord(sock, ctype, payload) then begin writeln('FAIL'); Halt(1); end;
  while ctype = 20 do
    if not ReadRecord(sock, ctype, payload) then begin writeln('FAIL'); Halt(1); end;
  if ctype <> 23 then begin writeln('expected encrypted record, ctype=', ctype); writeln('FAIL'); Halt(1); end;

  rec := Chr(23) + Chr($03) + Chr($03) +
         Chr((Length(payload) shr 8) and $ff) + Chr(Length(payload) and $ff) + payload;
  if cipher = CS_CHACHA20_POLY1305 then
  begin
    if Tls13Open(TLS_CHACHA20_POLY1305, sKey, sIv, seq, rec, ptext, rct) then
      writeln('decrypt-server-flight=ok inner-type=', rct, ' len=', Length(ptext))
    else writeln('decrypt-server-flight=FAIL');
  end
  else
  begin
    if Tls13Open(TLS_AES_128_GCM, sKey, sIv, seq, rec, ptext, rct) then
      writeln('decrypt-server-flight=ok inner-type=', rct, ' len=', Length(ptext))
    else writeln('decrypt-server-flight=FAIL');
  end;

  NetClose(sock);
  if (Length(ptext) > 0) and (rct = 22) then writeln('ALL OK (phase1)') else writeln('FAIL');
end.
