program devtest_tls13_handshake;
{ Dev-only: a from-scratch TLS 1.3 client doing a FULL handshake + https GET
  against a loopback `openssl s_server -tls1_3`, wiring the M1-M6 units:
  ClientHello -> ServerHello -> X25519 ECDHE -> key schedule -> decrypt the
  server flight (EncryptedExtensions/Certificate/CertificateVerify/Finished) ->
  verify the server Finished MAC -> send client Finished -> application keys ->
  send an HTTP GET -> decrypt the response. Driven by tls13-handshake-devtest.
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

var gSock: TNetSocket;

function RecvN(n: Integer): AnsiString;
var got: Int64; buf: array[0..4095] of Byte; need, chunk, k: Integer;
begin
  Result := ''; need := n;
  while need > 0 do
  begin
    chunk := need; if chunk > 4096 then chunk := 4096;
    got := NetRecv(gSock, @buf[0], chunk);
    if got <= 0 then Exit;
    for k := 0 to got - 1 do Result := Result + Chr(buf[k]);
    need := need - Integer(got);
  end;
end;

function ReadRecord(var ctype: Byte; var payload: AnsiString): Boolean;
var hdr: AnsiString; len: Integer;
begin
  Result := False;
  hdr := RecvN(5);
  if Length(hdr) <> 5 then Exit;
  ctype := Ord(hdr[1]);
  len := (Ord(hdr[4]) shl 8) or Ord(hdr[5]);
  payload := RecvN(len);
  Result := Length(payload) = len;
end;

procedure SendBytes(const s: AnsiString);
begin NetSend(gSock, @s[1], Length(s)); end;

function RecHdr(ctype, len: Integer): AnsiString;
begin
  RecHdr := Chr(ctype) + Chr($03) + Chr($03) +
            Chr((len shr 8) and $ff) + Chr(len and $ff);
end;

function FinishedKey(const secret: AnsiString): AnsiString;
begin FinishedKey := HkdfExpandLabel(secret, 'finished', '', 32); end;

var
  port, suite, i: Integer;
  priv, pub, clientRandom, chMsg, transcript: AnsiString;
  ctype: Byte; payload, shBody: AnsiString;
  cipher: Integer; serverKeyShare, ecdhe: AnsiString;
  es, hsSec, ms, hsHash: AnsiString;
  sHs, cHs, sKey, sIv, cKey, cIv: AnsiString;
  keyLen: Integer;
  srvBuf: AnsiString; parsePos: Integer;
  mt: Byte; body: AnsiString; np: Integer; sawFinished: Boolean;
  seqS, seqC: Int64;
  rec, ptext: AnsiString; rct: Byte;
  sFinKey, cFinKey, expectFin, cFinData, cFinMsg, cFinRec: AnsiString;
  cApp, sApp, cAppKey, cAppIv, sAppKey, sAppIv: AnsiString;
  getMsg, getRec, resp: AnsiString;

  procedure Fail(const m: string);
  begin writeln(m); writeln('FAIL'); Halt(1); end;

  procedure DeriveTraffic(const secret: AnsiString; var key, iv: AnsiString);
  begin
    if suite = CS_CHACHA20_POLY1305 then key := TrafficKey(secret, 32)
    else key := TrafficKey(secret, 16);
    iv := TrafficIv(secret);
  end;

  function AeadSuite: Integer;
  begin if suite = CS_CHACHA20_POLY1305 then AeadSuite := TLS_CHACHA20_POLY1305 else AeadSuite := TLS_AES_128_GCM; end;

begin
  if ParamCount >= 1 then port := StrToInt(ParamStr(1)) else port := 28790;

  priv := ''; for i := 1 to 32 do priv := priv + Chr(i);
  pub := X25519Base(priv);
  clientRandom := ''; for i := 1 to 32 do clientRandom := clientRandom + Chr(100 + i);

  gSock := NetTcpConnect(NetLoopback(port));
  if gSock < 0 then Fail('connect failed');
  writeln('connect=ok');

  chMsg := BuildClientHello(clientRandom, pub, 'localhost');
  SendBytes(RecHdr(22, Length(chMsg)) + chMsg);
  transcript := chMsg;

  { ServerHello (skip any change_cipher_spec) }
  if not ReadRecord(ctype, payload) then Fail('read sh');
  while ctype = 20 do if not ReadRecord(ctype, payload) then Fail('read sh2');
  if ctype <> 22 then Fail('expected ServerHello');
  HsRead(payload, 1, mt, shBody, np);
  if mt <> HS_SERVER_HELLO then Fail('not ServerHello');
  if not ParseServerHello(shBody, cipher, serverKeyShare) then Fail('parse sh');
  suite := cipher;
  transcript := transcript + payload;
  writeln('serverhello=ok cipher=', cipher);

  { ECDHE + handshake key schedule }
  ecdhe := X25519(priv, serverKeyShare);
  es := EarlySecret('');
  hsSec := HandshakeSecret(es, ecdhe);
  hsHash := TranscriptHash(transcript);              { CH..SH }
  sHs := DeriveSecret(hsSec, 's hs traffic', hsHash);
  cHs := DeriveSecret(hsSec, 'c hs traffic', hsHash);
  DeriveTraffic(sHs, sKey, sIv);
  DeriveTraffic(cHs, cKey, cIv);

  { read + decrypt the server flight until Finished }
  srvBuf := ''; parsePos := 1; sawFinished := False; seqS := 0;
  sFinKey := FinishedKey(sHs);
  while not sawFinished do
  begin
    if not ReadRecord(ctype, payload) then Fail('read flight');
    if ctype = 20 then continue;                     { skip CCS }
    if ctype <> 23 then Fail('flight: unexpected ctype');
    rec := RecHdr(23, Length(payload)) + payload;
    if not Tls13Open(AeadSuite, sKey, sIv, seqS, rec, ptext, rct) then Fail('decrypt flight');
    seqS := seqS + 1;
    if rct <> 22 then continue;                      { only handshake here }
    srvBuf := srvBuf + ptext;
    { parse complete handshake messages }
    while parsePos + 4 <= Length(srvBuf) + 1 do
    begin
      np := (Ord(srvBuf[parsePos+1]) shl 16) or (Ord(srvBuf[parsePos+2]) shl 8) or Ord(srvBuf[parsePos+3]);
      if parsePos + 4 + np > Length(srvBuf) + 1 then Break;   { incomplete }
      mt := Ord(srvBuf[parsePos]);
      body := Copy(srvBuf, parsePos, 4 + np);        { full message }
      if mt = HS_FINISHED then
      begin
        { verify server Finished over transcript CH..CertVerify (before appending it) }
        expectFin := HmacSha256(sFinKey, TranscriptHash(transcript));
        if Copy(srvBuf, parsePos + 4, np) <> expectFin then Fail('server Finished MAC mismatch')
        else writeln('server-finished-verified=ok');
        transcript := transcript + body;
        sawFinished := True;
        Break;
      end
      else
      begin
        transcript := transcript + body;             { EE / Cert / CertVerify }
        if mt = HS_CERTIFICATE then writeln('got Certificate len=', np);
        if mt = HS_CERTIFICATE_VERIFY then writeln('got CertificateVerify');
      end;
      parsePos := parsePos + 4 + np;
    end;
  end;

  { client Finished over transcript CH..server-Finished }
  cFinKey := FinishedKey(cHs);
  cFinData := HmacSha256(cFinKey, TranscriptHash(transcript));
  cFinMsg := HsWrap(HS_FINISHED, cFinData);

  { application keys (Master Secret, transcript = CH..server-Finished) }
  ms := MasterSecret(hsSec);
  hsHash := TranscriptHash(transcript);
  cApp := DeriveSecret(ms, 'c ap traffic', hsHash);
  sApp := DeriveSecret(ms, 's ap traffic', hsHash);
  DeriveTraffic(cApp, cAppKey, cAppIv);
  DeriveTraffic(sApp, sAppKey, sAppIv);

  { send change_cipher_spec then the encrypted client Finished (client hs keys) }
  SendBytes(RecHdr(20, 1) + Chr(1));
  seqC := 0;
  cFinRec := Tls13Seal(AeadSuite, cKey, cIv, seqC, CT_HANDSHAKE, cFinMsg);
  SendBytes(cFinRec);
  writeln('client-finished-sent=ok');

  { send the HTTP GET encrypted under client application keys }
  getMsg := 'GET / HTTP/1.0' + Chr(13) + Chr(10) + 'Host: localhost' + Chr(13) + Chr(10) + Chr(13) + Chr(10);
  getRec := Tls13Seal(AeadSuite, cAppKey, cAppIv, 0, CT_APPLICATION_DATA, getMsg);
  SendBytes(getRec);

  { read + decrypt the server's application response }
  resp := ''; seqS := 0;
  for i := 1 to 8 do
  begin
    if not ReadRecord(ctype, payload) then Break;
    if ctype = 20 then continue;
    if ctype <> 23 then continue;
    rec := RecHdr(23, Length(payload)) + payload;
    { server hs Finished already consumed; app records use server app keys at seq 0.. }
    if Tls13Open(AeadSuite, sAppKey, sAppIv, seqS, rec, ptext, rct) then
    begin
      seqS := seqS + 1;
      if rct = 23 then resp := resp + ptext;         { application_data }
      if Pos('HTTP/', resp) > 0 then Break;
    end
    else Break;                                       { likely a NewSessionTicket under hs key; stop }
  end;

  NetClose(gSock);
  writeln('response-head=', Copy(resp, 1, 20));
  if Pos('HTTP/', resp) > 0 then writeln('ALL OK (https GET)') else writeln('FAIL');
end.
